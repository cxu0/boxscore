# Design spec: Join flow v2, stat-keeper delegation, public join, universal links

Status: **designed, not built**. This doc is the source of truth for the next
build phases. It assumes the codebase as of commit `07ed5d6` and migrations
0001–0003 applied. Each numbered feature below is independently shippable, in
order. One combined migration (`0004_join_and_staff.sql`) covers features 1–3;
feature 4 has no schema changes.

Product principles behind these designs (from design discussion):
- The join code is an *address*, not a gate — entering it should show you the
  league, not a form. Public leagues are also addressable by search, so codes
  and search are two doors to the same league page.
- League names are NOT globally unique. Search results disambiguate with
  metadata (format, organizer, later city). The code is the unambiguous address.
- Permissions are per-league relationships on an account (owner / stat-keeper /
  member / visitor) — never a persistent "code stored on a profile."
- Codes are redeemed once, server-side, producing an account-based grant that
  can be revoked/rotated. Rights never travel with the code itself.

---

## 1. Code opens the league page + player-created teams + caps

### Behavior
- Entering a join code (Leagues tab → Join) no longer drops into a join form.
  It resolves the league and **pushes LeagueDetailView** in browse mode.
- On the league page, a visitor (signed-in, no roster spot, not owner) sees a
  **Join this league** CTA. Tapping it opens a team picker sheet:
  - Existing teams listed with roster counts ("Thunder · 7 players", plus
    "FULL" state when at the roster cap).
  - If the league allows player-created teams and the team cap isn't reached:
    a **Create a new team** option (name field) that creates the team and
    joins it in one step.
  - Name field prefilled with the user's display name (same as today).
- Guests tapping Join get the existing sign-in sheet, then bounce back.
- Organizer controls (in the existing Edit League sheet):
  - `Allow players to create teams` toggle (default ON).
  - `Max teams` (optional int, nil = unlimited).
  - `Max players per team` (optional int, nil = unlimited).

### Schema (part of 0004)
```sql
alter table public.leagues
  add column if not exists allow_player_teams boolean not null default true,
  add column if not exists max_teams int,
  add column if not exists max_roster_size int;
```

### RPCs (security definer)
- `create_team_and_join(p_league_id uuid, p_team_name text, p_display_name text) returns roster_spots`
  1. League must exist; caller must be authenticated.
  2. Requires `allow_player_teams = true` (owner bypasses this check).
  3. Counts teams in the league's **current season** (most recent by
     created_at, same rule the app uses); raises if `max_teams` reached.
  4. Creates the team, inserts a roster spot with `player_id = auth.uid()`.
- Modify `join_league_self` (join by code) to:
  1. Enforce `max_roster_size` (count roster_spots on the target team).
  2. **Reject if the caller already has a roster spot on any team in this
     league's current season** — prevents accidental double-join. Error text:
     "You're already on a team in this league."

### Swift changes
- `JoinLeagueView` shrinks to a code-entry sheet; on success it dismisses and
  pushes `LeagueDetailView(league:)` (LeaguesTabView owns the navigation).
  The league page receives `viaJoinCode: String?` so its Join CTA can call
  `join_league_self` for private leagues (the code is the proof of invite).
- New `JoinTeamSheet` (team list + create-team row + name field) used by the
  league page CTA. Calls `joinLeagueSelf` or `createTeamAndJoin`.
- `LeagueDetailView`: compute viewer relationship (owner / member via
  `resolveMyTeam` which already exists / visitor) and show the CTA for
  visitors. After joining, reload (`loadAll`) so the Your Team card appears.
- `EditLeagueSheet`: add the three new settings; `LeagueService.updateLeague`
  gains the new fields. `LeagueService.createLeague` too (Create tab can keep
  defaults; no UI needed there yet).
- Roster counts for the picker: reuse `fetchRosterCount(teamId:)`.

### Edge cases
- Team cap counts only the current season's teams.
- Create-team-and-join must be atomic (single RPC) so a cap can't be raced.
- Owner joining their own league as a player is allowed (existing model).

---

## 2. Stat-keeper delegation (account-based)

### Behavior
- A league has a **stat-keeper code**, separate from the join code, visible
  only to the owner (Manage → Stat Keepers screen), with Share and
  **Regenerate** (rotation invalidates the old code but never removes people
  already added).
- Anyone who enters that code once becomes a **stat keeper of that league**:
  a durable, per-league grant on their account. The code is not stored on the
  profile; redemption inserts a membership row.
- One code-entry field serves everything: the existing Join field first tries
  join codes, then stat-keeper codes ("smart code entry"). If it matches a
  staff code → redeem + open the league with edit rights visible.
- What stat keepers can do: enter/edit **box scores** and **final scores**
  (mark game final). They cannot schedule/delete games, edit teams/rosters,
  or change league settings — those stay owner-only.
- Owner screen lists current stat keepers (name) with a Remove button.

### Schema (part of 0004)
```sql
alter table public.leagues
  add column if not exists staff_code text unique
  default upper(substr(md5(random()::text), 1, 6));
update public.leagues set staff_code = upper(substr(md5(random()::text || id::text), 1, 6))
  where staff_code is null;
alter table public.leagues alter column staff_code set not null;

create table public.league_staff (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (league_id, profile_id)
);
alter table public.league_staff enable row level security;
-- select: the staff member themselves, or the league owner
-- delete: league owner only (removal)
```

Helper used by policies and RPCs:
```sql
create function public.can_keep_stats(p_league_id uuid) returns boolean
  language sql security definer as $$
    select exists (select 1 from public.leagues where id = p_league_id and owner_id = auth.uid())
        or exists (select 1 from public.league_staff where league_id = p_league_id and profile_id = auth.uid());
  $$;
```

RLS changes:
- `box_scores` manage policy: replace the owner-chain check with
  `can_keep_stats(<league id via game→season chain>)`.
- `set_game_result` RPC: owner check becomes `can_keep_stats`.
- Everything else (games/teams/rosters/league CRUD) unchanged, owner-only.

RPCs:
- `redeem_staff_code(p_code text) returns leagues` — security definer. Finds
  league by staff_code, `insert … on conflict do nothing` into league_staff
  for `auth.uid()`, returns the league row.
- `regenerate_staff_code(p_league_id uuid) returns text` — owner-only.

### Swift changes
- `LeagueService`: `redeemStaffCode(_:)`, `fetchStaffStatus(leagueId:)`
  (bool via league_staff select), `fetchStaff(leagueId:)`,
  `removeStaff(id:)`, `regenerateStaffCode(leagueId:)`.
- `LeagueDetailView`: load `canKeepStats = isOwner || isStaff` and pass it
  down. `GameDetailView` gates box-score editing, the pencil affordance, and
  Enter Final Score on `canKeepStats` (rename its `isOwner` param or add a
  second flag — reschedule/delete menu stays owner-gated).
- New `StatKeepersView` (owner-only, from the league ⋯ menu): staff code card
  (share/regenerate) + staff list with remove.
- Join sheet "smart code" fallthrough: try `findLeague(byJoinCode:)`; on
  failure try `redeemStaffCode`; on failure show the not-found error.

### Why not the "code saved to profile" model
Codes leak (screenshots); a persistent code-as-key can't be revoked per
person and grants rights to "any league matching the code." Account-based
membership is revocable, auditable, and rotation-safe. (Decision recorded
from design discussion.)

### Future (not this phase)
Photo-of-stat-sheet → AI-parsed box score for stat keepers (Claude vision).
Delegation is the prerequisite; note it in the backlog, don't build it here.

---

## 3. Public leagues: direct join / request-to-join

### Behavior
- A **public** league's page shows a join CTA to any signed-in visitor with
  no code required. What the CTA does depends on a new league setting,
  `join_policy`:
  - `open` (default): same instant team-picker join as feature 1.
  - `approval`: CTA reads **Request to join**; picker works the same but
    submits a request. Visitor sees a "Request pending" state; owner
    approves/denies from the league page; approval creates the roster spot.
- Private leagues are unchanged: page reachable only via code, and the code
  is what authorizes instant join.
- Owner setting lives in Edit League: "Who can join" → Open / Approval
  (only shown when the league is public).

### Schema (part of 0004)
```sql
alter table public.leagues
  add column if not exists join_policy text not null default 'open'
  check (join_policy in ('open','approval'));

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  team_id uuid references public.teams(id) on delete set null,
  new_team_name text,           -- set when the requester wants to create a team
  display_name text not null,
  status text not null default 'pending' check (status in ('pending','approved','denied')),
  created_at timestamptz not null default now(),
  unique (league_id, requested_by)
);
-- RLS mirrors claim_requests: requester sees own; owner sees/manages theirs.
```

RPCs (security definer):
- `join_league_public(p_league_id, p_team_id, p_display_name)` — requires
  `is_public and join_policy='open'`; enforces roster cap + already-on-a-team
  guard; inserts the spot. (Code-based `join_league_self` remains the private
  path.)
- `request_to_join(p_league_id, p_team_id, p_new_team_name, p_display_name)`
  — requires `is_public and join_policy='approval'`; upserts pending request.
- `approve_join_request(p_request_id)` — owner-only; creates team if
  `new_team_name` set (re-checking caps), inserts roster spot, marks
  approved.
- `deny_join_request(p_request_id)` — owner-only.

### Swift changes
- `JoinTeamSheet` from feature 1 gains a mode: instant vs request (button
  copy + which RPC).
- `LeagueDetailView`: CTA logic — member: none; owner: none; visitor +
  private: only if arrived `viaJoinCode`; visitor + public+open: Join;
  visitor + public+approval: Request to join / Pending.
- Owner "Join requests" section (league page, above teams in Rosters tab)
  with approve/deny — same UI pattern as claim requests in TeamDetailView.
- `EditLeagueSheet`: join policy picker, shown when public.

---

## 4. Universal links (tap-to-open)

No database changes. Two halves: web infrastructure (user-owned) and app.

### Infrastructure (requires Cooper: domain + hosting + paid Apple team)
1. Buy/choose a domain (e.g. `getboxscore.app`).
2. Host a tiny static site (Cloudflare Pages / Vercel / Netlify, free tier):
   - `/.well-known/apple-app-site-association` — JSON, served as
     `application/json`, no redirect:
     ```json
     { "applinks": { "details": [ {
       "appIDs": ["DT44QH4CUK.cooper.Boxscore"],
       "components": [
         { "/": "/join/*" }, { "/": "/keeper/*" }, { "/": "/league/*" }
       ] } ] } }
     ```
     (Team ID `DT44QH4CUK` from the Xcode project; confirm the final bundle
     id — currently `cooper.Boxscore` — before shipping; App Store builds may
     rename it, which requires updating this file.)
   - Fallback pages for each path: "Get Boxscore" + the embedded code shown
     in plain text so a user without the app can still join manually.
3. Note: Apple's CDN caches AASA for hours; first-install association can lag.

### Link formats
- `https://<domain>/join/<JOIN_CODE>` → open league page via code (feature 1
  path), ready to join.
- `https://<domain>/keeper/<STAFF_CODE>` → redeem stat-keeper code (feature 2)
  and open the league.
- `https://<domain>/league/<LEAGUE_ID>` → open a public league page (browse).

### App changes
- Xcode: add Associated Domains capability, `applinks:<domain>` (edit the
  pbxproj entitlements; requires the paid developer account).
- New `AppRouter` (ObservableObject in the environment): holds an optional
  `Destination` enum (`.league(code:)`, `.staffCode(String)`,
  `.publicLeague(UUID)`).
- `BoxscoreApp`: `.onOpenURL` parses the path into a Destination.
- `MainTabView`/`LeaguesTabView`: observe the router — switch to the Leagues
  tab, resolve the destination (find by code / redeem / fetch by id), push
  `LeagueDetailView`, then clear it. If the user is a guest and the action
  needs auth (keeper redeem), show the sign-in sheet first and re-run after.
- Update every `ShareLink` (join code card, future stat-keeper card) to share
  the URL form with the code as fallback text in the message.

### Build order note
Ship 1→2→3 without links (codes + share sheet keep working). Do 4 whenever
the domain exists; it only *changes the payload* of the existing share
buttons and adds the router.

---

## Combined migration checklist (0004_join_and_staff.sql)
1. leagues: `allow_player_teams`, `max_teams`, `max_roster_size`,
   `staff_code` (backfilled, unique, not null), `join_policy`.
2. `league_staff` table + RLS.
3. `join_requests` table + RLS.
4. `can_keep_stats()` helper.
5. Rewrite `box_scores` manage policy on top of `can_keep_stats`.
6. RPCs: `create_team_and_join`, updated `join_league_self` (caps +
   double-join guard), `redeem_staff_code`, `regenerate_staff_code`,
   `join_league_public`, `request_to_join`, `approve_join_request`,
   `deny_join_request`, updated `set_game_result` (can_keep_stats).
7. Grants: execute on all new RPCs to `authenticated`.

## Explicitly out of scope (recorded for later)
- Stripe payments (league fees, Stripe Connect, per-team vs per-player) —
  design when the free loop is proven; Apple permits external payment for
  physical services, so no IAP constraint.
- Location-based "leagues near you" discovery.
- AI stat-sheet photo import; AI game recaps (Home feed).
- Roster-size UI on team creation by owner (cap enforcement is join-side).
