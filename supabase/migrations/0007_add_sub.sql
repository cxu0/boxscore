-- Game-night subs: stat keepers (and owners) can add a name-only player to a
-- team in their league so the sub's stats can be recorded. No email — the
-- organizer can attach one later and the stats follow the player.
-- Ignores max_roster_size on purpose: a sub who showed up still played.

create function public.add_sub(p_team_id uuid, p_display_name text)
returns public.roster_spots
language plpgsql
security definer set search_path = public
as $$
declare
  v_league_id uuid;
  v_name text := nullif(trim(p_display_name), '');
  v_spot public.roster_spots;
begin
  select s.league_id into v_league_id
  from public.teams t join public.seasons s on s.id = t.season_id
  where t.id = p_team_id;

  if v_league_id is null or not public.can_keep_stats(v_league_id) then
    raise exception 'Not allowed to add players to this team';
  end if;
  if v_name is null then
    raise exception 'Enter a name';
  end if;

  insert into public.roster_spots (team_id, display_name)
  values (p_team_id, v_name)
  returning * into v_spot;

  return v_spot;
end;
$$;

revoke execute on function public.add_sub(uuid, text) from public, anon;
grant execute on function public.add_sub(uuid, text) to authenticated;
