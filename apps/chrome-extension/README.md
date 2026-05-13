# DripAdvisor Chrome Extension

Manifest V3. Save garments, outfits, and product pages from any URL into your
DripAdvisor wardrobe.

## Install (local dev)

1. `chrome://extensions` → enable **Developer mode** (top right)
2. **Load unpacked** → select this `chrome-extension/` folder
3. Pin the extension to your toolbar

## Sign in

v0.1 uses a pasted session token (matches the iOS app's Apple Sign-In JWT).
Future v0.2 swaps in `chrome.identity.launchWebAuthFlow` against
`https://dripadvisor.app/auth/extension/callback`.

1. Click the extension icon
2. Paste your session token (get from iOS app → Profile → Developer)
3. Optional: set API base (default `https://api.dripadvisor.app`, use
   `http://localhost:8080` for local backend)

## Save items

- **Right-click any page / image / link** → "Save to DripAdvisor"
- **Click the toolbar icon** → "Save current page"

Both routes call `POST /v1/wardrobe/scrape` on your backend with the page URL.
The backend extracts OG / schema.org product metadata + image, creates a
wishlist-source wardrobe item, and the iOS app picks it up on next sync.

## Files

- `manifest.json` — MV3 manifest, permissions, host permissions
- `background.js` — service worker; context menu, message handler, API forward
- `content.js` — page-context helpers (minimal in v0.1)
- `popup.html` / `popup.js` — popup UI for sign-in and one-click save

## TODO before v0.2

- [ ] Real OAuth flow via `chrome.identity.launchWebAuthFlow`
- [ ] Inline "Save to DripAdvisor" badges on outfit photos (Instagram, Pinterest)
- [ ] Multi-item batch save from a Pinterest board
- [ ] Icons (currently referenced but not committed — drop PNGs in `icons/`)
- [ ] Firefox port (Manifest V3 differences)
