-- SoGym v0.4: steps leagues, streaks and badges.
-- Synced step days, workout logs, weekly leagues with invite codes, a weekly
-- close that ranks members and notifies them, streak math, and a badge
-- catalogue awarded by one function after every sync or logged workout.

-- --------------------------------------------------------------- step days
-- One row per member per day, pushed from HealthKit / Health Connect through
-- sync_steps(). Never written directly by clients.
create table public.step_days (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  day        date not null,
  steps      int not null check (steps between 0 and 200000),
  source     text not null default 'health' check (source in ('health', 'demo', 'manual')),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);
create index step_days_day_idx on public.step_days (day);

-- ------------------------------------------------------------ workout logs
create table public.workout_logs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  routine_id   uuid references public.routines(id) on delete set null,
  routine_name text not null default '',
  day_title    text not null default '',
  duration_sec int not null default 0 check (duration_sec between 0 and 86400),
  sets         int not null default 0 check (sets between 0 and 500),
  completed_at timestamptz not null default now()
);
create index workout_logs_user_idx on public.workout_logs (user_id, completed_at desc);

-- ----------------------------------------------------------------- leagues
create or replace function public.gen_invite_code()
returns text language sql volatile as $$
  select upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 6));
$$;

create table public.leagues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 40),
  emoji       text not null default '🏆',
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  invite_code text not null unique default public.gen_invite_code(),
  max_members int not null default 20 check (max_members between 2 and 50),
  created_at  timestamptz not null default now()
);

create table public.league_members (
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index league_members_user_idx on public.league_members (user_id);

-- Written by close_week() every Monday.
create table public.league_results (
  league_id  uuid not null references public.leagues(id) on delete cascade,
  week_start date not null,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  rank       int not null,
  steps      int not null,
  primary key (league_id, week_start, user_id)
);
create index league_results_user_idx on public.league_results (user_id, week_start desc);

-- ------------------------------------------------------------------ badges
create table public.badges (
  code        text primary key,
  name        text not null,
  emoji       text not null,
  description text not null,
  tier        int not null default 1 check (tier between 1 and 3)
);

insert into public.badges (code, name, emoji, description, tier) values
  ('first_workout',  'First rep',        '🏁', 'Finished a workout in the player', 1),
  ('workouts_10',    'Regular',          '🔟', 'Ten workouts logged', 2),
  ('workouts_50',    'Fixture',          '💪', 'Fifty workouts logged', 3),
  ('step_streak_7',  'One week on foot', '🔥', 'Hit your step goal seven days running', 1),
  ('step_streak_30', 'Thirty on foot',   '🌋', 'Hit your step goal thirty days running', 3),
  ('week_100k',      '100k week',        '👟', 'A hundred thousand steps in one week', 2),
  ('first_post',     'Said hello',       '📣', 'Shared something with the gym', 1),
  ('first_video',    'On camera',        '🎬', 'Posted a clip', 2),
  ('tried_10',       'Copied',           '📋', 'Ten people tried your routines', 2),
  ('league_win',     'League winner',    '🥇', 'Finished first in a weekly league', 2),
  ('league_podium',  'Podium',           '🏅', 'Finished top three in a weekly league', 1),
  ('early_bird',     'Early bird',       '🌅', 'Finished a workout before 7 am', 1);

create table public.user_badges (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  badge     text not null references public.badges(code) on delete cascade,
  earned_at timestamptz not null default now(),
  meta      jsonb not null default '{}'::jsonb,
  primary key (user_id, badge)
);
create index user_badges_user_idx on public.user_badges (user_id, earned_at desc);

-- ----------------------------------------------------------- notifications
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('follow', 'like', 'recommend', 'comment', 'try', 'coach', 'video', 'moderation', 'creator', 'league', 'badge'));

-- ----------------------------------------------------------------- streaks
-- Consecutive days (ending today or yesterday) at or above the step goal.
create or replace function public.step_streak(p_user uuid)
returns int language plpgsql stable security definer set search_path = public as $$
declare
  goal int;
  d date := current_date;
  n int := 0;
  s int;
begin
  select step_goal into goal from public.profiles where id = p_user;
  if goal is null then return 0; end if;
  -- Today may still be in progress: a miss today does not break the streak.
  select steps into s from public.step_days where user_id = p_user and day = d;
  if s is null or s < goal then d := d - 1; end if;
  loop
    select steps into s from public.step_days where user_id = p_user and day = d;
    exit when s is null or s < goal;
    n := n + 1;
    d := d - 1;
    exit when n > 3660;
  end loop;
  return n;
end;
$$;

-- Longest run of goal days ever.
create or replace function public.step_streak_best(p_user uuid)
returns int language plpgsql stable security definer set search_path = public as $$
declare
  goal int;
  best int := 0;
  run int := 0;
  prev date;
  r record;
begin
  select step_goal into goal from public.profiles where id = p_user;
  if goal is null then return 0; end if;
  for r in select day, steps from public.step_days where user_id = p_user order by day loop
    if r.steps >= goal and (prev is null or r.day = prev + 1) then
      run := run + 1;
    elsif r.steps >= goal then
      run := 1;
    else
      run := 0;
    end if;
    best := greatest(best, run);
    prev := r.day;
  end loop;
  return best;
end;
$$;

-- Consecutive weeks (ending this week or last) with at least days_per_week workouts.
create or replace function public.workout_streak(p_user uuid)
returns int language plpgsql stable security definer set search_path = public as $$
declare
  need int;
  wk date := date_trunc('week', current_date)::date;
  n int := 0;
  c int;
begin
  select days_per_week into need from public.profiles where id = p_user;
  if need is null then return 0; end if;
  select count(*) into c from public.workout_logs where user_id = p_user and completed_at >= wk and completed_at < wk + 7;
  if c < need then wk := wk - 7; end if;   -- this week still in progress
  loop
    select count(*) into c from public.workout_logs where user_id = p_user and completed_at >= wk and completed_at < wk + 7;
    exit when c < need;
    n := n + 1;
    wk := wk - 7;
    exit when n > 520;
  end loop;
  return n;
end;
$$;

create or replace function public.my_streaks()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'stepStreak', public.step_streak(auth.uid()),
    'stepBest', public.step_streak_best(auth.uid()),
    'workoutStreak', public.workout_streak(auth.uid()),
    'weekWorkouts', (select count(*) from public.workout_logs
                     where user_id = auth.uid() and completed_at >= date_trunc('week', current_date)),
    'weekSteps', (select coalesce(sum(steps), 0) from public.step_days
                  where user_id = auth.uid() and day >= date_trunc('week', current_date)::date),
    'totalWorkouts', (select count(*) from public.workout_logs where user_id = auth.uid())
  );
$$;

-- ------------------------------------------------------------------ badges
-- Evaluates every rule for one member, inserts what is new, notifies, and
-- returns the codes just earned. Cheap enough to run after every sync.
create or replace function public.award_badges(p_user uuid)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  earned text[] := '{}';
  bcode text;
  candidates text[] := '{}';
  workouts int;
  tries int;
begin
  select count(*) into workouts from public.workout_logs where user_id = p_user;
  if workouts >= 1 then candidates := array_append(candidates, 'first_workout'); end if;
  if workouts >= 10 then candidates := array_append(candidates, 'workouts_10'); end if;
  if workouts >= 50 then candidates := array_append(candidates, 'workouts_50'); end if;
  if public.step_streak_best(p_user) >= 7 then candidates := array_append(candidates, 'step_streak_7'); end if;
  if public.step_streak_best(p_user) >= 30 then candidates := array_append(candidates, 'step_streak_30'); end if;
  if exists (select 1 from public.step_days where user_id = p_user
             group by date_trunc('week', day) having sum(steps) >= 100000) then
    candidates := array_append(candidates, 'week_100k');
  end if;
  if exists (select 1 from public.posts where author_id = p_user) then candidates := array_append(candidates, 'first_post'); end if;
  if exists (select 1 from public.posts where author_id = p_user and kind = 'video') then candidates := array_append(candidates, 'first_video'); end if;
  select coalesce(sum(try_count), 0) into tries from public.routines where author_id = p_user;
  if tries >= 10 then candidates := array_append(candidates, 'tried_10'); end if;
  if exists (select 1 from public.league_results where user_id = p_user and rank = 1) then candidates := array_append(candidates, 'league_win'); end if;
  if exists (select 1 from public.league_results where user_id = p_user and rank <= 3) then candidates := array_append(candidates, 'league_podium'); end if;
  if exists (select 1 from public.workout_logs where user_id = p_user and extract(hour from completed_at at time zone 'utc') < 7) then
    candidates := array_append(candidates, 'early_bird');
  end if;

  foreach bcode in array candidates loop
    insert into public.user_badges (user_id, badge) values (p_user, bcode) on conflict do nothing;
    if found then
      earned := array_append(earned, bcode);
      insert into public.notifications (user_id, kind, preview)
      select p_user, 'badge', b.emoji || ' ' || b.name || ': ' || b.description from public.badges b where b.code = bcode;
    end if;
  end loop;
  return earned;
end;
$$;

-- --------------------------------------------------------------- sync APIs
-- p_days: [{"day": "2026-09-04", "steps": 8123, "source": "health"}, ...]
create or replace function public.sync_steps(p_days jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  d jsonb;
begin
  if auth.uid() is null then raise exception 'sign in' using errcode = '42501'; end if;
  if jsonb_typeof(p_days) <> 'array' or jsonb_array_length(p_days) > 400 then
    raise exception 'p_days must be an array of at most 400 days';
  end if;
  for d in select * from jsonb_array_elements(p_days) loop
    insert into public.step_days (user_id, day, steps, source)
    values (auth.uid(), (d ->> 'day')::date, least(greatest((d ->> 'steps')::int, 0), 200000), coalesce(d ->> 'source', 'health'))
    on conflict (user_id, day) do update
      set steps = excluded.steps, source = excluded.source, updated_at = now()
      where public.step_days.steps <> excluded.steps;
  end loop;
  return jsonb_build_object('badges', to_jsonb(public.award_badges(auth.uid())), 'streaks', public.my_streaks());
end;
$$;

create or replace function public.log_workout(p_routine uuid, p_routine_name text, p_day_title text, p_duration_sec int, p_sets int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then raise exception 'sign in' using errcode = '42501'; end if;
  insert into public.workout_logs (user_id, routine_id, routine_name, day_title, duration_sec, sets)
  values (auth.uid(), p_routine, left(coalesce(p_routine_name, ''), 80), left(coalesce(p_day_title, ''), 80),
          least(greatest(coalesce(p_duration_sec, 0), 0), 86400), least(greatest(coalesce(p_sets, 0), 0), 500))
  returning id into new_id;
  return jsonb_build_object('id', new_id, 'badges', to_jsonb(public.award_badges(auth.uid())), 'streaks', public.my_streaks());
end;
$$;

-- ---------------------------------------------------------------- leagues
create or replace function public.create_league(p_name text, p_emoji text default '🏆')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then raise exception 'sign in' using errcode = '42501'; end if;
  if (select count(*) from public.league_members where user_id = auth.uid()) >= 10 then
    raise exception 'You are already in ten leagues';
  end if;
  insert into public.leagues (name, emoji, owner_id) values (left(p_name, 40), coalesce(nullif(p_emoji, ''), '🏆'), auth.uid())
  returning id into new_id;
  insert into public.league_members (league_id, user_id) values (new_id, auth.uid());
  return new_id;
end;
$$;

create or replace function public.join_league(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  l public.leagues%rowtype;
  n int;
begin
  if auth.uid() is null then raise exception 'sign in' using errcode = '42501'; end if;
  select * into l from public.leagues where invite_code = upper(trim(p_code));
  if l.id is null then raise exception 'No league with that code'; end if;
  select count(*) into n from public.league_members where league_id = l.id;
  if n >= l.max_members then raise exception 'That league is full'; end if;
  insert into public.league_members (league_id, user_id) values (l.id, auth.uid()) on conflict do nothing;
  return l.id;
end;
$$;

create or replace function public.leave_league(p_league uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.league_members where league_id = p_league and user_id = auth.uid();
  -- An empty league disappears; an owner leaving hands the league to the earliest member.
  if not exists (select 1 from public.league_members where league_id = p_league) then
    delete from public.leagues where id = p_league;
  else
    update public.leagues set owner_id = (select user_id from public.league_members where league_id = p_league order by joined_at limit 1)
      where id = p_league and owner_id = auth.uid();
  end if;
end;
$$;

-- Standings for one week (default: the current one). Members only.
-- [{userId, name, handle, emoji, steps, days:[7], rank}]
create or replace function public.league_standings(p_league uuid, p_week_start date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  wk date := coalesce(p_week_start, date_trunc('week', current_date)::date);
  out jsonb;
begin
  if auth.uid() is not null and not exists (select 1 from public.league_members where league_id = p_league and user_id = auth.uid()) and not public.is_moderator() then
    raise exception 'members only' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(row_to_json(s) order by s.rank), '[]'::jsonb) into out from (
    select p.id as "userId", p.name, p.handle, p.emoji,
           coalesce(sum(sd.steps), 0)::int as steps,
           (select coalesce(jsonb_agg(coalesce(x.steps, 0) order by g.d), '[]'::jsonb)
              from generate_series(wk, wk + 6, interval '1 day') g(d)
              left join public.step_days x on x.user_id = p.id and x.day = g.d::date) as days,
           rank() over (order by coalesce(sum(sd.steps), 0) desc, p.handle) as rank
    from public.league_members m
    join public.profiles p on p.id = m.user_id
    left join public.step_days sd on sd.user_id = p.id and sd.day >= wk and sd.day < wk + 7
    where m.league_id = p_league
    group by p.id, p.name, p.handle, p.emoji
  ) s;
  return out;
end;
$$;

-- Ranks every league for the week that just ended, records results, tells
-- members, awards podium badges. Scheduled Monday 00:05 UTC by pg_cron;
-- moderators may run it by hand.
create or replace function public.close_week(p_week_start date default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  wk date := coalesce(p_week_start, date_trunc('week', current_date)::date - 7);
  l record;
  s jsonb;
  row jsonb;
  total int;
  closed int := 0;
begin
  if auth.uid() is not null and not public.is_moderator() then
    raise exception 'moderators only' using errcode = '42501';
  end if;
  for l in select id, name, emoji from public.leagues loop
    if exists (select 1 from public.league_results where league_id = l.id and week_start = wk) then continue; end if;
    s := public.league_standings(l.id, wk);
    total := jsonb_array_length(s);
    if total = 0 then continue; end if;
    for row in select * from jsonb_array_elements(s) loop
      insert into public.league_results (league_id, week_start, user_id, rank, steps)
      values (l.id, wk, (row ->> 'userId')::uuid, (row ->> 'rank')::int, (row ->> 'steps')::int);
      insert into public.notifications (user_id, kind, preview)
      values ((row ->> 'userId')::uuid, 'league',
              left(l.emoji || ' ' || l.name || ': you finished ' || (row ->> 'rank') || ' of ' || total || ' with ' ||
                   to_char((row ->> 'steps')::int, 'FM999,999,999') || ' steps', 120));
      perform public.award_badges((row ->> 'userId')::uuid);
    end loop;
    closed := closed + 1;
  end loop;
  return closed;
end;
$$;

-- Compact summary for watch complications and the Me tab:
-- [{leagueId, name, emoji, rank, of, steps, leaderSteps, daysLeft}]
create or replace function public.my_league_ranks()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  out jsonb := '[]'::jsonb;
  l record;
  s jsonb;
  mine jsonb;
  days_left int := 7 - extract(isodow from current_date)::int + 1;
begin
  if auth.uid() is null then return out; end if;
  for l in select lg.id, lg.name, lg.emoji from public.leagues lg join public.league_members m on m.league_id = lg.id where m.user_id = auth.uid() loop
    s := public.league_standings(l.id);
    select e into mine from jsonb_array_elements(s) e where e ->> 'userId' = auth.uid()::text;
    out := out || jsonb_build_object(
      'leagueId', l.id, 'name', l.name, 'emoji', l.emoji,
      'rank', coalesce((mine ->> 'rank')::int, 0), 'of', jsonb_array_length(s),
      'steps', coalesce((mine ->> 'steps')::int, 0),
      'leaderSteps', coalesce((s -> 0 ->> 'steps')::int, 0),
      'daysLeft', days_left);
  end loop;
  return out;
end;
$$;

-- --------------------------------------------------------------------- RLS
alter table public.step_days      enable row level security;
alter table public.workout_logs   enable row level security;
alter table public.leagues        enable row level security;
alter table public.league_members enable row level security;
alter table public.league_results enable row level security;
alter table public.badges         enable row level security;
alter table public.user_badges    enable row level security;

create or replace function public.shares_league_with(p_other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_other = auth.uid() or exists (
    select 1 from public.league_members a join public.league_members b on a.league_id = b.league_id
    where a.user_id = auth.uid() and b.user_id = p_other);
$$;

create or replace function public.is_league_member(p_league uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.league_members where league_id = p_league and user_id = auth.uid());
$$;

-- step days: mine, and league-mates' (that is what a league is). Writes via sync_steps only.
create policy step_days_read on public.step_days for select to authenticated using (public.shares_league_with(user_id));

-- workout logs: private. Writes via log_workout only.
create policy workout_logs_read on public.workout_logs for select to authenticated using (user_id = auth.uid());

-- leagues: members read; owner renames; creation and joining go through functions.
create policy leagues_read   on public.leagues for select to authenticated using (public.is_league_member(id) or public.is_moderator());
create policy leagues_update on public.leagues for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy leagues_delete on public.leagues for delete to authenticated using (owner_id = auth.uid());

create policy league_members_read   on public.league_members for select to authenticated using (public.is_league_member(league_id) or public.is_moderator());
create policy league_members_delete on public.league_members for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.leagues l where l.id = league_id and l.owner_id = auth.uid()));

create policy league_results_read on public.league_results for select to authenticated using (public.is_league_member(league_id) or user_id = auth.uid());

create policy badges_read      on public.badges for select to authenticated using (true);
create policy user_badges_read on public.user_badges for select to authenticated using (true);

revoke all on function public.award_badges(uuid) from public, anon, authenticated;
revoke all on function public.close_week(date) from public, anon;
revoke all on function public.sync_steps(jsonb) from public, anon;
revoke all on function public.log_workout(uuid, text, text, int, int) from public, anon;
revoke all on function public.create_league(text, text) from public, anon;
revoke all on function public.join_league(text) from public, anon;
revoke all on function public.leave_league(uuid) from public, anon;
revoke all on function public.league_standings(uuid, date) from public, anon;
revoke all on function public.my_streaks() from public, anon;
revoke all on function public.my_league_ranks() from public, anon;
grant execute on function public.award_badges(uuid) to service_role;
grant execute on function public.close_week(date) to authenticated, service_role;
grant execute on function public.sync_steps(jsonb) to authenticated;
grant execute on function public.log_workout(uuid, text, text, int, int) to authenticated;
grant execute on function public.create_league(text, text) to authenticated;
grant execute on function public.join_league(text) to authenticated;
grant execute on function public.leave_league(uuid) to authenticated;
grant execute on function public.league_standings(uuid, date) to authenticated;
grant execute on function public.my_streaks() to authenticated;
grant execute on function public.my_league_ranks() to authenticated;

-- ---------------------------------------------------------------- schedule
-- Supabase ships pg_cron; close last week's leagues every Monday 00:05 UTC.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('sogym-close-week', '5 0 * * 1', $cron$select public.close_week()$cron$);
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.league_members, public.user_badges;
  end if;
end $$;
