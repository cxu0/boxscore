-- Join flow v2, stat-keeper delegation, public join.
-- Additive to 0001–0003. Run against a database that already has them.

-- ============================================================
-- leagues: caps, staff code, join policy
-- ============================================================
alter table public.leagues
  add column if not exists allow_player_teams boolean not null default true;
alter table public.leagues
  add column if not exists max_teams int;
alter table public.leagues
  add column if not exists max_roster_size int;
alter table public.leagues
  add column if not exists join_policy text not null default 'open'
  check (join_policy in ('open', 'approval'));

alter table public.leagues add column if not exists staff_code text;
update public.leagues
  set staff_code = upper(substr(md5(random()::text || id::text), 1, 6))
  where staff_code is null;
alter table public.leagues alter column staff_code set not null;
alter table public.leagues
  add constraint leagues_staff_code_unique unique (staff_code);
alter table public.leagues
  alter column staff_code set default upper(substr(md5(random()::text), 1, 6));

-- ============================================================
-- league_staff: accounts allowed to keep stats for a league
-- ============================================================
create table public.league_staff (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (league_id, profile_id)
);

alter table public.league_staff enable row level security;

create policy "staff visible to self or league owner"
  on public.league_staff for select
  to authenticated
  using (
    profile_id = auth.uid()
    or exists (select 1 from public.leagues l where l.id = league_staff.league_id and l.owner_id = auth.uid())
  );

create policy "league owner removes staff"
  on public.league_staff for delete
  to authenticated
  using (exists (select 1 from public.leagues l where l.id = league_staff.league_id and l.owner_id = auth.uid()));

-- ============================================================
-- can_keep_stats: owner OR designated stat keeper
-- ============================================================
create or replace function public.can_keep_stats(p_league_id uuid)
returns boolean
language sql
security definer set search_path = public
as $$
  select exists (select 1 from public.leagues where id = p_league_id and owner_id = auth.uid())
      or exists (select 1 from public.league_staff where league_id = p_league_id and profile_id = auth.uid());
$$;

-- box_scores: stat keepers (not just owners) can manage
drop policy if exists "league owners manage box scores" on public.box_scores;
create policy "stat keepers manage box scores"
  on public.box_scores for all
  to authenticated
  using (exists (
    select 1 from public.games g
    join public.seasons s on s.id = g.season_id
    where g.id = box_scores.game_id and public.can_keep_stats(s.league_id)
  ))
  with check (exists (
    select 1 from public.games g
    join public.seasons s on s.id = g.season_id
    where g.id = box_scores.game_id and public.can_keep_stats(s.league_id)
  ));

-- set_game_result: allow stat keepers, not only owners
create or replace function public.set_game_result(
  p_game_id uuid,
  p_home_score int,
  p_away_score int
)
returns public.games
language plpgsql
security definer set search_path = public
as $$
declare
  v_league_id uuid;
  v_game public.games;
begin
  select s.league_id into v_league_id
  from public.games g
  join public.seasons s on s.id = g.season_id
  where g.id = p_game_id;

  if v_league_id is null or not public.can_keep_stats(v_league_id) then
    raise exception 'Not allowed to set this game result';
  end if;

  update public.games
  set home_score = p_home_score, away_score = p_away_score, status = 'final'
  where id = p_game_id
  returning * into v_game;

  return v_game;
end;
$$;

create function public.redeem_staff_code(p_code text)
returns public.leagues
language plpgsql
security definer set search_path = public
as $$
declare
  v_league public.leagues;
begin
  select * into v_league from public.leagues where staff_code = p_code;
  if v_league.id is null then
    raise exception 'Invalid stat-keeper code';
  end if;

  insert into public.league_staff (league_id, profile_id)
  values (v_league.id, auth.uid())
  on conflict (league_id, profile_id) do nothing;

  return v_league;
end;
$$;

grant execute on function public.redeem_staff_code(text) to authenticated;

create function public.regenerate_staff_code(p_league_id uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_code text;
begin
  if not exists (select 1 from public.leagues where id = p_league_id and owner_id = auth.uid()) then
    raise exception 'Only the league owner can regenerate the stat-keeper code';
  end if;
  v_code := upper(substr(md5(random()::text || p_league_id::text || clock_timestamp()::text), 1, 6));
  update public.leagues set staff_code = v_code where id = p_league_id;
  return v_code;
end;
$$;

grant execute on function public.regenerate_staff_code(uuid) to authenticated;

grant execute on function public.can_keep_stats(uuid) to authenticated;

-- ============================================================
-- Team creation by players + caps on join
-- ============================================================
create function public.create_team_and_join(
  p_league_id uuid,
  p_team_name text,
  p_display_name text
)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_is_owner boolean;
  v_allow boolean;
  v_max_teams int;
  v_season_id uuid;
  v_team_id uuid;
  v_spot public.roster_spots;
begin
  select (owner_id = auth.uid()), allow_player_teams, max_teams
    into v_is_owner, v_allow, v_max_teams
  from public.leagues where id = p_league_id;

  if v_season_id is null then
    select id into v_season_id from public.seasons
    where league_id = p_league_id order by created_at desc limit 1;
  end if;

  if v_season_id is null then
    raise exception 'League has no season yet';
  end if;

  if not v_is_owner and not coalesce(v_allow, true) then
    raise exception 'This league does not allow players to create teams';
  end if;

  if v_max_teams is not null then
    if (select count(*) from public.teams where season_id = v_season_id) >= v_max_teams then
      raise exception 'This league has reached its team limit';
    end if;
  end if;

  insert into public.teams (season_id, name) values (v_season_id, p_team_name)
  returning id into v_team_id;

  insert into public.roster_spots (team_id, display_name, player_id)
  values (v_team_id, p_display_name, auth.uid())
  returning * into v_spot;

  return v_spot;
end;
$$;

grant execute on function public.create_team_and_join(uuid, text, text) to authenticated;

-- Shared guard: caller not already rostered in the target team's season,
-- and the target team isn't full. Raises on violation.
create function public.assert_can_join_team(p_team_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_season_id uuid;
  v_league_id uuid;
  v_max int;
begin
  select t.season_id, s.league_id into v_season_id, v_league_id
  from public.teams t join public.seasons s on s.id = t.season_id
  where t.id = p_team_id;

  if v_season_id is null then
    raise exception 'That team does not exist';
  end if;

  if exists (
    select 1 from public.roster_spots rs
    join public.teams t on t.id = rs.team_id
    where t.season_id = v_season_id and rs.player_id = auth.uid()
  ) then
    raise exception 'You are already on a team in this league';
  end if;

  select max_roster_size into v_max from public.leagues where id = v_league_id;
  if v_max is not null and (select count(*) from public.roster_spots where team_id = p_team_id) >= v_max then
    raise exception 'That team is full';
  end if;
end;
$$;

-- Rewrite join_league_self to enforce the guard.
create or replace function public.join_league_self(
  p_join_code text,
  p_team_id uuid,
  p_display_name text
)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_league_id uuid;
  v_spot public.roster_spots;
begin
  select id into v_league_id from public.leagues where join_code = p_join_code;
  if v_league_id is null then
    raise exception 'Invalid join code';
  end if;

  if not exists (
    select 1 from public.teams t
    join public.seasons s on s.id = t.season_id
    where t.id = p_team_id and s.league_id = v_league_id
  ) then
    raise exception 'That team does not belong to this league';
  end if;

  perform public.assert_can_join_team(p_team_id);

  insert into public.roster_spots (team_id, display_name, player_id)
  values (p_team_id, p_display_name, auth.uid())
  returning * into v_spot;

  return v_spot;
end;
$$;

-- ============================================================
-- Public join: direct (open) and request-to-join (approval)
-- ============================================================
create function public.join_league_public(
  p_league_id uuid,
  p_team_id uuid,
  p_display_name text
)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_spot public.roster_spots;
begin
  if not exists (
    select 1 from public.leagues
    where id = p_league_id and is_public = true and join_policy = 'open'
  ) then
    raise exception 'This league is not open for direct joining';
  end if;

  if not exists (
    select 1 from public.teams t
    join public.seasons s on s.id = t.season_id
    where t.id = p_team_id and s.league_id = p_league_id
  ) then
    raise exception 'That team does not belong to this league';
  end if;

  perform public.assert_can_join_team(p_team_id);

  insert into public.roster_spots (team_id, display_name, player_id)
  values (p_team_id, p_display_name, auth.uid())
  returning * into v_spot;

  return v_spot;
end;
$$;

grant execute on function public.join_league_public(uuid, uuid, text) to authenticated;

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  team_id uuid references public.teams(id) on delete set null,
  new_team_name text,
  display_name text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied')),
  created_at timestamptz not null default now(),
  unique (league_id, requested_by)
);

alter table public.join_requests enable row level security;

create policy "join requests visible to requester or owner"
  on public.join_requests for select
  to authenticated
  using (
    requested_by = auth.uid()
    or exists (select 1 from public.leagues l where l.id = join_requests.league_id and l.owner_id = auth.uid())
  );

create function public.request_to_join(
  p_league_id uuid,
  p_team_id uuid,
  p_new_team_name text,
  p_display_name text
)
returns public.join_requests
language plpgsql
security definer set search_path = public
as $$
declare
  v_request public.join_requests;
begin
  if not exists (
    select 1 from public.leagues
    where id = p_league_id and is_public = true and join_policy = 'approval'
  ) then
    raise exception 'This league is not accepting join requests';
  end if;

  insert into public.join_requests (league_id, requested_by, team_id, new_team_name, display_name)
  values (p_league_id, auth.uid(), p_team_id, p_new_team_name, p_display_name)
  on conflict (league_id, requested_by)
  do update set team_id = excluded.team_id,
                new_team_name = excluded.new_team_name,
                display_name = excluded.display_name,
                status = 'pending'
  returning * into v_request;

  return v_request;
end;
$$;

grant execute on function public.request_to_join(uuid, uuid, text, text) to authenticated;

create function public.approve_join_request(p_request_id uuid)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_req public.join_requests;
  v_is_owner boolean;
  v_season_id uuid;
  v_team_id uuid;
  v_max_teams int;
  v_spot public.roster_spots;
begin
  select * into v_req from public.join_requests where id = p_request_id and status = 'pending';
  if v_req.id is null then
    raise exception 'Request not found or already resolved';
  end if;

  select (owner_id = auth.uid()), max_teams into v_is_owner, v_max_teams
  from public.leagues where id = v_req.league_id;
  if not coalesce(v_is_owner, false) then
    raise exception 'Only the league owner can approve join requests';
  end if;

  v_team_id := v_req.team_id;
  if v_team_id is null and v_req.new_team_name is not null then
    select id into v_season_id from public.seasons
    where league_id = v_req.league_id order by created_at desc limit 1;
    if v_max_teams is not null and
       (select count(*) from public.teams where season_id = v_season_id) >= v_max_teams then
      raise exception 'This league has reached its team limit';
    end if;
    insert into public.teams (season_id, name) values (v_season_id, v_req.new_team_name)
    returning id into v_team_id;
  end if;

  if v_team_id is null then
    raise exception 'Request has no team';
  end if;

  insert into public.roster_spots (team_id, display_name, player_id)
  values (v_team_id, v_req.display_name, v_req.requested_by)
  returning * into v_spot;

  update public.join_requests set status = 'approved' where id = p_request_id;
  return v_spot;
end;
$$;

grant execute on function public.approve_join_request(uuid) to authenticated;

create function public.deny_join_request(p_request_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from public.join_requests jr
    join public.leagues l on l.id = jr.league_id
    where jr.id = p_request_id and l.owner_id = auth.uid()
  ) then
    raise exception 'Only the league owner can deny join requests';
  end if;
  update public.join_requests set status = 'denied' where id = p_request_id;
end;
$$;

grant execute on function public.deny_join_request(uuid) to authenticated;
