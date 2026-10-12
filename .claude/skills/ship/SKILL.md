---
name: ship
description: Verify and ship the current Boxscore change — build, run tests, install on the simulator, look at a screenshot, commit, and push. Use when Cooper says "ship it", "/ship", or a change is finished.
---

# Ship a change

1. **Verify.** Run `scripts/verify.sh <scratchpad>/ship.png`. If the build or a test fails, fix it and re-run — never ship red. If you changed logic that has no test (parsing, standings, decoding, permissions helpers), add a test in `BoxscoreTests/` first.
2. **Look.** Read the screenshot. If the change is visible on a screen you can reach (signed-in screens are reachable once Cooper has signed into the simulator; drive them with the iOS Simulator tool), navigate there and screenshot it too. Say plainly what you did and didn't see.
3. **Migrations.** If this change added a file in `supabase/migrations/`, follow the `migrate` skill — the change isn't live until Cooper runs it.
4. **Commit + push.** Stage only files that belong to the change. Descriptive message (what + why), ending with the attribution lines from the session's system reminder. Then `git push`.
5. **Report** in plain language for Cooper: what changed, how it was verified (tests passed count, screenshots), anything he must do by hand, and what to tap to try it.
