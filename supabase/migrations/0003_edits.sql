-- Edits batch: league format, manual game scores, player headshots.
-- Additive to 0001 + 0002 — run against a database that already has them.

-- ============================================================
-- leagues: play format (5v5 / 3v3 / rec)
-- ============================================================
alter table public.leagues
  add column if not exists format text not null default '5v5'
  check (format in ('5v5', '3v3', 'rec'));

-- ============================================================
-- games: manual final score (organizer types it when marking final)
-- ============================================================
alter table public.games add column if not exists home_score int;
alter table public.games add column if not exists away_score int;

-- Set the final score and flip the game to final in one call, owner-only.
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
  v_is_owner boolean;
  v_game public.games;
begin
  select exists (
    select 1 from public.games g
    join public.seasons s on s.id = g.season_id
    join public.leagues l on l.id = s.league_id
    where g.id = p_game_id and l.owner_id = auth.uid()
  ) into v_is_owner;

  if not v_is_owner then
    raise exception 'Only the league owner can set a game result';
  end if;

  update public.games
  set home_score = p_home_score,
      away_score = p_away_score,
      status = 'final'
  where id = p_game_id
  returning * into v_game;

  return v_game;
end;
$$;

grant execute on function public.set_game_result(uuid, int, int) to authenticated;

-- ============================================================
-- profiles: headshot / avatar
-- ============================================================
alter table public.profiles add column if not exists avatar_url text;

-- ============================================================
-- Storage bucket for player headshots
-- ============================================================
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Anyone can view headshots (public bucket, needed to render on profiles).
drop policy if exists "avatars are publicly readable" on storage.objects;
create policy "avatars are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- A user may only write to files under a folder named for their own uid,
-- e.g. avatars/<uid>/headshot.jpg — so nobody can overwrite someone else's.
drop policy if exists "users manage their own avatar" on storage.objects;
create policy "users manage their own avatar"
  on storage.objects for all
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
