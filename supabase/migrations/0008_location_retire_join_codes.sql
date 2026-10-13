-- League location (gym + city + coordinates), game night, and a link to the
-- league's own signup website. Retires the player join-code path.
-- Additive to 0001–0007.

-- ============================================================
-- leagues: where/when they play, and where to sign up
-- ============================================================
alter table public.leagues
  add column if not exists venue_name text,
  add column if not exists venue_address text,
  add column if not exists city text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists game_night text,
  add column if not exists signup_url text;

alter table public.leagues
  add constraint leagues_signup_url_http
  check (signup_url is null or signup_url ~* '^https?://');

-- "Near you" filters public leagues by a lat/lng bounding box.
create index if not exists leagues_public_location_idx
  on public.leagues (latitude, longitude)
  where is_public;

-- ============================================================
-- Retire player join codes. Players now get in by roster import + email
-- match, or public-league join. (join_code column stays; nothing reads it.)
-- join_league_self let anyone who could read a league row — every signed-in
-- user — add themselves to a private league.
-- ============================================================
drop function if exists public.join_league_self(text, uuid, text);

-- create_team_and_join didn't check the league was joinable at all. Now:
-- the owner, or anyone in a public open-join league that allows player teams.
create or replace function public.create_team_and_join(
  p_league_id uuid,
  p_team_name text,
  p_display_name text
)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_league public.leagues;
  v_is_owner boolean;
  v_season_id uuid;
  v_team_id uuid;
  v_spot public.roster_spots;
begin
  select * into v_league from public.leagues where id = p_league_id;
  if v_league.id is null then
    raise exception 'League not found';
  end if;
  v_is_owner := v_league.owner_id = auth.uid();

  if not v_is_owner then
    if not (v_league.is_public and v_league.join_policy = 'open') then
      raise exception 'This league is not open for joining';
    end if;
    if not v_league.allow_player_teams then
      raise exception 'This league does not allow players to create teams';
    end if;
  end if;

  select id into v_season_id from public.seasons
  where league_id = p_league_id order by created_at desc limit 1;
  if v_season_id is null then
    raise exception 'League has no season yet';
  end if;

  if v_league.max_teams is not null and
     (select count(*) from public.teams where season_id = v_season_id) >= v_league.max_teams then
    raise exception 'This league has reached its team limit';
  end if;

  if exists (
    select 1 from public.roster_spots rs
    join public.teams t on t.id = rs.team_id
    where t.season_id = v_season_id and rs.player_id = auth.uid()
  ) then
    raise exception 'You are already on a team in this league';
  end if;

  insert into public.teams (season_id, name) values (v_season_id, p_team_name)
  returning id into v_team_id;

  insert into public.roster_spots (team_id, display_name, player_id)
  values (v_team_id, p_display_name, auth.uid())
  returning * into v_spot;

  return v_spot;
end;
$$;
