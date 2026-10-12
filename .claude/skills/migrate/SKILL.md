---
name: migrate
description: Hand a new Supabase migration to Cooper and confirm it was applied. Use whenever a change adds or edits a file in supabase/migrations/, or Cooper says "/migrate".
---

# Run a migration (Cooper runs it; you verify)

Cooper applies migrations by hand in the Supabase SQL Editor. Your job is to make that one paste, then prove it worked.

1. **Copy it.** `pbcopy < supabase/migrations/000N_name.sql` (several pending? `cat` them in order into one `pbcopy`). Check `CLAUDE.md` "Applied so far" first so you never re-hand an applied one — re-running `create table`/`create function` fails with "already exists".
2. **Tell Cooper**, in this order: Supabase dashboard → project → **SQL Editor** → **+ New query** → **Cmd+V** → **Run** → expect "Success. No rows returned." If he gets an error, have him paste it to you; don't let him hand-edit SQL.
3. **Verify from here** once he says done, using the public anon key from `Boxscore/Services/SupabaseService.swift` against `$URL/rest/v1/...`:
   - New table → `GET /rest/v1/<table>?select=*&limit=1` returns `[]`/rows, not a `PGRST205`/42P01 "not found".
   - New RPC → `POST /rest/v1/rpc/<fn>` with its real parameter names; any app-level error (e.g. "Only the league owner…", P0001) or `42501 permission denied` proves it exists. `PGRST202` means missing (or wrong param names).
   - Changed function bodies / triggers can't be observed with the anon key — say so rather than claiming it's verified.
4. **Record it.** Update "Applied so far" in `CLAUDE.md`, commit, push.

If an "already exists" error comes back, probe as in step 3 to see which pieces are present before suggesting anything — usually it was already applied.
