# Maintrix backend inventory (reconstruction reference)

> Captured from the live Supabase project `uwvgfxnwtgnwcwostwxs` **while it was still
> running**, earlier in a Claude Code session. The database later crashed (disk full) and
> this inventory is the only surviving record of its structure.
>
> **What this IS:** the complete list of tables (with row counts at capture time) and the
> complete list of database functions **with their argument signatures**.
>
> **What this is NOT (unrecoverable without the live DB or the source migrations):**
> - exact column names / types / constraints / defaults / indexes / foreign keys
> - Row-Level-Security (RLS) policies — the access rules on every table
> - the **bodies** of the functions — the actual logic (ELO math, rate limiting, PoW
>   verification, moderation, the anti-abuse system). Only names + arg types are known.
> - the 3 edge functions' code: `send-push`, `captcha-verify`, `delete-account`
>
> Caveat: captured before Maintrix 3.x; the live app may have added tables/functions since.

## Tables (public schema) — 45

| table | rows@capture | table | rows@capture |
|---|---|---|---|
| traits | 23 | room_reads | 45 |
| profiles | 63 | push_subscriptions | 7 |
| rooms | 55 | rate_limits | 46 |
| room_members | 37 | dm_streaks | 5 |
| messages | 568 | debate_end_votes | 0 |
| friendships | 2 | ban_marks | 5 |
| friend_requests | 8 | login_events | 128 |
| dm_requests | 9 | ip_intel | 52 |
| user_likes | 5 | security_events | 0 |
| posts | 4 | security_alerts | 0 |
| post_comments | 3 | reports | 0 |
| post_likes | 14 | captcha_passes | 0 |
| notifications | 320 | tor_exits | 1369 |
| moderation_actions | 66 | intel_jobs | 1 |
| post_hashtags | 0 | pow_challenges | 1 |
| badges | 62 | streak_saves | 0 |
| comment_likes | 3 | polls | 2 |
| message_reactions | 24 | poll_votes | 2 |
| blocks | 0 | saved_posts | 0 |
| room_mutes | 0 | events | 0 |
| app_config | 1 | event_rsvps | 0 |
| debates | 0 | debate_votes | 0 |
| voice_channels | 0 | | |

All tables had RLS **enabled**.

## Functions (public schema, app-defined) — names + argument signatures

### Social / core
- `accept_friend_request(from_user uuid)`
- `are_friends(a uuid, b uuid)`
- `friend_ids(uid uuid)`
- `mutual_friends(other uuid)`
- `get_or_create_dm(other uuid)`
- `can_post_dm(room uuid)`
- `is_member(room uuid)`
- `is_blocked(a uuid, b uuid)`
- `room_kind(room uuid)`
- `room_readable(room uuid)`
- `realtime_topic_allowed(t text)`
- `notify_mentions(actor uuid, ntype text, body text, entity jsonb)`

### Identity / onboarding / streaks
- `handle_new_user()`  (signup trigger — creates the profile)
- `validate_traits()`
- `bump_streak()`
- `streak_savers_left()`
- `use_streak_saver(p_room uuid)`

### Debates
- `create_debate(p_title text, p_desc text)`
- `join_debate(d_id uuid)`
- `is_debate_participant(room uuid)`
- `can_post_debate_chat(room uuid)`
- `vote_debate(d_id uuid, for_user uuid)`
- `vote_end_debate(d_id uuid)`
- `end_debate(d_id uuid)`
- `finalize_debate(d_id uuid)`
- `delete_own_open_debate(d_id uuid)`

### Security / anti-abuse  (the sophisticated layer — logic NOT recoverable)
- `is_admin()`  · `is_main()`  · `self_banned()`  · `is_muted(uid uuid)`
- `captcha_required(target uuid, p_action text)`  · `check_captcha(p_action text)`
- `pow_challenge(p_action text)`  · `pow_difficulty(target uuid, p_action text)`  · `pow_verify(p_id uuid, p_solution text, p_signals jsonb)`  · `leading_zero_bits(d bytea)`
- `enforce_rate_limit(p_action text, p_max integer, p_window interval)`
- `session_check(p_device text, p_fp text, p_tz text)`
- `request_ip()`  · `intel_request(p_ip text)`  · `intel_resolve()`  · `score_intel(r ip_intel)`
- `recompute_risk(target uuid)`  · `record_event(target uuid, p_kind text, p_sev integer, p_details jsonb)`  · `raise_alert(target uuid, p_kind text, p_sev integer, p_details jsonb)`  · `alert_title(kind text)`
- `vpn_assessment(target uuid)`  · `vpn_org_match(org text)`
- `tor_refresh()`  · `tor_resolve()`
- `ban_user_internal(target uuid, p_reason text, p_by uuid)`
- `report_user(target uuid, p_reason text, p_context jsonb)`
- `purge_user_content(target uuid)`
- `audit(p_action text, p_type text, p_id text, p_details jsonb)`

### Badges
- `award_badge_if_missing(p_uid uuid, p_label text, p_icon text, p_color text)`

### Admin / Overwatch
- `admin_stats()`  · `admin_alerts(p_limit integer, p_open_only boolean)`  · `admin_ack_alert(p_id bigint)`
- `admin_ban_info(target uuid)`  · `admin_user_security(target uuid)`
- `admin_delete_account(target uuid)`  · `admin_delete_user_messages(target uuid)`  · `admin_delete_debate(d_id uuid)`
- `admin_edit_profile(target uuid, patch jsonb)`  · `admin_kick(target uuid, room uuid)`
- `admin_set_admin(target uuid, val boolean)`  · `admin_set_banned(target uuid, val boolean)`  · `admin_set_muted(target uuid, until_ts timestamptz)`  · `admin_set_tier(target uuid, val text)`  · `admin_set_risk(target uuid, p_level text, p_note text)`
- `admin_set_server_official(target_room uuid, val boolean)`
- `admin_set_maintenance(enabled boolean, title text, details text)`
- `admin_set_human_check(p_mode text, p_min_age_minutes integer, p_pow_bits integer)`
- `admin_set_require_mfa(val boolean)`  · `admin_set_security(p_site_key text, p_actions text[], p_monitor boolean)`
- `admin_reset_user_elo(target uuid)`  · `admin_reset_debate_leaderboard()`  · `admin_run_monitor()`
- `push_admins(p_title text, p_body text, p_tag text)`

### Trigger functions (fired by table events)
- `audit_admin_delete()` · `audit_app_config()` · `audit_badge_award()` · `audit_profile_changes()` · `audit_room_official()`
- `award_first_message()` · `award_first_post()` · `award_founding_member()` · `award_social_butterfly()`
- `on_badge_notify()` · `on_comment_notify()` · `on_dm_message()` · `on_dm_message_streak()` · `on_friend_request_notify()` · `on_message_notify()` · `on_post_like_notify()` · `on_server_join_notify()` · `on_user_like_notify()`
- `trg_captcha()` · `trg_captcha_signup()` · `trg_rate_limit()` · `trg_rate_limit_client()`
- `lock_identity()` · `lock_media_path()` · `lock_member_rank()` · `lock_message_fields()` · `lock_profile_paths()` · `lock_request_ids()` · `lock_room_fields()`
- `extract_hashtags()` · `notify_push()` · `push_secrets()` · `detect_rules()` · `detect_tick()` · `tz_mismatch(client_tz text, ip_tz text)` · `poll_options_ok(o jsonb)` · `own_storage_path(p text)`

### Edge functions (Deno/TypeScript — code not recoverable)
- `send-push`  (verify_jwt: false)
- `captcha-verify`  (verify_jwt: true)
- `delete-account`  (verify_jwt: true)

---

### Notes for the rebuild
- A fresh project is empty — recreating the above is required before the app works at all.
- The **client (`app.js`) is obfuscated** and has the *old* project's URL/key compiled in, so it
  can't talk to a new project. You'll need the source build to repoint it (or rebuild the frontend).
- The security/anti-abuse logic (PoW, captcha gating, rate limits, IP/VPN/Tor intel, risk scoring)
  is the hard part and is **not reconstructable from this list** — only the live DB or the source
  migrations contain it.
