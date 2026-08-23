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

Bottom-nav "Nexus" opens the nexus hub. Every nexus room shows each user's
**location (country/state)** near their name, for everyone.

- **World** (the original "Nexus"): one global room for all app users. Label shown:
  **"World"**.
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
