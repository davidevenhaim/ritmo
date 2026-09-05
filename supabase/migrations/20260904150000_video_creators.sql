-- SoGym v0.3: video and creators.
-- Creator flags and applications, hosted videos (Cloudflare Stream or Mux),
-- exercise tagging, view analytics, reports and a moderation queue.
--
-- Conventions carry over from v0.2: RLS everywhere, counters and moderation
-- state are trigger- or function-owned, JSON shapes match lib/core/models.dart.

-- ------------------------------------------------------------- profiles
alter table public.profiles
  add column creator       boolean not null default false,
  add column moderator     boolean not null default false,
  add column banned        boolean not null default false,
  add column creator_since timestamptz;

comment on column public.profiles.creator   is 'May upload video. Granted by a moderator through approve_creator().';
comment on column public.profiles.moderator is 'May read the report queue and call moderate(). Set by an operator in SQL.';

create or replace function public.is_moderator()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select moderator from public.profiles where id = auth.uid()), false);
$$;

-- Trusted server-side writers (counter triggers, record_view) set this
-- transaction-local flag so the column-protection triggers let them through.
create or replace function public.trusted_write()
returns boolean language sql stable as $$
  select coalesce(current_setting('sogym.trusted', true), '') = '1';
$$;

create or replace function public.is_banned()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select banned from public.profiles where id = auth.uid()), false);
$$;

-- Owners edit their profile, never their own trust flags.
drop policy profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and (plus, creator, moderator, banned) = (select p.plus, p.creator, p.moderator, p.banned from public.profiles p where p.id = auth.uid())
  );

-- ------------------------------------------------- creator applications
create table public.creator_applications (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  statement   text not null check (char_length(statement) between 10 and 500),
  links       text[] not null default '{}',
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------------ videos
-- One row per upload. The `video` edge function creates it (service role)
-- when it hands out a direct-upload URL, and the provider webhook fills in
-- playback details when transcoding finishes. 60-second cap is enforced by
-- the provider (Cloudflare maxDurationSeconds) and again here.
create table public.videos (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references public.profiles(id) on delete cascade,
  provider      text not null check (provider in ('cloudflare', 'mux')),
  provider_uid  text,                       -- Cloudflare video uid / Mux asset id
  upload_id     text,                       -- Mux direct-upload id (asset id arrives later)
  status        text not null default 'uploading'
                check (status in ('uploading', 'processing', 'ready', 'failed', 'removed')),
  duration_sec  numeric(6,2) check (duration_sec is null or duration_sec between 0 and 60),
  width         int,
  height        int,
  playback_url  text,                       -- HLS manifest
  thumbnail_url text,
  exercise_ids  text[] not null default '{}',   -- free-exercise-db ids shown as chips under the player
  screen        jsonb,                      -- automated screening verdict {safe, categories, note}
  view_count    int not null default 0,
  error         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (provider, provider_uid)
);
create index videos_author_idx on public.videos (author_id, created_at desc);
create index videos_upload_idx on public.videos (upload_id);
create trigger videos_touch before update on public.videos
  for each row execute function public.touch_updated_at();

alter table public.posts
  add column video_id   uuid references public.videos(id) on delete set null,
  add column hidden     boolean not null default false,
  add column view_count int not null default 0;
create index posts_video_idx on public.posts (video_id);

-- ------------------------------------------------------------------- views
-- One row per viewer per post per day; the counter only moves on first view.
create table public.post_views (
  post_id   uuid not null references public.posts(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  day       date not null default current_date,
  primary key (post_id, viewer_id, day)
);

create or replace function public.record_view(p_post uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  inserted boolean;
  vid uuid;
begin
  if auth.uid() is null then return; end if;
  insert into public.post_views (post_id, viewer_id) values (p_post, auth.uid())
    on conflict do nothing;
  inserted := found;
  if inserted then
    perform set_config('sogym.trusted', '1', true);
    update public.posts set view_count = view_count + 1 where id = p_post returning video_id into vid;
    if vid is not null then
      update public.videos set view_count = view_count + 1 where id = vid;
    end if;
    perform set_config('sogym.trusted', '', true);
  end if;
end;
$$;

-- ----------------------------------------------------------------- reports
create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles(id) on delete set null,   -- null = automated screening
  target_kind text not null check (target_kind in ('post', 'comment', 'profile')),
  target_id   uuid not null,
  reason      text not null check (reason in ('spam', 'harassment', 'unsafe_advice', 'nudity', 'violence', 'copyright', 'automated', 'other')),
  details     text not null default '' check (char_length(details) <= 500),
  status      text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  action      text,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);
create unique index reports_once_idx on public.reports (reporter_id, target_kind, target_id) where reporter_id is not null;
create index reports_open_idx on public.reports (status, created_at) where status = 'open';
create index reports_target_idx on public.reports (target_kind, target_id);

create table public.moderation_actions (
  id           bigint generated always as identity primary key,
  moderator_id uuid references public.profiles(id) on delete set null,
  report_id    uuid references public.reports(id) on delete set null,
  target_kind  text not null,
  target_id    uuid not null,
  action       text not null check (action in ('dismiss', 'hide', 'restore', 'remove', 'warn', 'ban')),
  note         text not null default '',
  created_at   timestamptz not null default now()
);

-- Three open reports on a post hide it until a moderator looks.
create or replace function public.auto_hide_reported_post()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.target_kind = 'post' and (
    new.reason = 'automated' or
    (select count(*) from public.reports where target_kind = 'post' and target_id = new.target_id and status = 'open') >= 3
  ) then
    update public.posts set hidden = true where id = new.target_id and not hidden;
  end if;
  return new;
end;
$$;
create trigger reports_auto_hide after insert on public.reports
  for each row execute function public.auto_hide_reported_post();

-- Clients may edit their post text but never moderation or counter columns.
-- The v0.2 counter trigger is re-issued so it raises the trusted flag first.
create or replace function public.bump_post_counter()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  col text := tg_argv[0];
  delta int := case when tg_op = 'INSERT' then 1 else -1 end;
  pid uuid := case when tg_op = 'INSERT' then new.post_id else old.post_id end;
begin
  perform set_config('sogym.trusted', '1', true);
  execute format('update public.posts set %I = greatest(0, %I + $1) where id = $2', col, col)
    using delta, pid;
  perform set_config('sogym.trusted', '', true);
  return coalesce(new, old);
end;
$$;

create or replace function public.protect_post_columns()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_moderator() and not public.trusted_write() then
    new.hidden := old.hidden;
    new.view_count := old.view_count;
    new.like_count := old.like_count;
    new.recommend_count := old.recommend_count;
    new.comment_count := old.comment_count;
  end if;
  return new;
end;
$$;
create trigger posts_protect before update on public.posts
  for each row execute function public.protect_post_columns();

-- ---------------------------------------------------------- notifications
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('follow', 'like', 'recommend', 'comment', 'try', 'coach', 'video', 'moderation', 'creator'));

-- Tell the author when their upload is playable or failed.
create or replace function public.notify_on_video_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('ready', 'failed') then
    insert into public.notifications (user_id, kind, post_id, preview)
    select new.author_id, 'video', p.id,
           case when new.status = 'ready' then 'Your video is live' else coalesce('Upload failed: ' || new.error, 'Upload failed') end
    from (select id from public.posts where video_id = new.id limit 1) p
    union all
    select new.author_id, 'video', null,
           case when new.status = 'ready' then 'Your video is live' else coalesce('Upload failed: ' || new.error, 'Upload failed') end
    where not exists (select 1 from public.posts where video_id = new.id);
  end if;
  return new;
end;
$$;
create trigger videos_notify after update on public.videos
  for each row execute function public.notify_on_video_status();

-- --------------------------------------------------------------- moderate
-- The only write path for reports. Applies the action, records it, resolves
-- every open report on the same target and tells the author when relevant.
create or replace function public.moderate(p_report uuid, p_action text, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare
  r public.reports%rowtype;
  target_author uuid;
  target_title text := '';
begin
  if not public.is_moderator() then
    raise exception 'moderators only' using errcode = '42501';
  end if;
  if p_action not in ('dismiss', 'hide', 'restore', 'remove', 'warn', 'ban') then
    raise exception 'unknown action %', p_action;
  end if;
  select * into r from public.reports where id = p_report;
  if r.id is null then
    raise exception 'report not found';
  end if;

  if r.target_kind = 'post' then
    select author_id, title into target_author, target_title from public.posts where id = r.target_id;
  elsif r.target_kind = 'comment' then
    select author_id, left(body, 80) into target_author, target_title from public.comments where id = r.target_id;
  else
    target_author := r.target_id;
  end if;

  if p_action = 'hide' and r.target_kind = 'post' then
    update public.posts set hidden = true where id = r.target_id;
  elsif p_action = 'restore' and r.target_kind = 'post' then
    update public.posts set hidden = false where id = r.target_id;
  elsif p_action = 'remove' then
    if r.target_kind = 'post' then
      update public.videos v set status = 'removed'
        from public.posts p where p.id = r.target_id and v.id = p.video_id;
      delete from public.posts where id = r.target_id;
    elsif r.target_kind = 'comment' then
      delete from public.comments where id = r.target_id;
    end if;
  elsif p_action = 'ban' then
    update public.profiles set banned = true, creator = false where id = target_author;
    update public.posts set hidden = true where author_id = target_author;
  end if;

  if p_action in ('remove', 'warn', 'ban') and target_author is not null then
    insert into public.notifications (user_id, kind, preview)
    values (target_author, 'moderation',
      left(case p_action
        when 'remove' then 'Removed: ' || target_title || case when p_note <> '' then ' · ' || p_note else '' end
        when 'warn' then 'Warning: ' || coalesce(nullif(p_note, ''), 'please keep it safe and on topic')
        else 'Your account was suspended' || case when p_note <> '' then ': ' || p_note else '' end
      end, 120));
  end if;

  insert into public.moderation_actions (moderator_id, report_id, target_kind, target_id, action, note)
  values (auth.uid(), p_report, r.target_kind, r.target_id, p_action, p_note);

  update public.reports
     set status = case when p_action = 'dismiss' then 'dismissed' else 'actioned' end,
         action = p_action, resolved_by = auth.uid(), resolved_at = now()
   where target_kind = r.target_kind and target_id = r.target_id and status = 'open';
end;
$$;

-- Approve or reject a creator application.
create or replace function public.approve_creator(p_user uuid, p_approve boolean, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then
    raise exception 'moderators only' using errcode = '42501';
  end if;
  update public.creator_applications
     set status = case when p_approve then 'approved' else 'rejected' end,
         reviewed_by = auth.uid(), reviewed_at = now()
   where user_id = p_user;
  if p_approve then
    update public.profiles set creator = true, creator_since = coalesce(creator_since, now()) where id = p_user;
  end if;
  insert into public.notifications (user_id, kind, preview)
  values (p_user, 'creator',
    case when p_approve then 'You are a creator now. Uploads are open.' else 'Creator application not approved' || case when p_note <> '' then ': ' || p_note else '' end end);
end;
$$;

-- Creator analytics in one call. Only the creator and moderators may read it.
create or replace function public.creator_stats(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  out jsonb;
begin
  if auth.uid() is distinct from p_user and not public.is_moderator() then
    raise exception 'own stats only' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'followers', (select follower_count from public.profiles where id = p_user),
    'following', (select following_count from public.profiles where id = p_user),
    'posts',      (select count(*) from public.posts where author_id = p_user),
    'views',      (select coalesce(sum(view_count), 0) from public.posts where author_id = p_user),
    'likes',      (select coalesce(sum(like_count), 0) from public.posts where author_id = p_user),
    'recommends', (select coalesce(sum(recommend_count), 0) from public.posts where author_id = p_user),
    'comments',   (select coalesce(sum(comment_count), 0) from public.posts where author_id = p_user),
    'tries',      (select coalesce(sum(try_count), 0) from public.routines where author_id = p_user),
    'viewsByDay', (
      select coalesce(jsonb_agg(c order by d), '[]'::jsonb) from (
        select d::date as d, (select count(*) from public.post_views v join public.posts p on p.id = v.post_id
                              where p.author_id = p_user and v.day = d::date) as c
        from generate_series(current_date - 6, current_date, interval '1 day') d
      ) s
    ),
    'topPosts', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'postId', p.id, 'title', p.title, 'kind', p.kind, 'views', p.view_count, 'likes', p.like_count,
        'comments', p.comment_count, 'recommends', p.recommend_count,
        'tries', coalesce((select try_count from public.routines r where r.id = p.routine_id), 0),
        'createdAt', p.created_at
      ) order by p.view_count desc, p.like_count desc), '[]'::jsonb)
      from (select * from public.posts where author_id = p_user order by view_count desc, like_count desc limit 20) p
    )
  ) into out;
  return out;
end;
$$;

-- --------------------------------------------------------------------- RLS
alter table public.creator_applications enable row level security;
alter table public.videos               enable row level security;
alter table public.post_views           enable row level security;
alter table public.reports              enable row level security;
alter table public.moderation_actions   enable row level security;

-- Hidden posts are visible to their author and to moderators only.
drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to authenticated
  using (not hidden or author_id = auth.uid() or public.is_moderator());

-- Banned accounts read but cannot write.
drop policy posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated
  with check (author_id = auth.uid() and like_count = 0 and recommend_count = 0 and comment_count = 0
              and view_count = 0 and not hidden and not public.is_banned()
              and (video_id is null or exists (select 1 from public.videos v where v.id = video_id and v.author_id = auth.uid())));
drop policy comments_insert on public.comments;
create policy comments_insert on public.comments for insert to authenticated
  with check (author_id = auth.uid() and not public.is_banned());

create policy creator_apps_read   on public.creator_applications for select to authenticated using (user_id = auth.uid() or public.is_moderator());
create policy creator_apps_insert on public.creator_applications for insert to authenticated with check (user_id = auth.uid() and status = 'pending');

-- videos: rows are created and updated by the edge function (service role).
create policy videos_read on public.videos for select to authenticated
  using (status <> 'removed' or author_id = auth.uid() or public.is_moderator());
create policy videos_update on public.videos for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());   -- exercise tags only; protected below

create or replace function public.protect_video_columns()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_moderator() and not public.trusted_write() then
    new.provider := old.provider; new.provider_uid := old.provider_uid; new.upload_id := old.upload_id;
    new.status := old.status; new.duration_sec := old.duration_sec; new.width := old.width; new.height := old.height;
    new.playback_url := old.playback_url; new.thumbnail_url := old.thumbnail_url; new.screen := old.screen;
    new.view_count := old.view_count; new.error := old.error; new.author_id := old.author_id;
  end if;
  return new;
end;
$$;
create trigger videos_protect before update on public.videos
  for each row execute function public.protect_video_columns();

-- post_views: written through record_view() only; authors see their own audience via creator_stats().

create policy reports_read   on public.reports for select to authenticated using (reporter_id = auth.uid() or public.is_moderator());
create policy reports_insert on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open' and reason <> 'automated' and not public.is_banned());

create policy mod_actions_read on public.moderation_actions for select to authenticated using (public.is_moderator());

revoke all on function public.approve_creator(uuid, boolean, text) from public, anon;
revoke all on function public.moderate(uuid, text, text) from public, anon;
revoke all on function public.creator_stats(uuid) from public, anon;
revoke all on function public.record_view(uuid) from public, anon;
grant execute on function public.approve_creator(uuid, boolean, text) to authenticated;
grant execute on function public.moderate(uuid, text, text) to authenticated;
grant execute on function public.creator_stats(uuid) to authenticated;
grant execute on function public.record_view(uuid) to authenticated;

-- Realtime: the feed refreshes when a video turns ready or a post is hidden.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.videos;
  end if;
end $$;

-- Feed query (client): posts.select('*, author:profiles(*), routine:routines(*), video:videos(*)')
