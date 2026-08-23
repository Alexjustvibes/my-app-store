# BACKEND.md — Maintrix on Supabase

Scope for turning Maintrix from a local/front-end prototype into a **functioning
multi-user web app**. This is the plan of record for the backend build; the
front-end contract in `CLAUDE.md` (Lite/Main gating, room types, data shapes) is
the source of truth the schema must honor. Read `CLAUDE.md` first.

**Sequencing decision (already made):** front-end first (shipped in v0.7), backend
now. **Platform decision (already made):** Supabase.

---

## 1. Goals & principles

- **One interconnected world.** Every user shares a global namespace of rooms
  (World, trait nexuses, topic rooms, servers, DMs, lives, Lobby). The backend
  models *rooms* and *memberships*, not walled silos.
- **Real identity, set once.** Traits (goals + fears) are captured by the
  signup test and are **immutable** after creation — enforced in the DB, not just
  the UI. (Signup is an MBTI-style test the user will author; the backend just
  needs to persist the resulting `goals[]`/`fears[]`.)
- **Security in the database, not the client.** Every table is protected by
  Row-Level Security (RLS). The browser only ever holds the **anon** key. Privacy
  rules (DMs are private, Main-gating, admin powers) are Postgres policies.
- **Incremental swap.** Introduce a data-access layer in `index.html` so screens
  call `db.*` instead of touching `localStorage` directly, then swap the
  implementation table-by-table. The app keeps working the whole way.
- **Keep The Commons's spirit everywhere.** The ntfy.sh live room proved the feel;
  Supabase Realtime replaces ntfy and extends "live" to every room.

## 2. Stack

| Concern | Choice | Notes |
|---|---|---|
| DB | **Supabase Postgres** | Single source of truth; RLS everywhere. |
| Auth | **Supabase Auth — email OTP / magic link** (passwordless) | Decided. Google OAuth / anonymous-upgrade are possible later, not now. |
| Realtime chat/presence | **Supabase Realtime** | `postgres_changes` for messages, **Presence** for online status, **Broadcast** for typing indicators. Replaces ntfy. |
| Media (avatars, post images/video files) | **Supabase Storage** | Signed uploads; RLS-scoped buckets. |
| Live video (camera → many viewers) | **LiveKit** (or Daily/Agora) — **deferred** | Supabase does not do WebRTC SFU. Own-camera preview already works client-side; multi-viewer needs this. Store stream *metadata* in Postgres, video in LiveKit. |
| Payments (Main subscription) | **Stripe** — **deferred** | `subscriptions` table + webhook Edge Function. Until then `tier` is a flag flipped in-app. |
| Server-authoritative logic | **Supabase Edge Functions** (Deno) | Friend-accept atomicity, notification fan-out, Stripe webhook, moderation, "ranking intelligence." |

## 3. Auth model

**Decided: email OTP / magic link only** (passwordless). No passwords for us to
handle, low friction, real cross-device identity. (Claude must never enter
credentials or create accounts — this describes the flow the app implements.)
Google OAuth and anonymous-then-upgrade remain easy future adds but are out of
scope for now.

Flow: **enter email → click magic link → (first time) take the identity test →
profile row created → enter app.**

- `auth.users` is Supabase-managed. Our `profiles.id` is a FK to `auth.users.id`.
  A trigger (`on auth.users insert`) creates a stub profile; the test fills it in
  and sets the unique `@handle`.

## 4. Data model

Types: `trait` values come from the fixed `GOALS`/`FEARS` lists (store as `text[]`
with a GIN index for matchmaking, plus a `traits` lookup table for validation).
Room model is **unified** — one `rooms` table with a `kind`, so messages, members,
pins, and realtime all work the same everywhere.

### Identity
- **profiles** — `id (uuid, pk → auth.users)`, `handle (citext, unique)` — the
  immutable `@handle` used for mentions/URLs, `name (text)` — the changeable
  display name, `goals text[]`, `fears text[]`, `bio`, `color`, `like_icon`,
  `country`, `region`, `tier ('lite'|'main')`, `is_admin bool`,
  `created_at`, `live_stream_id (nullable fk)`.
  - **Immutability:** a `BEFORE UPDATE` trigger rejects changes to `goals`/`fears`
    and `handle` (traits and handle are locked after signup); `name`, `bio`,
    `color`, `like_icon` stay editable per the appearance rules.
- **traits** — `value (pk)`, `kind ('goal'|'fear')`. Seed from `GOALS`/`FEARS`.

### Social graph
- **friendships** — `a uuid`, `b uuid`, `created_at`; store canonical `(least,
  greatest)` pair, unique. Membership = "are friends".
- **friend_requests** — `from_id`, `to_id`, `status ('pending'|'accepted'|'denied')`,
  unique `(from_id,to_id)`. Accept → Edge Function creates friendship + notif.
- **dm_requests** — enforces **one DM until accepted**: `from_id`, `to_id`,
  `status`. A DM room is only writable by `from` once until `to` accepts (policy +
  the request row).
- **blocks** *(future)* — `blocker`, `blocked`.

### Rooms & messages (the core)
- **rooms** — `id (uuid pk)`, `kind ('world'|'trait'|'topic'|'server'|'dm'|
  'live'|'training'|'acolyte'|'commons'|'admin')`, `title`, `category`,
  `trait (nullable)`, `scope ('global'|'location')`, `owner_id (nullable)`,
  `is_public bool`, `created_at`, `expires_at (nullable — topic rooms: +24h)`,
  `meta jsonb`.
  - The singletons (World, Commons, Acolyte Hub, each trait nexus, training rooms)
    are seeded rows. DMs and topic rooms and server channels are created on demand.
- **room_members** — `room_id`, `user_id`, `rank ('Initiate'|'Operator'|
  'Architect'|'Owner')`, `roles text[]`, `joined_at`, `muted bool`. PK `(room_id,
  user_id)`. Used for servers, DMs (the 2 participants), private membership.
- **messages** — `id (uuid pk)`, `room_id`, `author_id`, `body text`,
  `reply_to (nullable fk messages)`, `edited bool`, `pinned bool`, `is_system bool`
  (Overwatch/bot), `created_at`. Indexed `(room_id, created_at)`. Realtime source.
  - `@mentions` are parsed client-side for display; **mention rows** (below) drive
    notifications.
- **mentions** — `message_id`, `mentioned_id`. Insert-time fan-out → notification.

### Servers
Servers are `rooms` with `kind='server'` plus:
- **servers** — `room_id (pk fk rooms)`, `icon`, `bio`. `is_public`, `title`,
  `category`, `owner_id` live on `rooms`. Owners flip `is_public` anytime (policy:
  owner or admin). Ranks are the app's pre-ordained ladder (assigned via
  `room_members.rank`); custom roles are `room_members.roles[]`.
- Public server discovery = `select rooms where kind='server' and is_public`.

### Posts & media (Main-gated)
- **posts** — `id`, `author_id`, `body`, `media_kind ('image'|'video'|'text')`,
  `media_path (storage)`, `created_at`. **Insert policy requires author `tier='main'`.**
  **Select policy requires viewer `tier='main'`** (Lite sees blur-lock in UI).
- **post_comments** — `id`, `post_id`, `author_id`, `body`, `created_at`. Enables
  "tag friends on posts". Mentions fan out like message mentions.
- **post_likes** — `post_id`, `user_id`, PK `(post_id,user_id)`. **Post-like only;
  distinct from user-likes.**

### Likes (people, not posts)
- **user_likes** — `liker_id`, `liked_id`, PK. Drives "People I like" and a user's
  like count. One per user, toggleable. (Kept separate from `post_likes` — a v0.7
  invariant.)

### Livestreams
- **live_streams** — `id`, `host_id`, `topic`, `status ('live'|'ended')`,
  `viewer_count int`, `started_at`, `livekit_room (nullable)`. Chat = a `rooms`
  row `kind='live'` linked by id. Camera/video via LiveKit; Postgres holds
  presence + chat + metadata. Admin can end (delete) any stream.

### Notifications
- **notifications** — `id`, `user_id (recipient)`, `type ('tag'|'reply'|
  'post_like'|'like'|'friend')`, `actor_id`, `target jsonb` (room/post/message
  ref), `read bool`, `created_at`. Written by triggers/Edge Functions on the
  originating events; realtime-subscribed for the bell.

### Lobby (program authored later)
- **programs** / **lessons** — the self-actualization curriculum the user will
  author; leave as tables with pluggable content. Training rooms
  (Paradigm-Broadening, Self-Awareness) are seeded `rooms` `kind='training'`.
- **task_completions** — `user_id`, `task_id`, `day (date)`, `done`. Daily program
  progress per user.

### Membership & moderation
- **subscriptions** *(Stripe, later)* — `user_id`, `status`, `current_period_end`,
  `stripe_customer`, `stripe_sub`. Source of truth for `profiles.tier` via webhook.
- **moderation_actions** — `admin_id`, `action ('delete'|'mute'|'kick')`,
  `target_type`, `target_id`, `created_at`. Audit trail for Overwatch powers.

## 5. Row-Level Security (the security model)

RLS **on for every table**. Representative policies:

- **profiles**: anyone authenticated can `select` (public identities); user can
  `update` only their own row; traits are frozen by trigger.
- **messages**:
  - `select`: room is public/global **OR** the user is in `room_members` for that
    room. DMs and private servers require membership.
  - `insert`: author = `auth.uid()`, user is a member (or room is open), **and**
    for DM rooms the one-message-until-accepted rule holds.
  - `update`/`delete`: author only — **except** `is_admin` users may delete any
    (Overwatch "delete anything").
- **posts**: `insert`/`select` gated on `tier='main'` (see §7).
- **dm rooms**: only the two participants can read/write; no one else, ever
  (mirrors "even Overwatch can't see DMs").
- **user_likes / post_likes / friend_requests / notifications**: users act only as
  themselves; recipients read their own notifications.
- **rooms.is_public toggle**: `update` allowed to `owner_id` or `is_admin`.
- Admin power = `profiles.is_admin` surfaced as a JWT claim (custom access-token
  hook) so policies read it cheaply.

## 6. Realtime

- **Messages:** subscribe to `postgres_changes` on `messages filtered by room_id`.
  Replaces the per-room render loop; The Commons's WebSocket/ntfy path is removed.
- **Presence:** Supabase Presence channel per surface for online/idle/dnd dots and
  live-room viewer counts — real presence instead of seeded `status`.
- **Typing / ephemeral:** Realtime **Broadcast** (no DB writes).
- **Notifications bell:** subscribe to `notifications where user_id = me`.
- Scale note: free tier allows ~200 concurrent Realtime connections; fine for
  early users. Batch/paginate message history via REST, stream only new rows.

## 7. Membership gating (Lite vs Main)

Enforced **server-side**, not just hidden in UI:
- Posting, going live, joining non-home trait nexuses, creating topic rooms,
  choosing appearance → **RLS insert policies check `profiles.tier='main'`**.
- Viewing posts/feeds → **select policy checks viewer `tier='main'`** (Lite gets
  the blur-lock; the data never reaches the client).
- Today `tier` is flipped in-app (instant unlock). When Stripe lands, the webhook
  sets `tier` from `subscriptions.status`; the app never sets it directly.

## 8. Edge Functions (service-role logic)

- `accept-friend` — atomic: flip request, create friendship, emit notification.
- `notify` — fan-out for mentions/replies/likes (or do via DB triggers; pick one).
- `stripe-webhook` — sync `subscriptions` → `profiles.tier`. *(later)*
- `moderate` — admin delete/mute/kick with audit row (server-authoritative).
- `assign-rank` — the "ranking intelligence" that suggests/sets server ranks.
- `expire-rooms` — scheduled (pg_cron): mark topic rooms past `expires_at`;
  owners' rooms stay listed for renew (renew = set `expires_at = now()+24h`).

## 9. Front-end integration strategy

1. **Introduce `db` module** in `index.html`: `db.messages.list(roomId)`,
   `db.messages.send(...)`, `db.friends.request(...)`, etc. First implementation
   just wraps the current `localStorage`/`state` code — **no behavior change**.
2. **Add the Supabase JS client** (pinned version; the one allowed CDN dep, or
   vendored) and a session boot: on load, get session → load profile → `render()`.
3. **Swap table-by-table** behind `db.*`, following the phases below. Each swap is
   shippable; the app never fully breaks.
4. Keep the room-`key` scheme as a stable id map (e.g. `world`, `dm-<uid>`,
   `topic-<id>`) → `rooms.id`, so existing screen logic changes minimally.

## 10. Feature → backend mapping

| App feature (v0.7) | Backend mechanism |
|---|---|
| Signup test → locked identity | `profiles` + immutability trigger; `traits` validation |
| World / Your World / trait nexuses | seeded `rooms` (kind `world`/`trait`, scope global/location); trait match via `goals[]`/`fears[]` GIN |
| Topic rooms + 24h expiry + renew | `rooms` kind `topic`, `owner_id`, `expires_at`; `expire-rooms` cron |
| Everyone-to-everyone live chat | `messages` + Realtime `postgres_changes` (all rooms) |
| The Commons | a `rooms` row kind `commons`; ntfy path retired |
| DMs + one-DM-until-accept + requests | `rooms` kind `dm`, `room_members`, `dm_requests` + insert policy |
| Friends + requests + mutual friends | `friendships`, `friend_requests`, mutual = set intersect query |
| Servers public/private + ranks/roles | `rooms` kind `server` + `servers` + `room_members.rank/roles` |
| Posts (Main) + TikTok viewer + Lite blur | `posts` + Storage + tier RLS |
| Post comments + tagging friends | `post_comments` + `mentions` |
| Like a person / like a post (separate) | `user_likes` vs `post_likes` |
| @-tagging in rooms + notifications | `mentions` → `notifications` |
| Notifications bell | `notifications` + Realtime |
| Overwatch broadcast (targeted, pinned) | insert `messages` with `pinned/is_system` into chosen rooms (Edge Function fan-out) |
| Admin delete anything | admin-branch RLS delete + `moderation_actions` |
| Go Live w/ camera + in-stream chat | `live_streams` + `rooms` kind `live`; video via LiveKit |
| Lobby program + training + acolyte hub | `programs`/`lessons`/`task_completions`; training/acolyte are seeded rooms |
| Membership (Lite/Main) | `profiles.tier` (+ `subscriptions` when Stripe lands) |
| Presence / online dots | Realtime Presence |

## 11. Phased rollout

- **Phase 1 — Identity & auth.** Supabase project, `profiles`/`traits`, auth (email
  OTP), signup-test writes the profile, session boot, RLS on profiles. *App reads
  real "me"; others still seeded.*
- **Phase 2 — Rooms & live messaging.** `rooms`/`room_members`/`messages` + Realtime.
  Make World, trait nexuses, topic rooms, and servers real & live. Retire ntfy.
- **Phase 3 — Social graph & DMs.** `friendships`, `friend_requests`, `dm_requests`,
  DM rooms with the one-message rule; `user_likes`.
- **Phase 4 — Posts, media, comments, likes.** `posts` + Storage + `post_likes` +
  `post_comments`; tier gating on read/write.
- **Phase 5 — Notifications, presence, tagging fan-out, admin/moderation.**
  `mentions`, `notifications`, Presence, `moderation_actions`, admin RLS.
- **Phase 6 — Live video (LiveKit) & payments (Stripe).** Multi-viewer camera;
  real Main subscription. Both optional/independent.

## 12. Decisions (resolved)

1. **Auth** — ✅ **Email OTP / magic link only.** (Google OAuth / anonymous-upgrade
   deferred.)
2. **Live video** — ✅ **Deferred to Phase 6** (LiveKit or similar). Own-camera
   preview already works; multi-viewer streaming waits until the core is proven.
3. **Payments** — ✅ **Deferred.** Keep the instant in-app unlock; add Stripe later
   without touching gating logic.
4. **Identity naming** — ✅ **Display name + unique @handle.** `handle` is immutable
   (used for mentions/URLs); `name` is the changeable display name.

Still to decide when we get there: live-video provider (Phase 6), Stripe pricing.

## 13. Cost / limits (Supabase free tier)

500 MB Postgres, 1 GB storage, ~2 GB egress/mo, ~200 concurrent Realtime, 50k
monthly active auth users. Comfortable for prototype → early traction; the Pro
tier ($25/mo) lifts these when needed. LiveKit and Stripe bill separately.
