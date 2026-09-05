-- v0.5: user-first home. Public leagues that can be discovered from the
-- "+ Join a league nearby" menu. Distance ranking needs a coarse location the
-- app does not collect yet, so nearby_leagues() ranks public leagues by
-- members and recency; the area label is free text the owner sets.

alter table public.leagues
  add column if not exists is_public boolean not null default false,
  add column if not exists area      text    not null default '' check (char_length(area) <= 60);

create index if not exists leagues_public_idx on public.leagues (is_public) where is_public;

-- Anyone signed in can see public leagues (members and moderators already can).
drop policy if exists leagues_read on public.leagues;
create policy leagues_read on public.leagues for select to authenticated
  using (is_public or public.is_league_member(id) or public.is_moderator());

-- Owners flag a league public and give it an area label.
create or replace function public.set_league_public(p_league uuid, p_public boolean, p_area text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.leagues set is_public = p_public, area = left(coalesce(p_area, ''), 60)
   where id = p_league and owner_id = auth.uid();
  if not found then raise exception 'Only the owner can change that'; end if;
end $$;
grant execute on function public.set_league_public(uuid, boolean, text) to authenticated;

-- Public leagues the caller has not joined, with room left, busiest first.
create or replace function public.nearby_leagues()
returns table (
  id uuid, name text, emoji text, owner_id uuid, invite_code text, max_members int,
  created_at timestamptz, is_public boolean, area text, member_count bigint
) language sql stable security definer set search_path = public as $$
  select l.id, l.name, l.emoji, l.owner_id, l.invite_code, l.max_members, l.created_at, l.is_public, l.area,
         (select count(*) from public.league_members m where m.league_id = l.id) as member_count
    from public.leagues l
   where l.is_public
     and not exists (select 1 from public.league_members m where m.league_id = l.id and m.user_id = auth.uid())
     and (select count(*) from public.league_members m where m.league_id = l.id) < l.max_members
   order by member_count desc, l.created_at desc
   limit 30;
$$;
grant execute on function public.nearby_leagues() to authenticated;
