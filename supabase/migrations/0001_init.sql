-- Boxscore V1 schema
-- Tables, RLS policies, and the invite-claim RPC.

-- ============================================================
-- profiles
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('commissioner', 'player')),
  display_name text not null,
  email text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Anyone signed in can read basic profile info (needed to show player
-- names on rosters/box scores across leagues they don't own).
create policy "profiles are readable by authenticated users"
  on public.profiles for select
  to authenticated
  using (true);

create policy "users can update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid());

-- Auto-create a profile row whenever a new auth user signs up.
-- Expects role/display_name passed via signUp's `data` metadata.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, role, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'role', 'player'),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.email),
    new.email
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- leagues
-- ============================================================
create table public.leagues (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.leagues enable row level security;

create policy "leagues are readable by authenticated users"
  on public.leagues for select
  to authenticated
  using (true);

create policy "commissioners can create their own leagues"
  on public.leagues for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy "owners can update/delete their leagues"
  on public.leagues for update
  to authenticated
  using (owner_id = auth.uid());

create policy "owners can delete their leagues"
  on public.leagues for delete
  to authenticated
  using (owner_id = auth.uid());

-- ============================================================
-- seasons
-- ============================================================
create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  name text not null,
  start_date date,
  end_date date,
  created_at timestamptz not null default now()
);

alter table public.seasons enable row level security;

create policy "seasons are readable by authenticated users"
  on public.seasons for select
  to authenticated
  using (true);

create policy "league owners manage seasons"
  on public.seasons for all
  to authenticated
  using (exists (
    select 1 from public.leagues
    where leagues.id = seasons.league_id and leagues.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.leagues
    where leagues.id = seasons.league_id and leagues.owner_id = auth.uid()
  ));

-- ============================================================
-- teams
-- ============================================================
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

alter table public.teams enable row level security;

create policy "teams are readable by authenticated users"
  on public.teams for select
  to authenticated
  using (true);

create policy "league owners manage teams"
  on public.teams for all
  to authenticated
  using (exists (
    select 1 from public.seasons
    join public.leagues on leagues.id = seasons.league_id
    where seasons.id = teams.season_id and leagues.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.seasons
    join public.leagues on leagues.id = seasons.league_id
    where seasons.id = teams.season_id and leagues.owner_id = auth.uid()
  ));

-- ============================================================
-- roster_spots
-- ============================================================
create table public.roster_spots (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  display_name text not null,
  player_id uuid references public.profiles(id) on delete set null,
  invite_code text unique,
  created_at timestamptz not null default now()
);

alter table public.roster_spots enable row level security;

create policy "roster spots are readable by authenticated users"
  on public.roster_spots for select
  to authenticated
  using (true);

create policy "league owners manage roster spots"
  on public.roster_spots for all
  to authenticated
  using (exists (
    select 1 from public.teams
    join public.seasons on seasons.id = teams.season_id
    join public.leagues on leagues.id = seasons.league_id
    where teams.id = roster_spots.team_id and leagues.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.teams
    join public.seasons on seasons.id = teams.season_id
    join public.leagues on leagues.id = seasons.league_id
    where teams.id = roster_spots.team_id and leagues.owner_id = auth.uid()
  ));

-- Players claim an open roster spot via RPC (security definer) rather
-- than a direct RLS update, so the invite-code check happens atomically
-- and can't be bypassed by guessing another player's spot id.
create function public.claim_invite(p_invite_code text)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_spot public.roster_spots;
begin
  update public.roster_spots
  set player_id = auth.uid(), invite_code = null
  where invite_code = p_invite_code and player_id is null
  returning * into v_spot;

  if v_spot.id is null then
    raise exception 'Invalid or already-claimed invite code';
  end if;

  return v_spot;
end;
$$;

grant execute on function public.claim_invite(text) to authenticated;

-- ============================================================
-- games
-- ============================================================
create table public.games (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  home_team_id uuid not null references public.teams(id) on delete cascade,
  away_team_id uuid not null references public.teams(id) on delete cascade,
  scheduled_at timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled', 'final')),
  created_at timestamptz not null default now()
);

alter table public.games enable row level security;

create policy "games are readable by authenticated users"
  on public.games for select
  to authenticated
  using (true);

create policy "league owners manage games"
  on public.games for all
  to authenticated
  using (exists (
    select 1 from public.seasons
    join public.leagues on leagues.id = seasons.league_id
    where seasons.id = games.season_id and leagues.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.seasons
    join public.leagues on leagues.id = seasons.league_id
    where seasons.id = games.season_id and leagues.owner_id = auth.uid()
  ));

-- ============================================================
-- box_scores
-- ============================================================
create table public.box_scores (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  roster_spot_id uuid not null references public.roster_spots(id) on delete cascade,
  pts int not null default 0,
  reb int not null default 0,
  ast int not null default 0,
  stl int not null default 0,
  blk int not null default 0,
  turnovers int not null default 0,
  fgm int not null default 0,
  fga int not null default 0,
  tpm int not null default 0,
  tpa int not null default 0,
  ftm int not null default 0,
  fta int not null default 0,
  pf int not null default 0,
  created_at timestamptz not null default now(),
  unique (game_id, roster_spot_id)
);

alter table public.box_scores enable row level security;

create policy "box scores are readable by authenticated users"
  on public.box_scores for select
  to authenticated
  using (true);

create policy "league owners manage box scores"
  on public.box_scores for all
  to authenticated
  using (exists (
    select 1 from public.games
    join public.seasons on seasons.id = games.season_id
    join public.leagues on leagues.id = seasons.league_id
    where games.id = box_scores.game_id and leagues.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.games
    join public.seasons on seasons.id = games.season_id
    join public.leagues on leagues.id = seasons.league_id
    where games.id = box_scores.game_id and leagues.owner_id = auth.uid()
  ));

-- ============================================================
-- Career/season aggregation view
-- ============================================================
-- One row per (player, league, season) with summed stats, plus a
-- games_played count. Career totals = SUM(...) grouped by player only;
-- season/league breakdown = this view as-is.
create view public.player_season_stats
with (security_invoker = true) as
select
  rs.player_id,
  l.id as league_id,
  l.name as league_name,
  s.id as season_id,
  s.name as season_name,
  count(distinct bs.game_id) as games_played,
  sum(bs.pts) as pts,
  sum(bs.reb) as reb,
  sum(bs.ast) as ast,
  sum(bs.stl) as stl,
  sum(bs.blk) as blk,
  sum(bs.turnovers) as turnovers,
  sum(bs.fgm) as fgm,
  sum(bs.fga) as fga,
  sum(bs.tpm) as tpm,
  sum(bs.tpa) as tpa,
  sum(bs.ftm) as ftm,
  sum(bs.fta) as fta,
  sum(bs.pf) as pf
from public.box_scores bs
join public.roster_spots rs on rs.id = bs.roster_spot_id
join public.teams t on t.id = rs.team_id
join public.seasons s on s.id = t.season_id
join public.leagues l on l.id = s.league_id
where rs.player_id is not null
group by rs.player_id, l.id, l.name, s.id, s.name;
