-- Roster import + automatic email matching.
-- Organizers attach an email to each roster spot (usually via bulk import).
-- When a user with that CONFIRMED email exists — now or when they sign up
-- later — they're linked to the spot automatically. No codes, no approval.
-- Additive to 0001–0004.

-- ============================================================
-- roster_spot_emails: private, owner-only. Kept off roster_spots because
-- roster spots are readable by every signed-in user.
-- ============================================================
create table public.roster_spot_emails (
  roster_spot_id uuid primary key references public.roster_spots(id) on delete cascade,
  email text not null check (email = lower(email) and email <> ''),
  created_at timestamptz not null default now()
);

create index roster_spot_emails_email_idx on public.roster_spot_emails (email);

alter table public.roster_spot_emails enable row level security;

create policy "league owners manage roster emails"
  on public.roster_spot_emails for all
  to authenticated
  using (exists (
    select 1 from public.roster_spots rs
    join public.teams t on t.id = rs.team_id
    join public.seasons s on s.id = t.season_id
    join public.leagues l on l.id = s.league_id
    where rs.id = roster_spot_emails.roster_spot_id and l.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.roster_spots rs
    join public.teams t on t.id = rs.team_id
    join public.seasons s on s.id = t.season_id
    join public.leagues l on l.id = s.league_id
    where rs.id = roster_spot_emails.roster_spot_id and l.owner_id = auth.uid()
  ));

-- ============================================================
-- Internal: link every unclaimed spot whose email matches this user's
-- confirmed email. Not callable by clients (it takes any user id).
-- ============================================================
create function public.link_roster_spots_for_user(p_user_id uuid)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_email text;
  v_count int;
begin
  select lower(email) into v_email
  from auth.users
  where id = p_user_id and email_confirmed_at is not null;

  if v_email is null then
    return 0;
  end if;

  update public.roster_spots rs
  set player_id = p_user_id
  from public.roster_spot_emails e
  where e.roster_spot_id = rs.id
    and e.email = v_email
    and rs.player_id is null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.link_roster_spots_for_user(uuid) from public, anon, authenticated;

-- Client safety net: the app calls this on sign-in (covers accounts that
-- existed before this migration). Only ever links the caller.
create function public.claim_my_roster_spots()
returns int
language sql
security definer set search_path = public
as $$
  select public.link_roster_spots_for_user(auth.uid());
$$;

grant execute on function public.claim_my_roster_spots() to authenticated;

-- ============================================================
-- Trigger: organizer adds/edits an email → link right away if that person
-- already has a confirmed account.
-- ============================================================
create function public.on_roster_email_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid;
begin
  select id into v_user_id
  from auth.users
  where lower(email) = new.email and email_confirmed_at is not null
  limit 1;

  if v_user_id is not null then
    update public.roster_spots
    set player_id = v_user_id
    where id = new.roster_spot_id and player_id is null;
  end if;
  return new;
end;
$$;

create trigger roster_email_link
  after insert or update of email on public.roster_spot_emails
  for each row execute function public.on_roster_email_change();

-- ============================================================
-- Trigger: a user confirms their email (or signs up already confirmed)
-- → link any spots waiting for them.
-- ============================================================
create function public.on_auth_user_confirmed()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  perform public.link_roster_spots_for_user(new.id);
  return new;
end;
$$;

-- Named "on_auth_user_link_*" so it sorts (and fires) after 0001's
-- on_auth_user_created, which creates the profile row player_id points to.
create trigger on_auth_user_link_roster_update
  after update of email_confirmed_at on auth.users
  for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
  execute function public.on_auth_user_confirmed();

create trigger on_auth_user_link_roster_insert
  after insert on auth.users
  for each row
  when (new.email_confirmed_at is not null)
  execute function public.on_auth_user_confirmed();

-- ============================================================
-- import_roster: owner bulk-creates teams + roster spots (+ emails) in the
-- league's current season from rows [{team, name, email}]. Teams are matched
-- by name (case-insensitive) or created. A row whose email is already on a
-- roster in this season is skipped, so re-importing an updated sheet is safe.
-- ============================================================
create function public.import_roster(p_league_id uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_season_id uuid;
  v_row jsonb;
  v_team_name text;
  v_name text;
  v_email text;
  v_team_id uuid;
  v_spot_id uuid;
  v_spot_ids uuid[] := '{}';
  v_teams_created int := 0;
  v_skipped int := 0;
begin
  if not exists (select 1 from public.leagues where id = p_league_id and owner_id = auth.uid()) then
    raise exception 'Only the league owner can import rosters';
  end if;

  select id into v_season_id from public.seasons
  where league_id = p_league_id order by created_at desc limit 1;
  if v_season_id is null then
    raise exception 'League has no season yet';
  end if;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_team_name := nullif(trim(v_row ->> 'team'), '');
    v_name := nullif(trim(v_row ->> 'name'), '');
    v_email := nullif(lower(trim(v_row ->> 'email')), '');

    if v_team_name is null or v_name is null then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if v_email is not null and exists (
      select 1 from public.roster_spot_emails e
      join public.roster_spots rs on rs.id = e.roster_spot_id
      join public.teams t on t.id = rs.team_id
      where t.season_id = v_season_id and e.email = v_email
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    select id into v_team_id from public.teams
    where season_id = v_season_id and lower(name) = lower(v_team_name)
    limit 1;

    if v_team_id is null then
      insert into public.teams (season_id, name) values (v_season_id, v_team_name)
      returning id into v_team_id;
      v_teams_created := v_teams_created + 1;
    end if;

    insert into public.roster_spots (team_id, display_name)
    values (v_team_id, v_name)
    returning id into v_spot_id;

    if v_email is not null then
      insert into public.roster_spot_emails (roster_spot_id, email) values (v_spot_id, v_email);
    end if;

    v_spot_ids := v_spot_ids || v_spot_id;
  end loop;

  return jsonb_build_object(
    'teams_created', v_teams_created,
    'players_added', coalesce(array_length(v_spot_ids, 1), 0),
    'already_joined', (select count(*) from public.roster_spots where id = any(v_spot_ids) and player_id is not null),
    'skipped', v_skipped
  );
end;
$$;

grant execute on function public.import_roster(uuid, jsonb) to authenticated;
