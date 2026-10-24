-- ============================================================================
-- Maintrix backend — first-pass rebuild migration (from build-37 contract)
-- Run on a FRESH Supabase project (SQL editor, or `supabase db push`).
-- Derived from maintrix-backend-spec.md. Types/keys are best-effort; RLS is a
-- safe baseline; the security + debate function BODIES are stubs to iterate on.
--   ✅ runnable   🟡 tighten later   ❗ SECURITY: implement before real use
-- ============================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists citext;      -- case-insensitive handle

-- ----------------------------------------------------------------------------
-- IDENTITY
-- ----------------------------------------------------------------------------
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  handle      citext unique,          -- NULL until onboarding sets it (app shows setup when empty)
  name        text not null,
  bio         text,
  color       text,
  country     text,
  region      text,
  like_icon   text,
  mbti        text,
  enneagram_core text, enneagram_wing text, enneagram_tritype text,
  temperament_dominant text, temperament_secondary text,
  goals       text[] default '{}',
  fears       text[] default '{}',
  -- admin / security (used by admin_* RPCs)
  tier        text    not null default 'lite',
  is_admin    boolean not null default false,
  banned      boolean not null default false,
  muted_until timestamptz,
  risk        text    not null default 'none',
  elo         integer not null default 1000,
  created_at  timestamptz not null default now()
);

-- public, safe projection (client reads debate stats + handle/name here)
create view profiles_public as
  select p.id, p.handle, p.name, p.elo,
         coalesce(w.wins,0)  as debate_wins,
         coalesce(w.losses,0) as debate_losses,
         coalesce(w.ties,0)   as debate_ties
  from profiles p
  left join lateral (select 0 wins, 0 losses, 0 ties) w on true;  -- 🟡 wire to real debate results

-- ----------------------------------------------------------------------------
-- ROOMS & MESSAGES
-- ----------------------------------------------------------------------------
create table rooms (
  id          uuid primary key default gen_random_uuid(),
  title       text,
  slug        text unique,
  bio         text,
  category    text,
  kind        text not null default 'world',   -- world | dm | debate | group
  icon        text,
  icon_path   text,
  is_public   boolean not null default true,
  is_official boolean not null default false,
  owner_id    uuid references profiles(id) on delete set null,
  meta        jsonb not null default '{}',
  created_at  timestamptz not null default now(),
  expires_at  timestamptz
);
create table room_members (
  room_id uuid references rooms(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  rank    text not null default 'member',
  roles   text[] not null default '{}',
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
create table room_reads (
  room_id uuid references rooms(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
create table room_mutes (
  room_id uuid references rooms(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  primary key (room_id, user_id)
);
create table messages (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references rooms(id) on delete cascade,
  author_id  uuid not null references profiles(id) on delete cascade,
  body       text not null,
  edited     boolean not null default false,
  created_at timestamptz not null default now()
);
create table message_reactions (
  message_id uuid references messages(id) on delete cascade,
  user_id    uuid references profiles(id) on delete cascade,
  emoji      text not null,
  primary key (message_id, user_id, emoji)
);

-- ----------------------------------------------------------------------------
-- SOCIAL GRAPH & DMs
-- ----------------------------------------------------------------------------
create table friendships (
  user_a uuid references profiles(id) on delete cascade,
  user_b uuid references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)                    -- store normalized
);
create table friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references profiles(id) on delete cascade,
  to_id   uuid not null references profiles(id) on delete cascade,
  status  text not null default 'pending',   -- pending | accepted | declined
  created_at timestamptz not null default now(),
  unique (from_id, to_id)
);
create table dm_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references profiles(id) on delete cascade,
  to_id   uuid not null references profiles(id) on delete cascade,
  status  text not null default 'pending',
  created_at timestamptz not null default now(),
  unique (from_id, to_id)
);
create table dm_streaks (
  room_id uuid primary key references rooms(id) on delete cascade,
  count   integer not null default 0,
  last_at timestamptz
);
create table blocks (
  blocker_id uuid references profiles(id) on delete cascade,
  blocked_id uuid references profiles(id) on delete cascade,
  primary key (blocker_id, blocked_id)
);
create table user_likes (
  liker_id uuid references profiles(id) on delete cascade,
  liked_id uuid references profiles(id) on delete cascade,
  primary key (liker_id, liked_id)
);

-- ----------------------------------------------------------------------------
-- FEED
-- ----------------------------------------------------------------------------
create table posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references profiles(id) on delete cascade,
  body text,
  caption text,
  created_at timestamptz not null default now()
);
create table post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  author_id uuid not null references profiles(id) on delete cascade,
  parent_id uuid references post_comments(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
create table post_likes (
  post_id uuid references posts(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  primary key (post_id, user_id)
);
create table comment_likes (
  comment_id uuid references post_comments(id) on delete cascade,
  user_id    uuid references profiles(id) on delete cascade,
  primary key (comment_id, user_id)
);
create table saved_posts (
  post_id uuid references posts(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table post_hashtags (
  post_id uuid references posts(id) on delete cascade,
  tag text not null,
  primary key (post_id, tag)
);

-- ----------------------------------------------------------------------------
-- ENGAGEMENT: polls, debates, events, voice
-- ----------------------------------------------------------------------------
create table polls (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references rooms(id) on delete cascade,
  author_id uuid not null references profiles(id) on delete cascade,
  question text not null,
  options jsonb not null,                    -- ["opt a","opt b",...]
  created_at timestamptz not null default now()
);
create table poll_votes (
  poll_id uuid references polls(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  option_idx integer not null,
  primary key (poll_id, user_id)
);
create table debates (
  id uuid primary key default gen_random_uuid(),
  title text, "desc" text,
  status text not null default 'open',       -- open | live | ended
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table debate_votes (
  debate_id uuid references debates(id) on delete cascade,
  voter_id  uuid references profiles(id) on delete cascade,
  vote_for  uuid references profiles(id) on delete cascade,
  primary key (debate_id, voter_id)
);
create table debate_end_votes (
  debate_id uuid references debates(id) on delete cascade,
  voter_id  uuid references profiles(id) on delete cascade,
  primary key (debate_id, voter_id)
);
create table events (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references rooms(id) on delete cascade,
  created_by uuid references profiles(id) on delete set null,
  title text not null,
  starts_at timestamptz,
  created_at timestamptz not null default now()
);
create table event_rsvps (
  event_id uuid references events(id) on delete cascade,
  user_id  uuid references profiles(id) on delete cascade,
  primary key (event_id, user_id)
);
create table voice_channels (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references rooms(id) on delete cascade,
  created_by uuid references profiles(id) on delete set null,
  name text not null,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- BADGES / NOTIFICATIONS / PUSH / CONFIG
-- ----------------------------------------------------------------------------
create table badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  label text not null, icon text, color text,
  awarded_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  kind text, body text, entity jsonb,
  actor_id uuid references profiles(id) on delete set null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create table push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  endpoint text not null, p256dh text, auth text,
  user_agent text, last_seen timestamptz not null default now(),
  unique (user_id, endpoint)
);
create table app_config (
  id integer primary key default 1,
  maintenance boolean not null default false,
  maintenance_title text, maintenance_details text,
  human_check_mode text default 'off', human_check_min_age_minutes integer default 0, pow_bits integer default 0,
  require_mfa boolean not null default false,
  turnstile_site_key text, security_actions text[] default '{}', monitor boolean not null default false,
  check (id = 1)
);
insert into app_config (id) values (1) on conflict do nothing;

-- ============================================================================
-- SIGNUP TRIGGER — make a profile for every new auth user  ✅ (tighten meta keys)
-- ============================================================================
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, handle, name, country, region, goals, fears, bio,
                               mbti, enneagram_core, enneagram_wing, enneagram_tritype,
                               temperament_dominant, temperament_secondary)
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'handle', ''),   -- left NULL so the app runs its profile setup
    coalesce(new.raw_user_meta_data->>'name', 'New User'),
    new.raw_user_meta_data->>'country', new.raw_user_meta_data->>'region',
    coalesce((select array_agg(x) from jsonb_array_elements_text(new.raw_user_meta_data->'goals') x), '{}'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(new.raw_user_meta_data->'fears') x), '{}'),
    new.raw_user_meta_data->>'bio',
    new.raw_user_meta_data->>'mbti', new.raw_user_meta_data->>'enneagram_core',
    new.raw_user_meta_data->>'enneagram_wing', new.raw_user_meta_data->>'enneagram_tritype',
    new.raw_user_meta_data->>'temperament_dominant', new.raw_user_meta_data->>'temperament_secondary'
  );
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================================================
-- HELPERS
-- ============================================================================
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;
create or replace function is_member(room uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from room_members where room_id = room and user_id = auth.uid());
$$;

-- ============================================================================
-- RLS — enable on every table + baseline policies 🟡 (review before real use)
-- ============================================================================
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname='public' loop
    execute format('alter table public.%I enable row level security;', t);
  end loop;
end $$;

-- app_config: client reads it on boot (maintenance/human-check); writes only via admin RPCs
create policy appcfg_read on app_config for select to authenticated using (true);

-- profiles: everyone authed can read; you edit only yourself; admins do anything
create policy profiles_read   on profiles for select to authenticated using (true);
create policy profiles_update on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_admin  on profiles for all to authenticated using (is_admin()) with check (is_admin());

-- messages: read if member; insert as self in a room you're in; edit/delete own
create policy msg_read   on messages for select to authenticated using (is_member(room_id));
create policy msg_insert on messages for insert to authenticated with check (author_id = auth.uid() and is_member(room_id));
create policy msg_modify on messages for update to authenticated using (author_id = auth.uid());
create policy msg_delete on messages for delete to authenticated using (author_id = auth.uid() or is_admin());

-- rooms: read public or your rooms; owner/admin manage
create policy room_read on rooms for select to authenticated using (is_public or is_member(id) or is_admin());
create policy room_write on rooms for all to authenticated using (owner_id = auth.uid() or is_admin()) with check (owner_id = auth.uid() or is_admin());

-- room_members: you see your memberships / rooms you're in
create policy rm_read on room_members for select to authenticated using (user_id = auth.uid() or is_member(room_id));
create policy rm_self on room_members for all to authenticated using (user_id = auth.uid() or is_admin()) with check (user_id = auth.uid() or is_admin());

-- generic "owned by user_id" tables
do $$ declare t text; begin
  foreach t in array array['notifications','push_subscriptions','saved_posts','room_reads','room_mutes','poll_votes','event_rsvps']
  loop
    execute format('create policy %1$s_own on public.%1$I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());', t);
  end loop;
end $$;

-- feed: readable by all authed; writes must be as the author/liker
create policy posts_read on posts for select to authenticated using (true);
create policy posts_own  on posts for all to authenticated using (author_id = auth.uid() or is_admin()) with check (author_id = auth.uid());
create policy pc_read on post_comments for select to authenticated using (true);
create policy pc_own  on post_comments for all to authenticated using (author_id = auth.uid() or is_admin()) with check (author_id = auth.uid());
create policy pl_own on post_likes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy cl_own on comment_likes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 🟡 TODO: friendships/requests/dm/blocks/reactions/debates/badges — add party-scoped
--          policies the same way. Left permissive-read only until you design them.

-- ============================================================================
-- RPCs — ✅ real where simple, ❗ stub where security/complex (iterate with Claude)
-- ============================================================================

-- get or create a 1:1 DM room between caller and `other`
create or replace function get_or_create_dm(other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r uuid;
begin
  select rm.room_id into r
  from room_members rm
  join rooms ro on ro.id = rm.room_id and ro.kind = 'dm'
  where rm.user_id in (auth.uid(), other)
  group by rm.room_id having count(distinct rm.user_id) = 2 limit 1;
  if r is not null then return r; end if;
  insert into rooms(kind, is_public, title) values ('dm', false, 'DM') returning id into r;
  insert into room_members(room_id, user_id) values (r, auth.uid()), (r, other);
  return r;
end $$;

create or replace function accept_friend_request(from_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update friend_requests set status='accepted' where from_id=from_user and to_id=auth.uid();
  insert into friendships(user_a, user_b)
  values (least(from_user, auth.uid()), greatest(from_user, auth.uid())) on conflict do nothing;
end $$;

create or replace function mutual_friends(other uuid) returns integer
language sql stable security definer set search_path = public as $$
  with me as (select case when user_a=auth.uid() then user_b else user_a end f
              from friendships where auth.uid() in (user_a,user_b)),
       them as (select case when user_a=other then user_b else user_a end f
                from friendships where other in (user_a,user_b))
  select count(*)::int from me join them using (f);
$$;

create or replace function create_debate(p_title text, p_desc text) returns uuid
language plpgsql security definer set search_path = public as $$
declare d uuid;
begin insert into debates(title,"desc",created_by) values(p_title,p_desc,auth.uid()) returning id into d; return d; end $$;

create or replace function report_user(target uuid, p_reason text, p_context jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- 🟡 create a `reports` table if you want these persisted; no-op insert for now
  insert into notifications(user_id, kind, body, entity)
  select id, 'report', p_reason, jsonb_build_object('target',target,'ctx',p_context)
  from profiles where is_admin;
end $$;

-- ❗ SECURITY STUBS — these currently ALLOW everything. Implement real logic
--    (proof-of-work, device/risk checks) before exposing the app publicly.
create or replace function pow_challenge(p_action text) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('id', gen_random_uuid(), 'bits', 0, 'action', p_action);  -- ❗ stub
$$;
create or replace function pow_verify(p_id uuid, p_solution text, p_signals jsonb) returns boolean
language sql security definer set search_path = public as $$ select true; $$;            -- ❗ stub: always passes
create or replace function session_check(p_device text, p_fp text, p_tz text) returns jsonb
language sql security definer set search_path = public as $$ select '{}'::jsonb; $$;      -- ❗ stub

-- admin toggles — real bodies, all gated on is_admin()
create or replace function admin_set_banned(target uuid, val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set banned=val where id=target; end $$;
create or replace function admin_set_admin(target uuid, val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set is_admin=val where id=target; end $$;
create or replace function admin_set_muted(target uuid, until_ts timestamptz) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set muted_until=until_ts where id=target; end $$;
create or replace function admin_set_tier(target uuid, val text) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set tier=val where id=target; end $$;
create or replace function admin_set_risk(target uuid, p_level text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set risk=p_level where id=target; end $$;
create or replace function admin_set_maintenance(enabled boolean, title text, details text) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update app_config set maintenance=enabled, maintenance_title=title, maintenance_details=details where id=1; end $$;
create or replace function admin_set_human_check(p_mode text, p_min_age_minutes integer, p_pow_bits integer) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update app_config set human_check_mode=p_mode, human_check_min_age_minutes=p_min_age_minutes, pow_bits=p_pow_bits where id=1; end $$;
create or replace function admin_set_security(p_site_key text, p_actions text[], p_monitor boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update app_config set turnstile_site_key=p_site_key, security_actions=p_actions, monitor=p_monitor where id=1; end $$;
create or replace function admin_set_require_mfa(val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if; update app_config set require_mfa=val where id=1; end $$;
create or replace function admin_stats() returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('users',(select count(*) from profiles),
                            'rooms',(select count(*) from rooms),
                            'messages',(select count(*) from messages)); $$;

-- ❗ TODO stubs — create so the client doesn't 404; fill bodies with Claude:
--   join_debate(uuid) vote_debate(uuid,uuid) vote_end_debate(uuid) end_debate(uuid)
--   delete_own_open_debate(uuid) admin_ack_alert(bigint) admin_alerts(int,bool)
--   admin_ban_info(uuid) admin_user_security(uuid) admin_delete_account(uuid)
--   admin_delete_user_messages(uuid) admin_delete_debate(uuid) admin_edit_profile(uuid,jsonb)
--   admin_kick(uuid,uuid) admin_set_server_official(uuid,bool) admin_reset_user_elo(uuid)
--   admin_reset_debate_leaderboard() admin_run_monitor()
-- (Each should `return` its expected shape; add `is_admin()` guard on the admin_* ones.)
