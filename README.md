# My App Store (PWA starter)

A personal app store, the Naval way — but built on web tech so there's **no Apple
gate, no $99/yr, no device-keying**. Every "app" is a small web app you add to your
home screen. The store is itself an installable app that lists them.

## What's here

```
personal-app-store/
├── index.html      ← THE STORE. Lists your apps. Edit the REGISTRY array here.
├── manifest.json   ← makes the store installable
├── sw.js           ← offline cache for the store
├── icons/
│   └── store-icon.png
└── apps/
    └── notes/      ← example app (a working, installable notepad)
        ├── index.html
        ├── manifest.json
        └── sw.js
```

## Run it locally

PWAs need to be *served* (not opened as a file), because service workers don't run
over `file://`. From this folder:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000` on your computer, or — to test on your phone —
find your computer's local IP and open `http://<that-ip>:8000` on your phone while
on the same Wi-Fi.

## Get it onto your iPhone home screen

1. Host the folder somewhere with HTTPS — **Vercel, Netlify, or GitHub Pages** are
   all free and take ~2 minutes. (iOS only installs PWAs over HTTPS.)
2. Open the URL in **Safari** on your iPhone.
3. Tap **Share → Add to Home Screen**.
4. Now you've got "My App Store" as an icon. Open any app from it and Add-to-Home-Screen
   that too — each one gets its own icon and launches fullscreen.

> iOS quirk: only Safari can install PWAs, and each app is added individually.
> That's the trade for skipping Apple's developer program entirely.

## Add a new app (the Claude Code loop)

This is the whole point — the store is built to be extended by an agent.

**1.** Add an entry to the `REGISTRY` array in `index.html`:

```js
{
  id: "mood",                       // = folder name under /apps/
  name: "Mood Journal",
  version: "1.0", build: 1, updated: "2026-06-05",
  icon: "🎨",
  bg: "linear-gradient(145deg,#7c5cff,#3d9bff)",
  status: "open"
}
```

**2.** Create `apps/mood/` with `index.html`, `manifest.json`, `sw.js`
(copy the `notes/` folder as your template).

A prompt you can hand Claude Code:

> "Scaffold a new app called Mood Journal at `apps/mood/`. Copy the structure of
> `apps/notes/`. It should let me log a mood (1–5) plus a short note each day, store
> entries in localStorage, and render a simple p5.js generative visual that shifts
> color with the average mood. Then add it to the REGISTRY in index.html."

## When you outgrow PWAs

If you later want the real native "Build 18 / one-tap install" experience Naval has,
that's the paid Apple Developer account ($99/yr) + ad-hoc OTA distribution route,
with apps built in Xcode and Claude Code driving the build. This PWA store is the
zero-cost rung that proves the concept first.
