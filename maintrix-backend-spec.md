# Maintrix backend reconstruction spec (from build 37)

Derived from the **readable (pre-obfuscation) build‑37 client** (`app.js` @ commit `85efc8e`,
Maintrix 1.2) by harvesting every `.from("table")` query and `.rpc("fn", {...})` call, merged
with the exact SQL argument types captured from the live database's `pg_proc` earlier.

**Confidence levels**
- ✅ **Known:** table names, the columns the client reads/writes, RPC names + parameter names/types.
- 🟡 **Inferred:** column SQL types, primary keys, foreign keys (from naming + usage).
- ❌ **Not recoverable from the client — you design these:** exact constraints/defaults/indexes,
  **all RLS policies**, and the **bodies** (logic) of every function. The client only shows the
  *contract* (what it calls), never the server-side implementation.

This is a **1.2-era** schema (smaller than the 3.x that was live). It's a working baseline to
build on.

---

## 0. Project setup (do first)

- **Extensions:** `pgcrypto` (for `gen_random_uuid()`), `citext` (the live DB used citext — `handle`
  and email are case-insensitive), likely `pg_net`/`http` (IP intel + web push) and `pg_cron`
  (background monitors: `detect_tick`, `tor_refresh`). Enable citext + pgcrypto at minimum.
- **Auth:** email + password. **Turn on Attack Protection → CAPTCHA and tighten signup rate limits
  from day one** (this is what the attack exploited).
- **Signup trigger:** `handle_new_user()` on `auth.users AFTER INSERT` → creates the matching
  `profiles` row. Without it, signups 500. (Build the profile from `raw_user_meta_data`.)
- **Storage buckets:** one for post media/attachments, one for room icons (`rooms.icon_path`),
  one for profile media. The client builds public URLs from stored paths.
- **Realtime:** enabled on `messages`, `room_members`, `notifications`, `dm_requests`, debate
  tables (the client subscribes to live changes).

Convention below: every `*_id` is `uuid`; `*_at` is `timestamptz default now()`; booleans default
`false`. PK is `id uuid default gen_random_uuid()` unless noted.

---

## 1. Tables (32) — columns ✅, types 🟡

### Identity
**profiles** — one row per user (`id` = `auth.users.id`).
`id uuid PK → auth.users`, `handle citext unique` (permanent), `name text`, `bio text`,
`color text`, `country text`, `region text`, `like_icon text`,
personality: `mbti text`, `enneagram_core text`, `enneagram_wing text`, `enneagram_tritype text`,
`temperament_dominant text`, `temperament_secondary text`,
`goals text[]` (the one pick) 🟡, `fears text[]` (up to two) 🟡.
_(Live DB also had tier/role/risk/banned/muted columns used by admin RPCs — add: `tier text`,
`is_admin bool`, `banned bool`, `muted_until timestamptz`, `risk text`, `elo int`.)_

**profiles_public** — 🟡 a **VIEW** exposing safe fields: `id, handle, name, elo, debate_wins,
debate_losses, debate_ties`. (Exists because RLS hides full `profiles`; expose public stats via view.)

### Rooms & messages
**rooms** — `id`, `title text`, `slug text`, `bio text`, `category text`, `kind text`
(e.g. world/dm/debate/group), `icon text`, `icon_path text` (storage), `is_public bool`,
`is_official bool`, `owner_id uuid→profiles`, `meta jsonb`, `created_at`, `expires_at timestamptz`.
**room_members** — `room_id uuid→rooms`, `user_id uuid→profiles`, `rank text/int`, `roles text[]`
(staff roles). PK `(room_id,user_id)`. Client joins `rooms!inner`.
**room_reads** — `room_id`, `user_id`, `read_at`. PK `(room_id,user_id)` (unread tracking).
**room_mutes** — `room_id`, `user_id`. PK `(room_id,user_id)`.
**messages** — `id`, `room_id uuid→rooms`, `author_id uuid→profiles`, `body text`,
`edited bool`, `created_at`.
**message_reactions** — `message_id uuid→messages`, `user_id uuid→profiles`, `emoji text`.
PK `(message_id,user_id,emoji)`.

### Social graph & DMs
**friendships** — `user_a uuid→profiles`, `user_b uuid→profiles` (store normalized a<b). PK pair.
**friend_requests** — `from_id`, `to_id`, `status text` (pending/accepted/declined).
**dm_requests** — `from_id`, `to_id`, `status text`.
**dm_streaks** — `room_id uuid→rooms` (the DM room), streak counters 🟡 (`count int`, `last_at`).
**blocks** — `blocker_id`, `blocked_id`. PK pair.
**user_likes** — `liker_id`, `liked_id`. PK pair.

### Feed
**posts** — `id`, `author_id uuid→profiles`, `body text`, `caption text`, `created_at`.
**post_comments** — `id`, `post_id uuid→posts`, `author_id uuid→profiles`, `body text`,
`parent_id uuid→post_comments` (threading), `created_at`.
**post_likes** — `post_id`, `user_id`. PK pair.
**comment_likes** — `comment_id uuid→post_comments`, `user_id`. PK pair.
**saved_posts** — `post_id`, `user_id`, `created_at`. PK pair.
**post_hashtags** — `post_id uuid→posts`, `tag text` (populated by a trigger that extracts
`#tags` from `posts.body`). PK `(post_id,tag)`.

### Engagement
**polls** — `id`, `room_id→rooms`, `author_id→profiles`, `question text`, `options jsonb`.
**poll_votes** — `poll_id→polls`, `user_id`, `option_idx int`. PK `(poll_id,user_id)`.
**debates** — `id`, `created_at`, + 🟡 `title`, `desc`, `status`, participant/score columns.
**debate_votes** — `debate_id→debates`, `voter_id→profiles`, `vote_for uuid→profiles`.
PK `(debate_id,voter_id)`.
**debate_end_votes** — `debate_id`, `voter_id`. PK pair.
**events** — `id`, `room_id→rooms`, `created_by→profiles`, `title text`, `starts_at timestamptz`.
**event_rsvps** — `event_id→events`, `user_id`. PK pair.
**voice_channels** — `id`, `room_id→rooms`, `created_by→profiles`, `name text`, `created_at`.

### Badges / notifications / push
**badges** — `id`, `user_id→profiles`, `label text`, `icon text`, `color text`,
`awarded_by uuid→profiles`, `created_at`.
**notifications** — `id`, `user_id→profiles`, `read bool`, `created_at`, + 🟡 `kind text`,
`body text`, `entity jsonb`, `actor_id uuid`.
**push_subscriptions** — `id`, `user_id→profiles`, `endpoint text`, `p256dh text`, `auth text`,
`user_agent text`, `last_seen timestamptz`. (Web-Push keys.)

### Config
**app_config** — singleton (`id`), holds maintenance flag/title/details, human-check mode,
security settings (site_key, actions, monitor), require-mfa, etc. (written by the `admin_set_*` RPCs).

> **Not read directly by the 1.2 client but present in the live DB** (add if you want the full
> security layer): `moderation_actions`, `login_events`, `ip_intel`, `security_events`,
> `security_alerts`, `reports`, `captcha_passes`, `tor_exits`, `intel_jobs`, `pow_challenges`,
> `rate_limits`, `ban_marks`, `streak_saves`, `traits`.

---

## 2. RPC functions (36) — signature ✅, behavior 🟡/❌

Types merged from the live `pg_proc`. **Bodies must be written** — the client only shows the call.

### User actions
- `accept_friend_request(from_user uuid)` — accept a pending request; create `friendships` row.
- `mutual_friends(other uuid)` → set/count of shared friends.
- `get_or_create_dm(other uuid)` → returns a DM `room` id, creating it + both `room_members` if absent.
- `create_debate(p_title text, p_desc text)` → new `debates` row (open).
- `join_debate(d_id uuid)` — add caller as participant.
- `vote_debate(d_id uuid, for_user uuid)` — cast a side vote.
- `vote_end_debate(d_id uuid)` — vote to end; `end_debate`/`finalize_debate` resolve + apply ELO.
- `end_debate(d_id uuid)` · `delete_own_open_debate(d_id uuid)`.
- `report_user(target uuid, p_reason text, p_context jsonb)` — file a report.

### Anti-abuse (❌ logic is the hard, security-critical part)
- `pow_challenge(p_action text)` → issues a proof-of-work challenge (id + difficulty/bits).
- `pow_verify(p_id uuid, p_solution text, p_signals jsonb)` → validates PoW + device signals,
  returns pass/fail. Gates sensitive actions.
- `session_check(p_device text, p_fp text, p_tz text)` → records device/fingerprint/timezone,
  returns risk/human-check requirements.

### Admin / Overwatch (gate all on an `is_admin()` check)
- `admin_stats()` · `admin_alerts(p_limit int, p_open_only bool)` · `admin_ack_alert(p_id bigint)`
- `admin_ban_info(target uuid)` · `admin_user_security(target uuid)`
- `admin_delete_account(target uuid)` · `admin_delete_user_messages(target uuid)` · `admin_delete_debate(d_id uuid)`
- `admin_edit_profile(target uuid, patch jsonb)` · `admin_kick(target uuid, room uuid)`
- `admin_set_admin(target uuid, val bool)` · `admin_set_banned(target uuid, val bool)`
- `admin_set_muted(target uuid, until_ts timestamptz)` · `admin_set_tier(target uuid, val text)`
- `admin_set_risk(target uuid, p_level text, p_note text)` · `admin_set_server_official(target_room uuid, val bool)`
- `admin_set_maintenance(enabled bool, title text, details text)`
- `admin_set_human_check(p_mode text, p_min_age_minutes int, p_pow_bits int)`
- `admin_set_require_mfa(val bool)` · `admin_set_security(p_site_key text, p_actions text[], p_monitor bool)`
- `admin_reset_user_elo(target uuid)` · `admin_reset_debate_leaderboard()` · `admin_run_monitor()`

---

## 3. RLS — you must design all of it (❌ nothing in the client reveals it)

Baseline to implement (enable RLS on **every** table):
- **profiles:** anyone authenticated can `select` public columns (or expose via `profiles_public`
  view); a user may `update` only their own row; `handle` immutable after set (trigger).
- **messages / posts / comments / reactions / likes:** `insert` only as `author_id = auth.uid()`;
  `select` only for members of the room / public feed; `update`/`delete` only own rows.
- **room_members:** a user sees rooms they belong to; joins/leaves constrained.
- **friend_requests / dm_requests / friendships / blocks:** only rows where the caller is a party.
- **notifications / push_subscriptions / saved_posts / room_reads:** only `user_id = auth.uid()`.
- **admin RPCs:** `security definer` + internal `is_admin()` guard; never expose tables for direct
  admin writes.

---

## 4. Edge functions (❌ code not recoverable — reimplement)
- **captcha-verify** (verify_jwt: true) — server-side verify of the Cloudflare Turnstile token
  against the secret, before allowing the gated action.
- **send-push** (verify_jwt: false) — send Web Push to `push_subscriptions` via VAPID keys
  (set as function secrets).
- **delete-account** (verify_jwt: true) — delete the caller's auth user + cascade their data
  (uses the service-role key).

---

## 5. Suggested build order
1. Extensions + `profiles` + `handle_new_user` trigger → signup works.
2. `rooms` + `room_members` + `messages` + RLS → core chat.
3. Social graph (friends/DMs) + the RPCs that touch them.
4. Feed (posts/comments/likes), badges, notifications + push.
5. Debates + polls + events.
6. Anti-abuse (PoW, captcha, rate limits) + admin/Overwatch — last, and carefully.

> Reminder: the current frontend to pair with this is **build 37** (repointable — plaintext URL/key).
> After the backend exists, swap its Supabase URL + anon key to the new project, re-stamp with
> `tools/stamp_maintrix.py`, and deploy.
