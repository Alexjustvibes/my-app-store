# CLAUDE.md — Maintrix

App-scoped guide for `apps/maintrix/`. The repo-wide rules in the root
`../../CLAUDE.md` still apply (relative paths, localStorage namespacing, iOS PWA
meta tags, bump the SW `CACHE` on any change, register/version in the root
`index.html` REGISTRY, regen the icon via `tools/gen_icons.py`). This file covers
what's specific to Maintrix.

## What Maintrix is

"Discord for smart people." One **persistent identity** (built from your traits —
life goals + fears) sits at the center of a space that is at once a **communication
tool** (friends, DMs, servers), a **content platform** (feed, live), and a
**self-improvement system** (the Lobby). The whole user base is treated as **one
interconnected world**, not a pile of walled-off servers. Tagline: *"Welcome to
heaven on earth."* Brand parent (intro splash): **EXPANSION**.

## Status

**Front-end prototype.** Everything is seeded/local (localStorage key
`maintrix.v2`) EXCEPT **The Commons**, which is a real live public room over a
keyless relay (ntfy.sh). No accounts, no real cross-device identity, DMs/servers
are local. **Next major step: scope + build the real backend** (accounts, real
messaging, presence) — the user has asked to start scoping this.

It's a single self-contained file: `index.html` (HTML + CSS + JS inline). Runs from
the App Store like every other app; open `apps/maintrix/index.html`.

## Layout & tech

- **Mobile-first, single column** in a centered **phone frame** (`.frame`,
  `max-width:480px`, `100dvh`) — reads as a phone app on desktop too.
- **Bottom nav** (`.botnav`) is the primary navigation. A top bar shows the screen
  title, the tier pill, and the user's avatar (tap → own profile sheet).
- **Screens** render into `#view` (`<section class="screen" id="s-…">`), toggled by
  a tiny router (`render()` / `state.screen`). Overlays (profiles, editors, admin
  tools) render into a bottom **sheet** (`#sheetScrim`/`#sheet`, `showSheet`/`closeSheet`).
- **Message thread engine**: `renderMsgs(list)` + a thread view (`renderThread`)
  reused by DMs, servers, the Commons, Overwatch, and inline by the Nexus.
- **Tap-to-profile**: any element with `data-user="<name>"` opens that profile via
  one delegated listener on `#view`. Add `data-user` anywhere a person appears.
- **Helpers**: `avatar(name,size,{dot,ring})`, `person(name)`, `shared(p)`
  (returns a shared goal/fear vs. the current user for trait-match tags), `fmt()`
  (inline markdown + @mentions), `esc()`/`attr()` (escaping), `toast()`.
- **Icons**: one `IC` map of inline SVGs. Bottom-nav icons need `class="ni"`.
- **Intro**: EXPANSION splash (`#intro`) plays on launch, ~2.7s, tap-to-skip,
  respects reduced-motion.

### Aesthetic (red)
Tokens in `:root`. Accent `--accent:#ed2e44` (Maintrix red); warm near-black
grounds (`--ground:#150e10`, `--surface:#201417`, …); `--live:#ff2d55` for live.
Fonts: **Hanken Grotesk** (UI), **Fraunces** (display/serif moments), **JetBrains
Mono** (labels). Per-user accent color + like-aesthetic are chosen by the user
(Main only, going forward).

## Tiers (subscription only)

**Lite (free)** gets:
- The **World** Nexus (global room for everyone)
- **Your World** ("My Nexus") — the room of people with your traits
- The **Connect** section (search users, DMs, servers)
- Add friends + friend list

**Main (paid subscription)** adds:
- **Media** — the feed, viewing others' posts, livestreams; and creating your own
  posts / going live
- **The Lobby** (self-actualization program + acolyte hub)
- **Trait Nexus Browsing** (join other trait rooms, incl. others' "My Nexus")
- **Nexus Topic Rooms** (create/join topic-based nexuses)
- **Choosing the aesthetic** of your username + profile

Paywall = subscription (no per-section one-time unlock). The "you're missing this"
pressure is mostly implicit; emphasize lightly. Locked Main surfaces show a
preview + Unlock. Prototype unlock is instant/free.

## The Nexus system (core, novel piece)

**Current state (v0.8): scaled down to just The Nexus** (the single global room
below) while the user base is small — see the v0.8 build-state note. The rest of
this section describes the full design, which is **preserved for later, not
abandoned**: re-introduce Your World / Trait Nexus Browsing / Nexus Topic Rooms
once there's enough of a user base to justify splitting into multiple rooms.
Their code is already written and untouched (`openYourWorld`, `openTraitBrowse`,
`openTopicRooms`, `createTopicRoom`) — re-adding them is a `renderNexus()` UI
change, not a rebuild.

Bottom-nav "Nexus" opens the nexus hub. Every nexus room shows each user's
**location (country/state)** near their name, for everyone.

- **The Nexus** (formerly "World"): one global room for all app users. Live today.
- **Your World** (the "My Nexus"): a room for people who share **your** traits.
  Label shown: **"Your World"**. The room's traits show top-right for everyone.
  While in your own trait room, the **"at home"** label shows next to your name.
  Has a **global** version (all app users with your traits) and a **location**
  version (users with your traits in your country/state).
- **Trait Nexus Browsing** (Main): "Choose trait nexus to join" → a fullscreen
  browser of all trait nexuses; global section + location section. Joining a room
  that isn't your trait shows the **"foreigner"** label on you; your own shows
  **"at home"**. The room's traits show top-right.
- **Nexus Topic Rooms** (Main): create your own (requires **Topic Category** +
  **Room Title**) or browse by topic category → join. In a topic room, the Title +
  Category show top-right for everyone.

## Connect (bottom-nav; renamed from "Chats")

Three tabs: **Search · DMs · Servers**.

- **Search**: search people by name; tap a result → their profile; add them. Also a
  **"People I like"** area listing everyone you've liked (quick access to profiles
  you found insightful).
- **DMs**:
  - **DM requests** entry at the top-left → opens the requests people sent you;
    **Accept** or **Deny** (Deny asks *"Are you sure you want to deny? Yes / No"*).
  - You can send a person **only one DM** until they accept (Discord-style).
  - Accepted DMs live in the middle of the section (as now).
- **Servers**: a **Private** side and a **Public** side. Users create servers and
  toggle public/private anytime. **Browse public servers**: app-recommended list +
  a search bar; browse by **topic category**. Creating a server requires **Topic
  Category + a bio (what it's about) + Title**.
  - **Ranks**: app-provided pre-ordained ranks (by "ranking intelligence") that
    owners assign; a user's rank shows next to their name in the server. Plus
    owner-created custom **roles** (Discord-style).

## Identity & Profile

- **Traits are set at SIGN-UP and are not editable afterward.** The sign-up screen
  collects the identity (name + life goals + fears; color/aesthetic if applicable).
  There is **no "Edit identity"** in settings.
- Profile shows: avatar (red **live ring** when live), **likes** (aesthetic icon) +
  **server-scoped likes**, bio, **Chasing** (goals) / **Escaping** (fears), a
  **Badges** section (accomplishments — none defined yet), and a **Posts** section.
- **Friend list**: visible **only to the owner**, reached from **their own profile
  → Settings → Friend list** (this replaces the old "Edit identity" row). On
  **other** people's profiles you can see **mutual friends** (Discord-style).
- **Likes, not follow**: the button on a user's posts / profile says **Like** (not
  Follow). Liking adds to that user's like count; **one like per user**, and it's
  toggleable (you can take it back). Likeable from a post and from their profile.
- **Posts**: a Posts section at the bottom of every profile. **Post/view requires
  Main.** Tapping a post opens it **fullscreen, TikTok-style** (video fills screen).
  For Lite users, posts on any profile are **blurred + locked**.
- **Go live**: red **Go Live** button on the Live page (Main-gated), not in settings.

## Messages

- **Reply** to any message (yours or others') — **long-press** a message → a reply
  option (Discord-style).
- **Edit** and **delete** your own messages.

## The Commons (live, public, real)

A public server whose room syncs over **ntfy.sh** (keyless public relay): anyone
running Maintrix and in the room sees typed messages in real time. Topic:
`maintrix-commons-…`. **Public** — never for private content; label it clearly.
Private DMs/GCs stay local and never hit the network. Implemented via a plain
`WebSocket` (`wss://ntfy.sh/<topic>/ws`) for receive + `fetch` POST for send;
own-echo filtered by a per-session `CLIENT_ID`.

## Build state (as of v0.12)

**v0.12** — app-wide themes, a couple more personal display settings, and
debate ELO ranks (migration `0014`):

- **App themes** (`APP_THEMES`, Profile → Settings → **Theme & display**):
  7 presets (Crimson/Azure/Violet/Emerald/Amber/Rose/Graphite) that recolor
  `--accent`/`--accent-hi`/`--accent-press`/`--accent-soft` on `:root` via
  `applyAppTheme()`. **Personal and client-side only** — it changes how the
  app looks to you, not how your name/messages look to others (that's still
  the separate per-user `color` swatch in Appearance). Applied on every boot
  from `enter()`.
- **Text size** (`state.textSize`, small/medium/large) — scales the whole
  `.frame` via `zoom` (`applyTextSize()`) rather than touching individual
  font-size rules, so it scales everything (text, icons, spacing) together
  without a big refactor.
- **Reduce motion** (`state.reduceMotion`) — an explicit override alongside
  the existing OS-level `prefers-reduced-motion` check; both now gate the
  intro splash, and a `body.reduce-motion` class kills transitions/animations
  app-wide (`applyReduceMotion()`).
- **Debate ELO / ranks** — winning a debate raises your ELO (`profiles.elo`,
  starts at 1000), losing lowers it, a tie nudges both toward the midpoint —
  standard ELO math with a high K-factor (64) so rank changes are fast and
  visible, computed entirely inside `end_debate()` (no client-side scoring).
  Also tracks `debate_wins`/`debate_losses`/`debate_ties`. Seven rank tiers
  (`DEBATE_RANKS`: Novice → Contender → Skilled → Sharp → Expert → Elite →
  Master) are purely a client-side label over the ELO number
  (`debateRankFor`/`debateRankBadge`) — shown next to debaters' names in the
  debates list, the debate head (VS card), and on a profile (new "Debate
  Rank" trait-group, shown once someone has at least one recorded
  win/loss/tie). The debates tab also got a **🏆 leaderboard**
  (`openDebateLeaderboard`, `db.debates.leaderboard()`) ranking everyone
  who's played by ELO.
- **Fix (same batch):** the theme system originally just swapped `--accent`/
  `--accent-hi`, but ~39 places already reused `--accent-hi` to mean
  "destructive/danger" (delete server, kick, ban, the DND status dot, message
  delete) — so a green or blue theme was turning delete buttons that color
  too. Added a fixed `--danger`/`--danger-line` pair (never touched by
  `applyAppTheme()`) and repointed every genuinely destructive control at it;
  everything else (badges, likes, active tabs, mentions) still correctly
  follows the theme. Also added `--accent-deep` to the themed set so
  `.card:hover` (previously a silently-unthemed hardcoded fallback) recolors
  too. Verified in-browser: switching themes now leaves Kick/Delete/DND red
  while the rest of the chrome recolors.

## Build state (as of v0.20 — deeper audio fix, universal viewport-jump guard, landscape handling, more visual polish)

- **Audio: found a second real bug on top of last round's fix, both now
  fixed together.** `SFX.play()` called `unlock()` then fired the sound
  *immediately after*, without waiting for `resume()` to actually land —
  the very first sound of a session could get scheduled on a context that
  was still technically `'suspended'` at that exact millisecond and got
  silently dropped, even though the unlock had genuinely started and
  every sound after it played fine. If someone's whole test was "tap
  once, don't hear anything," that's exactly what this produces. Now
  `play()` defers the very first sound ~60ms (only when the context
  isn't already running — zero added latency once it is) so `resume()`
  has a beat to land before anything's scheduled. Also widened the
  unlock trigger from `pointerdown` alone to also `touchend`/`mousedown`/
  `click`/`keydown` (idempotent, near-zero cost once unlocked — different
  iOS/WebKit versions have disagreed on which event types count as a
  real "user activation" for audio), and raised the master gain .16→.28
  since some of the shorter taps were plausibly just too quiet to
  register as "working" on a phone speaker. Real, unfixable-from-the-web
  caveat repeated from last round: the iOS silent/mute switch mutes all
  Web Audio output regardless of any of this. Still couldn't be verified
  on an actual phone in this environment.
- **The "screen goes up when you tap a button" report, round 2**: added
  a universal safety net rather than continuing to chase the exact
  trigger — every click in the app now re-runs `syncFrame()` +
  `resetFrameScroll()` (immediately and again 150ms later), on top of
  the existing visibility/focus/pageshow triggers from v0.18. Self-
  correcting regardless of which specific thing (iOS Safari chrome
  show/hide, a focus change, a sheet transition) is actually causing the
  drift, and cheap enough (two reads, two writes, worst case) to run on
  every tap without it being noticeable.
- **Landscape phone orientation is now handled on purpose instead of
  silently looking broken.** A phone-chat layout genuinely has nowhere
  to put itself at landscape phone *heights* (topbar + composer +
  bottom nav alone can eat most of ~375px) — this had literally zero
  handling before (one `@media` rule in the whole app, for a desktop
  border). Added `#rotatePrompt`, shown via
  `@media (orientation:landscape) and (max-height:500px)` — deliberately
  keyed on height, not width, so it catches an actually-rotated phone
  without also catching a normal short-but-wide desktop window. Verified
  in-browser at 375×667 (shortest common iPhone height), 430×932
  (largest common iPhone), and a rotated 844×390 — all three correct,
  and rotating back to portrait recovers instantly with no reload
  needed (pure CSS, nothing to re-render).
- **More visual polish**: every avatar app-wide now renders a two-tone
  diagonal gradient (`color-mix` off the same stored color) instead of a
  flat fill — one change in the shared `avatar()` helper, so it applies
  everywhere a person renders (messages, profiles, search, DMs,
  servers) at once. Liking something now bursts a quick expanding ring
  outline alongside the existing pop. The notification bell does a
  quick shake (`bell-ring`) on a genuinely new real-time notification —
  previously arrived with no sound *or* animation at all online (the
  local/offline demo path already had a chime; the real online
  Realtime-subscription path didn't). Badge chips got a subtle
  metallic shine sweep and real depth shadow instead of a flat chip
  background, closer to a trophy-case feel. All of the above respect
  `body.reduce-motion`.

## Build state (as of v0.19 — Discord-style avatar cropper, per-screen visual identity, mobile audio fix, real install path)

- **Push notifications: verified already working in production, no code
  change needed.** Queried `net._http_response` directly against the live
  project — real (non-synthetic) rows exist with `status_code:200` and
  bodies like `{"sent":1,"removed":0,"errors":[]}`, meaning actual pushes
  have been successfully delivered to real subscribed devices. Also
  confirmed 4 of the 5 live `push_subscriptions` rows are
  `web.push.apple.com` endpoints — i.e. at least one real person has
  already installed the PWA to an iPhone Home Screen *and* has push
  working. Didn't fire a fresh test push this round since that means a
  real notification lands on a real person's phone with fabricated
  content — confirmed via existing history instead of manufacturing new
  evidence.
- **Fixed mobile sounds not playing — the real bug was a one-shot unlock
  flag.** `SFX.arm()` set a permanent `armed=true` after its *first*
  attempt to resume the shared `AudioContext`, whether or not that resume
  actually took. iOS in particular doesn't always fully unlock on the
  first try; once `armed` was set, every subsequent tap for the rest of
  the session silently skipped trying again, even though each of those
  taps was a perfectly good gesture that could have unlocked it. Replaced
  with `unlock()`, which keeps retrying on every `pointerdown` until the
  context genuinely reports `'running'` (cheap no-op once it already is),
  and also plays a silent buffer via a real `AudioBufferSourceNode`
  alongside `resume()` — the same combination Howler.js and other audio
  libraries use because `resume()` alone has historically been
  insufficient on some iOS/WebKit versions. Real caveat that's outside
  what any web app can fix: iOS Safari's Web Audio output respects the
  physical silent/mute switch by default — if that's flagged, no web
  audio plays regardless of unlocking, same as it would for any other
  website. Couldn't be verified on an actual phone in this environment.
- **"Add to Home Screen" is a real one-tap install wherever the platform
  allows it — this was already true, but it now actually gets the chance
  to fire.** `beforeinstallprompt` was only ever checked for *after* the
  service worker registration that `enter()` kicks off, meaning on a
  first-ever visit Chrome frequently hadn't had time to evaluate
  installability yet by the time `postSignupFlow()` looked for it. The
  service worker now registers immediately at boot instead. **iOS is a
  hard platform wall, not a bug**: no browser engine on iOS — Safari,
  Chrome-for-iOS, anything — exposes *any* API for a website to trigger
  "Add to Home Screen" itself; Apple simply doesn't allow it, for any
  site, including ones far bigger than this one. The three-tap manual
  guide (`openInstallGuide()`, shipped last round) is the actual ceiling
  of what's possible there.
- **Profile pictures now get a real Discord-style cropper**, not an
  instant auto-crop. `openAvatarCropper(file)`: drag to reposition, a
  zoom slider, plus a monochrome slider and a blur slider — all three
  previewed live via CSS `filter` and then genuinely baked into the
  saved image (Canvas 2D `ctx.filter`, not just a client-side preview
  effect that gets thrown away). Always outputs a real 512×512 square
  regardless of what was uploaded or how it's framed. Server icons keep
  the plain auto-center-crop from last round — nobody asked for the full
  picker there.
- **Every main screen now has its own visual identity** instead of
  sharing one bare background: Feed gets a photo/film light-leak
  diagonal, Connect a fading constellation of dots, Debates a top-down
  arena spotlight, Lobby slowly rising warm embers (gold, not the usual
  all-red palette — reduce-motion kills the rise animation like
  everywhere else), Watch/Live thin broadcast scanlines with an on-air
  glow, and Overwatch a fading HUD/targeting grid. All pure CSS
  (`::before`, `z-index:-1`, `pointer-events:none`) — no HTML/JS
  structure changes, so risk of breaking anything underneath is close to
  zero. Live and Lobby are still unreachable from navigation (unchanged
  from earlier — re-add per the existing note in `navItems()`), so their
  treatments are ready for whenever those come back, same as the
  Nexus-variant code already preserved that way.
- **Fixed a real topbar collision found while testing the above**: the
  "Overwatch" title was long enough to visually overlap the tier pill
  next to it — `.tb-title > span:first-child` was pinned
  `flex:0 0 auto` (deliberately non-shrinking, from the v0.15.1 title-
  wrap fix) with no overflow handling of its own, so when the title
  itself didn't fit, it spilled into its neighbor instead of clipping.
  Now shrinks with `overflow:hidden;text-overflow:ellipsis` as a
  fallback. Also found the actual root cause was mostly starvation, not
  just missing ellipsis: `SUBS` had `feed:'main'`, `live:'main'`,
  `lobby:'main'`, `overwatch:'admin'` — pure duplicate noise, since the
  tier pill sitting right next to it already says exactly that — and
  removing those gave the title back most of the room it needed. Only
  `nexus` and `debates` keep a real, non-duplicate subtitle now.

## Build state (as of v0.18 — security hardening, avatar fix, viewport jump fix, admin delete account, Nexus rebrand)

- **Root-caused and fixed the sign-up/onboarding "completely unaligned" report**
  from v0.17: `#auth, #supaAuth { position:relative; overflow:hidden; }`
  (added to give `.auth-glow` a positioning context) silently overrode the
  base rule's `position:absolute` — same selector, same specificity, later
  in the cascade wins. That collapsed the screen from filling the frame to
  content-height only, leaving a large dead gap below. Fixed by dropping
  `position` from that rule entirely (`position:absolute` was already a
  valid containing block for `.auth-glow` — didn't need touching). Also
  found and fixed two related scroll bugs while re-verifying the whole
  flow in-browser: `.frame.scrollTop`/`scrollLeft` could end up non-zero
  after a screen or onboarding-step transition (seen on real taps, not
  synthetic clicks — browser-triggered, not app-triggered), shifting
  content up or sideways with a dead gap on the opposite edge. Fixed with
  `resetFrameScroll()`, called on every auth/onboarding screen transition
  and every onboarding step change — cheap enough to just always reset
  rather than chase the exact trigger. Re-verified all 4 onboarding steps,
  trait-card selection, and text-size small/medium/large end to end.
- **Fixed profile-picture/server-icon stretching.** Avatars are displayed
  everywhere in square (1:1) boxes with `object-fit:cover`, but the raw
  uploaded photo — whatever aspect ratio the source image happened to be —
  was uploaded unprocessed, so anywhere a container wasn't pixel-perfect
  square the image rendered as a warped oval instead of a clean circular
  crop. `cropToSquare(file, size)` now center-crops and downsizes to a real
  512×512 square client-side (via canvas) before it ever reaches storage,
  wired into the profile picture, server-create picture, and server-edit
  picture uploads — every avatar/icon in the app is now guaranteed square
  at the source, regardless of what was uploaded.
- **Fixed the screen randomly jumping when switching tabs/apps.**
  `syncFrame()` only ever re-ran on `visualViewport` resize/scroll — coming
  back from the background (app switcher, alt-tab) doesn't fire either, so
  the frame stayed pinned to whatever height was measured before switching
  away, even if the browser's own chrome (address bar, etc.) had changed
  in the meantime. Now also re-syncs on `visibilitychange` (tab/app
  becoming visible again), `pageshow`, and `focus` — each re-runs
  `syncFrame()` immediately, on the next frame, and again after 150ms,
  plus snaps any stray page scroll back to origin.
- **Admins can now delete an account outright**, not just wipe its
  messages. `admin_delete_account(target)` (migration `0022`) deletes the
  `auth.users` row directly — `profiles.id → auth.users(id) on delete
  cascade` (from `0001`) takes care of everything downstream. Gated behind
  the same type-to-confirm ("DELETE") pattern as the existing wipe-messages
  action, in the same Danger section of Overwatch → Tools → Manage a
  member.
- **The Nexus room header is rebranded.** The embedded Nexus thread-head
  used to show nothing but the phone/debates icons (decluttered in
  v0.12.2). It now also shows **"CHAMBER OF THE AWARE"** (small caps,
  gradient text) and, on its own line below, a pulsing live dot +
  **"everyone, everywhere · live"** — stacked on two lines rather than
  one row, since at phone width the two pieces of text don't fit
  side-by-side without truncating one of them badly.
- **Sent notifications about being installed a real Home Screen page, not
  just a settings note.** `openInstallGuide()` is a proper page (a sheet):
  a real one-tap **Install** button where the platform actually supports
  it (`beforeinstallprompt`, captured globally and reused — Android/
  Chrome/desktop), or three-step manual Share → Add to Home Screen
  instructions in-app for iOS Safari (which never fires that event —
  there's no programmatic install path there at all). Reachable anytime
  from **Profile → Settings → Add to Home Screen**, and also offered
  once, skippably, right after finishing sign-up — alongside a new
  "Turn on notifications?" prompt (`postSignupFlow()`), asked one at a
  time since iOS treats push and install as separate capabilities.
- **Security hardening batch** (migration `0022`, run live on production):
  - **Storage bucket now has real limits.** The `media` bucket had none —
    any authenticated user could upload an arbitrarily large file of any
    content type into their own folder. Now capped at 60MB with an
    `allowed_mime_types` allowlist (real image/video/audio types only —
    also closes off uploading SVG/HTML into a *public* bucket, which
    could otherwise host attacker-controlled markup on a supabase.co
    URL). Client-side `checkUploadSize()` gives a fast, friendly error
    before even attempting the upload, with tighter per-kind caps
    (8MB image / 60MB video / 15MB audio).
  - **Server-side length caps on every piece of free-text content that
    didn't already have one**: `profiles.name`/`bio`, `messages.body`,
    `posts.body`/`caption`, `post_comments.body`. Client `maxlength`
    attributes were the *only* limit before this — trivially bypassed by
    calling the REST API directly, which could otherwise insert
    arbitrarily large rows (storage bloat, rendering DoS). Same pattern
    already used for `status_line` since `0012`.
  - **Real rate limiting**, not just a client-side debounce: a generic
    sliding-window limiter (`rate_limits` table + `enforce_rate_limit()`,
    both server-only — no RLS policy grants the client any access at all,
    so it can't be read or defeated from outside) wired via a `before
    insert` trigger onto `messages` (20/10s), `posts` (5/min),
    `post_comments` (20/min), `friend_requests` (20/min), and
    `dm_requests` (20/min — this one only actually fires on a genuine new
    DM-request row, which the existing `on_dm_message()` trigger already
    only creates once per stranger pair, so it doesn't touch an ongoing
    conversation's rate budget).
  - **Sign-up now checks the email's domain** against a list of real,
    well-known providers (Gmail, Outlook, iCloud, Yahoo, etc.) — a soft,
    client-side deterrent against typing something like `fake@fake.com`,
    not real verification (email confirmation already covers that) and
    not enforced on sign-*in*, so nobody who already signed up with an
    unlisted domain gets locked out later.
  - **Added a `Content-Security-Policy` meta tag** — the only CSP
    mechanism available to a static-hosted single-file app (no server to
    set a real header). Restricts `connect-src` to this app's actual
    backends (Supabase, ntfy, the esm.sh module host the Supabase client
    itself loads from) and disables `object-src`, so even if an XSS bug
    ever slipped through, exfiltrating data to an arbitrary attacker
    domain or loading a plugin would still be blocked. `script-src`/
    `style-src` need `'unsafe-inline'` since the whole app is one inline
    `<script>`/`<style>` by design — that's the real remaining gap, and no
    meta-tag CSP can close it without a build step. (Caught my own mistake
    here before shipping: an earlier draft included `frame-ancestors`,
    which browsers silently ignore entirely when set via `<meta>` — it
    needs a real HTTP header. Removed rather than ship a no-op line that
    just spams the console. Also caught: the first draft's `script-src`
    didn't allow `esm.sh`, which would have broken the Supabase client's
    own dynamic `import()` and silently killed all backend functionality
    the moment this shipped — verified by loading the page with CSP
    active before ship, not just by reading the directive back.)
  - **Audited RLS coverage across every table** (all 30 have row-level
    security enabled — verified by diffing every `create table` against
    every `enable row level security` across all migrations, not just
    spot-checked) and the `esc()`/`attr()`/`fmt()` templating helpers
    (HTML-escape before any markdown-style tag injection, so stored XSS
    via a message/bio/post isn't possible through the normal render path).
  - **What this pass does *not* claim**: this is a real, scoped hardening
    pass, not a guarantee of "zero vulnerabilities" — that's not a thing
    any app can honestly claim. No dedicated pen-test was run. Say the
    word if there's a specific vector to dig into further.

## Build state (as of v0.17 — sign-up/onboarding visual overhaul)

- **Auth + sign-in screens** (`#auth`, `#supaAuth`): added `.auth-glow` — a
  slower, dimmer version of the app frame's aurora technique, scoped behind
  the hero instead of the whole app. Logo mark now has a pulsing glow ring
  (`logoPulse`). Added a three-pill feature row under the tagline (Talk /
  Grow / Become, reusing existing IC glyphs). Email/password inputs
  rebuilt as `.field-ic` — icon-prefixed, matching the app's real input
  language instead of ad-hoc inline styles — plus a working show/hide
  password toggle (`saPassToggle`, eye icon swaps `type="password"` ↔
  `"text"`).
- **Onboarding progress replaced entirely**: the old thin `.ob-bar` fill is
  gone, replaced with `.ob-dots` — four numbered dots joined by connector
  lines, each dot glowing when current, filling solid with a checkmark
  (`IC.check`) once passed, connector lines filling left-to-right as you
  advance. `obShow()` now drives this instead of a bar width percentage.
  Each step's eyebrow label also got a small matching icon (people/target/
  shield/sparkle).
- **Trait cards (goals/fears) got real visual identity.** `.trait-opt` grew
  an icon slot (`GOAL_ICONS`/`FEAR_ICONS` maps onto existing `IC` glyphs —
  no new SVGs) in a rounded-square tile that goes solid gradient + glows
  when selected, plus an explicit checkmark badge in the corner — clearer
  than the old plain-background swap. Fear chips got the same icons inline.
  Both play the `like` SFX on select for a bit of tactile feedback.
- **"Continue"/"Enter Maintrix" pulses when the step is actually ready** —
  `.ready` class (reuses the `obReadyPulse` glow keyframe pattern from
  elsewhere) turns on once name+handle are valid on step 1, and always on
  the final step, so the button visibly invites the tap instead of sitting
  static the whole time.
- **A completion beat on finishing sign-up**: `showSignupFx()` fires the
  `rankup` SFX + a haptic buzz + three quick expanding rings
  (`.signupfx-scrim`/`.signupfx-burst`, same ring technique as the debate
  rank-up celebration) between "profile saved" and actually landing in the
  app, instead of an instant, uneventful cut. Skipped entirely under
  `body.reduce-motion` (goes straight to `enter()`).
- Verified in-browser end to end: dots correctly show done/current/pending
  state and connector fill as you step through all 4 pages; selecting a
  goal/fear shows the icon-tile + glow + checkmark; the ready-pulse
  toggles on/off correctly typing into name/handle; the password
  show/hide toggle flips the input's type; the completion burst fires and
  the app boots normally afterward.

## Build state (as of v0.16.1 — regression fixes: viewport jump, send-scroll, DM call button)

- **Fixed a real regression from `v0.14.1`'s keyboard/text-size fix**: the
  screen would randomly jump upward on a real phone, exposing the OS status
  bar over the chat (reported with a screenshot). Root cause was
  `syncFrame()` also setting `frame.style.top` to chase
  `visualViewport.offsetTop`, meant to counter iOS repositioning fixed
  content when the keyboard opens — but on-device this fought the
  browser's own compensation and produced a visible upward shift instead.
  That was never verified against a real device, only reasoned about; the
  screenshot proved it wrong. Removed the `top` compensation entirely —
  `syncFrame()` now only sets `.frame`'s height (the part that WAS verified,
  against actual dvh/zoom scaling math). The existing
  `window.addEventListener('scroll', ()=>scrollTo(0,0))` snap-back plus
  `body{position:fixed}` already cover the layout-viewport-scroll case this
  was also trying to handle.
- **Fixed "sending a message scrolls the chat up."** `.msg` carried a
  blanket `animation:msgIn` — since `renderMsgs()` rebuilds the *entire*
  message list as one HTML blob on every send/receive/reaction/edit, that
  animation replayed for **every message in the thread simultaneously**
  each time, not just the new one. Right as `scrollTop` jumped to the
  bottom, the whole history would visibly "rise into place" at once —
  reads exactly like an unwanted scroll. Fixed by moving the animation to
  a `.msg-in` class applied only to the specific message that just
  arrived: `renderMsgs(list, ctx)` now checks `ctx._animateId` per row, and
  every call site that appends exactly one message (online send, offline
  send, media upload, the realtime INSERT handler, the offline simulated
  reply, and the Commons relay) sets `th._animateId = <newMsgId>`
  immediately before rendering and clears it right after — so a plain
  reaction/edit repaint (which sets no `_animateId`) no longer animates
  anything, and a send animates only its own bubble.
- **DMs now show the same call/phone icon as the Nexus header**, replacing
  Room Options there. `isCall = isEmbed || !!th.dmKey` drives both the
  icon (`IC.phone` vs `IC.gear`/`IC.bell`) and the click handler
  (`openVoiceChannel(th.roomId, th.title)` vs `openRoomOptions`) — DMs and
  the embedded Nexus room now behave identically for this button. Servers
  are unaffected (still gear → Room settings).
- Verified in-browser: sending two messages in a row animates only the
  second bubble and leaves history untouched; a DM thread's header button
  reads "Voice call" with the phone glyph and routes into
  `openVoiceChannel` (falls back to a toast offline, same as Nexus). The
  viewport-jump fix couldn't be re-verified on a real device here (no
  physical keyboard in this environment) — the removed code was the
  unverified part in the first place, so this trades a speculative,
  now-disproven fix for a plainer one that's actually been checked.

## Build state (as of v0.16 — right-click/long-press moderation, admin panel overhaul)

- **Admins can right-click (desktop) or long-press (touch) any avatar/name
  anywhere in the app** — messages, search results, profiles, mini-profiles,
  DM headers, anywhere carrying `data-user` — to get a moderation menu
  directly, no detour through Overwatch → Tools required (`showAdminUserMenu`,
  wired once in `wireAdminUserMenu` on `.frame`). Right-clicking/long-pressing
  a message's *body* instead of its avatar still opens the normal
  reply/edit/delete menu, which now carries a "Moderate <name>…" entry for
  admins that opens the same menu — so both entry points exist, as asked
  ("even though it should be there too" → Overwatch Tools also got every
  action, in a fuller "Manage a member" panel).
- **Bug caught while wiring this**: the menu's own guard against moderating
  yourself was `p.id===me().id||p.name===me().name` — offline demo profiles
  have no `.id` field at all, so `undefined===undefined` was `true` and the
  menu silently refused to open for *anyone* in local/demo mode. Fixed to
  compare the lookup key itself (name offline, uuid online) against both of
  `me()`'s identifiers. Caught by testing offline before shipping, not by a
  report.
- **New moderation powers** (migration `0021`, already run on production):
  - **Timed mute** (1h/24h/7d, or Unmute) — `profiles.muted_until`,
    enforced in `msg_insert`'s RLS policy via `is_muted()` alongside the
    existing ban check. Can still read, can't post until it passes.
  - **Remove a badge** — badge deletion already had an RLS policy
    (`badges_delete`, admin-only, from `0007`) but no UI; added
    `openRemoveBadge()` (a dedicated sheet, tap a badge to remove it) and an
    inline "✕" on each badge chip in the Overwatch member panel.
  - **Rename**, **clear bio & status**, **reset avatar & banner** —
    `admin_edit_profile(target, patch jsonb)`, a single RPC that only ever
    touches `name`/`bio`/`status_line`/`avatar_path`/`banner_path` — never
    handle/goals/fears/tier/admin/banned, which all keep their own
    dedicated, narrower RPCs.
  - **Delete all of a member's messages** — `admin_delete_user_messages`,
    gated behind `confirmType()`'s type-to-confirm ("DELETE"), returns the
    row count so the toast can say how many were removed.
  - **Reset one member's ELO** — `admin_reset_user_elo` (the single-user
    sibling of `0019`'s leaderboard-wide reset).
  - **Kick from a server** — `admin_kick(target, room)`, refuses to kick
    the room's owner.
- **Overwatch → Tools → Manage a member panel rewritten** to expose all of
  the above (previously just admin/tier/ban toggles): grouped into Access /
  Mute / Profile / Badges / Danger, each member's badges listed live with a
  tap-to-remove "✕", header line shows ELO and remaining mute time.
- Every action funnels through one `run(fn, successMessage)` helper (both
  in the context menu and the Tools panel) — plays the success/error chime,
  toasts, and re-renders from a fresh `db.profiles.byId()` fetch so the
  panel never shows stale state after an action.
- **Verified in-browser** (offline, since these are admin-privileged RPCs
  with no local/demo equivalent to hit against a real DB): right-click on
  an avatar opens the menu with the correct self-check now passing; the
  message-menu's "Moderate…" entry chains into the same menu; the Tools
  panel renders all 10-12 action chips correctly for muted/unmuted and
  admin/banned member states; rename/wipe dialogs show correct copy;
  Award/Remove badge sheets render and prefill the target. **Not
  verified**: an actual live RPC round-trip (needs a second real admin
  account to moderate) — logic verified against the confirmed-live
  migration `0021` schema instead.

## Build state (as of v0.15.1 — profile sheet gap, mention/reply highlight)

- **Profile sheet dark strip above the banner is gone.** `.sheet-grab`
  (10px margin + 4px bar + 4px) sat above the banner as a bare band.
  `.prof-banner` now gets `margin-top:-19px` (height bumped 88→106 so the
  visible area is unchanged) and the grab handle floats over it
  (`position:relative; z-index:3` + a small drop shadow so it reads on any
  banner color).
- **Messages that @mention you or reply to you are highlighted** in every
  thread: `forMe(mm)` (handle/name mention regex, or `replyTo.a` matching
  you; never your own messages) adds `.msg-hi` — gold left rail + gold
  gradient wash, and the `@you` chip itself flips to solid gold. Mono
  theme (Awake) gets a white rail on `#1a1a1a` instead.
- **Fix**: the topbar title could shrink to nothing at narrow widths (title
  span had `overflow:hidden` + default flex-shrink while the sub was
  `flex:0 0 auto`, so "Nexus" collapsed to a dot on 375px). Flipped it: the
  title is `flex:0 0 auto`, the `· one world` sub truncates with an
  ellipsis instead.

## Build state (as of v0.15 — Web Push notifications, iOS included)

- **Push works end-to-end** (migration `0020`, already run on production;
  Edge Function `send-push` deployed via the dashboard editor with **Verify
  JWT OFF**). Pipeline: any `insert into notifications` → `trg_notify_push`
  checks the recipient's `profiles.notif_prefs` + that they have a
  `push_subscriptions` row → builds title/body/url → `net.http_post` (pg_net)
  to the function → function loads that user's subscriptions and sends via
  the Web Push protocol (`npm:web-push`), deleting endpoints that 404/410.
  **Verified live**: synthetic subscription on `ret` with a dead FCM endpoint
  → badge notification insert → `net._http_response` shows `200
  {"sent":0,"removed":1}` — trigger fired, secret accepted, payload
  encrypted, FCM reached, dead endpoint pruned. Only the last hop (a real
  phone) is unproven here; tap-test on an installed iPhone/Android.
- **Secrets are in Supabase Vault, not in git**: `push_secret` (trigger→
  function auth header `x-push-secret`), `vapid_public`, `vapid_private`.
  The function reads all three via `push_secrets()` — a `security definer`
  RPC granted **only to `service_role`**, so nothing had to be pasted into
  Edge Function secrets. If Vault is empty the trigger silently skips and
  the function answers 503. The public VAPID key is hardcoded client-side
  (`VAPID_PUBLIC`) — it's public by design. To rotate: new keypair, update
  the two vault rows + `VAPID_PUBLIC`, and existing subscriptions must
  re-subscribe (they're bound to the old key).
- **iOS reality**: push only reaches an app installed to the Home Screen on
  iOS 16.4+ — a Safari tab can't subscribe at all. `PushMgr.status()`
  returns `needs-install` in that case and the Notifications sheet explains
  Share → Add to Home Screen. Other states: `on`/`off`/`blocked`/
  `unsupported`.
- **Client**: `PushMgr` (`enable` = permission → SW register → subscribe →
  `db.push.save` upsert on `endpoint`; `disable`; `sync` runs on every boot
  when permission is already granted, since browsers rotate endpoints and
  iOS drops them). `sw.js` got `push` (always shows — Chrome and iOS both
  penalize silent pushes) and `notificationclick` (focus an open window and
  postMessage `push-open`, else `openWindow`). `routeFromUrl()` handles the
  deep links pushes carry: `?post=`, `?room=`, `?notifs=1` (also used by
  the SW message path when the app is already open).
- **Notification settings** (Profile → Settings → Notifications, online
  only): master push switch with live status, then per-type rows — DMs,
  Mentions, Replies, Likes, Comments, Friends, Debates, Badges, Servers —
  stored in `profiles.notif_prefs` jsonb (missing key = on). Enforced
  **server-side in the trigger**, not just hidden client-side.
- **New notification producers** ("almost everything"): `debate_join`
  (opponent joined your debate), `debate_end` (both debaters, with a
  per-recipient summary like `You won "X" · +24 ELO`), `badge` (trigger on
  `badges` insert — covers auto-awards and admin awards), `server_join`
  (someone joined a server you own). `on_message_notify` now stores a
  140-char `preview` in entity so DM/reply/mention pushes show the text.
- **Bug found and fixed on the way**: `notifications.type` check constraint
  from `0006` was never widened when `0015` started inserting `'dm'`. After
  this morning's `0015` run, **every DM send would have failed** (trigger
  raises → message insert rolls back) — production showed 17 DM messages,
  all pre-0015, and 0 `dm` notifications. `0020` recreates the constraint
  with every type. If anyone reported "Send failed" in DMs today, that was
  it.

## Build state (as of v0.14.1 — mobile typing fix (real root cause), medal podium, leaderboard reset)

- **Mobile "typing pushes everything down" on small/medium text size — actually
  diagnosed this time.** Two stacked causes, both tied to text size being
  implemented as CSS `zoom` on `.frame`:
  1. **iOS Safari auto-zooms the page when a focused text field renders under
     16px.** `.composer input` was 15px; under the frame's zoom that rendered
     as 13.8px (small) / 15px (medium) / 16.5px (large). Only large cleared
     the threshold — which is exactly the reported pattern. Fix: one rule
     forces every text field in the frame to
     `max(16.5px, calc(16.5px / var(--zoom)))` with `!important` (inline
     styles exist on a few inputs). `max()` of both forms keeps it ≥16px
     whether WebKit measures computed or zoom-adjusted size.
  2. **Chromium scales viewport units by `zoom`** (verified in-browser: at
     zoom .92, `height:100dvh` rendered 747px in an 812px viewport; at 1.1,
     893px). So small always had a 65px gap under the bottom nav and large
     always overflowed 81px (nav clipped) — on every screen, keyboard or not.
     The old `fitViewport` IIFE pinned inline px height from `vv.height`
     without dividing by zoom, so it had the identical bug, and it raced a
     second near-duplicate handler (`syncFrameToVisualViewport`). Both
     replaced by one `syncFrame()`: `height = vv.height / zoom`, `top =
     vv.offsetTop / zoom` (iOS scrolls the layout viewport to reveal the
     input), run on visualViewport resize/scroll, on load, and — crucially —
     from `applyTextSize()` whenever zoom changes. px lengths scale by zoom
     in every engine, so px ÷ zoom is the one measurement that lands exactly
     right everywhere; CSS fallback is `calc(100dvh / var(--zoom))`.
  Verified in-browser: frame is exactly viewport-height on all three sizes,
  and stays glued to a keyboard-shrunk (480px) visual viewport with the
  composer fully visible. **Still wants one real iPhone tap-test** — no
  simulator here has an actual on-screen keyboard.
- **Debate leaderboard podium is medal-colored**: 1st gold, 2nd silver, 3rd
  bronze (`MEDAL` map inside `openDebateLeaderboard`) for the avatar ring,
  pedestal gradient/border and placement number. The rank pill under each
  name still shows the ELO tier color, so tier info isn't lost.
- **Admin: Reset debate leaderboard** (Overwatch → Tools → Debates). Typed
  `RESET` confirm (`confirmType` grew `{title,yes}` options — its hardcoded
  "Delete?"/"Delete" copy was wrong for a reset). RPC
  `admin_reset_debate_leaderboard()` (migration `0019`, **already run on
  production**) sets every profile to `elo=1000`, wins/losses/ties `0`, and
  returns the affected row count. Finished debates are kept — only standings
  reset.

## Build state (as of v0.14 — full visual overhaul + synthesized sound)

- **Sound system (`SFX`)**: every sound is synthesized live with Web Audio
  (oscillators + filtered noise) — no audio files shipped, works offline.
  Bank: `tap`, `nav`, `send`, `receive`, `react`, `like`, `notify`, `open`,
  `close`, `success`, `error`, `win`, `lose`, `rankup`. Master gain is low
  (.16) on purpose. `SFX.arm()` runs on the first `pointerdown` because
  browsers refuse audio before a real gesture. `state.sound` toggle lives in
  Profile → Settings → Theme & display ("Sound effects"), default on. Wired
  into: sheets open/close, message send/receive (receive skips own echo),
  reactions, notifications, post/profile likes, debate results, bottom nav.
- **Tactile layer**: one delegated `pointerdown` listener
  (`wireTactile`) gives `.btn/.chip/.card/.row/.settings-row/.botnav
  button/.tb-btn/.segmented button/...` a spawned `.ripple` span + the tap
  sound. Ripple is skipped under `body.reduce-motion`.
- **Design tokens** added to `:root`: `--glass`/`--glass-2`/`--glass-blur`
  (backdrop-blur surfaces built with `color-mix` off the themed `--ground`/
  `--surface`, so every theme stays correct), `--sh-1/2/3` shadows,
  `--sh-glow`, `--ease-spring`, `--ease-out`.
- **Ambient aurora**: `.frame::before` — three blurred accent radial
  gradients drifting on a 42s loop, opacity .11. Tuned down from .3 after
  it flooded the whole UI in-browser. `#app` got `position:relative;
  z-index:1` so content sits above it. Frozen under reduce-motion.
- **Glass chrome**: topbar, bottom nav, msgbar, thread-head, sheet, toast
  all use `--glass` + `backdrop-filter`. Hairline borders are gradient
  lines with an accent highlight in the middle instead of flat `--line`.
- **Bottom nav**: animated active pill (`button::before`, spring scale-in)
  behind the icon + `navPop` icon bounce on switch.
- **Buttons/chips/cards**: gradient fills, glow shadows, inset top
  highlight, spring `:active`, `.btn::after` shine sweep on hover, cards
  lift 2px on hover.
- **Avatars**: inset depth shadow; `.av.live` pulses (`liveRing`); status
  dots glow in their color. Profile hero avatar gets a ground+accent double
  ring — target `.p-av .av` not `.p-av` (the wrapper is full-width; ring on
  it rendered as a giant ellipse, caught in-browser).
- **Intro splash**: accent glow bloom (`#intro::before`, `exGlow`) + a
  light sweep across the EXPANSION word (`ex-word::after`, `exShine`).
- **Misc**: `screenIn` now translate+scale; display headings
  (`#auth h1`, `.prof-hero h2`, `.lock h2`, `.ob-step h2`, `.prof-stats b`)
  get a white-to-accent gradient text fill; MAIN tier pill shimmers; inputs
  get an accent focus ring; `.likebtn.on`/`.tick.done` pop; topbar title
  no longer wraps ("For You" was breaking onto two lines — `white-space:
  nowrap` + ellipsis on the title span). Mono-theme (Awake) strips the
  glass/aurora to stay stark.

## Build state (as of v0.13.4 — messaging visuals, flashier rank-ups, read receipts)

- **Messaging got a full visual pass.** Messages now animate in
  (`msgIn` keyframe on `.msg`) instead of popping in instantly. Reactions
  get a spring "burst" animation on the exact chip you just toggled
  (`_lastReactedKey` tracked through `applyReaction`→`repaintThread`,
  since the whole list re-renders on every reaction and the specific
  chip has to be re-found by its `data-react` value afterward). The
  typing indicator is now a proper chat bubble with three bouncing dots
  (`.typing-bubble`/`.typing-dots`) instead of a plain italic line.
  Messages containing links now render a lightweight **link preview
  card** below the text — domain + favicon (via Google's public favicon
  service, so no backend fetch/CORS problem, at the cost of not showing a
  real title/description) — client-only, works offline and online alike.
- **Read receipts for DMs are real now, not cosmetic.** New `room_reads`
  table (migration `0018`) + `db.rooms.markRead/getRead/subscribeReads`.
  A room's members can see everyone's read marker in it (that's the
  point — the other person has to see yours). `hydrateOnlineRoom` marks
  the room read on open and on every new incoming message while you're
  looking at it; for DMs it also fetches the other person's last-read
  timestamp and a live Realtime subscription keeps it current while
  you're both in the room. `renderMsgs` shows a small "Seen" + avatar
  under the most recent message *you* sent that's at or before their
  read timestamp — same one-line-under-the-last-message convention as
  iMessage/Discord, not a receipt on every message.
- **Debate rank-ups got measurably flashier.** Reaching a new tier now
  triggers a brief screen shake (`rankfx-scrim.impact`) and three
  expanding ring pulses in the new rank's color behind the result card
  (`.rankfx-burst`), plus a haptic buzz on supported devices
  (`navigator.vibrate`, pattern varies by rank-up vs. plain win vs.
  loss). Added a **progress-to-next-rank bar** (`nextRankInfo()`/
  `nextRankBarHtml()`) — shows `X% to <NextRank>` (or "Top rank reached"
  at Master) — both on the rank-up result screen and permanently on the
  `debateRankCardHtml()` card (profile + Debates tab), restructured that
  card to stack badge-row/progress-bar vertically instead of cramming
  the bar into the same flex row as the W/L/T text.
- **A few global polish passes**: toast messages can now carry a small
  leading icon (`toast(msg, icon)`, backward-compatible — existing
  icon-less calls are unaffected) and got a springier slide+scale-in.
  Room message loading now shows an animated shimmer skeleton
  (`skeletonMsgs()`) instead of a bare "Loading…" line. Added a reusable
  `emptyState(icon, text)` helper (icon in a soft circle + muted text)
  and wired it into the "be the first to speak here" empty room state.
  Added a very subtle animated noise texture over the whole `.frame`
  (`::after`, SVG `feTurbulence`, 5% opacity, `mix-blend-mode:overlay`,
  `pointer-events:none` so it never intercepts taps) — respects
  `body.reduce-motion` by hiding entirely.

**Migration `0018_read_receipts.sql` has already been run directly against
production** (verified via the SQL editor — `room_reads` exists live), so
read receipts work immediately, no pending action.

## Build state (as of v0.13.3 — personality sections collapse by default)

- **MBTI / Enneagram / Temperament on a profile are collapsed by default.**
  `personalityBlock()`'s three rows used to always render their full
  description text inline, which made the top of every profile a wall of
  text. `personalityRow()` now renders each system as a single collapsed
  line (icon, label, current value, a chevron) with the description/
  functions/tritype detail hidden in a `.pt-detail` div until tapped —
  `wirePersonalityToggles()` handles the expand/collapse (guarding against
  the edit-pencil's own click via `closest('.tg-edit')`), wired both for
  your own profile and for others' (previously only `wirePersonalityEdit()`
  ran, which only fires `if(own)`). Verified in-browser: each row expands/
  collapses independently and the edit pencil still opens its picker
  without also toggling the row.

## Build state (as of v0.13.2 — loads more appearance options, UI cleanup, animation polish)

- **Appearance is dramatically bigger now.** `SWATCH` (profile color) went
  from 7 to 16 preset colors; `APP_THEMES` from 7 to 14. Both also got a
  **custom color swatch** — a native `<input type="color">` behind a
  palette-icon tile — so color choice is effectively unlimited, not just
  presets. `synthTheme(hex)`/`currentThemeObj()` synthesize a full theme
  (accent/hi/press) from any single custom hex via the existing HSL
  round-trip, so a custom app theme still gets the same hue-rotated
  neutral-palette treatment as the presets. `LIKE_ICONS` grew from 5 to 12
  glyphs. New **profile banner style** picker (diagonal/radial/vertical/
  sunburst gradients built from your own color) — this had to become a real
  `profiles.banner_style` column (migration `0017`, still pending — decoupled/
  best-effort like `status_line`, so it degrades gracefully either way)
  rather than local client state, since it's about how *your* profile looks
  to *other* people, not a personal view preference like wallpapers/text
  size are.
- **Nexus header decluttered further**: the embedded room's `.thread-head`
  no longer has a visible border/background bar — the phone + debates icons
  now float directly over the top of the room instead of sitting in a
  boxed strip (`#s-nexus .thread-head { border-bottom:none; background:
  transparent; }`).
- **Room Options removed from debate threads.** Mute/wallpaper/events/voice
  never made sense for a 1-on-1 debate exchange — `renderThread()` now skips
  rendering `#thOptions` entirely when `isDebate`, rather than showing a
  generic room-options sheet that didn't fit the content.
- **Animation polish pass**: `.tb-btn` (every icon button — gear, phone,
  debates, bell, search, notif, profile, etc.) had *zero* tap feedback
  before this — added a proper `:active` scale + background transition,
  which matters a lot more than it sounds on a touch-first app. Same for
  bottom-nav buttons. Color/theme/like/banner swatches got a springy
  `cubic-bezier(.34,1.56,.64,1)` scale transition on select instead of
  snapping instantly. Screen/tab transitions upgraded from a flat fade to a
  fade+rise (`screenIn` keyframe, replaces the old bare `fade` one).
- **Fixed**: the custom-color swatch in Appearance didn't show as selected
  on reopening if the user's color was already a custom (non-preset) value
  — cosmetic only (the color itself was always saved/applied correctly),
  but the selection ring gave the wrong impression that nothing was chosen.

## Build state (as of v0.13.1 — flashy debate ranks, DM-request fix, admin auto-grant)

- **Debate ranks are dramatically flashier now.** `DEBATE_RANKS` entries got
  a `t` (tier 1-7) field; `.rank-pill.rank-t5/6/7` get a progressively
  faster pulsing `box-shadow:currentColor` glow (Expert/Elite/Master).
  Debater avatars in the VS card (`debateAvatarRing()`) get a colored ring +
  glow matching their own rank tier — two debaters at different tiers now
  visibly look different. The "VS" is bigger, italic, and pulses. The vote
  tally bar (`.debate-bar-fill`) got a gradient fill, a glow, and a
  continuously sweeping shine. `renderDebateHead()`'s container gets a
  subtle radial accent-colored glow from the top. The debate leaderboard
  (`openDebateLeaderboard`) now shows a **podium** for the top 3 (crown on
  #1, tier-colored glowing pedestals sized by placement) before falling
  back to a plain list for 4th onward. The profile's debate-rank line is
  now a full showcase card (`debateRankCardHtml()`, shared with the Debates
  tab's own rank card) with a tier-tinted gradient background instead of a
  plain text line.
- **DM "message requests" now only apply to actual strangers.** Previously,
  `can_post_dm()` only ever bypassed the one-message-then-wait gate for
  friends or a formally-accepted request — an ongoing conversation where
  the other person had already replied didn't count for anything, so
  tightening your `dm_privacy` mid-conversation (or never having explicitly
  "accepted") could still gate someone you'd already been talking to.
  Migration `0016`: if the other person has ever sent a message in that DM
  room, `can_post_dm()` returns true immediately, before any privacy/
  friendship/request check — a real two-way conversation is never gated
  again, full stop. Offline demo mirrors this via `dmFree()` checking local
  message history for a reply from the other party.
- **`ret`/`5` admin is now a standing rule, not a one-time grant.** Direct
  production check found `auth.users` and `profiles` both completely
  empty — **nobody has ever actually signed up through the live backend
  yet** — which is the actual reason the earlier one-off
  `update profiles set is_admin=true where handle in (...)` grants (0013,
  0015) never took effect: there was no row to update. `lock_identity()`
  (migration `0016`) now special-cases `new.handle in ('ret','5')` to force
  `is_admin=true` on that row regardless of the acting user's own admin
  status, so whenever either account actually signs up with that exact
  handle, they become admin automatically at that moment — no re-running a
  migration needed. (Couldn't be a separate trigger: the handle is set via
  `UPDATE` during signup, not `INSERT`, and a same-event second trigger
  would race `lock_identity()`'s own reset on alphabetical firing order —
  simplest fix was teaching `lock_identity()` itself about the two handles.)
- **Git identity**: commits now use a fully anonymous placeholder identity
  (`5438252392` / `5438252392@users.noreply.github.com`) instead of the
  collaborator's real GitHub username, at their request. Already-merged
  commits on `main` from before this request still carry the old identity —
  rewriting `main`'s history is blocked by Claude Code's own destructive-git
  safety guardrail (same category that blocks direct merges), and even a
  successful rewrite likely wouldn't scrub it from already-merged PR pages
  #1/#2, which GitHub keeps as an independent permanent record regardless
  of what `main`'s current history looks like.



A large friend-feedback batch. Grouped by area:

- **No more emoji in app chrome.** Rank tiers, debate result screens, badges,
  the icebreaker banner, reduce-motion row, broadcast buttons, etc. now use
  proper inline SVGs from the `IC` map instead of emoji characters, so the
  app reads as one consistent icon system instead of a mix of emoji and
  icons. Deliberately **left alone**: the message-reaction emoji picker
  (`EMOJI_SET`) and the per-user "like glyph" choice (`LIKE_ICONS`) — both
  are intentional emoji-based features, not chrome. `DEBATE_RANKS` entries
  no longer carry an `icon` field (can't reference `IC` before it's defined
  in load order); `debateRankBadge()` picks `IC.medal`/`IC.trophy` (top tier)
  at call time instead.
- **The gear icon actually looks like a gear now.** The old one (`IC.gear`)
  was a circle with 8 straight radiating spokes — reads as a sun/asterisk at
  small sizes, which is what prompted "change the sun logo into a settings
  logo." Replaced with a real cog silhouette (Material's `settings` glyph).
  Also **consolidated the two server-header icons into one**: server threads
  used to show a bell (`thOptions`, all members) *and* a separate gear
  (`thManage`, owner/admin) side by side. Now there's a single gear that
  opens Room Options for everyone, with a new "Server management" section
  inside that sheet (visibility + delete) that only renders for
  owners/admins — same underlying `serverManageOnline`/`serverManage`
  functions, just reached from one place instead of two icons.
- **Nexus's icon is a phone now, and voice channels are real (member-
  creatable).** The Nexus room header's action icon is `IC.phone` and opens
  a voice call directly (`openVoiceChannel`), skipping the options-sheet
  detour entirely — tapping it while offline shows a toast instead of
  crashing (`sb` doesn't exist yet in local/demo mode). Servers get a proper
  **voice channel list** inside Room Options (`db.voice.list/create`, new
  `voice_channels` table, migration `0015`) — any member can start one by
  name; each is its own Presence channel (`voice:<channelId>`) instead of
  the old one-ad-hoc-room-wide-channel model. Still preview-only (presence +
  local mute, no real audio — needs a provider like LiveKit, same gap as
  documented for live video).
- **Profile leads with personality, not goals/fears.** `personalityBlock(u)`
  now takes an `editable` flag: on your own profile, MBTI/Enneagram/
  Temperament each get a pencil icon (`.tg-edit`) that opens the matching
  picker (`openMbtiPicker('profile')` etc.) right from the profile sheet —
  no detour through Settings. Chasing/Escaping (goals/fears) moved from
  their own big chip blocks to one compact muted line under the bio
  ("Chasing X · Escaping Y") so personality is what's visually featured. The
  now-redundant MBTI/Enneagram/Temperament rows were removed from Settings
  (same picker, one entry point) as part of decluttering it — see below.
- **DM notifications are real now, not just tag/reply.** `on_message_notify()`
  (migration `0015`) fires a `'dm'`-type notification on every new DM
  message (unless the room's muted), carrying `media_kind` in `entity` so
  the client can show "dmed you!" vs. "sent you a picture!" / "…a video!" /
  "…a voice note!" (`dmNotifText()`). DMs skip the generic @mention/reply
  path now — redundant in a 1:1. Client-side, `groupNotifs()` collapses
  **consecutive** unread DM notifications from the same person in the same
  room into one row: "sent you 3 dms", capped at "9+ dms" once the run hits
  9 or more.
- **Debates got a first-run intro, a rank card, and admin deletion.**
  First time anyone opens Debates, `renderDebatesIntro()` shows a full hype
  screen (what it is, three how-it-works steps, a CTA) gated by
  `state.seenDebatesIntro` (set once, forever after goes straight to the
  normal list). Above the list, a `.debate-rank-card` shows your own
  `debateRankBadge` + W/L/T once you've played at least one. Admins can now
  delete any debate outright from Overwatch → Tools (`admin_delete_debate`
  RPC, cascades the room/messages/votes with it).
- **The EXPANSION intro splash is theme-aware.** `applyAppTheme()` now runs
  once immediately at script load (before `runIntro()`), not just inside
  `enter()` after auth resolves — so the splash's ring/glow/subtitle
  (already `var(--accent)`-driven) actually reflect your saved theme instead
  of always being crimson. The intro's background gradient and word glow
  were also switched from hardcoded crimson hex to `var(--surface-2)`/
  `var(--ground)`/`var(--accent)`, which `applyAppTheme()`'s hue-rotation
  already covers.
- **Settings is grouped now**: Profile / Display / Privacy & security /
  Account section headers instead of one long flat list — mostly achieved by
  removing the redundant MBTI/Enneagram/Temperament rows (now edited from
  the profile directly) rather than adding UI chrome.
- **Expanded admin powers**: delete any debate (above), plus a new
  **maintenance banner** system — `app_config` singleton table (public
  read, admin-only write via `admin_set_maintenance` RPC), a form in
  Overwatch → Tools to toggle it and set a title + details blurb, and a
  slim banner (`#maintBanner`, `checkMaintenanceBanner()`) that shows across
  the whole app with a "More details" button opening the full text in a
  sheet. This is a **banner, not a hard lockout** — the app stays fully
  usable underneath it; that matched how the ask read ("banner… with more
  details button"), but flag it if an actual maintenance-mode lockout is
  wanted instead.
- **Badges are curated + auto-awarded now, not just admin-typed emoji.**
  `badges.icon` stores an **icon key** (matched against `IC` client-side via
  `BADGE_ICON_KEYS`) instead of a freeform emoji string — `openAwardBadge()`
  is now an icon picker, not a text box. Auto-award triggers (migration
  `0015`, all idempotent via `award_badge_if_missing()`): **Founding
  Member** (signed up while `profiles` count ≤ 100), **First Words** (first
  message), **First Post**, **Debate Debut** (first finished debate) /
  **Debate Champion** (10 wins), **Social Butterfly** (10 accepted friends),
  **Week Warrior** / **Streak Legend** (7-day / 30-day streak — see next).
- **Texting streaks — per-user daily, not per-conversation.** Scoped this as
  a single daily-activity streak on `profiles.streak_count`/
  `streak_last_date` (bumped by `bump_streak()` on any non-system message,
  once per calendar day), **not** a Snapchat-style per-DM-pair streak —
  that's a materially bigger feature (a streak per conversation, not per
  person) and wasn't specified either way, so the simpler, still-meaningful
  version shipped. Say the word if per-DM-pair streaks are actually wanted.
- **Nexus header decluttered**: the embedded room no longer repeats "The
  Nexus / everyone, everywhere / The Nexus / live" (title+sub *and* a
  roomTag rendering the same info twice) — for the embedded case the
  thread-head now shows nothing but the action icons, since the topbar
  above it already says "Nexus."
- **Mobile: composer/keyboard fix, best-effort.** Reported as "on normal
  text size, typing pushes everything down; not on large." Root cause
  wasn't reproducible in this environment (no real mobile keyboard/visual-
  viewport event to test against), so this shipped as a legitimate
  standards-based fix rather than a guess-and-check patch:
  `syncFrameToVisualViewport()` keeps `.frame`'s height locked to
  `window.visualViewport.height` whenever it's meaningfully smaller than
  `window.innerHeight` (keyboard open) and hands back to CSS `100dvh` the
  moment it isn't — addresses the actual symptom (content getting pushed
  off-screen under the keyboard) regardless of the text-size-specific
  asymmetry, which is consistent with `--frame` using the non-standard CSS
  `zoom` property for text scaling (interacts unpredictably with visual-
  viewport resize on mobile Safari in particular). **Needs a real-device
  check** — this could not be verified against an actual on-screen keyboard.
- **Admin grants**: migration `0015` grants admin to handles `'ret'` and
  `'5'` (in addition to the existing one-off `'ret'` grant already sitting
  unresolved in migration `0013`) — takes effect once run, and only for
  accounts that have already signed up with those exact handles.

**Action needed:** run `supabase/migrations/0015_voice_streaks_badges_maintenance.sql`
(or the regenerated `RUN_THIS_ONCE.sql`, which now includes it) against
production — none of the voice channels / DM notifications / streaks /
badge auto-awards / maintenance banner / admin_delete_debate / new admin
grants exist server-side until it's run.

## Build state (as of v0.12.2 — Nexus-as-room, debate fixes, flashy ranks)

Friend feedback round: the Nexus tab felt like an unnecessary extra tap, the
bottom nav order was off, DMs were buried, and Debates couldn't actually be
created (still migrations — see below) plus ranks looked flat.

- **The Nexus tab IS the room now** — no more hub screen with a single "The
  Nexus" card to tap through. `renderNexus()` now calls `renderNexusHome()`,
  which sets `active` to the world-room config with `embed:true` and calls
  `renderThread()` directly. `renderThread()` grew an `isEmbed` branch: when
  `th.embed`, it renders into `#s-nexus` instead of the fullscreen `#s-thread`
  overlay, skips the `thread-open` class (so the topbar + bottom nav stay
  visible — this is a tab, not a drill-down), and omits the back button.
  `#s-nexus.on` gets its own CSS (`display:flex;flex-direction:column;
  height:100%`) so the embedded `.thread` fills it exactly like the fullscreen
  version does. To avoid duplicate-ID collisions (`#thInput`, `#thScroll`,
  etc. both existing at once if a real DM/server thread opened while the
  embedded Nexus markup was still sitting in the hidden `#s-nexus`),
  `renderThread()` now clears whichever host it's *not* using
  (`#s-thread`/`#s-nexus`) at the top of every render. Verified in-browser:
  exactly one `.thread` with a live `#thInput` exists at a time, in either
  location, no matter how you navigate between them.
- **Debates is no longer a bottom-nav tab.** It's reached via a small
  debate-icon button top-right of the Nexus room header (`#thDebates`, only
  rendered when `isEmbed`) and has its own back arrow (`renderDebates()` now
  prepends a back button that returns to `state.screen='nexus'`) since it no
  longer has a nav tab to return to.
- **Bottom nav reordered**: Nexus · Feed · Connect (`navItems()`), Watch still
  appended for admins. Feed is now the middle tab, matching the requested
  layout.
- **A "Messages" quick-access bar** now sits above the bottom nav
  (`.msgbar`/`#msgBar`, global chrome, hidden together with the bottom nav
  during a fullscreen thread) — tapping it jumps straight to Connect's DMs
  tab (`state.connectTab='dms'`) instead of requiring Connect → DMs.
- **Debate creation error clarity.** `db.debates.create()`/`.list()` failures
  are now checked with `isMissingSchemaError()` (matches PostgREST's
  "table/column not found" style errors) and surface a specific toast/empty-
  state — *"Debates aren't set up on the server yet — ask an admin to run the
  pending database update"* — instead of a generic "Could not create debate."
  This doesn't fix debates (that's still the pending migrations — see
  `supabase/RUN_THIS_ONCE.sql`, a straight concatenation of migrations
  0009-0014 in order, added purely so there's one file to paste into the SQL
  editor instead of six), but it makes the actual cause visible instead of
  looking like a random bug.
- **Flashy ranks.** `DEBATE_RANKS` entries got a tier icon (🔰🥉🥈⚔️🥇💎👑).
  `.rank-pill` got a `.rp-shine` sweep animation (a skewed gradient sweeping
  across every 3.4s) and a gradient background instead of flat fill; a `.big`
  variant is used in the new result screens. A debate's ended-state composer
  card (`renderDebateComposer`) is now a proper result card: emoji (🏆/🥊/🤝),
  "You won!" / "You lost" / tie copy, and a colored ELO delta (green/red) —
  personalized to the viewer instead of one generic line for everyone.
  Ending a debate you're part of (or having it end while you're watching, via
  the existing `debates` Realtime subscription) now triggers
  `maybeCelebrateDebate()` → `showRankUpFx()`: a full-screen celebration card
  with confetti (on a win or a rank-tier change), an animated ELO count-up/
  down, and — if you crossed a tier boundary — a before→after badge
  transition with a "RANK UP!" headline. All of this respects the existing
  `body.reduce-motion` kill-switch (wildcard `animation-duration:.001ms`
  selector already covers the new keyframes, no extra work needed). Verified
  in-browser via a temporary debug hook (removed before shipping).

**The merged v0.12 update went out before migrations 0009–0014 were ever run
against the live database.** Confirmed directly against the live Supabase
project (read-only REST checks) that every column/table from this whole
multi-round collaboration is still missing in production. That silently broke
things far beyond the new features themselves, because several INSERT/UPDATE
calls bundled a brand-new column into the *same request* as pre-existing
columns — and Postgres/PostgREST rejects the whole request if any one column
doesn't exist:

- **Every message send was broken app-wide** — `db.messages.send()` always
  included `poll_id` (even `null`, for ordinary messages), so with that
  column missing, *no message could be sent anywhere* (Nexus, DMs, servers,
  everywhere). Fixed: `poll_id` is now only included in the payload when
  actually creating a poll message.
- **Every new post failed to create** — `db.posts.create()` always included
  `caption`, which the composer now requires client-side, so with that column
  missing, posting was fully broken. Fixed: tries with `caption` first, falls
  back to posting without it.
- **"Your servers" list was broken** ("your servers is bugged") —
  `db.servers.mine()` explicitly selected `is_official,theme` in a join,
  which hard-errors if those columns don't exist (unlike `select('*')`, which
  just omits them). Fixed to `rooms!inner(*)`.
- **New signups were fully blocked** — `db.profiles.create()` bundled the new
  personality columns into the same UPDATE as core signup fields
  (handle/name/goals/fears/bio/etc.), so a missing personality column failed
  the *entire* signup. Fixed: core fields save first (must succeed); the
  personality fields save separately and best-effort.
- **Profile picture uploads were broken** ("pfps buggy") — `openAppearance`'s
  save bundled the new `status_line` field into the same request as
  `avatar_path`/`color`/`like_icon`, so *any* appearance change failed,
  including ones that had nothing to do with the new fields. Fixed: avatar/
  color/likes save first (must succeed); `status_line`/`banner_path` save
  separately and best-effort.
- **"ret" was never actually granted admin`** — migration 0013 (which
  contains that one-off grant) simply never ran.

None of this needed a code fix once migrations are run — the schema mismatch
*is* the bug. But the resilience changes above are staying regardless: no
future column addition should ever be allowed to take down messaging or
posting again just because a migration lagged behind a deploy.

**Also fixed in this pass: themes now actually retint the background**, not
just the accent. `applyAppTheme()` converts each theme's accent to HSL, takes
its hue, and re-renders `--ground`/`--surface`/`--surface-2`/`--elevated`/
`--line`/`--hover`/`--muted`/`--dim`/`--faint` at that hue (same saturation/
lightness as the original crimson palette, so contrast never changes) via a
small hex↔HSL round-trip (`hexToHsl`/`hslToHex`). Graphite is a special case
(`neutralSatMul:0`) — true desaturated gray rather than a hue-rotated one,
since its accent itself is achromatic. Also fixed Graphite's accent contrast
(was a near-white `#d4d4d4` behind white button text) and themed
`--accent-deep` (`.card:hover` border was silently never themed before).

**Resolved 2026-09-18: migrations 0009–0014 have been run against
production** (via `supabase/RUN_THIS_ONCE.sql`, run directly in the Supabase
SQL editor). Debates, admin tools, personality systems, the Awake server,
etc. are now live against real schema. One migration bug was caught and
fixed in the process: `0013_debates_admin_awake.sql` created the
`msg_insert` policy (which references `profiles.banned`) *before* that
column was added later in the same file — running the migration fresh threw
`column "banned" does not exist`. Fixed by moving the `alter table
public.profiles add column if not exists banned ...` line to the top of the
file, ahead of the debates section; `RUN_THIS_ONCE.sql` was regenerated from
the corrected migrations. Verified post-run via direct REST checks against
the live project: `debates` table reachable (200, was a schema-cache 404
before), `rooms.is_official`/`theme` columns reachable, and `admin_stats()`
correctly executes and returns its own "not authorized" business-logic error
for an anon caller (proving the function exists and runs, not missing).

## Build state (as of v0.11)

**v0.11** — a Debates tab, expanded admin powers, and one official server
(migration `0013`):

- **Debates** (new bottom-nav tab, `IC.debates`, ungated for Lite too): 1-on-1
  only. A member starts one with a **title** + a **description** of what
  they're arguing (`openCreateDebate` → `create_debate` RPC, which also spins
  up a `rooms` row of kind `'debate'`). Anyone else can **join as the
  opponent** once (`join_debate`) — after that it's locked to those two.
  Spectators can always **read** the exchange (`room_readable` now includes
  `'debate'`) but only the two debaters can **post** into it
  (`is_debate_participant` gates `msg_insert`); spectators instead get a vote
  panel (`renderDebateComposer`) — "Vote <name>" for either side, one vote
  each, changeable (`vote_debate` RPC, upsert). Live tallies
  (`refreshDebateTally`) update over Realtime on `debates`/`debate_votes`
  (`subscribeDebate`). The **creator** (or an admin) can **end it anytime**
  (`end_debate`) — most votes wins, an equal split (including 0-0) is a
  **tie** (`winner_id` left null). The debate room reuses the normal
  `renderThread()` pipeline (reactions, polls, mentions all still work for the
  two debaters) via a `kind:'debate'` branch — `renderDebateHead` injects the
  description/VS card/tally/End button above the message list.
- **Expanded admin powers**, all in Overwatch → Tools (online only):
  - **Promote/demote admin** (`admin_set_admin` RPC) and **grant/revoke Main**
    (`admin_set_tier`) on any searched member (`renderAdminUserPanel`).
  - **Ban / unban** (`admin_set_banned`, new `profiles.banned` column) — a
    banned member can still read everything but can't post anywhere
    (`msg_insert` now also checks `not banned`) or join new rooms/servers
    (`rm_join` same check).
  - **Verify a server** (`admin_set_server_official`) — toggles the black
    checkmark badge (`verifiedBadge()`, `rooms.is_official`) from a simple
    list in Tools.
  - **Live stats dashboard** (`admin_stats` RPC) — member/Main/message/post/
    server/live-debate/banned counts, refreshed each time Tools opens.
  - `lock_identity()` (the trigger that locks `tier`/`is_admin`/`banned`) now
    has an admin bypass: it only re-locks those three columns when the
    **acting** user (`auth.uid()`, not the row being edited) isn't already an
    admin — so the RPCs above can actually take effect, while a normal user
    still can't self-promote.
  - Migration `0013` also grants admin to the profile with **handle `'ret'`**
    directly (same one-off pattern as the founder grant in `0006`) — adjust
    the handle in the migration if it doesn't match exactly.
- **"Awake" — the one official, mono-theme server.** Seeded as a public
  server (`rooms.is_official=true`, `rooms.theme='mono'`). `theme` is a new
  `rooms` column (currently only allows `'mono'` by constraint) — **Awake is
  the only server anyone has set it on**; nothing in the UI offers it for
  other servers. When `theme==='mono'`, `renderThread()` adds a `mono-theme`
  class that repaints that one thread pure black/white in `--mono`
  (JetBrains Mono — already loaded, no new font) via scoped CSS overrides;
  every other server keeps the normal red aesthetic. The verified badge
  (`verifiedBadge()`) shows next to "Awake" everywhere a server name renders
  (server lists, thread header) — and next to *any* server an admin marks
  official via the new Tools toggle. Mirrored in the offline demo too
  (`PUBLIC_BROWSE`'s `awake` entry, `openServer`) so it's testable without
  the backend.

## Build state (as of v0.10)

**v0.10** — a QOL / customization / settings / feature batch (migration `0012`):

- **Per-room notification mutes** (`room_mutes`, `db.rooms.mute/unmute`) — bell icon
  in the thread header (`openRoomOptions`) toggles mute for that room. Enforced
  server-side too: `notify_mentions`/`on_message_notify` skip muted recipients.
- **Draft persistence** — composer text is saved to `state.drafts[roomKey]` on
  input and restored on reopen; cleared on send.
- **Undo on delete** — `toastUndo()` gives a 5s "Undo" action before a message or
  post delete actually commits (optimistic removal, restorable).
- **Typing indicators** — `wireTyping`/`showTypingHint`, Realtime **Broadcast**
  only (no DB writes), per BACKEND.md's plan.
- **Jump-to-unread** — `state.lastRead[roomKey]` + a "New" divider
  (`renderMsgs`'s `unreadFromId`) and a floating "↓ New messages" button
  (`showJumpButton`) when reopening an online room with unseen messages.
- **Global search** (`openGlobalSearch`, topbar search icon) — people + posts +
  messages in one sheet; message search reuses `openRoomById` (factored out of
  `openNotifTarget`) to jump straight into the room.
- **Customization**: status line (`status_line`, shown next to your name),
  profile banner (`banner_path`, Storage-backed like avatars), per-room
  wallpaper (`state.wallpapers`, local-only — a personal view preference, not
  synced), message density toggle (`state.density`, `body.density-compact`),
  and a **shareable personality card** (`sharePersonalityCard` — Canvas-drawn
  PNG of your MBTI/Enneagram/Temperament, `navigator.share` with a download
  fallback).
- **Settings**: DM privacy (`dm_privacy`: everyone/friends/none, enforced in
  `can_post_dm`), location visibility (`loc_visibility`: exact/country/hidden,
  masked client-side in `locStr()`), blocked users (`blocks` table +
  `openBlockedList`; also blocks friend-requests both ways), **sign out of all
  devices** (`sb.auth.signOut({scope:'global'})` — works today, no extra infra),
  and **delete account** — needs the `delete-account` Edge Function deployed
  with your own service-role key (see `supabase/functions/delete-account/`);
  the client already calls `sb.functions.invoke('delete-account')`.
- **Polls** (`polls`/`poll_votes`, `messages.poll_id`) — a poll composer button
  in any online room, inline vote bars in the thread (`renderPollBlock`),
  results update live via the existing poll message realtime path.
- **Scheduled events** (`events`/`event_rsvps`) — "Create event" +
  upcoming-events list live in Room options (`openRoomOptions` →
  `renderRoomEvents`/`openCreateEvent`); RSVP toggles a chip. No push
  reminders yet (needs a push provider — see Voice below for the same kind of
  gap).
- **Saved posts** (`saved_posts`) — bookmark icon on feed posts
  (`toggleSave`), a "Saved posts" row in Settings (`openSavedPosts`).
- **Personality-match icebreaker** (`personalityOverlap`) — a dismissible
  banner in a DM thread when you and the other person share an exact MBTI,
  Enneagram Core+Wing, or Temperament match.
- **Voice channel — preview only, not real audio.** `openVoiceChannel` joins a
  Supabase **Presence** channel (`voice:<roomId>`) and shows who's "in" the
  channel with a local-only mute toggle. This is a real, working foundation
  (presence, join/leave) but **carries no audio** — actual voice transport
  needs a provider like LiveKit/Daily/Agora (an SFU, API keys, and typically
  an Edge Function to mint room tokens), which is out of scope without that
  account. Same category of gap as the deferred live-video work in
  `BACKEND.md` §2 — wire it in the same way when ready.

## Build state (as of v0.9)

**v0.9** — three personality systems, all editable anytime, unlike goals/fears:

- **MBTI**: unchanged mechanically from v0.8 but now offers **Unsure** as a first-class
  pick, shows each type's **cognitive-function stack** (e.g. INTJ → Ni·Te·Fi·Se) next
  to its description, and is now reachable **at signup** as well as from the profile.
- **Enneagram** (`openEnneagramFlow`): full **Core + Wing** (`enneagramCore`,
  `enneagramWing` — wing must be core±1, wrapping 1↔9, shown as e.g. `4w5`) plus
  **Tritype** (`enneagramTritype`, format `x-x-x`): one pick from each of the three
  triads — Gut (8/9/1, anger), Heart (2/3/4, self-worth), Head (5/6/7, thinking) —
  then ranked most-to-least dominant. Wing and tritype are individually skippable;
  picking "Unsure" for the core skips both.
- **Four Temperaments** (`openTemperamentFlow`): **Dominant** (`temperamentDominant`,
  mandatory or "Unsure") + optional **Secondary** (`temperamentSecondary`, any of the
  other three) — shown as `Melancholic-Choleric` or just `Melancholic`.
- **Tests, one per system**, member picks how many questions (more = more accurate):
  MBTI keeps its dichotomy-pair test (`startMbtiTest`, `MBTI_QUESTIONS`, 8/16/24/32
  questions). Enneagram and Temperament share a **yes/no category engine**
  (`openCategoryTestSetup`/`startCategoryTest`/`finishCategoryTest`,
  `CATEGORY_TEST_CONFIG`, `ENNEAGRAM_QUESTIONS`/`TEMPERAMENT_QUESTIONS`) — answer
  "That's me" / "Not really" per statement, highest-scoring type wins. A finished
  Enneagram test sets the core and rolls straight into the **wing** step; a finished
  Temperament test sets the dominant and rolls into the **secondary** step — the test
  is just an alternate entry point into the same manual flow.
- **Signup integration**: onboarding is now **4 steps** (was 3) — step 4
  ("Who are you, deeper down?") shows all three systems, each defaulting to
  **Unsure** so Continue never blocks; tapping a row launches that system's picker
  (same code as the profile version, via a `ctx` param: `'onboard'` writes to the
  in-memory `ob` object and returns to the step; `'profile'` calls
  `savePersonalityFields` and saves immediately, online or off).
- Profile display (`personalityBlock`) and the three Settings rows (MBTI /
  Enneagram / Temperament) read `enneagramLabel()`/`temperamentLabel()` for the
  compact form and show full descriptions inline.
- Backend: `mbti`, `enneagram_core`, `enneagram_wing`, `enneagram_tritype`,
  `temperament_dominant`, `temperament_secondary` on `profiles` — see migrations
  `0010`/`0011`. None of these are in `trg_lock_identity`, so they stay editable
  server-side too, matching "change anytime" in the front end.

## Build state (as of v0.8)

**v0.8** (state key still `maintrix.v4`):
- **Nexus scaled down to one room.** `renderNexus()` now shows only **The Nexus**
  (the old global "World" room, relabeled). **Your World**, **Trait Nexus
  Browsing**, and **Nexus Topic Rooms** are hidden from the UI while the user
  base is small — their code (`openYourWorld`, `openTraitBrowse`,
  `openTopicRooms`, `createTopicRoom`) is **untouched and still fully wired**,
  just unlinked from the hub screen. **Do not delete that code.** Re-add their
  cards to `renderNexus()` once there are enough users to justify splitting into
  multiple nexus rooms again.
- **Posts require a caption.** The feed used to derive a text post's "picture"
  card by slicing the first ~44 chars of the body, which cut off mid-word and
  looked broken. `openCompose()` now has a required **Caption** field (≤60
  chars) used as that picture-card text (`posts.caption`, migration `0009`);
  the body textarea is now optional/supplementary. Existing posts (seeded +
  already-live) are untouched — they keep rendering via the old sliced-body
  fallback since their `caption` is null.
- **MBTI.** Members can set/change their MBTI type anytime from **Profile →
  Settings → MBTI type** (`openMbtiPicker`) — pick directly from all 16 types
  (`MBTI_TYPES`, with a one-line description each) or take an in-app **mini
  test** (`openMbtiTestSetup` → `startMbtiTest`): forced-choice statement pairs
  per dichotomy (E/I, S/N, T/F, J/P), 8 pooled questions per axis
  (`MBTI_QUESTIONS`), and the member picks how many rounds to answer (8/16/24/32
  — more rounds = more accurate). Result shown with type + description, saved
  via `saveMbti()`. Unlike goals/fears, **mbti is NOT locked** — editable
  anytime, enforced by leaving it out of `trg_lock_identity` (migration `0010`).
  Shown on every profile (`mbtiBlock`) when set.

## Build state (as of v0.7)

**v0.7 shipped the front-end half of the "treat it as a functioning web-app" round** (state key
bumped to `maintrix.v4` — old sessions re-onboard). Done, all front-end/local:
- **Connect › Search reordered**: **People I like** at top → **Friend requests** (accept/deny, deny
  confirms) → **Find people** (`friendRequests` in state; accept adds to `friends` + fires a notif).
- **Chats open TikTok-style**: any thread now takes over full-screen (`#app.thread-open` hides
  topbar/botnav; `#s-thread.on` slides in). Its own back button restores.
- **Tappable DM header** (avatar+name carry `data-user` → profile).
- **Server public/private toggle anytime**: gear in the thread head (owner or admin) → `serverManage`
  sheet (visibility segmented + delete server).
- **Post-likes are separate from user-likes**: `state.postLikes` (`author|idx`) drives feed + post-viewer
  like buttons; the **profile** Like still drives `likesGiven` ("People I like"). New helpers
  `postLiked/postLikeCount/togglePostLike`.
- **Share a post**: `sharePost()` → `navigator.share` (native sheet) with clipboard-copy fallback.
- **Mutual friend → mini-profile**: `openMiniProfile` (compact `.sheet.mini`); mutual chips use
  `data-mini`, not `data-user`.
- **Traits only in profile**: removed the per-message trait badge (still shown on profiles + as
  matchmaking tags in search/acolytes).
- **Lobby**: added two training rooms — **Paradigm-Broadening** & **Self-Awareness** (`openTraining`) —
  and the **Acolyte Hub is now its own room** (`openAcolyteHub`, seeded, pinned intro).
- **Topic rooms**: creator's rooms pinned in a **Your rooms** section at the top; rooms **expire after
  24h** (`roomExpired`, `createdAt`+`owner` on create) but the owner's stays pinned with a **Renew**.
- **Overwatch broadcast targeting**: `openAdminTools` picks a target (World / any public server /
  Acolyte Hub / Everywhere) and posts a **pinned** (`pin:true`) Overwatch message, rendered as a
  `.pinbar` banner by `renderMsgs`.
- **Admin delete anything (partial)**: admins can delete **any message** (msg menu), **topic rooms**
  (browse list), and **servers** (manage sheet).
- **@-tagging**: mention autocomplete (`wireMentions`) in every room composer + the livestream chat;
  members scoped by room (`roomMembers`). Mentions render via `fmt`.
- **Notifications**: bell in the topbar (`#notifBtn`, unread dot via `paintBell`) → `openNotifications`
  sheet (tags/replies/post-likes/likes). Seeded + event-driven (`pushNotif`; reply/friend events fire).
- **Livestreams are real screens**: tapping a live room or Go Live opens `#lsScreen` (`openLiveStream`)
  with an in-stream **chat** (+ tagging). **Go Live uses the camera** via `getUserMedia` (own preview);
  other people's streams show a topic placeholder until real streaming lands (needs backend/WebRTC).
- Softened "prototype" copy (not real accounts yet, but no longer framed as a throwaway).

**Still pending the backend (Supabase — next phase, front-end-first was chosen):** everyone-to-everyone
live messaging across all rooms (only The Commons is real today), the **account databank** / auth /
persistent cross-device identity, opening *real* other users' profiles, real membership/payments gating,
delivering tags/replies/likes as real notifications, admin-deleting **posts & livestreams** (both still
seeded constants — move to state when the data model lands), and **multi-viewer** live video (own camera
works; broadcasting to others needs WebRTC/LiveKit).

## Build state (as of v0.6)

**v0.6 shipped the full feedback round:** traits set at signup & locked (+ location);
Chats → **Connect**; **DM requests** (accept / deny-with-confirm) + **one-DM-until-
accepted** (non-friends); **friend list** (own settings) + **mutual friends** on others;
message **reply / edit / delete** (long-press or right-click); **Posts** on every
profile + **TikTok fullscreen viewer** + **Lite blur-lock**; **Like** (not Follow),
likeable from post & profile, one-per-user, toggle; **People I like** in Connect; the
full **Nexus** system (World / Your World global+location / Trait Nexus Browsing /
Nexus Topic Rooms create+browse) with location + at-home/foreigner labels + room tags;
**servers** public/private + create (category/bio/title) + browse public (recommended +
search + category) + **ranks** + roles; **Appearance** (color + like icon, Main only);
tier gating aligned to the access lists. State key is now `maintrix.v3` (fresh — old
sessions re-onboard). Still front-end/local + the live Commons.

Below is the historical v0.5 note.

## Build state (as of v0.5)

**Built:** phone-frame shell + bottom nav; EXPANSION intro; login → World Nexus;
World Nexus room + composer + trait-match banner; Connect (Search / DMs / Servers)
with user search; tappable profiles everywhere; profile with Chasing/Escaping,
aesthetic likes, server likes, empty badges; tier Lite/Main with locked Main
surfaces + instant unlock; Feed (aesthetic likes), Live (+ Go Live), Lobby (program
+ acolytes); Overwatch admin bottom-nav item (admin chat + Tools sheet, admin-mode
toggle); The Commons live relay.

**To build (this round's feedback):** move trait selection to sign-up + lock it
(remove Edit identity, add Friend list in settings); rename Chats → **Connect**;
**DM requests** + accept/deny (with confirm) + one-DM-until-accepted; **friend
list** (own-only) + **mutual friends** on others; **reply / edit / delete**
messages; **Posts** section + fullscreen TikTok viewer + Lite blur-lock; **Like**
(replacing Follow) + like-from-profile + **People I like**; the full **Nexus
system** (World / Your World / Trait Nexus Browsing / Nexus Topic Rooms) with
location + labels; **servers** public/private + browse + create (category/bio/title)
+ ranks/roles; align tier gating to the access lists above.

**Deferred:** Lobby task authorship (owner will define later); aesthetic depth
(accent + like-icon for now, more later if asked).

## Backend (next major effort)

Prototype is local + the one live Commons room. The real product needs a backend:
accounts/auth, persistent identity, real DMs/servers/nexus rooms, presence, likes,
posts/media, moderation. Scope this before deepening further; decide stack (e.g.
Supabase or Firebase) with the user. Keep Lite/Main gating and the data shapes here
as the contract.
