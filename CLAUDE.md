# CLAUDE.md — Personal PWA App Store

## What this repo is

A personal app store that runs as a PWA. The root `index.html` is the store shell; it
renders a list of apps from a `REGISTRY` array. Each app lives in `apps/<id>/` as its
own self-contained PWA. No build step, no bundler — plain HTML/CSS/JS, served as
static files via GitHub Pages.

## Repo layout

```
index.html          ← The store. Edit REGISTRY here.
manifest.json       ← Makes the store itself installable
sw.js               ← Store service worker
apple-touch-icon.png  icon-192.png  icon-512.png   ← store's own home-screen icons
tools/
  gen_icons.py      ← Regenerates every icon (see "Home-screen icons")
icons/
  store-icon.png    ← legacy shared icon (kept; no longer referenced)
apps/
  notes/            ← Template app — copy this for every new app
    index.html
    manifest.json
    sw.js
    apple-touch-icon.png  icon-192.png  icon-512.png
```

## Adding a new app — two steps, always both

**Step 1 — REGISTRY entry in `index.html`:**

```js
{
  id: "courage",          // must match the folder name under apps/
  name: "Daily Courage",
  version: "1.0",
  build: 1,
  updated: "2026-06-04",  // ISO date of last change
  icon: "🔥",
  bg: "linear-gradient(145deg,#ff4d4d,#ff8a3d)",
  status: "open"          // "open" or "update"
}
```

**Step 2 — `apps/<id>/` folder with three files (plus icons):**

- `index.html` — the app UI (use `apps/notes/index.html` as the starting template)
- `manifest.json` — PWA manifest (copy from `apps/notes/manifest.json`, update fields)
- `sw.js` — service worker (copy from `apps/notes/sw.js`, update `CACHE` constant name)
- icons — add a spec to `tools/gen_icons.py` and run it (see "Home-screen icons")

Both steps are required. An entry without a folder 404s; a folder without an entry is invisible.

## Path conventions

The site is served from a GitHub Pages subpath (e.g. `https://user.github.io/my-app-store/`).
Use **relative paths everywhere** — no leading `/`. Examples:

- Store → app: `href="apps/courage/index.html"`
- App back-link: `href="../../index.html"` (two levels up from `apps/<id>/`)
- App manifest: `"start_url": "index.html"` (relative, inside the app folder)
- Shared icons: `"src": "../../icons/store-icon.png"` (in each app's manifest.json)

## Persistence

**localStorage only** — no backend, no accounts, no network calls for data.

Namespace every key with the app id to avoid collisions:

```js
localStorage.setItem('courage.v1.streak', value);
localStorage.getItem('courage.v1.completions');
```

## iOS PWA requirements

Every app's `<head>` must include:

```html
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Short Name">
<meta name="theme-color" content="#hexcolor">
<link rel="manifest" href="manifest.json">
```

Without these, "Add to Home Screen" on iOS will open in Safari instead of launching
standalone.

## Home-screen icons

Every installable target — the root store **and** each app — has its own distinct
home-screen icon so they don't collapse to a generic glyph when saved to an iPhone.

**Each target ships three PNGs, stored next to the `index.html` that references them**
(root for the store, `apps/<id>/` for each app), keeping paths relative and offline-safe:

| File | Size | Used by |
|------|------|---------|
| `apple-touch-icon.png` | 180×180 | iOS Add to Home Screen |
| `icon-192.png` | 192×192 | manifest (small) |
| `icon-512.png` | 512×512 | manifest (large) |

Wire them up per target:

- In `<head>`: `<link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">`
- In `manifest.json`: two `icons` entries pointing at `icon-192.png` and `icon-512.png`

Icons are **opaque PNGs with no rounded corners** — iOS applies its own squircle mask,
so the source must be a full-bleed square. Each icon is the app's CSS gradient (the same
`bg` as its REGISTRY entry) with the app's emoji centered on top, so the icon matches the
app's identity (e.g. 🔥 on coral for Courage). Keep the emoji within the centered ~70% so
it survives Android's maskable crop.

### Generating / regenerating icons

Icons are rendered by `tools/gen_icons.py` (Pillow + numpy; renders color emoji from
`C:\Windows\Fonts\seguiemj.ttf`). The committed PNGs are static — you only rerun this when
an emoji or gradient changes, or when adding an app:

```bash
pip install Pillow            # one-time; numpy is already present
python tools/gen_icons.py     # run from the repo root
```

To add an app's icons, append a spec to the `SPECS` list in `tools/gen_icons.py`
(`dir`, `emoji`, `c0`/`c1` gradient stops matching the REGISTRY `bg`) and rerun.
Then bump that app's service-worker `CACHE` (the icon files are listed in `ASSETS`).

## Service worker cache

When you change any file in an app, bump the `CACHE` constant in that app's `sw.js`
so stale assets don't persist on installed PWAs:

```js
// before
const CACHE = 'courage-v1';
// after a change
const CACHE = 'courage-v2';
```

Also add any new files to the `ASSETS` array.

## Styling conventions

- Dark background, one strong accent color per app (not the same as another app's accent)
- Self-contained CSS in the `<style>` block — no shared stylesheet
- No external CSS frameworks
- Mobile-first; test at 390 px wide (iPhone 14 viewport)
- Use `env(safe-area-inset-*)` for notch/home-indicator clearance

## External libraries

**Ask before adding.** The store runs offline; every CDN dependency is a potential
failure point. Prefer inline SVG, CSS, and vanilla JS. If a library genuinely saves
significant complexity, pin a specific version URL (not `@latest`).

## Deployment

Push to `main` → GitHub Pages auto-deploys. No CI step needed. After pushing, allow
~30 s for Pages to update before testing on device.

## Notes sync (`notes/`)

`notes/` at the repo root is **not a normal folder** — it's a Windows directory
**junction** to a wiki kept outside the repo (`C:\Users\andre\LLM Wiki`), which must
stay where it is. Created with:

```bat
mklink /J "C:\Users\andre\Documents\my-app-store\notes" "C:\Users\andre\LLM Wiki"
```

Git follows the junction like a real folder and commits the actual note **files** (not a
link reference), so no `core.symlinks` config is needed. `/J` junctions don't require an
admin terminal; `/D` symlinks would (and would store a broken reference instead — don't
use them here).

`tools/sync-notes.ps1` is the unattended sync: it rebuilds `apps/wiki/notes-index.json`
from the notes, commits changes under `notes/` (and that index) with a timestamped message,
pushes only when the branch is ahead of `origin/main`, no-ops when nothing changed, and
fails quietly when offline (next run retries). It's registered in **Task Scheduler**
("Sync LLM Wiki", every 5 min, run only when logged on) so the push uses the logged-in
user's stored GitHub credential.

The **Wiki app** (`apps/wiki/`) is the in-store reader: a read-only markdown browser that
fetches `notes-index.json` for the list and the live `../../notes/<path>` files for each
note (rendered by a small inline markdown function — no libraries). The index is generated
data, not hand-edited; `[]` until the first sync runs.

**This repo is public** — everything under `notes/` is published to GitHub and the Pages
site. **Junction footgun:** never `Remove-Item -Recurse notes`, delete it in Explorer, or
`git clean -fdx` here — those can reach through the junction and delete the real wiki. To
drop the link safely: `rmdir notes` (cmd), which leaves the target untouched.

## Scope discipline

When building a new app, ship a focused v1:
- One core loop that works fully offline
- Persistence via localStorage
- No feature flags, no "coming soon" stubs
- If it needs more than ~300 lines of JS it probably needs scoping down

Do not add configuration screens, account systems, sync, or sharing unless explicitly
requested.
