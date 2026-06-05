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
icons/
  store-icon.png
apps/
  notes/            ← Template app — copy this for every new app
    index.html
    manifest.json
    sw.js
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

**Step 2 — `apps/<id>/` folder with three files:**

- `index.html` — the app UI (use `apps/notes/index.html` as the starting template)
- `manifest.json` — PWA manifest (copy from `apps/notes/manifest.json`, update fields)
- `sw.js` — service worker (copy from `apps/notes/sw.js`, update `CACHE` constant name)

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

## Scope discipline

When building a new app, ship a focused v1:
- One core loop that works fully offline
- Persistence via localStorage
- No feature flags, no "coming soon" stubs
- If it needs more than ~300 lines of JS it probably needs scoping down

Do not add configuration screens, account systems, sync, or sharing unless explicitly
requested.
