# CLAUDE.md — Maintrix (backend-connected app)

> Read this before touching anything in `apps/maintrix/`. Maintrix is the
> **exception** to the store's "localStorage only, no backend" rule (see root
> `CLAUDE.md`). It has accounts, auth, and a live backend.

## What Maintrix is

A Supabase-backed PWA — auth ("Create your identity"), and data/storage/realtime
over the network. Unlike the other apps in this store, it is **not** self-contained
static source.

## ⚠️ These files are BUILT output — do not hand-edit

- `app.js` (~1.1 MB) and `app.css` are **minified, bundled** artifacts. `app.js` has
  the `@supabase/supabase-js` client compiled in.
- **The source code is NOT in this repo.** There is no `package.json`, `src/`, or
  bundler config here — the build lives in a **separate project** that produces
  `app.js`/`app.css` and copies them here.
- **Never try to fix behavior by editing the minified `app.js`.** Real code changes
  happen in the external source project, which then rebuilds these files. If you need
  to change Maintrix's code, **ask the user where the source project is** first.
- `index.html`, `manifest.json`, icons, `sw.js`, `pow-worker.js` are the only
  hand-editable files here — and even `index.html` references the hashed built assets
  (`app.css?v=…`, `app.js?v=…`) with Subresource Integrity hashes, so if a build
  regenerates the bundles those `?v=` and `integrity=` values must match.

## Backend: Supabase

- **Project ref:** `uwvgfxnwtgnwcwostwxs` (URL `https://uwvgfxnwtgnwcwostwxs.supabase.co`)
- The `index.html` CSP allows `https://*.supabase.co` + `wss://*.supabase.co`
  (REST, Auth/GoTrue, Storage, Realtime), Supabase Storage for images/media, and
  `ntfy.sh` for push notifications. Keep the CSP in sync if endpoints change.
- Anon key + project URL are injected at **build time** (from the external source
  project's env) — they are intentionally not committed here.

## Supabase MCP server (how to inspect/manage the backend)

A hosted Supabase MCP server is configured in the repo root **`.mcp.json`**
(gitignored, no secrets — OAuth-based). It targets project `uwvgfxnwtgnwcwostwxs`
with features: docs, account, database, debugging, development, functions, branching.

- If the `supabase` MCP tools aren't loaded in your session: run **`/mcp`** and
  complete the browser OAuth sign-in (the user does this — it's their account).
- Once connected, use the `supabase` tools to inspect tables, schema, RLS policies,
  edge functions, logs, and to run SQL.
- **It is currently full-access, not read-only.** Be deliberate with any write/DDL —
  confirm with the user before mutating data or schema. (To make it read-only, add
  `&read_only=true` to the URL in `.mcp.json`.)

## Deploying changes

Pushing to `main` auto-deploys via GitHub Pages (see root `CLAUDE.md` → Deployment),
so the built files committed here go **live**. When updating the bundles:
1. Rebuild in the external source project.
2. Copy the new `app.js` / `app.css` (and any other changed assets) here.
3. **Run `python tools/stamp_maintrix.py`** (from the repo root). This recomputes
   the `integrity=` SRI hashes in `index.html` and the `INTEGRITY` map + `CACHE`
   in `sw.js` from the actual bundle bytes. It leaves the `?v=` id alone (the
   bundle references assets by that id internally) and only touches those two files.
4. Commit and push.

> ⚠️ **Do not hand-edit the SRI / INTEGRITY hashes.** The external build's own
> stamping step has shipped mismatched hashes more than once (builds 39 and 40
> both deployed dead — a wrong SRI hash makes the browser block `app.js`, so the
> app never boots and never reaches Supabase). Always run the stamper, and gate
> deploys with `python tools/stamp_maintrix.py --check` (exit 1 = stale). The
> real fix is in the external `build.mjs`; until that's corrected, the stamper is
> the safety net. See `tools/stamp_maintrix.py` for details.

_Setup note: repo cloned to the user's Desktop and Supabase MCP wired up 2026-09-24._
