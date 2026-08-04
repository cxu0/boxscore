# Universal links setup (Feature 4)

The app side is built. To make `https://<domain>/join/CODE` (and `/keeper/`,
`/league/`) actually open the app, two things you must do — they need a domain
you own and the paid Apple Developer account:

## 1. Host the web files (from `/web`)
Deploy the `web/` folder to any static host (Cloudflare Pages, Vercel,
Netlify — free tiers are fine) on your domain, e.g. `getboxscore.app`.
- `web/.well-known/apple-app-site-association` must be served at
  `https://<domain>/.well-known/apple-app-site-association`
  with `Content-Type: application/json` and **no redirect**.
- Route `/join/*`, `/keeper/*`, `/league/*` to `web/index.html` (it reads the
  code from the path and shows it as a manual fallback). On Cloudflare Pages,
  add a `_redirects` line: `/*  /index.html  200`.

## 2. Xcode: Associated Domains capability
- In the target's Signing & Capabilities, add **Associated Domains** and the
  entry `applinks:getboxscore.app` (swap in your domain).
- Requires the paid developer account; the entitlement is rejected otherwise.

## 3. Update the app's domain constant
- Set `AppConfig.linkDomain` in `Boxscore/App/AppRouter.swift` to your domain.
  Until then, share links point at `getboxscore.app` (a placeholder).

## 4. If the bundle id changes for the App Store
- The AASA `appIDs` is `DT44QH4CUK.cooper.Boxscore`. If the bundle id changes
  at submission, update `apple-app-site-association` to match, or links break.

## Notes
- Apple caches the AASA for hours; first-launch association can lag.
- Everything works without this: the in-app "Join" code entry and the share
  sheet (which includes the code in its message) are the fallback path.
