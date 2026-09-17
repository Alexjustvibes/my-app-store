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
