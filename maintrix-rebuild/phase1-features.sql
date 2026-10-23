-- ============================================================================
-- Maintrix 3.x features — PHASE 1
-- Run once in the Supabase SQL Editor (project dvrcrwyjqlrowsnevduz).
-- Re-runnable: everything uses IF NOT EXISTS / CREATE OR REPLACE / DROP IF EXISTS.
--
-- Restores the backend the 3.15 client expects:
--   * profile, debate, badge, room, streak, post, notification columns
--   * debate_hands, feedback, update_logs, ranked_queue, ranked_matches, streak_saves
--   * realtime publication (was EMPTY -> nothing updated live)
--   * storage buckets: media, attachments
--   * notification triggers (none existed), hashtags, DM streaks, room modes
--   * functions: debates v2, ranked, group DMs, badges, staff, admin suite, push, streaks
-- Security layer (PoW, captcha, VPN/Tor, lockdown, age gates) and moderation
-- (reports, appeals, filters, held messages, warnings, audit) are STUBBED by request.
-- ============================================================================


-- ============================================================================
-- A. COLUMNS
-- ============================================================================
alter table profiles
  add column if not exists avatar_path    text,
  add column if not exists banner_path    text,
  add column if not exists banner_style   text,
  add column if not exists status_line    text,
  add column if not exists dm_privacy     text    not null default 'everyone',
  add column if not exists loc_visibility text    not null default 'region',
  add column if not exists notif_prefs    jsonb   not null default '{}'::jsonb,
  add column if not exists is_mod         boolean not null default false,
  add column if not exists is_owner       boolean not null default false,
  add column if not exists debate_wins    integer not null default 0,
  add column if not exists debate_losses  integer not null default 0,
  add column if not exists debate_ties    integer not null default 0,
  add column if not exists main_until     timestamptz,
  add column if not exists ban_reason     text,
  add column if not exists risk_level     text    not null default 'none',
  add column if not exists vpn_seen       boolean not null default false;

alter table debates
  add column if not exists description     text,
  add column if not exists creator_id      uuid references profiles(id) on delete set null,
  add column if not exists opponent_id     uuid references profiles(id) on delete set null,
  add column if not exists winner_id       uuid references profiles(id) on delete set null,
  add column if not exists room_id         uuid references rooms(id)    on delete set null,
  add column if not exists chat_room_id    uuid references rooms(id)    on delete set null,
  add column if not exists ranked          boolean not null default false,
  add column if not exists rounds          integer not null default 3,
  add column if not exists round_secs      integer not null default 0,
  add column if not exists turn_secs       integer not null default 0,
  add column if not exists turn_no         integer not null default 0,
  add column if not exists turn_holder     uuid references profiles(id) on delete set null,
  add column if not exists turn_started_at timestamptz,
  add column if not exists turn_ends_at    timestamptz,
  add column if not exists started_at      timestamptz,
  add column if not exists ends_at         timestamptz,
  add column if not exists ended_at        timestamptz,
  add column if not exists paused_at       timestamptz,
  add column if not exists paused_by       uuid references profiles(id) on delete set null,
  add column if not exists paused_left     integer,
  add column if not exists stage_guest     uuid references profiles(id) on delete set null,
  add column if not exists stage_return    uuid references profiles(id) on delete set null,
  add column if not exists elo_delta       integer,
  add column if not exists elo_gain        integer,
  add column if not exists elo_loss        integer,
  add column if not exists vote_bonus      integer not null default 0;
update debates set creator_id = coalesce(creator_id, created_by),
                   description = coalesce(description, "desc");

alter table badges
  add column if not exists is_public boolean not null default true,
  add column if not exists pinned    integer check (pinned between 1 and 3),
  add column if not exists rarity    text,
  add column if not exists style     text;

alter table dm_streaks
  add column if not exists streak_count     integer not null default 0,
  add column if not exists last_streak_date date;

alter table rooms
  add column if not exists locked      boolean not null default false,
  add column if not exists slow_mode_s integer not null default 0;

alter table posts add column if not exists thumb_path text;

alter table notifications add column if not exists type text;
update notifications set type = coalesce(type, kind);

alter table app_config
  add column if not exists banner           jsonb,
  add column if not exists lockdown         text,
  add column if not exists age_gates        jsonb,
  add column if not exists human_strictness text;


-- ============================================================================
-- B. NEW TABLES (+ RLS)
-- ============================================================================
create table if not exists debate_hands (
  debate_id uuid references debates(id)  on delete cascade,
  user_id   uuid references profiles(id) on delete cascade,
  raised_at timestamptz not null default now(),
  primary key (debate_id, user_id)
);
create table if not exists feedback (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references profiles(id) on delete set null default auth.uid(),
  kind       text,
  body       text not null,
  status     text not null default 'open',
  admin_note text,
  created_at timestamptz not null default now()
);
create table if not exists update_logs (
  id                uuid primary key default gen_random_uuid(),
  title             text,
  version           text,
  items             jsonb not null default '[]'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  notified_at       timestamptz,
  notified_count    integer not null default 0,
  notified_audience text
);
create table if not exists ranked_queue (
  user_id   uuid primary key references profiles(id) on delete cascade,
  joined_at timestamptz not null default now()
);
create table if not exists ranked_matches (
  id           uuid primary key default gen_random_uuid(),
  a            uuid references profiles(id) on delete cascade,
  b            uuid references profiles(id) on delete cascade,
  status       text not null default 'coinflip',   -- coinflip | topic | review | accepted | ended | cancelled
  caller       uuid,
  flip         text,
  flip_winner  uuid,
  proposer     uuid,
  rejects      integer not null default 0,
  last_reason  text,
  topic_title  text,
  topic_desc   text,
  turns        integer,
  turn_secs    integer,
  debate_id    uuid references debates(id) on delete set null,
  ended_reason text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create table if not exists streak_saves (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  room_id uuid references rooms(id) on delete cascade,
  used_at timestamptz not null default now()
);

alter table debate_hands   enable row level security;
alter table feedback       enable row level security;
alter table update_logs    enable row level security;
alter table ranked_queue   enable row level security;
alter table ranked_matches enable row level security;
alter table streak_saves   enable row level security;

drop policy if exists hands_read on debate_hands;
create policy hands_read on debate_hands for select to authenticated using (true);
drop policy if exists hands_own on debate_hands;
create policy hands_own on debate_hands for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists fb_insert on feedback;
create policy fb_insert on feedback for insert to authenticated with check (user_id = auth.uid());
drop policy if exists fb_read on feedback;
create policy fb_read on feedback for select to authenticated using (user_id = auth.uid() or is_admin());
drop policy if exists fb_admin on feedback;
create policy fb_admin on feedback for update to authenticated using (is_admin()) with check (is_admin());
drop policy if exists fb_admin_del on feedback;
create policy fb_admin_del on feedback for delete to authenticated using (is_admin());

drop policy if exists updlog_read on update_logs;
create policy updlog_read on update_logs for select to authenticated using (true);
drop policy if exists updlog_admin on update_logs;
create policy updlog_admin on update_logs for all to authenticated using (is_admin()) with check (is_admin());

drop policy if exists rq_read on ranked_queue;
create policy rq_read on ranked_queue for select to authenticated using (user_id = auth.uid());

drop policy if exists rmatch_read on ranked_matches;
create policy rmatch_read on ranked_matches for select to authenticated using (auth.uid() in (a, b) or is_admin());

drop policy if exists ss_read on streak_saves;
create policy ss_read on streak_saves for select to authenticated using (user_id = auth.uid());

-- badges: owners can pin / show-hide their own (guard below keeps the badge itself fixed)
drop policy if exists badges_own_update on badges;
create policy badges_own_update on badges for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- admins award / revoke badges from the admin panel
drop policy if exists badges_admin on badges;
create policy badges_admin on badges for all to authenticated using (is_admin()) with check (is_admin());

-- friend & DM requests: sender creates; EITHER party can read/accept/decline/withdraw
-- (old "for all ... with check (from_id = me)" blocked the recipient from accepting)
drop policy if exists freq_party on friend_requests;
drop policy if exists freq_insert on friend_requests;
create policy freq_insert on friend_requests for insert to authenticated with check (from_id = auth.uid());
drop policy if exists freq_select on friend_requests;
create policy freq_select on friend_requests for select to authenticated using (auth.uid() in (from_id, to_id));
drop policy if exists freq_update on friend_requests;
create policy freq_update on friend_requests for update to authenticated
  using (auth.uid() in (from_id, to_id)) with check (auth.uid() in (from_id, to_id));
drop policy if exists freq_delete on friend_requests;
create policy freq_delete on friend_requests for delete to authenticated using (auth.uid() in (from_id, to_id));

drop policy if exists dmreq_party on dm_requests;
drop policy if exists dmreq_insert on dm_requests;
create policy dmreq_insert on dm_requests for insert to authenticated with check (from_id = auth.uid());
drop policy if exists dmreq_select on dm_requests;
create policy dmreq_select on dm_requests for select to authenticated using (auth.uid() in (from_id, to_id));
drop policy if exists dmreq_update on dm_requests;
create policy dmreq_update on dm_requests for update to authenticated
  using (auth.uid() in (from_id, to_id)) with check (auth.uid() in (from_id, to_id));
drop policy if exists dmreq_delete on dm_requests;
create policy dmreq_delete on dm_requests for delete to authenticated using (auth.uid() in (from_id, to_id));

-- messages: public rooms open to any signed-in user; private rooms (DMs, groups) members only
-- (same as fix-messaging.sql — included so this file is self-contained)
drop policy if exists msg_read on messages;
create policy msg_read on messages for select to authenticated
  using (exists (select 1 from rooms r where r.id = room_id and (r.is_public or is_member(room_id))));
drop policy if exists msg_insert on messages;
create policy msg_insert on messages for insert to authenticated
  with check (author_id = auth.uid()
              and exists (select 1 from rooms r where r.id = room_id and (r.is_public or is_member(room_id))));

-- room owners manage membership of their own rooms (kick, roles)
drop policy if exists rm_owner on room_members;
create policy rm_owner on room_members for all to authenticated
  using (exists (select 1 from rooms r where r.id = room_id and r.owner_id = auth.uid()))
  with check (exists (select 1 from rooms r where r.id = room_id and r.owner_id = auth.uid()));

create index if not exists messages_room_created_idx on messages(room_id, created_at desc);
create index if not exists notifications_user_created_idx on notifications(user_id, created_at desc);
create index if not exists debate_votes_debate_idx on debate_votes(debate_id);
create index if not exists ranked_queue_joined_idx on ranked_queue(joined_at);
create index if not exists ranked_matches_a_idx on ranked_matches(a);
create index if not exists ranked_matches_b_idx on ranked_matches(b);


-- ============================================================================
-- C. PUBLIC PROFILE VIEW (real debate stats now)
-- ============================================================================
drop view if exists profiles_public;
create view profiles_public with (security_invoker = on) as
  select id, handle, name, color, like_icon, avatar_path, tier, elo,
         debate_wins, debate_losses, debate_ties, is_admin, is_mod, is_owner
  from profiles;


-- ============================================================================
-- D. REALTIME (publication was empty -> no live updates anywhere)
-- ============================================================================
do $$ declare t text; begin
  foreach t in array array['messages','message_reactions','debates','debate_hands','debate_votes',
                           'debate_end_votes','ranked_matches','notifications','badges','room_reads','update_logs']
  loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
alter table debate_hands      replica identity full;
alter table message_reactions replica identity full;
alter table debate_votes      replica identity full;
alter table debate_end_votes  replica identity full;


-- ============================================================================
-- E. STORAGE BUCKETS (images, video, voice messages, attachments)
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('media', 'media', true), ('attachments', 'attachments', true)
on conflict (id) do nothing;

drop policy if exists maintrix_media_read on storage.objects;
create policy maintrix_media_read on storage.objects for select
  using (bucket_id in ('media', 'attachments'));
drop policy if exists maintrix_media_insert on storage.objects;
create policy maintrix_media_insert on storage.objects for insert to authenticated
  with check (bucket_id in ('media', 'attachments'));
drop policy if exists maintrix_media_update on storage.objects;
create policy maintrix_media_update on storage.objects for update to authenticated
  using (bucket_id in ('media', 'attachments') and owner = auth.uid());
drop policy if exists maintrix_media_delete on storage.objects;
create policy maintrix_media_delete on storage.objects for delete to authenticated
  using (bucket_id in ('media', 'attachments') and owner = auth.uid());


-- ============================================================================
-- F. INTEGRITY GUARDS
--   Direct client updates (role "authenticated") can't touch privileged fields.
--   SECURITY DEFINER functions run as the owner role, so they're unaffected.
-- ============================================================================
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin or is_owner from profiles where id = auth.uid()), false);
$$;

create or replace function guard_profile_privileged() returns trigger
language plpgsql as $$
begin
  if current_user not in ('authenticated', 'anon') or is_admin() then return new; end if;
  new.is_admin := old.is_admin;        new.is_mod := old.is_mod;          new.is_owner := old.is_owner;
  new.tier := old.tier;                new.elo := old.elo;
  new.debate_wins := old.debate_wins;  new.debate_losses := old.debate_losses; new.debate_ties := old.debate_ties;
  new.banned := old.banned;            new.ban_reason := old.ban_reason;  new.muted_until := old.muted_until;
  new.risk := old.risk;                new.risk_level := old.risk_level;  new.main_until := old.main_until;
  new.vpn_seen := old.vpn_seen;        new.created_at := old.created_at;
  -- handle is permanent once it's no longer the auto-generated placeholder
  if old.handle is not null and old.handle::text not like 'user\_%' then new.handle := old.handle; end if;
  return new;
end $$;
drop trigger if exists trg_guard_profile on profiles;
create trigger trg_guard_profile before update on profiles
  for each row execute function guard_profile_privileged();

create or replace function guard_room_member() returns trigger
language plpgsql as $$
declare owns boolean;
begin
  if current_user not in ('authenticated', 'anon') or is_admin() then return new; end if;
  select exists (select 1 from rooms r where r.id = new.room_id and r.owner_id = auth.uid()) into owns;
  if owns then return new; end if;
  if tg_op = 'INSERT' then
    new.rank := 'Initiate'; new.roles := '{}';
  else
    new.rank := old.rank; new.roles := old.roles; new.room_id := old.room_id; new.user_id := old.user_id;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_room_member on room_members;
create trigger trg_guard_room_member before insert or update on room_members
  for each row execute function guard_room_member();

create or replace function guard_badge() returns trigger
language plpgsql as $$
begin
  if current_user not in ('authenticated', 'anon') or is_admin() then return new; end if;
  new.user_id := old.user_id; new.label := old.label; new.icon := old.icon; new.color := old.color;
  new.rarity := old.rarity;   new.style := old.style; new.awarded_by := old.awarded_by;
  new.created_at := old.created_at;
  return new;   -- only pinned / is_public may change
end $$;
drop trigger if exists trg_guard_badge on badges;
create trigger trg_guard_badge before update on badges
  for each row execute function guard_badge();

-- room modes (locked / slow mode) + mute/ban enforcement on posting
create or replace function guard_message_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; p record; last_at timestamptz;
begin
  if auth.uid() is null or is_admin() then return new; end if;
  select locked, slow_mode_s, owner_id into r from rooms where id = new.room_id;
  select banned, muted_until into p from profiles where id = auth.uid();
  if coalesce(p.banned, false) then raise exception 'Your account is banned'; end if;
  if p.muted_until is not null and p.muted_until > now() then
    raise exception 'You are muted until %', to_char(p.muted_until, 'Mon DD HH24:MI');
  end if;
  if coalesce(r.locked, false) and r.owner_id is distinct from auth.uid() then
    raise exception 'This room is locked';
  end if;
  if coalesce(r.slow_mode_s, 0) > 0 and r.owner_id is distinct from auth.uid() then
    select max(created_at) into last_at from messages where room_id = new.room_id and author_id = auth.uid();
    if last_at is not null and last_at > now() - make_interval(secs => r.slow_mode_s) then
      raise exception 'Slow mode is on — wait % seconds between messages', r.slow_mode_s;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_guard_message on messages;
create trigger trg_guard_message before insert on messages
  for each row execute function guard_message_insert();


-- ============================================================================
-- G. NOTIFICATIONS (none were being created) + hashtags + DM streaks
-- ============================================================================
create or replace function notify_user(p_user uuid, p_type text, p_actor uuid, p_entity jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_user is not distinct from p_actor then return; end if;
  insert into notifications (user_id, type, kind, actor_id, entity, body)
  values (p_user, p_type, p_type, p_actor, coalesce(p_entity, '{}'::jsonb), p_entity->>'preview');
end $$;
revoke execute on function notify_user(uuid, text, uuid, jsonb) from public, anon, authenticated;

create or replace function trg_notify_friend_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' then perform notify_user(new.to_id, 'friend_request', new.from_id); end if;
  return new;
end $$;
drop trigger if exists notify_friend_request on friend_requests;
create trigger notify_friend_request after insert on friend_requests
  for each row execute function trg_notify_friend_request();

create or replace function trg_notify_user_like() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform notify_user(new.liked_id, 'like', new.liker_id); return new; end $$;
drop trigger if exists notify_user_like on user_likes;
create trigger notify_user_like after insert on user_likes
  for each row execute function trg_notify_user_like();

create or replace function trg_notify_post_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare p record;
begin
  select author_id, body, caption into p from posts where id = new.post_id;
  perform notify_user(p.author_id, 'post_like', new.user_id,
    jsonb_build_object('preview', left(coalesce(nullif(p.caption, ''), p.body, ''), 100)));
  return new;
end $$;
drop trigger if exists notify_post_like on post_likes;
create trigger notify_post_like after insert on post_likes
  for each row execute function trg_notify_post_like();

create or replace function trg_notify_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare post_author uuid; parent_author uuid;
begin
  select author_id into post_author from posts where id = new.post_id;
  perform notify_user(post_author, 'comment', new.author_id, jsonb_build_object('preview', left(new.body, 100)));
  if new.parent_id is not null then
    select author_id into parent_author from post_comments where id = new.parent_id;
    if parent_author is distinct from post_author then
      perform notify_user(parent_author, 'reply', new.author_id, jsonb_build_object('preview', left(new.body, 100)));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists notify_comment on post_comments;
create trigger notify_comment after insert on post_comments
  for each row execute function trg_notify_comment();

create or replace function trg_notify_badge() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_user(new.user_id, 'badge', new.awarded_by, jsonb_build_object('title', new.label));
  return new;
end $$;
drop trigger if exists notify_badge on badges;
create trigger notify_badge after insert on badges
  for each row execute function trg_notify_badge();

create or replace function trg_notify_server_join() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select kind, owner_id, title into r from rooms where id = new.room_id;
  if r.kind = 'server' then
    perform notify_user(r.owner_id, 'server_join', new.user_id, jsonb_build_object('room_id', new.room_id, 'title', r.title));
  end if;
  return new;
end $$;
drop trigger if exists notify_server_join on room_members;
create trigger notify_server_join after insert on room_members
  for each row execute function trg_notify_server_join();

-- messages: replies, @mentions, DM streaks
create or replace function trg_message_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare rk text; rpub boolean; reply_author uuid; h text; uid uuid; ent jsonb;
begin
  select kind, is_public into rk, rpub from rooms where id = new.room_id;
  ent := jsonb_build_object('room_id', new.room_id, 'preview', left(coalesce(new.body, ''), 120),
                            'media_kind', new.media_kind, 'group', rk = 'group');

  if new.reply_to is not null then
    select author_id into reply_author from messages where id = new.reply_to;
    perform notify_user(reply_author, 'reply', new.author_id, ent);
  end if;

  for h in select distinct lower(m[1]) from regexp_matches(coalesce(new.body, ''), '@([A-Za-z0-9_.]{2,20})', 'g') as m
  loop
    select id into uid from profiles where lower(handle::text) = h;
    if uid is not null and uid is distinct from reply_author
       and (coalesce(rpub, false) or exists (select 1 from room_members where room_id = new.room_id and user_id = uid)) then
      perform notify_user(uid, 'tag', new.author_id, ent);
    end if;
    uid := null;
  end loop;

  if rk = 'dm' then
    insert into dm_streaks (room_id, count, last_at, streak_count, last_streak_date)
    values (new.room_id, 1, now(), 1, current_date)
    on conflict (room_id) do update set
      count = dm_streaks.count + 1,
      last_at = now(),
      streak_count = case when dm_streaks.last_streak_date = current_date     then dm_streaks.streak_count
                          when dm_streaks.last_streak_date = current_date - 1 then dm_streaks.streak_count + 1
                          else 1 end,
      last_streak_date = current_date;
  end if;
  return new;
end $$;
drop trigger if exists trg_message_after on messages;
create trigger trg_message_after after insert on messages
  for each row execute function trg_message_after();

create or replace function trg_post_hashtags() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from post_hashtags where post_id = new.id;
  insert into post_hashtags (post_id, tag)
  select distinct new.id, lower(m[1])
  from regexp_matches(coalesce(new.body, '') || ' ' || coalesce(new.caption, ''), '#([A-Za-z0-9_]{2,40})', 'g') as m
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists trg_post_hashtags on posts;
create trigger trg_post_hashtags after insert or update of body, caption on posts
  for each row execute function trg_post_hashtags();


-- ============================================================================
-- H. FIXED SIGNATURES (3.x sends extra args)
-- ============================================================================
drop function if exists pow_challenge(text);
create or replace function pow_challenge(p_action text, p_v integer default null) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('id', gen_random_uuid(), 'bits', 0, 'action', p_action);   -- security stubbed
$$;

drop function if exists report_user(uuid, text, jsonb);
create or replace function report_user(target uuid, p_reason text, p_context jsonb default null, p_category text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a uuid;
begin
  for a in select id from profiles where is_admin or is_owner loop
    perform notify_user(a, 'report', auth.uid(),
      jsonb_build_object('text', coalesce(p_category || ': ', '') || coalesce(p_reason, ''), 'target', target));
  end loop;
end $$;

create or replace function accept_friend_request(from_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update friend_requests set status = 'accepted' where from_id = from_user and to_id = auth.uid();
  insert into friendships (user_a, user_b)
  values (least(from_user, auth.uid()), greatest(from_user, auth.uid())) on conflict do nothing;
  perform notify_user(from_user, 'friend', auth.uid());
end $$;


-- ============================================================================
-- I. DEBATES v2 — turns, timers, raised hands, stage guests, pause, ELO
-- ============================================================================
create or replace function create_debate(p_title text, p_desc text) returns uuid
language plpgsql security definer set search_path = public as $$
declare d uuid; r uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if length(trim(coalesce(p_title, ''))) < 3 then raise exception 'Give your debate a title'; end if;
  insert into rooms (kind, title, is_public, owner_id)
  values ('debate', left(trim(p_title), 120), true, auth.uid()) returning id into r;
  insert into room_members (room_id, user_id, rank) values (r, auth.uid(), 'Owner') on conflict do nothing;
  insert into debates (title, "desc", description, created_by, creator_id, status, room_id, chat_room_id)
  values (left(trim(p_title), 140), p_desc, p_desc, auth.uid(), auth.uid(), 'open', r, r)
  returning id into d;
  return d;
end $$;

create or replace function set_debate_format(p_debate uuid, p_round_secs integer, p_rounds integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  update debates set round_secs = greatest(0, coalesce(p_round_secs, 0)),
                     rounds = greatest(1, least(coalesce(p_rounds, 3), 10))
  where id = p_debate and status = 'open' and (creator_id = auth.uid() or is_admin());
  if not found then raise exception 'Only the host can change the format before it starts'; end if;
end $$;

create or replace function set_debate_turns(p_debate uuid, p_turn_secs integer, p_turns integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  update debates set turn_secs = greatest(0, least(coalesce(p_turn_secs, 0), 1800)),
                     rounds = greatest(1, least(coalesce(p_turns, 3), 20))
  where id = p_debate and status = 'open' and (creator_id = auth.uid() or is_admin());
  if not found then raise exception 'Only the host can change turns before it starts'; end if;
end $$;

create or replace function join_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates; t integer;
begin
  select * into d from debates where id = d_id for update;
  if not found then raise exception 'Debate not found'; end if;
  if d.status <> 'open' then raise exception 'This debate has already started'; end if;
  if d.creator_id = auth.uid() then raise exception 'You can''t debate yourself'; end if;
  t := nullif(d.turn_secs, 0);
  update debates set
    opponent_id = auth.uid(), status = 'active', started_at = now(),
    turn_no = 1, turn_holder = d.creator_id, turn_started_at = now(),
    turn_ends_at = case when t is null then null else now() + make_interval(secs => t) end,
    ends_at = case when coalesce(d.round_secs, 0) > 0
                   then now() + make_interval(secs => d.round_secs * greatest(d.rounds, 1)) end
  where id = d_id;
  if d.room_id is not null then
    insert into room_members (room_id, user_id, rank) values (d.room_id, auth.uid(), 'Initiate') on conflict do nothing;
  end if;
  perform notify_user(d.creator_id, 'debate_join', auth.uid(), jsonb_build_object('room_id', d.room_id, 'title', d.title));
end $$;

-- internal: move to the next speaker (or return the floor from a stage guest)
create or replace function _debate_next_turn(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates; nxt uuid; total integer; t integer;
begin
  select * into d from debates where id = p_id for update;
  if not found or d.status <> 'active' then return; end if;
  t := nullif(d.turn_secs, 0);
  if d.stage_guest is not null then
    update debates set turn_holder = d.stage_return, stage_guest = null, stage_return = null,
      turn_started_at = now(),
      turn_ends_at = case when t is null then null else now() + make_interval(secs => t) end,
      paused_at = null, paused_by = null, paused_left = null
    where id = p_id;
    return;
  end if;
  total := greatest(d.rounds, 1) * 2;
  if d.turn_no >= total then
    -- all turns done: floor opens for voting until the debaters end it
    update debates set turn_holder = null, turn_started_at = null, turn_ends_at = null, turn_no = total + 1,
      paused_at = null, paused_by = null, paused_left = null
    where id = p_id;
    return;
  end if;
  nxt := case when d.turn_holder = d.creator_id then d.opponent_id else d.creator_id end;
  update debates set turn_no = d.turn_no + 1, turn_holder = nxt, turn_started_at = now(),
    turn_ends_at = case when t is null then null else now() + make_interval(secs => t) end,
    paused_at = null, paused_by = null, paused_left = null
  where id = p_id;
  if d.ranked then
    perform notify_user(nxt, 'ranked_turn', auth.uid(), jsonb_build_object('room_id', d.room_id, 'title', d.title));
  end if;
end $$;
revoke execute on function _debate_next_turn(uuid) from public, anon, authenticated;

create or replace function debate_done_talking(p_debate uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates;
begin
  select * into d from debates where id = p_debate;
  if not found or d.status <> 'active' then return; end if;
  if auth.uid() is distinct from d.turn_holder
     and not (auth.uid() in (d.creator_id, d.opponent_id) and d.stage_guest is not null)
     and not is_admin() then
    raise exception 'It''s not your turn';
  end if;
  perform _debate_next_turn(p_debate);
end $$;

create or replace function debate_turn_expire(p_debate uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates;
begin
  select * into d from debates where id = p_debate;
  if not found or d.status <> 'active' or d.paused_at is not null or d.turn_ends_at is null then return; end if;
  if d.turn_ends_at <= now() + interval '2 seconds' then perform _debate_next_turn(p_debate); end if;
end $$;

create or replace function debate_pause(p_debate uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates;
begin
  select * into d from debates where id = p_debate for update;
  if not found or d.status <> 'active' then return; end if;
  if not (auth.uid() in (d.creator_id, d.opponent_id) or is_admin()) then raise exception 'Only the debaters can pause'; end if;
  if d.paused_at is not null then return; end if;
  update debates set paused_at = now(), paused_by = auth.uid(),
    paused_left = case when d.turn_ends_at is null then null
                       else greatest(0, ceil(extract(epoch from (d.turn_ends_at - now()))))::integer end,
    turn_ends_at = null
  where id = p_debate;
end $$;

create or replace function debate_resume(p_debate uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d debates;
begin
  select * into d from debates where id = p_debate for update;
  if not found then raise exception 'Debate not found'; end if;
  if not (auth.uid() in (d.creator_id, d.opponent_id) or is_admin()) then raise exception 'Only the debaters can resume'; end if;
  if d.paused_at is null then return to_jsonb(d); end if;
  update debates set
    turn_ends_at = case when d.paused_left is null then null else now() + make_interval(secs => d.paused_left) end,
    turn_started_at = now(), paused_at = null, paused_by = null, paused_left = null
  where id = p_debate returning * into d;
  return to_jsonb(d);
end $$;

create or replace function debate_raise_hand(p_debate uuid, p_up boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if coalesce(p_up, false) then
    insert into debate_hands (debate_id, user_id) values (p_debate, auth.uid()) on conflict do nothing;
  else
    delete from debate_hands where debate_id = p_debate and user_id = auth.uid();
  end if;
end $$;

create or replace function debate_bring_up(p_debate uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates; t integer;
begin
  select * into d from debates where id = p_debate for update;
  if not found or d.status <> 'active' then raise exception 'Debate isn''t live'; end if;
  if not (auth.uid() in (d.creator_id, d.opponent_id) or is_admin()) then raise exception 'Only the debaters can bring people up'; end if;
  if p_user is null then
    if d.stage_guest is not null then perform _debate_next_turn(p_debate); end if;
    return;
  end if;
  t := nullif(d.turn_secs, 0);
  update debates set stage_guest = p_user, stage_return = coalesce(d.turn_holder, d.creator_id),
    turn_holder = p_user, turn_started_at = now(),
    turn_ends_at = case when t is null then null else now() + make_interval(secs => t) end,
    paused_at = null, paused_by = null, paused_left = null
  where id = p_debate;
  delete from debate_hands where debate_id = p_debate and user_id = p_user;
end $$;

-- internal finalize: tally votes, W/L/T, ELO for ranked, notify
create or replace function _end_debate(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates; vc integer; vo integer; w uuid; ra integer; rb integer;
        ea double precision; sa double precision; delta integer := 0;
begin
  select * into d from debates where id = p_id for update;
  if not found or d.status = 'ended' then return; end if;
  if d.opponent_id is null then
    update debates set status = 'ended', ended_at = now(), turn_holder = null, turn_ends_at = null where id = p_id;
    return;
  end if;
  select count(*) filter (where vote_for = d.creator_id), count(*) filter (where vote_for = d.opponent_id)
    into vc, vo from debate_votes where debate_id = p_id;
  w := case when vc > vo then d.creator_id when vo > vc then d.opponent_id end;
  if d.ranked then
    select elo into ra from profiles where id = d.creator_id;
    select elo into rb from profiles where id = d.opponent_id;
    ea := 1.0 / (1.0 + power(10.0, (coalesce(rb, 1000) - coalesce(ra, 1000)) / 400.0));
    sa := case when w = d.creator_id then 1.0 when w is null then 0.5 else 0.0 end;
    delta := round(32 * (sa - ea));
    update profiles set elo = elo + delta where id = d.creator_id;
    update profiles set elo = elo - delta where id = d.opponent_id;
  end if;
  update profiles set
    debate_wins   = debate_wins   + case when w = id then 1 else 0 end,
    debate_losses = debate_losses + case when w is not null and w <> id then 1 else 0 end,
    debate_ties   = debate_ties   + case when w is null then 1 else 0 end
  where id in (d.creator_id, d.opponent_id);
  update debates set status = 'ended', ended_at = now(), winner_id = w,
    turn_holder = null, turn_ends_at = null, paused_at = null, paused_by = null, paused_left = null,
    elo_delta = case when d.ranked then abs(delta) end,
    elo_gain  = case when d.ranked then abs(delta) end,
    elo_loss  = case when d.ranked then abs(delta) end
  where id = p_id;
  update ranked_matches set status = 'ended', ended_reason = 'finished', updated_at = now() where debate_id = p_id;
  perform notify_user(d.creator_id,  'debate_end', auth.uid(), jsonb_build_object('room_id', d.room_id, 'title', d.title));
  perform notify_user(d.opponent_id, 'debate_end', auth.uid(), jsonb_build_object('room_id', d.room_id, 'title', d.title));
end $$;
revoke execute on function _end_debate(uuid) from public, anon, authenticated;

create or replace function end_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates;
begin
  select * into d from debates where id = d_id;
  if not found then raise exception 'Debate not found'; end if;
  if not (auth.uid() in (d.creator_id, d.opponent_id) or is_admin()) then raise exception 'Only the debaters can end this'; end if;
  perform _end_debate(d_id);
end $$;

-- both debaters voting to end finishes the debate
create or replace function vote_end_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d debates; n integer;
begin
  insert into debate_end_votes (debate_id, voter_id) values (d_id, auth.uid()) on conflict do nothing;
  select * into d from debates where id = d_id;
  if d.status = 'active' and d.opponent_id is not null and auth.uid() in (d.creator_id, d.opponent_id) then
    select count(*) into n from debate_end_votes where debate_id = d_id and voter_id in (d.creator_id, d.opponent_id);
    if n >= 2 then perform _end_debate(d_id); end if;
  end if;
end $$;


-- ============================================================================
-- J. RANKED — queue, coin flip, topic pick, review, live debate
-- ============================================================================
create or replace function ranked_state() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'queued',    exists (select 1 from ranked_queue where user_id = auth.uid()),
    'joined_at', (select joined_at from ranked_queue where user_id = auth.uid()),
    'match',     (select to_jsonb(m) from ranked_matches m
                  where auth.uid() in (m.a, m.b) and m.status not in ('ended', 'cancelled')
                  order by m.created_at desc limit 1));
$$;

create or replace function ranked_join() returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); opp uuid;
begin
  if me is null then raise exception 'Sign in first'; end if;
  if exists (select 1 from ranked_matches where me in (a, b) and status not in ('ended', 'cancelled')) then
    return ranked_state();
  end if;
  select user_id into opp from ranked_queue where user_id <> me order by joined_at limit 1 for update skip locked;
  if opp is null then
    insert into ranked_queue (user_id) values (me) on conflict do nothing;
  else
    delete from ranked_queue where user_id in (me, opp);
    insert into ranked_matches (a, b, status) values (opp, me, 'coinflip');
    perform notify_user(opp, 'ranked_match', me);
  end if;
  return ranked_state();
end $$;

create or replace function ranked_leave() returns void
language sql security definer set search_path = public as $$
  delete from ranked_queue where user_id = auth.uid();
$$;

create or replace function ranked_call(m_id uuid, p_side text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m ranked_matches; f text; other uuid;
begin
  select * into m from ranked_matches where id = m_id for update;
  if not found or auth.uid() not in (m.a, m.b) then raise exception 'Match not found'; end if;
  if m.status <> 'coinflip' or m.caller is not null then return to_jsonb(m); end if;
  f := case when random() < 0.5 then 'heads' else 'tails' end;
  other := case when m.a = auth.uid() then m.b else m.a end;
  update ranked_matches set caller = auth.uid(), flip = f,
    flip_winner = case when lower(coalesce(p_side, '')) = f then auth.uid() else other end,
    proposer    = case when lower(coalesce(p_side, '')) = f then auth.uid() else other end,
    status = 'topic', updated_at = now()
  where id = m_id returning * into m;
  perform notify_user(other, 'ranked_turn', auth.uid());
  return to_jsonb(m);
end $$;

create or replace function ranked_propose(m_id uuid, p_title text, p_desc text, p_turn_secs integer, p_turns integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m ranked_matches; other uuid;
begin
  select * into m from ranked_matches where id = m_id for update;
  if not found or auth.uid() not in (m.a, m.b) then raise exception 'Match not found'; end if;
  if m.status <> 'topic' or m.proposer is distinct from auth.uid() then raise exception 'It''s not your pick'; end if;
  if length(trim(coalesce(p_title, ''))) < 3 then raise exception 'Add a topic'; end if;
  update ranked_matches set topic_title = left(trim(p_title), 140), topic_desc = left(coalesce(p_desc, ''), 500),
    turn_secs = greatest(15, least(coalesce(p_turn_secs, 60), 600)),
    turns = greatest(1, least(coalesce(p_turns, 3), 10)),
    status = 'review', updated_at = now()
  where id = m_id returning * into m;
  other := case when m.a = auth.uid() then m.b else m.a end;
  perform notify_user(other, 'ranked_turn', auth.uid());
  return to_jsonb(m);
end $$;

create or replace function ranked_respond(m_id uuid, p_agree boolean, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m ranked_matches; me uuid := auth.uid(); other uuid; r uuid; d uuid; t integer;
begin
  select * into m from ranked_matches where id = m_id for update;
  if not found or me not in (m.a, m.b) then raise exception 'Match not found'; end if;
  if m.status <> 'review' then return to_jsonb(m); end if;
  if m.proposer = me then raise exception 'Waiting on your opponent'; end if;
  if coalesce(p_agree, false) then
    insert into rooms (kind, title, is_public, owner_id)
    values ('debate', left(m.topic_title, 120), true, m.proposer) returning id into r;
    insert into room_members (room_id, user_id, rank)
    values (r, m.proposer, 'Owner'), (r, me, 'Initiate') on conflict do nothing;
    t := nullif(m.turn_secs, 0);
    insert into debates (title, "desc", description, created_by, creator_id, opponent_id, status, room_id, chat_room_id,
                         ranked, rounds, turn_secs, started_at, turn_no, turn_holder, turn_started_at, turn_ends_at)
    values (m.topic_title, m.topic_desc, m.topic_desc, m.proposer, m.proposer, me, 'active', r, r,
            true, coalesce(m.turns, 3), coalesce(m.turn_secs, 60), now(), 1, m.proposer, now(),
            case when t is null then null else now() + make_interval(secs => t) end)
    returning id into d;
    update ranked_matches set status = 'accepted', debate_id = d, updated_at = now() where id = m_id returning * into m;
    perform notify_user(m.proposer, 'ranked_live', me, jsonb_build_object('room_id', r, 'title', m.topic_title));
  else
    update ranked_matches set rejects = rejects + 1, last_reason = left(coalesce(p_reason, ''), 200),
      topic_title = null, topic_desc = null, status = 'topic',
      proposer = case when rejects + 1 >= 3 then me else proposer end,
      updated_at = now()
    where id = m_id returning * into m;
    other := case when m.a = me then m.b else m.a end;
    perform notify_user(case when m.proposer = me then other else m.proposer end, 'ranked_turn', me);
  end if;
  return to_jsonb(m);
end $$;

create or replace function ranked_cancel(m_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m ranked_matches; other uuid;
begin
  select * into m from ranked_matches where id = m_id for update;
  if not found or (auth.uid() not in (m.a, m.b) and not is_admin()) then raise exception 'Match not found'; end if;
  if m.status in ('ended', 'cancelled') then return to_jsonb(m); end if;
  update ranked_matches set status = 'cancelled', ended_reason = 'cancelled', updated_at = now()
  where id = m_id returning * into m;
  other := case when m.a = auth.uid() then m.b else m.a end;
  perform notify_user(other, 'ranked_cancel', auth.uid());
  return to_jsonb(m);
end $$;


-- ============================================================================
-- K. GROUP DMs
-- ============================================================================
create or replace function create_group_dm(p_title text, p_members uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare r uuid; u uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if coalesce(array_length(p_members, 1), 0) < 1 then raise exception 'Add at least one person'; end if;
  if array_length(p_members, 1) > 24 then raise exception 'Groups are limited to 25 people'; end if;
  insert into rooms (kind, title, is_public, owner_id)
  values ('group', nullif(left(trim(coalesce(p_title, '')), 60), ''), false, auth.uid()) returning id into r;
  insert into room_members (room_id, user_id, rank) values (r, auth.uid(), 'Owner');
  foreach u in array p_members loop
    if u is not null and u <> auth.uid() and not exists (
         select 1 from blocks where (blocker_id = u and blocked_id = auth.uid()) or (blocker_id = auth.uid() and blocked_id = u)) then
      insert into room_members (room_id, user_id, rank) values (r, u, 'Initiate') on conflict do nothing;
    end if;
  end loop;
  return r;
end $$;

create or replace function group_add_members(p_room uuid, p_members uuid[]) returns integer
language plpgsql security definer set search_path = public as $$
declare u uuid; added integer := 0; n integer;
begin
  if not exists (select 1 from rooms where id = p_room and kind = 'group') then raise exception 'Group not found'; end if;
  if not is_member(p_room) then raise exception 'You''re not in this group'; end if;
  foreach u in array coalesce(p_members, '{}') loop
    if u is not null then
      insert into room_members (room_id, user_id, rank) values (p_room, u, 'Initiate') on conflict do nothing;
      get diagnostics n = row_count; added := added + n;
    end if;
  end loop;
  return added;
end $$;

create or replace function group_leave(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from room_members where room_id = p_room and user_id = auth.uid();
  update rooms set owner_id = (select user_id from room_members where room_id = p_room order by joined_at limit 1)
  where id = p_room and kind = 'group' and owner_id = auth.uid();
end $$;

create or replace function group_remove_member(p_room uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from rooms where id = p_room and kind = 'group' and (owner_id = auth.uid() or is_admin())) then
    raise exception 'Only the group owner can remove people';
  end if;
  delete from room_members where room_id = p_room and user_id = p_user;
end $$;

create or replace function group_rename(p_room uuid, p_title text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_member(p_room) then raise exception 'You''re not in this group'; end if;
  update rooms set title = nullif(left(trim(coalesce(p_title, '')), 60), '') where id = p_room and kind = 'group';
end $$;

create or replace function my_groups() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(g order by g.last_at desc nulls last), '[]'::jsonb)
  from (
    select r.id as room_id, r.id, r.title, r.owner_id, r.created_at,
           (select coalesce(jsonb_agg(m.user_id), '[]'::jsonb) from room_members m where m.room_id = r.id) as members,
           lm.created_at as last_at, lm.author_id as last_author, lm.body as last_body, lm.is_system as last_system
    from rooms r
    join room_members me on me.room_id = r.id and me.user_id = auth.uid()
    left join lateral (select created_at, author_id, body, is_system from messages
                       where room_id = r.id order by created_at desc limit 1) lm on true
    where r.kind = 'group'
  ) g;
$$;


-- ============================================================================
-- L. BADGES, STAFF, PUSH, STREAK SAVERS
-- ============================================================================
create or replace function badge_stats() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(label, n), '{}'::jsonb)
  from (select label, count(distinct user_id) as n from badges group by label) s;
$$;

create or replace function badge_collectors() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.n desc), '[]'::jsonb)
  from (select user_id, count(*) as n from badges group by user_id order by count(*) desc limit 50) x;
$$;

create or replace function my_badge_progress() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'messages', (select count(*) from messages where author_id = auth.uid()),
    'posts',    (select count(*) from posts where author_id = auth.uid()),
    'comments', (select count(*) from post_comments where author_id = auth.uid()),
    'friends',  (select count(*) from friendships where auth.uid() in (user_a, user_b)),
    'debates',  (select debate_wins + debate_losses + debate_ties from profiles where id = auth.uid()),
    'wins',     (select debate_wins from profiles where id = auth.uid()),
    'badges',   (select count(*) from badges where user_id = auth.uid()));
$$;

create or replace function list_staff() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id,
           'role', case when is_owner then 'owner' when is_admin then 'admin' else 'mod' end)), '[]'::jsonb)
  from profiles where is_owner or is_admin or is_mod;
$$;

create or replace function admin_set_mod(target uuid, val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set is_mod = coalesce(val, false) where id = target; end $$;

create or replace function admin_set_owner(target uuid, val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set is_owner = coalesce(val, false) where id = target; end $$;

create or replace function save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_ua text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_endpoint is null then return; end if;
  insert into push_subscriptions (user_id, endpoint, p256dh, auth, user_agent, last_seen)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, p_ua, now())
  on conflict (user_id, endpoint) do update
    set p256dh = excluded.p256dh, auth = excluded.auth, user_agent = excluded.user_agent, last_seen = now();
end $$;

create or replace function streak_savers_left() returns integer
language sql stable security definer set search_path = public as $$
  select greatest(0, 3 - (select count(*)::integer from streak_saves
                          where user_id = auth.uid() and used_at >= date_trunc('month', now())));
$$;

create or replace function use_streak_saver(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare remaining integer; s dm_streaks;
begin
  if not is_member(p_room) then raise exception 'Not your conversation'; end if;
  remaining := streak_savers_left();
  if remaining <= 0 then raise exception 'No streak savers left this month'; end if;
  select * into s from dm_streaks where room_id = p_room;
  if not found or s.streak_count <= 0 then raise exception 'There''s no streak to save'; end if;
  if s.last_streak_date >= current_date - 1 then
    return jsonb_build_object('ok', true, 'left', remaining, 'streak', s.streak_count, 'note', 'Streak is already safe');
  end if;
  update dm_streaks set last_streak_date = current_date - 1 where room_id = p_room returning * into s;
  insert into streak_saves (user_id, room_id) values (auth.uid(), p_room);
  return jsonb_build_object('ok', true, 'left', remaining - 1, 'streak', s.streak_count);
end $$;


-- ============================================================================
-- M. ADMIN / OVERWATCH SUITE  (all guarded by is_admin())
-- ============================================================================
create or replace function admin_members(p_filter text, p_limit integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f text := lower(coalesce(p_filter, '')); res jsonb;
begin
  if not is_admin() then raise exception 'not admin'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select id, handle, name, tier, elo, banned, muted_until, is_admin, is_mod, is_owner,
           main_until, risk_level, created_at, debate_wins, debate_losses, debate_ties
    from profiles
    where case f
      when 'banned' then banned
      when 'muted'  then muted_until > now()
      when 'staff'  then (is_admin or is_mod or is_owner)
      when 'main'   then main_until > now()
      when 'new'    then created_at > now() - interval '7 days'
      when ''       then true
      when 'all'    then true
      else (handle::text ilike '%' || f || '%' or name ilike '%' || f || '%')
    end
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  ) x;
  return res;
end $$;

create or replace function admin_member_lists(p_target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not admin'; end if;
  return jsonb_build_object(
    'friends',    (select coalesce(jsonb_agg(case when user_a = p_target then user_b else user_a end), '[]'::jsonb)
                   from friendships where p_target in (user_a, user_b)),
    'rooms',      (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title, 'kind', r.kind, 'rank', m.rank)), '[]'::jsonb)
                   from room_members m join rooms r on r.id = m.room_id where m.user_id = p_target),
    'blocked',    (select coalesce(jsonb_agg(blocked_id), '[]'::jsonb) from blocks where blocker_id = p_target),
    'blocked_by', (select coalesce(jsonb_agg(blocker_id), '[]'::jsonb) from blocks where blocked_id = p_target));
end $$;

create or replace function admin_member_stats(p_target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not admin'; end if;
  return (select jsonb_build_object(
    'messages',        (select count(*) from messages where author_id = p_target),
    'posts',           (select count(*) from posts where author_id = p_target),
    'comments',        (select count(*) from post_comments where author_id = p_target),
    'friends',         (select count(*) from friendships where p_target in (user_a, user_b)),
    'rooms',           (select count(*) from room_members where user_id = p_target),
    'badges',          (select count(*) from badges where user_id = p_target),
    'last_message_at', (select max(created_at) from messages where author_id = p_target),
    'elo', p.elo, 'wins', p.debate_wins, 'losses', p.debate_losses, 'ties', p.debate_ties,
    'created_at', p.created_at, 'tier', p.tier, 'main_until', p.main_until)
    from profiles p where p.id = p_target);
end $$;

create or replace function admin_member_action(p_target uuid, p_action text, p_arg text) returns integer
language plpgsql security definer set search_path = public as $$
declare a text := lower(coalesce(p_action, ''));
begin
  if not is_admin() then raise exception 'not admin'; end if;
  if a = 'ban' then update profiles set banned = true, ban_reason = p_arg where id = p_target;
  elsif a = 'unban' then update profiles set banned = false, ban_reason = null where id = p_target;
  elsif a = 'mute' then update profiles set muted_until = now() + make_interval(mins => coalesce(nullif(p_arg, '')::integer, 60)) where id = p_target;
  elsif a = 'unmute' then update profiles set muted_until = null where id = p_target;
  elsif a in ('tier', 'set_tier') then update profiles set tier = coalesce(nullif(p_arg, ''), 'lite') where id = p_target;
  elsif a in ('reset_elo', 'reset_ranked') then
    update profiles set elo = 1000, debate_wins = 0, debate_losses = 0, debate_ties = 0 where id = p_target;
  elsif a in ('mod', 'make_mod') then update profiles set is_mod = true where id = p_target;
  elsif a in ('unmod', 'remove_mod') then update profiles set is_mod = false where id = p_target;
  elsif a = 'clear_status' then update profiles set status_line = null where id = p_target;
  elsif a = 'clear_bio' then update profiles set bio = null where id = p_target;
  else return 0;
  end if;
  return 1;
end $$;

create or replace function admin_grant_main(p_target uuid, p_days integer) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare u timestamptz;
begin
  if not is_admin() then raise exception 'not admin'; end if;
  if coalesce(p_days, 0) <= 0 then
    update profiles set main_until = null, tier = 'lite' where id = p_target;
    return null;
  end if;
  update profiles set main_until = greatest(coalesce(main_until, now()), now()) + make_interval(days => p_days),
                      tier = 'main'
  where id = p_target returning main_until into u;
  return u;
end $$;

create or replace function admin_set_banner(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update app_config set banner = p where id = 1; end $$;

create or replace function admin_send_notice(p_target uuid, p_text text, p_feat text) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not is_admin() then raise exception 'not admin'; end if;
  insert into notifications (user_id, type, kind, actor_id, entity, body)
  select id, 'notice', 'notice', auth.uid(), jsonb_build_object('text', p_text, 'feat', p_feat), p_text
  from profiles where (p_target is null or id = p_target) and id <> auth.uid();
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function admin_notify_update(p_update uuid, p_audience text, p_message text, p_push boolean) returns integer
language plpgsql security definer set search_path = public as $$
declare u update_logs; n integer; aud text := lower(coalesce(p_audience, 'everyone'));
begin
  if not is_admin() then raise exception 'not admin'; end if;
  select * into u from update_logs where id = p_update;
  if not found then raise exception 'Update not found'; end if;
  insert into notifications (user_id, type, kind, actor_id, entity, body)
  select id, 'update', 'update', auth.uid(),
         jsonb_build_object('title', coalesce(u.title, u.version), 'text', p_message), p_message
  from profiles
  where case aud when 'staff'  then (is_admin or is_mod or is_owner)
                 when 'main'   then main_until > now()
                 when 'admins' then (is_admin or is_owner)
                 else true end;
  get diagnostics n = row_count;
  update update_logs set notified_at = now(), notified_count = n, notified_audience = aud, updated_at = now()
  where id = p_update;
  return n;
end $$;

create or replace function admin_set_handle(p_target uuid, p_handle text) returns void
language plpgsql security definer set search_path = public as $$
declare h text := lower(regexp_replace(coalesce(p_handle, ''), '^@+', ''));
begin
  if not is_admin() then raise exception 'not admin'; end if;
  if h !~ '^[a-z0-9_.]{2,20}$' then raise exception 'Handles are 2-20 letters, numbers, _ or .'; end if;
  if exists (select 1 from profiles where lower(handle::text) = h and id <> p_target) then raise exception 'That handle is taken'; end if;
  update profiles set handle = h where id = p_target;
end $$;

create or replace function admin_set_debate_stats(p_target uuid, p_elo integer, p_wins integer, p_losses integer, p_ties integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not admin'; end if;
  update profiles set elo = coalesce(p_elo, elo), debate_wins = coalesce(p_wins, debate_wins),
                      debate_losses = coalesce(p_losses, debate_losses), debate_ties = coalesce(p_ties, debate_ties)
  where id = p_target;
end $$;

create or replace function admin_delete_user_posts(p_target uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not is_admin() then raise exception 'not admin'; end if;
  delete from posts where author_id = p_target;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function admin_activity(p_days integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d integer := greatest(1, least(coalesce(p_days, 14), 90));
begin
  if not is_admin() then raise exception 'not admin'; end if;
  return jsonb_build_object(
    'days', (select coalesce(jsonb_agg(jsonb_build_object(
               'day', g.day::date,
               'signups',  (select count(*) from profiles where created_at::date = g.day::date),
               'messages', (select count(*) from messages where created_at::date = g.day::date),
               'posts',    (select count(*) from posts    where created_at::date = g.day::date),
               'active',   (select count(distinct author_id) from messages where created_at::date = g.day::date)
             ) order by g.day), '[]'::jsonb)
             from generate_series((current_date - (d - 1))::timestamp, current_date::timestamp, interval '1 day') as g(day)),
    'users',        (select count(*) from profiles),
    'active_users', (select count(distinct author_id) from messages where created_at > now() - make_interval(days => d)));
end $$;

create or replace function admin_room_list(p_q text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q text := coalesce(p_q, ''); res jsonb;
begin
  if not is_admin() then raise exception 'not admin'; end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select r.id, r.title, r.slug, r.kind, r.is_public, r.is_official, r.locked, r.slow_mode_s, r.owner_id, r.created_at,
           (select count(*) from room_members m where m.room_id = r.id) as members,
           (select count(*) from messages m where m.room_id = r.id) as messages
    from rooms r
    where r.kind not in ('dm', 'group')
      and (q = '' or r.title ilike '%' || q || '%' or r.slug ilike '%' || q || '%')
    order by r.created_at desc limit 200
  ) x;
  return res;
end $$;

create or replace function admin_set_room_mode(p_room uuid, p_locked boolean, p_slow integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not admin'; end if;
  update rooms set locked = coalesce(p_locked, locked), slow_mode_s = greatest(0, coalesce(p_slow, slow_mode_s))
  where id = p_room;
end $$;

create or replace function admin_pin_message(p_msg uuid, p_val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update messages set pinned = coalesce(p_val, false) where id = p_msg; end $$;

create or replace function admin_purge_room(p_room uuid, p_minutes integer) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not is_admin() then raise exception 'not admin'; end if;
  delete from messages where room_id = p_room
    and created_at > now() - make_interval(mins => greatest(1, coalesce(p_minutes, 60)));
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function admin_reset_user_ranked(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not admin'; end if;
  update profiles set elo = 1000, debate_wins = 0, debate_losses = 0, debate_ties = 0 where id = target;
  delete from ranked_queue where user_id = target;
  update ranked_matches set status = 'cancelled', ended_reason = 'reset', updated_at = now()
  where target in (a, b) and status not in ('ended', 'cancelled');
end $$;

create or replace function admin_reset_ranked_all() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not admin'; end if;
  update profiles set elo = 1000, debate_wins = 0, debate_losses = 0, debate_ties = 0;
  delete from ranked_queue;
  update ranked_matches set status = 'cancelled', ended_reason = 'reset', updated_at = now()
  where status not in ('ended', 'cancelled');
end $$;


-- ============================================================================
-- N. STUBS — moderation & security (skipped by request; exact signatures so
--    the client never 404s). Lists return [] / {}, actions explain they're off.
-- ============================================================================
create or replace function admin_reports(p_limit text, p_open text) returns jsonb language sql as $$ select '[]'::jsonb $$;
create or replace function admin_appeals(p_status text) returns jsonb language sql as $$ select '[]'::jsonb $$;
create or replace function admin_filters() returns jsonb language sql as $$ select '[]'::jsonb $$;
create or replace function mod_held_list(p_status text) returns jsonb language sql as $$ select '[]'::jsonb $$;
create or replace function my_reports() returns jsonb language sql as $$ select '[]'::jsonb $$;
create or replace function admin_audit_log(p_limit text) returns jsonb language sql as $$ select '[]'::jsonb $$;

create or replace function _moderation_off() returns void language plpgsql as $$
begin raise exception 'Moderation tools aren''t enabled yet'; end $$;
create or replace function admin_add_filter(p_kind text, p_pattern text, p_action text) returns void language sql as $$ select _moderation_off() $$;
create or replace function admin_remove_filter(p_id text) returns void language sql as $$ select _moderation_off() $$;
create or replace function admin_close_report(p_id text, p_outcome text, p_note text) returns void language sql as $$ select _moderation_off() $$;
create or replace function admin_resolve_report(p_id text) returns void language sql as $$ select _moderation_off() $$;
create or replace function admin_decide_appeal(p_id text, p_accept text, p_note text) returns void language sql as $$ select _moderation_off() $$;
create or replace function mod_decide_held(p_id text, p_approve text) returns void language sql as $$ select _moderation_off() $$;
create or replace function mod_delete_message(p_id text) returns void language sql as $$ select _moderation_off() $$;
create or replace function mod_mute(target text, p_minutes text) returns void language sql as $$ select _moderation_off() $$;
create or replace function submit_appeal(p_kind text, p_body text) returns void language sql as $$ select _moderation_off() $$;
create or replace function admin_warn(target text, p_text text) returns void language sql as $$ select _moderation_off() $$;
create or replace function admin_force_signout(target text) returns void language sql as $$ select _moderation_off() $$;

create or replace function admin_security_overview() returns jsonb language sql as $$ select '{}'::jsonb $$;
create or replace function my_security_overview(p_device text) returns jsonb language sql as $$ select '{}'::jsonb $$;
create or replace function admin_set_age_gates(p jsonb) returns void language plpgsql as $$ begin end $$;
create or replace function admin_set_human_strictness(p_level text) returns void language plpgsql as $$ begin end $$;
create or replace function admin_set_lockdown(p_level text) returns void language plpgsql as $$ begin end $$;


-- reload PostgREST so every new function/column is callable immediately
notify pgrst, 'reload schema';
