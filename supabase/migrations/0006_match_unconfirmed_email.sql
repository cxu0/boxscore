-- Match roster emails against the account email as entered — no email
-- confirmation required (product decision: signup should be instant).
-- Run after 0005.

create or replace function public.link_roster_spots_for_user(p_user_id uuid)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_email text;
  v_count int;
begin
  select lower(email) into v_email from auth.users where id = p_user_id;

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

create or replace function public.on_roster_email_change()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where lower(email) = new.email limit 1;

  if v_user_id is not null then
    update public.roster_spots
    set player_id = v_user_id
    where id = new.roster_spot_id and player_id is null;
  end if;
  return new;
end;
$$;

-- Link at signup regardless of confirmation state. Still named
-- on_auth_user_link_* so it fires after on_auth_user_created (profile row).
drop trigger if exists on_auth_user_link_roster_insert on auth.users;
create trigger on_auth_user_link_roster_insert
  after insert on auth.users
  for each row
  execute function public.on_auth_user_confirmed();
