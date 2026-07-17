-- Phase 1: unified account model, league join codes, placeholder claim requests.
-- Additive to 0001_init.sql — run this against a database that already has it.

-- ============================================================
-- profiles: drop the account-wide role
-- ============================================================
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles drop column if exists role;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.email),
    new.email
  );
  return new;
end;
$$;

-- ============================================================
-- leagues: public/private + one shareable join code
-- ============================================================
alter table public.leagues add column if not exists is_public boolean not null default false;
alter table public.leagues add column if not exists join_code text;

update public.leagues
set join_code = upper(substr(md5(random()::text || id::text), 1, 6))
where join_code is null;

alter table public.leagues alter column join_code set not null;
alter table public.leagues
  add constraint leagues_join_code_unique unique (join_code);
alter table public.leagues
  alter column join_code set default upper(substr(md5(random()::text), 1, 6));

-- ============================================================
-- roster_spots: drop the old per-spot invite code
-- ============================================================
drop function if exists public.claim_invite(text);
alter table public.roster_spots drop column if exists invite_code;

-- ============================================================
-- Self-serve join: one league join code, player adds themselves directly
-- ============================================================
create function public.join_league_self(
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
  select l.id into v_league_id
  from public.leagues l
  where l.join_code = p_join_code;

  if v_league_id is null then
    raise exception 'Invalid join code';
  end if;

  -- verify the chosen team actually belongs to this league
  if not exists (
    select 1 from public.teams t
    join public.seasons s on s.id = t.season_id
    where t.id = p_team_id and s.league_id = v_league_id
  ) then
    raise exception 'That team does not belong to this league';
  end if;

  insert into public.roster_spots (team_id, display_name, player_id)
  values (p_team_id, p_display_name, auth.uid())
  returning * into v_spot;

  return v_spot;
end;
$$;

grant execute on function public.join_league_self(text, uuid, text) to authenticated;

-- ============================================================
-- claim_requests: a player asking to take over a placeholder roster spot
-- ============================================================
create table public.claim_requests (
  id uuid primary key default gen_random_uuid(),
  roster_spot_id uuid not null references public.roster_spots(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied')),
  created_at timestamptz not null default now(),
  unique (roster_spot_id, requested_by)
);

alter table public.claim_requests enable row level security;

create policy "requesters can see their own claim requests"
  on public.claim_requests for select
  to authenticated
  using (requested_by = auth.uid());

create policy "league owners can see claim requests for their rosters"
  on public.claim_requests for select
  to authenticated
  using (exists (
    select 1 from public.roster_spots rs
    join public.teams t on t.id = rs.team_id
    join public.seasons s on s.id = t.season_id
    join public.leagues l on l.id = s.league_id
    where rs.id = claim_requests.roster_spot_id and l.owner_id = auth.uid()
  ));

create function public.request_claim(p_roster_spot_id uuid)
returns public.claim_requests
language plpgsql
security definer set search_path = public
as $$
declare
  v_request public.claim_requests;
begin
  if not exists (
    select 1 from public.roster_spots where id = p_roster_spot_id and player_id is null
  ) then
    raise exception 'That roster spot is not available to claim';
  end if;

  insert into public.claim_requests (roster_spot_id, requested_by)
  values (p_roster_spot_id, auth.uid())
  on conflict (roster_spot_id, requested_by) do update set status = 'pending'
  returning * into v_request;

  return v_request;
end;
$$;

grant execute on function public.request_claim(uuid) to authenticated;

create function public.approve_claim_request(p_request_id uuid)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_roster_spot_id uuid;
  v_requested_by uuid;
  v_is_owner boolean;
  v_spot public.roster_spots;
begin
  select cr.roster_spot_id, cr.requested_by into v_roster_spot_id, v_requested_by
  from public.claim_requests cr
  where cr.id = p_request_id and cr.status = 'pending';

  if v_roster_spot_id is null then
    raise exception 'Claim request not found or already resolved';
  end if;

  select exists (
    select 1 from public.roster_spots rs
    join public.teams t on t.id = rs.team_id
    join public.seasons s on s.id = t.season_id
    join public.leagues l on l.id = s.league_id
    where rs.id = v_roster_spot_id and l.owner_id = auth.uid()
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'Only the league owner can approve claim requests';
  end if;

  update public.roster_spots
  set player_id = v_requested_by
  where id = v_roster_spot_id
  returning * into v_spot;

  update public.claim_requests set status = 'approved' where id = p_request_id;
  update public.claim_requests
  set status = 'denied'
  where roster_spot_id = v_roster_spot_id and id != p_request_id and status = 'pending';

  return v_spot;
end;
$$;

grant execute on function public.approve_claim_request(uuid) to authenticated;

create function public.deny_claim_request(p_request_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_is_owner boolean;
begin
  select exists (
    select 1 from public.claim_requests cr
    join public.roster_spots rs on rs.id = cr.roster_spot_id
    join public.teams t on t.id = rs.team_id
    join public.seasons s on s.id = t.season_id
    join public.leagues l on l.id = s.league_id
    where cr.id = p_request_id and l.owner_id = auth.uid()
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'Only the league owner can deny claim requests';
  end if;

  update public.claim_requests set status = 'denied' where id = p_request_id;
end;
$$;

grant execute on function public.deny_claim_request(uuid) to authenticated;
