-- SoGym v0.2: real social graph.
-- Users, follows, routines, posts, likes, recommends, comments, routine tries,
-- notifications, coach quotas and event log, push tokens.
--
-- Conventions
--   * Every table has row level security on. Reads are public inside the app,
--     writes are restricted to the row owner. Counters and notifications are
--     maintained by triggers so clients never write them directly.
--   * JSON shapes (routine days, notification payloads) match the Flutter
--     models in lib/core/models.dart so the client needs no mapping layer.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  handle           text not null unique check (handle ~ '^[a-z0-9_.]{2,30}$'),
  name             text not null check (char_length(name) between 1 and 60),
  emoji            text not null default '🙂',
  bio              text not null default '' check (char_length(bio) <= 200),
  goal             text not null default 'generalHealth',
  diet             text[] not null default '{}',
  equipment        text[] not null default '{}',
  height_cm        numeric(5,1),
  weight_kg        numeric(5,1),
  target_weight_kg numeric(5,1),
  age              int check (age is null or age between 13 and 120),
  days_per_week    int not null default 3 check (days_per_week between 1 and 7),
  step_goal        int not null default 8000 check (step_goal between 1000 and 100000),
  plus             boolean not null default false,
  follower_count   int not null default 0,
  following_count  int not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.profiles is 'Public athlete profile. One row per auth user, created by trigger.';

-- Create a profile row the moment a user signs up. Handle comes from the
-- sign-up metadata when the client provides one, otherwise a short random one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  wanted text := lower(coalesce(new.raw_user_meta_data ->> 'handle', ''));
  chosen text;
begin
  if wanted !~ '^[a-z0-9_.]{2,30}$' then
    wanted := 'athlete_' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;
  chosen := wanted;
  -- Resolve collisions by suffixing a counter.
  for i in 1..20 loop
    exit when not exists (select 1 from public.profiles where handle = chosen);
    chosen := left(wanted, 26) || '_' || i;
  end loop;
  insert into public.profiles (id, handle, name, emoji)
  values (
    new.id,
    chosen,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(coalesce(new.email, 'Athlete'), '@', 1)),
    coalesce(nullif(new.raw_user_meta_data ->> 'emoji', ''), '🙂')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------- follows
create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followee_id uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index follows_followee_idx on public.follows (followee_id);

-- ---------------------------------------------------------------- routines
create table public.routines (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references public.profiles(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 80),
  description text not null default '',
  -- [{title, focus, items:[{exerciseId, exerciseName, sets, reps, restSec, notes}]}]
  days        jsonb not null default '[]'::jsonb check (jsonb_typeof(days) = 'array'),
  tags        text[] not null default '{}',
  source      text not null default 'me' check (source in ('me', 'ai', 'community')),
  forked_from uuid references public.routines(id) on delete set null,
  try_count   int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index routines_author_idx on public.routines (author_id, created_at desc);
create trigger routines_touch before update on public.routines
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------------- posts
create table public.posts (
  id              uuid primary key default gen_random_uuid(),
  author_id       uuid not null references public.profiles(id) on delete cascade,
  kind            text not null check (kind in ('workout', 'routine', 'steps', 'video', 'diet', 'weird')),
  title           text not null check (char_length(title) between 1 and 140),
  body            text not null default '' check (char_length(body) <= 2000),
  routine_id      uuid references public.routines(id) on delete set null,
  video_url       text,
  steps           int check (steps is null or steps between 0 and 200000),
  hot             boolean not null default false,
  tags            text[] not null default '{}',
  like_count      int not null default 0,
  recommend_count int not null default 0,
  comment_count   int not null default 0,
  created_at      timestamptz not null default now()
);
create index posts_created_idx on public.posts (created_at desc);
create index posts_author_idx on public.posts (author_id, created_at desc);
create index posts_kind_idx on public.posts (kind, created_at desc);

-- ------------------------------------------------------- likes / recommends
create table public.likes (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index likes_user_idx on public.likes (user_id);

create table public.recommends (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index recommends_user_idx on public.recommends (user_id);

-- ---------------------------------------------------------------- comments
create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);

-- ------------------------------------------------------------ routine tries
-- "Try it": a user copied someone else's routine into their library.
create table public.routine_tries (
  routine_id uuid not null references public.routines(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (routine_id, user_id)
);

-- ----------------------------------------------------------- notifications
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  actor_id   uuid references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('follow', 'like', 'recommend', 'comment', 'try', 'coach')),
  post_id    uuid references public.posts(id) on delete cascade,
  routine_id uuid references public.routines(id) on delete cascade,
  preview    text not null default '',
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, read, created_at desc);

-- ------------------------------------------------------------- coach usage
-- Weekly message quota, written only by the coach edge function (service role).
create table public.coach_usage (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  week_start date not null,
  messages   int not null default 0,
  primary key (user_id, week_start)
);

-- Tool-call and reply log for evals and abuse review. Service role only.
create table public.coach_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  request_id uuid not null,
  kind       text not null check (kind in ('request', 'tool_use', 'tool_result', 'reply', 'refusal', 'error')),
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index coach_events_user_idx on public.coach_events (user_id, created_at desc);

-- -------------------------------------------------------------- push tokens
create table public.push_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null check (platform in ('ios', 'android', 'web')),
  updated_at timestamptz not null default now()
);
create index push_tokens_user_idx on public.push_tokens (user_id);

-- ======================================================== counter triggers
create or replace function public.bump_post_counter()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  col text := tg_argv[0];
  delta int := case when tg_op = 'INSERT' then 1 else -1 end;
  pid uuid := case when tg_op = 'INSERT' then new.post_id else old.post_id end;
begin
  execute format('update public.posts set %I = greatest(0, %I + $1) where id = $2', col, col)
    using delta, pid;
  return coalesce(new, old);
end;
$$;

create trigger likes_counter after insert or delete on public.likes
  for each row execute function public.bump_post_counter('like_count');
create trigger recommends_counter after insert or delete on public.recommends
  for each row execute function public.bump_post_counter('recommend_count');
create trigger comments_counter after insert or delete on public.comments
  for each row execute function public.bump_post_counter('comment_count');

create or replace function public.bump_follow_counters()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  delta int := case when tg_op = 'INSERT' then 1 else -1 end;
  r record := coalesce(new, old);
begin
  update public.profiles set follower_count = greatest(0, follower_count + delta) where id = r.followee_id;
  update public.profiles set following_count = greatest(0, following_count + delta) where id = r.follower_id;
  return r;
end;
$$;

create trigger follows_counter after insert or delete on public.follows
  for each row execute function public.bump_follow_counters();

create or replace function public.bump_try_counter()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.routines set try_count = try_count + 1 where id = new.routine_id;
  return new;
end;
$$;

create trigger routine_tries_counter after insert on public.routine_tries
  for each row execute function public.bump_try_counter();

-- =================================================== notification triggers
-- One trigger function per social action. Self-actions never notify.
create or replace function public.notify_on_follow()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, actor_id, kind)
  values (new.followee_id, new.follower_id, 'follow');
  return new;
end;
$$;
create trigger follows_notify after insert on public.follows
  for each row execute function public.notify_on_follow();

create or replace function public.notify_on_post_action()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  kind text := tg_argv[0];
  row jsonb := to_jsonb(new);
  p record;
  -- likes/recommends carry user_id, comments carry author_id.
  actor uuid := coalesce(row ->> 'user_id', row ->> 'author_id')::uuid;
  preview text := '';
begin
  select author_id, title into p from public.posts where id = new.post_id;
  if p.author_id is null or p.author_id = actor then
    return new;
  end if;
  if kind = 'comment' then
    preview := left(row ->> 'body', 120);
  else
    preview := left(p.title, 120);
  end if;
  insert into public.notifications (user_id, actor_id, kind, post_id, preview)
  values (p.author_id, actor, kind, new.post_id, preview);
  return new;
end;
$$;

create trigger likes_notify after insert on public.likes
  for each row execute function public.notify_on_post_action('like');
create trigger recommends_notify after insert on public.recommends
  for each row execute function public.notify_on_post_action('recommend');
create trigger comments_notify after insert on public.comments
  for each row execute function public.notify_on_post_action('comment');

create or replace function public.notify_on_try()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  select author_id, name into r from public.routines where id = new.routine_id;
  if r.author_id is null or r.author_id = new.user_id then
    return new;
  end if;
  insert into public.notifications (user_id, actor_id, kind, routine_id, preview)
  values (r.author_id, new.user_id, 'try', new.routine_id, left(r.name, 120));
  return new;
end;
$$;
create trigger routine_tries_notify after insert on public.routine_tries
  for each row execute function public.notify_on_try();

-- ======================================================== row level security
alter table public.profiles       enable row level security;
alter table public.follows        enable row level security;
alter table public.routines       enable row level security;
alter table public.posts          enable row level security;
alter table public.likes          enable row level security;
alter table public.recommends     enable row level security;
alter table public.comments       enable row level security;
alter table public.routine_tries  enable row level security;
alter table public.notifications  enable row level security;
alter table public.coach_usage    enable row level security;
alter table public.coach_events   enable row level security;
alter table public.push_tokens    enable row level security;

-- profiles: everyone signed in can read, only the owner can edit.
create policy profiles_read   on public.profiles for select to authenticated using (true);
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid() and plus = (select plus from public.profiles where id = auth.uid()));

-- follows
create policy follows_read   on public.follows for select to authenticated using (true);
create policy follows_insert on public.follows for insert to authenticated with check (follower_id = auth.uid());
create policy follows_delete on public.follows for delete to authenticated using (follower_id = auth.uid());

-- routines: public catalogue, owner writes. try_count is trigger-owned.
create policy routines_read   on public.routines for select to authenticated using (true);
create policy routines_insert on public.routines for insert to authenticated with check (author_id = auth.uid());
create policy routines_update on public.routines for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy routines_delete on public.routines for delete to authenticated using (author_id = auth.uid());

-- posts: counters are trigger-owned; clients may only edit text fields of their own posts.
create policy posts_read   on public.posts for select to authenticated using (true);
create policy posts_insert on public.posts for insert to authenticated
  with check (author_id = auth.uid() and like_count = 0 and recommend_count = 0 and comment_count = 0);
create policy posts_update on public.posts for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy posts_delete on public.posts for delete to authenticated using (author_id = auth.uid());

-- likes / recommends / comments / tries
create policy likes_read   on public.likes for select to authenticated using (true);
create policy likes_insert on public.likes for insert to authenticated with check (user_id = auth.uid());
create policy likes_delete on public.likes for delete to authenticated using (user_id = auth.uid());

create policy recommends_read   on public.recommends for select to authenticated using (true);
create policy recommends_insert on public.recommends for insert to authenticated with check (user_id = auth.uid());
create policy recommends_delete on public.recommends for delete to authenticated using (user_id = auth.uid());

create policy comments_read   on public.comments for select to authenticated using (true);
create policy comments_insert on public.comments for insert to authenticated with check (author_id = auth.uid());
create policy comments_delete on public.comments for delete to authenticated using (author_id = auth.uid());

create policy tries_read   on public.routine_tries for select to authenticated using (true);
create policy tries_insert on public.routine_tries for insert to authenticated with check (user_id = auth.uid());

-- notifications: private to the recipient; they may only mark read.
create policy notifications_read   on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- coach usage: read own quota; writes are service role only (no policy).
create policy coach_usage_read on public.coach_usage for select to authenticated using (user_id = auth.uid());

-- coach events: service role only.

-- push tokens: owner manages their devices.
create policy push_tokens_all on public.push_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ================================================================ helpers
-- Weekly quota check used by the coach function. Returns remaining messages
-- (a large number for Plus members) and increments the counter atomically.
create or replace function public.consume_coach_message(p_user uuid, p_free_per_week int default 5)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  is_plus boolean;
  wk date := date_trunc('week', now())::date;
  used int;
begin
  select plus into is_plus from public.profiles where id = p_user;
  if is_plus is null then
    raise exception 'unknown user';
  end if;
  insert into public.coach_usage (user_id, week_start, messages)
  values (p_user, wk, 1)
  on conflict (user_id, week_start) do update set messages = public.coach_usage.messages + 1
  returning messages into used;
  if is_plus then
    return 1000000;
  end if;
  if used > p_free_per_week then
    -- Roll back the increment so a blocked message is not counted.
    update public.coach_usage set messages = messages - 1 where user_id = p_user and week_start = wk;
    return 0;
  end if;
  return p_free_per_week - used;
end;
$$;

-- Supabase grants execute on new public functions to anon/authenticated by default; take it back.
revoke all on function public.consume_coach_message(uuid, int) from public, anon, authenticated;
grant execute on function public.consume_coach_message(uuid, int) to service_role;

-- Feed query: newest posts with author and routine embedded. PostgREST embeds
-- these through the foreign keys, so the client uses
--   posts.select('*, author:profiles(*), routine:routines(*)')
-- No view needed.

-- Realtime: broadcast changes so open feeds refresh.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.posts, public.notifications, public.comments;
  end if;
end $$;
