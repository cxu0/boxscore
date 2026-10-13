# Boxscore

iOS app (SwiftUI) that gives amateur/rec-league basketball players the pro treatment: permanent cross-league career profiles, league management, box scores, standings, and (planned) full-game video + AI. North star: **make a rec player feel like a pro.**

The owner (Cooper) is non-technical and learning — explain decisions in plain language, give a recommendation plus the main tradeoff, and flag anything he must do by hand (running migrations, Apple/Supabase setup).

## Stack
- SwiftUI, iOS-only (deployment target 26.5). Xcode project uses file-system-synchronized groups — new files under `Boxscore/` are picked up automatically, no pbxproj edits.
- Backend: Supabase (Postgres + Auth + RLS + RPCs) via `supabase-swift` SPM. Config in `Boxscore/Services/SupabaseService.swift` (anon key is intentionally public; RLS enforces access). Custom JSON date parsing there handles Postgres `date` + `timestamptz`.
- Migrations live in `supabase/migrations/000N_*.sql`. They are **run manually by Cooper in the Supabase SQL Editor** — always remind him when a change needs a new migration. Applied so far: 0001–0007; **0008 (location + retire join codes) written — confirm it's been run.**

## Build & verify
- **`scripts/verify.sh [screenshot.png]`** — builds, runs all tests, installs + launches on the iPhone 17 simulator (`246AC1A1-B10E-446E-8B3E-53E8EBEA687E`), screenshots. Use it before every commit. Skills: `/ship` (verify → look → commit → push) and `/migrate` (hand Cooper a migration, then verify it via the REST API).
- Tests: `BoxscoreTests/` (Swift Testing, `@testable import Boxscore`, mark suites `@MainActor` — the app defaults to MainActor isolation). Add tests for pure logic: parsing, standings, model decoding against PostgREST-shaped JSON (use `SupabaseService.decoder`).
- xcode-select points at full Xcode (fixed 2026-10-13), so `xcodebuild`/`xcrun simctl` and the iOS Simulator MCP tool work directly.
- Signed-in flows: Claude must not type passwords into the app (backend is remote). Once Cooper has signed into the simulator himself, the session persists and Claude can drive signed-in screens with the simulator tool.

## Code layout
- `App/` — `BoxscoreApp` (injects `AuthService`, `AppRouter`), `RootView`, `MainTabView` (TabView + `CustomTabBar`), `AppRouter` (deep links + `AppConfig.linkDomain`).
- `Models/Models.swift` — Codable structs mirroring tables (snake_case auto-converted).
- `Services/` — `AuthService`, `LeagueService`, `RosterService`, `StatService`. Views never talk to Supabase directly.
- `Features/` — `Home`, `Leagues` (list/search/discover, `JoinFlow`), `Create`, `Me`, `Player` (profile, read-only + placeholder profiles), `Commissioner` (league/team/game detail, box score entry, stats leaderboard, stat keepers), `Shared` (Theme, tab bar, components).

## Domain model & permission rules (important)
- **One unified account.** "Organizer" and "player" are per-league *relationships*, never an account type: owner = `leagues.owner_id`; player = has a `roster_spot` in the league; stat keeper = row in `league_staff`.
- UI gating: `isOwner` (settings, teams, schedule, delete), `canKeepStats` = owner || staff (box scores, final scores, add game-night subs via `add_sub`). The **database RLS is the real lock**; UI checks are just for hiding buttons.
- Placeholders: roster spots with `player_id = null`. Organizers attach an email (`roster_spot_emails`, owner-only RLS) — usually via **Import Rosters** (paste/CSV, `import_roster` RPC). A user whose account email matches is linked automatically (DB triggers + `claim_my_roster_spots` on sign-in). No "That's me"/approval flow — mismatches are fixed by the organizer (Edit Email / Unlink Account). **No email confirmation, by Cooper's choice** (instant signup; accepted risk: someone could sign up with a teammate's email). Supabase "Confirm email" must stay OFF.
- Direction (agreed with Cooper): leagues already have their own signup websites and roster lists — Boxscore imports them rather than replacing signup. Player join codes are being removed; discovery = location search + universal links. Stat-keeper code stays.
- Joining: **no player join codes** (removed in 0008; `join_league_self` dropped, `leagues.join_code` column unused). Private leagues fill by roster import + email match. Public leagues: if `signup_url` is set, visitors get "Sign up on the league's website"; otherwise in-app join (`join_policy` open/approval). Stat keepers still use `staff_code` (Leagues tab → "Have a stat-keeper code?", or `/keeper/CODE` link). Caps: `max_teams`, `max_roster_size`, `allow_player_teams`.
- Location: leagues have `venue_name/venue_address/city/latitude/longitude/game_night/signup_url`. Gym picked via `VenuePickerField` (MapKit autocomplete, iOS 26 `MKMapItem.location/address` APIs). "Near you" = public leagues in a lat/lng box, sorted by haversine miles client-side (`LeagueService.fetchNearbyPublicLeagues`). Search matches name, city, or gym.
- Standings come from manually entered final scores (`games.home_score/away_score`); player stats from `box_scores` (end-of-game totals per roster spot).

## Design system (`Features/Shared/Theme.swift`)
- `Brand.orange` #FF5F1F accent; `Brand.background` warm off-white page; `Brand.card` white cards (dark mode adapts).
- `.font(.display(size))` = SF condensed black for headlines/numbers; `SectionHeaderText` for ALL-CAPS labels; `.brandCard()`, `.brandBackground()` (add to every new screen), `BrandPrimaryButtonStyle` / `BrandSecondaryButtonStyle`, `BrandTextField`, `SearchField`, `BigStatTile`, `TeamCrest`.
- Heroes: dark gradient header with condensed white title (see League/Team/Profile views).
- Tab bar: flat white bar, outline icons, condensed caps labels, selected tab fills orange; all four tabs equal size.
- Use `.system(size:weight:).width(.condensed)` (not `width:` in the initializer — that doesn't compile).

## Roadmap / decisions
- Next big bet: **full-game video capture + storage** (the moat). Planned architecture: phone records in chunks → dedicated video host (Cloudflare Stream or Mux, NOT Supabase Storage) → `video_assets` pointer table with a `t=0` → a time-indexed `game_events` table (offset, player, type, source, confidence, status) as the source of truth → webhook/job seam where ML plugs in later. Then stat-linked auto-highlights (needs live timestamped stat events), then AI-assisted stats (propose/confirm, not fully automatic).
- Other backlog: co-organizer role (organizer powers minus delete; stat keepers intentionally can't import/see emails), email verification at signup (6-digit code; prevents someone claiming a teammate's spot by signing up with their email — code screen existed in commit cfac079), AI game recaps (Home tab is a placeholder), stat-sheet photo → AI box score, push notifications, Stripe payments, jersey numbers, TestFlight pilot.
- Universal links: app side done; needs Cooper's domain + Associated Domains (`docs/universal-links-setup.md`).
- Specs: `docs/design-join-staff-links.md`.

## Working conventions
- Commit after each working change with a descriptive message. Remote `origin` = github.com/cxu0/boxscore; push after committing (gh auth is set up on this Mac).
- Don't fabricate data fields the schema doesn't have — say what's missing.
