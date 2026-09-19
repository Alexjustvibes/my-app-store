-- Maintrix backend — RUN_THIS_ONCE.sql
-- Auto-regenerated concatenation of every migration in order. Paste this whole file
-- into the Supabase SQL editor once to bring a fresh project up to date, instead of
-- running each migration file individually.

-- ═══════════════════════════════════════════════════════════════════════
-- 0001_phase1_identity.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — Phase 1: Identity & auth
-- Run this in the Supabase SQL editor (or `supabase db push`).
-- Covers: traits lookup + seed, profiles table, immutability of traits/handle,
-- auto-create stub profile on signup, and Row-Level Security.
-- See apps/maintrix/BACKEND.md for the full plan.

-- ───────────────────────── extensions ─────────────────────────
create extension if not exists citext;

-- ───────────────────────── traits lookup ──────────────────────
-- Fixed set the signup test chooses from. `kind` = goal | fear.
create table if not exists public.traits (
  value text primary key,
  kind  text not null check (kind in ('goal','fear'))
);

insert into public.traits (value, kind) values
  ('Discipline','goal'),('Wealth','goal'),('Mastery','goal'),('Courage','goal'),
  ('Focus','goal'),('Health','goal'),('Creativity','goal'),('Leadership','goal'),
  ('Purpose','goal'),('Freedom','goal'),
  ('Wasted potential','fear'),('Irrelevance','fear'),('Failure','fear'),
  ('Rejection','fear'),('Mediocrity','fear'),('Being forgotten','fear'),
  ('Running out of time','fear'),('Loneliness','fear')
on conflict (value) do nothing;

-- ───────────────────────── profiles ───────────────────────────
-- One row per auth user. handle + traits are LOCKED after signup.
-- Nullable until the identity test fills them in (a stub row is created on signup).
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  handle     citext unique,                               -- immutable @handle
  name       text,                                        -- changeable display name
  goals      text[] not null default '{}',
  fears      text[] not null default '{}',
  bio        text,
  color      text default '#ed2e44',
  like_icon  text default 'heart',
  country    text,
  region     text,
  tier       text not null default 'lite' check (tier in ('lite','main')),
  is_admin   boolean not null default false,
  created_at timestamptz not null default now()
);

-- handle format: 3–20 chars, lowercase letters/digits/underscore
alter table public.profiles
  drop constraint if exists profiles_handle_format;
alter table public.profiles
  add constraint profiles_handle_format
  check (handle is null or handle ~ '^[a-z0-9_]{3,20}$');

-- match people by shared traits (Your World / trait nexuses)
create index if not exists profiles_goals_gin on public.profiles using gin (goals);
create index if not exists profiles_fears_gin on public.profiles using gin (fears);

-- ─────────────────── immutability of traits + handle ──────────
-- Once set (non-null / non-empty), handle and traits can never change.
create or replace function public.lock_identity()
returns trigger
language plpgsql
as $$
begin
  if old.handle is not null and new.handle is distinct from old.handle then
    raise exception 'handle is immutable';
  end if;
  if array_length(old.goals,1) is not null and new.goals is distinct from old.goals then
    raise exception 'goals are locked after signup';
  end if;
  if array_length(old.fears,1) is not null and new.fears is distinct from old.fears then
    raise exception 'fears are locked after signup';
  end if;
  -- tier and is_admin are never set by the user directly (server/webhook only)
  new.tier := old.tier;
  new.is_admin := old.is_admin;
  return new;
end;
$$;

drop trigger if exists trg_lock_identity on public.profiles;
create trigger trg_lock_identity
  before update on public.profiles
  for each row execute function public.lock_identity();

-- ─────────────── auto-create a stub profile on signup ─────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────── validate traits ───────────────────
-- Reject goals/fears that aren't in the fixed list, and wrong-kind values.
create or replace function public.validate_traits()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from unnest(new.goals) g
             where g not in (select value from public.traits where kind='goal')) then
    raise exception 'invalid goal value';
  end if;
  if exists (select 1 from unnest(new.fears) f
             where f not in (select value from public.traits where kind='fear')) then
    raise exception 'invalid fear value';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_traits on public.profiles;
create trigger trg_validate_traits
  before insert or update on public.profiles
  for each row execute function public.validate_traits();

-- ───────────────────────── Row-Level Security ────────────────
alter table public.profiles enable row level security;
alter table public.traits   enable row level security;

-- traits: readable by anyone signed in
drop policy if exists traits_read on public.traits;
create policy traits_read on public.traits
  for select to authenticated using (true);

-- profiles: all identities are public to signed-in users
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (true);

-- profiles: you may only insert/update your own row
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (auth.uid() = id);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- (no delete policy — profiles are removed via auth.users cascade only)

-- ═══════════════════════════════════════════════════════════════════════
-- 0002_phase2_rooms.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — Phase 2: Rooms & live messaging
-- Run in the Supabase SQL editor after 0001. Adds rooms, room_members, messages,
-- RLS, seeded singleton rooms (World / Commons / Acolyte Hub / trait nexuses /
-- training), a get-or-create DM function, and Realtime on messages.
-- See apps/maintrix/BACKEND.md.

create extension if not exists pgcrypto;

-- ───────────────────────── rooms ──────────────────────────────
create table if not exists public.rooms (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in
             ('world','trait','topic','server','dm','live','training','acolyte','commons','admin')),
  slug       text unique,                    -- stable id for singletons/DMs (e.g. 'world', 'trait:Discipline', 'dm:a:b')
  title      text,
  category   text,
  trait      text,
  scope      text not null default 'global', -- 'global' | 'location'
  owner_id   uuid references public.profiles (id) on delete set null,
  is_public  boolean not null default true,
  created_at timestamptz not null default now(),
  expires_at timestamptz,                     -- topic rooms: +24h
  meta       jsonb not null default '{}'
);
create index if not exists rooms_kind_idx on public.rooms (kind);

-- ───────────────────────── room_members ───────────────────────
create table if not exists public.room_members (
  room_id   uuid references public.rooms (id) on delete cascade,
  user_id   uuid references public.profiles (id) on delete cascade,
  rank      text not null default 'Initiate' check (rank in ('Initiate','Operator','Architect','Owner')),
  roles     text[] not null default '{}',
  joined_at timestamptz not null default now(),
  muted     boolean not null default false,
  primary key (room_id, user_id)
);

-- ───────────────────────── messages ───────────────────────────
create table if not exists public.messages (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.rooms (id) on delete cascade,
  author_id  uuid references public.profiles (id) on delete set null,
  body       text not null,
  reply_to   uuid references public.messages (id) on delete set null,
  edited     boolean not null default false,
  pinned     boolean not null default false,
  is_system  boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists messages_room_time_idx on public.messages (room_id, created_at);

-- ───────────────────────── helpers ────────────────────────────
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_member(room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.room_members m
                 where m.room_id = room and m.user_id = auth.uid());
$$;

-- A room is readable if it's an open shared space, a public server, or you're a member.
create or replace function public.room_readable(room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.rooms r
    where r.id = room and (
      r.kind in ('world','trait','topic','training','acolyte','commons')
      or (r.kind = 'server' and r.is_public)
      or public.is_member(room)
      or public.is_admin()
    )
  );
$$;

-- Get (or create) the 1:1 DM room between the caller and `other`.
create or replace function public.get_or_create_dm(other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare meid uuid := auth.uid(); rid uuid; s text;
begin
  if other = meid or other is null then raise exception 'invalid dm target'; end if;
  s := 'dm:' || least(meid, other)::text || ':' || greatest(meid, other)::text;
  select id into rid from public.rooms where slug = s;
  if rid is null then
    insert into public.rooms (kind, slug, is_public, title) values ('dm', s, false, 'Direct message')
      returning id into rid;
    insert into public.room_members (room_id, user_id) values (rid, meid), (rid, other)
      on conflict do nothing;
  end if;
  return rid;
end; $$;

-- ───────────────────────── RLS ────────────────────────────────
alter table public.rooms        enable row level security;
alter table public.room_members enable row level security;
alter table public.messages     enable row level security;

-- rooms
drop policy if exists rooms_read on public.rooms;
create policy rooms_read on public.rooms for select to authenticated
  using (kind in ('world','trait','topic','training','acolyte','commons')
         or (kind='server' and is_public)
         or public.is_member(id)
         or public.is_admin());
drop policy if exists rooms_insert on public.rooms;
create policy rooms_insert on public.rooms for insert to authenticated
  with check (owner_id = auth.uid());
drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms for update to authenticated
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());
drop policy if exists rooms_delete on public.rooms;
create policy rooms_delete on public.rooms for delete to authenticated
  using (owner_id = auth.uid() or public.is_admin());

-- room_members
drop policy if exists rm_read on public.room_members;
create policy rm_read on public.room_members for select to authenticated
  using (public.room_readable(room_id));
drop policy if exists rm_join on public.room_members;
create policy rm_join on public.room_members for insert to authenticated
  with check (user_id = auth.uid() or public.is_admin());
drop policy if exists rm_leave on public.room_members;
create policy rm_leave on public.room_members for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- messages
drop policy if exists msg_read on public.messages;
create policy msg_read on public.messages for select to authenticated
  using (public.room_readable(room_id));
drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (author_id = auth.uid() and public.room_readable(room_id));
drop policy if exists msg_update on public.messages;
create policy msg_update on public.messages for update to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());
drop policy if exists msg_delete on public.messages;
create policy msg_delete on public.messages for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

grant execute on function public.get_or_create_dm(uuid) to authenticated;

-- ───────────────────────── Realtime ───────────────────────────
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.messages'; exception when duplicate_object then null; end;
  begin execute 'alter publication supabase_realtime add table public.rooms';    exception when duplicate_object then null; end;
end $$;

-- ───────────────────────── seed singleton rooms ───────────────
insert into public.rooms (kind, slug, title, scope) values
  ('world',   'world',       'The World',    'global'),
  ('commons', 'commons',     'The Commons',  'global'),
  ('acolyte', 'acolyte-hub', 'Acolyte Hub',  'global'),
  ('training','training:paradigm',  'Paradigm-Broadening', 'global'),
  ('training','training:awareness', 'Self-Awareness',      'global')
on conflict (slug) do nothing;

-- one global room per trait (Your World / trait nexuses)
insert into public.rooms (kind, slug, title, trait, scope)
  select 'trait', 'trait:' || value, value, value, 'global' from public.traits
on conflict (slug) do nothing;

-- optional: seed a welcome line in the World
insert into public.messages (room_id, body, is_system)
  select id, 'Welcome to the World — the one room every Maintrix member shares. Say who you are.', true
  from public.rooms where slug = 'world'
    and not exists (select 1 from public.messages m2 join public.rooms r2 on r2.id=m2.room_id where r2.slug='world');

-- ═══════════════════════════════════════════════════════════════════════
-- 0003_phase3_social.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — Phase 3: Social graph
-- Run after 0002. Adds friendships, friend_requests, dm_requests (with the
-- one-DM-until-accepted rule), user_likes, RLS, and helper RPCs.
-- See apps/maintrix/BACKEND.md.

-- ───────────────────────── tables ─────────────────────────────
create table if not exists public.friendships (
  user_a uuid references public.profiles(id) on delete cascade,
  user_b uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create table if not exists public.friend_requests (
  from_id uuid references public.profiles(id) on delete cascade,
  to_id   uuid references public.profiles(id) on delete cascade,
  status  text not null default 'pending' check (status in ('pending','accepted','denied')),
  created_at timestamptz not null default now(),
  primary key (from_id, to_id),
  check (from_id <> to_id)
);

create table if not exists public.dm_requests (
  from_id uuid references public.profiles(id) on delete cascade,
  to_id   uuid references public.profiles(id) on delete cascade,
  status  text not null default 'pending' check (status in ('pending','accepted','denied')),
  created_at timestamptz not null default now(),
  primary key (from_id, to_id),
  check (from_id <> to_id)
);

create table if not exists public.user_likes (
  liker_id uuid references public.profiles(id) on delete cascade,
  liked_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (liker_id, liked_id),
  check (liker_id <> liked_id)
);
create index if not exists user_likes_liked_idx on public.user_likes (liked_id);

-- ───────────────────────── helpers ────────────────────────────
create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships
                 where user_a = least(a,b) and user_b = greatest(a,b));
$$;

create or replace function public.friend_ids(uid uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select case when user_a = uid then user_b else user_a end
  from public.friendships where user_a = uid or user_b = uid;
$$;

-- Can the caller post into this DM room right now? (one message until accepted)
create or replace function public.can_post_dm(room uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare meid uuid := auth.uid(); other uuid;
begin
  select user_id into other from public.room_members where room_id = room and user_id <> meid limit 1;
  if other is null then return true; end if;
  if public.are_friends(meid, other) then return true; end if;
  if exists (select 1 from public.dm_requests where status='accepted'
             and ((from_id=meid and to_id=other) or (from_id=other and to_id=meid))) then return true; end if;
  if exists (select 1 from public.dm_requests where status='denied'
             and ((from_id=meid and to_id=other) or (from_id=other and to_id=meid))) then return false; end if;
  -- pending / none: allow only if the caller has not posted in this room yet
  return (select count(*) from public.messages where room_id = room and author_id = meid) = 0;
end; $$;

-- On first DM message to a non-friend, open a pending dm_request.
create or replace function public.on_dm_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare k text; other uuid;
begin
  select kind into k from public.rooms where id = new.room_id;
  if k <> 'dm' then return new; end if;
  select user_id into other from public.room_members where room_id = new.room_id and user_id <> new.author_id limit 1;
  if other is null or public.are_friends(new.author_id, other) then return new; end if;
  if not exists (select 1 from public.dm_requests
                 where (from_id=new.author_id and to_id=other) or (from_id=other and to_id=new.author_id)) then
    insert into public.dm_requests(from_id, to_id) values (new.author_id, other) on conflict do nothing;
  end if;
  return new;
end; $$;

drop trigger if exists trg_dm_message on public.messages;
create trigger trg_dm_message after insert on public.messages
  for each row execute function public.on_dm_message();

-- Re-scope the message insert policy so DM rooms honor the one-message rule.
drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.room_readable(room_id)
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'dm'
          or public.can_post_dm(room_id) )
  );

-- ───────────────────────── RPCs ───────────────────────────────
create or replace function public.accept_friend_request(from_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare meid uuid := auth.uid();
begin
  if not exists (select 1 from public.friend_requests where from_id=from_user and to_id=meid and status='pending') then
    raise exception 'no pending request'; end if;
  insert into public.friendships(user_a,user_b)
    values (least(from_user,meid), greatest(from_user,meid)) on conflict do nothing;
  update public.friend_requests set status='accepted' where from_id=from_user and to_id=meid;
end; $$;

create or replace function public.mutual_friends(other uuid)
returns setof public.profiles language sql stable security definer set search_path = public as $$
  select p.* from public.profiles p
  where p.id in (select public.friend_ids(auth.uid()) intersect select public.friend_ids(other));
$$;

grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.mutual_friends(uuid) to authenticated;

-- ───────────────────────── RLS ────────────────────────────────
alter table public.friendships     enable row level security;
alter table public.friend_requests enable row level security;
alter table public.dm_requests     enable row level security;
alter table public.user_likes      enable row level security;

-- friendships: only rows involving me are visible (keeps friend lists private;
-- mutual friends are exposed only through the mutual_friends() RPC)
drop policy if exists fr_read on public.friendships;
create policy fr_read on public.friendships for select to authenticated
  using (user_a = auth.uid() or user_b = auth.uid());
drop policy if exists fr_del on public.friendships;
create policy fr_del on public.friendships for delete to authenticated
  using (user_a = auth.uid() or user_b = auth.uid());

-- friend_requests
drop policy if exists freq_read on public.friend_requests;
create policy freq_read on public.friend_requests for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());
drop policy if exists freq_insert on public.friend_requests;
create policy freq_insert on public.friend_requests for insert to authenticated
  with check (from_id = auth.uid());
drop policy if exists freq_update on public.friend_requests;
create policy freq_update on public.friend_requests for update to authenticated
  using (to_id = auth.uid());

-- dm_requests
drop policy if exists dreq_read on public.dm_requests;
create policy dreq_read on public.dm_requests for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());
drop policy if exists dreq_insert on public.dm_requests;
create policy dreq_insert on public.dm_requests for insert to authenticated
  with check (from_id = auth.uid());
drop policy if exists dreq_update on public.dm_requests;
create policy dreq_update on public.dm_requests for update to authenticated
  using (to_id = auth.uid());

-- user_likes: counts are public; you only write your own likes
drop policy if exists likes_read on public.user_likes;
create policy likes_read on public.user_likes for select to authenticated using (true);
drop policy if exists likes_insert on public.user_likes;
create policy likes_insert on public.user_likes for insert to authenticated
  with check (liker_id = auth.uid());
drop policy if exists likes_delete on public.user_likes;
create policy likes_delete on public.user_likes for delete to authenticated
  using (liker_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════
-- 0004_phase4_posts.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — Phase 4: Posts, media, comments, post-likes
-- Run after 0003. Adds posts / post_comments / post_likes, a public "media"
-- Storage bucket, RLS (posts are Main-gated), and helper is_main().
-- See apps/maintrix/BACKEND.md.

-- ───────────────────────── membership helper ──────────────────
create or replace function public.is_main()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select tier = 'main' from public.profiles where id = auth.uid()), false);
$$;

-- ───────────────────────── posts ──────────────────────────────
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  author_id  uuid references public.profiles(id) on delete cascade,
  body       text not null default '',
  media_kind text not null default 'text' check (media_kind in ('text','image','video')),
  media_path text,
  color      text,
  created_at timestamptz not null default now()
);
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists posts_author_idx  on public.posts (author_id);

-- ───────────────────────── comments ───────────────────────────
create table if not exists public.post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid references public.posts(id) on delete cascade,
  author_id  uuid references public.profiles(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);
create index if not exists post_comments_post_idx on public.post_comments (post_id, created_at);

-- ───────────────────────── post likes ─────────────────────────
create table if not exists public.post_likes (
  post_id    uuid references public.posts(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists post_likes_post_idx on public.post_likes (post_id);

-- ───────────────────────── RLS ────────────────────────────────
alter table public.posts         enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_likes    enable row level security;

-- posts: Main can read & create; author or admin can delete
drop policy if exists posts_read on public.posts;
create policy posts_read on public.posts for select to authenticated using (public.is_main());
drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated
  with check (author_id = auth.uid() and public.is_main());
drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- comments: Main can read & create; author or admin can delete
drop policy if exists pc_read on public.post_comments;
create policy pc_read on public.post_comments for select to authenticated using (public.is_main());
drop policy if exists pc_insert on public.post_comments;
create policy pc_insert on public.post_comments for insert to authenticated
  with check (author_id = auth.uid() and public.is_main());
drop policy if exists pc_delete on public.post_comments;
create policy pc_delete on public.post_comments for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- post_likes: counts are public; you write only your own
drop policy if exists pl_read on public.post_likes;
create policy pl_read on public.post_likes for select to authenticated using (true);
drop policy if exists pl_insert on public.post_likes;
create policy pl_insert on public.post_likes for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists pl_delete on public.post_likes;
create policy pl_delete on public.post_likes for delete to authenticated
  using (user_id = auth.uid());

-- realtime for comments (nice-to-have live comments)
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.post_comments'; exception when duplicate_object then null; end;
end $$;

-- ───────────────────────── Storage (media bucket) ─────────────
insert into storage.buckets (id, name, public)
  values ('media', 'media', true)
on conflict (id) do nothing;

-- Public read; authenticated users may write/delete only inside their own
-- uid-named folder (path like "<uid>/<file>"). NOTE: files in a public bucket
-- are readable by URL — post *discovery* is still Main-gated by posts RLS.
drop policy if exists media_read on storage.objects;
create policy media_read on storage.objects for select
  using (bucket_id = 'media');
drop policy if exists media_insert on storage.objects;
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists media_delete on storage.objects;
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════════
-- 0005_tier_selfset.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0005: let members set their own tier (instant unlock)
-- Payments are deferred, so membership is still "instant unlock" in-app. The
-- 0001 identity trigger froze `tier`, which made is_main() always false and
-- blocked posting. Redefine the trigger to keep handle/traits/is_admin locked
-- but allow `tier` to change. Run after 0004.

create or replace function public.lock_identity()
returns trigger
language plpgsql
as $$
begin
  if old.handle is not null and new.handle is distinct from old.handle then
    raise exception 'handle is immutable';
  end if;
  if array_length(old.goals,1) is not null and new.goals is distinct from old.goals then
    raise exception 'goals are locked after signup';
  end if;
  if array_length(old.fears,1) is not null and new.fears is distinct from old.fears then
    raise exception 'fears are locked after signup';
  end if;
  -- is_admin is still server-controlled; tier is user-settable for now (no payments yet)
  new.is_admin := old.is_admin;
  return new;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- 0006_phase5_notifications.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — Phase 5: Notifications & moderation
-- Run after 0005. Adds a notifications table fed by triggers (mentions, replies,
-- post-likes, user-likes, comments, friend accepts), realtime on it, and a
-- moderation_actions audit table. Presence is client-only (Realtime Presence).
-- See apps/maintrix/BACKEND.md.

-- ───────────────────────── notifications ──────────────────────
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade, -- recipient
  type       text not null check (type in ('tag','reply','post_like','like','comment','friend_request','friend')),
  actor_id   uuid references public.profiles(id) on delete cascade,
  entity     jsonb not null default '{}',
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;
drop policy if exists notif_read on public.notifications;
create policy notif_read on public.notifications for select to authenticated
  using (user_id = auth.uid());
drop policy if exists notif_update on public.notifications;
create policy notif_update on public.notifications for update to authenticated
  using (user_id = auth.uid());
-- inserts happen only through security-definer triggers below (no client insert policy)

-- ───────────────────────── helper: fan out @mentions ──────────
create or replace function public.notify_mentions(actor uuid, ntype text, body text, entity jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare h text; uid uuid;
begin
  for h in select distinct lower((regexp_matches(body, '@([a-zA-Z0-9_]+)', 'g'))[1]) loop
    select id into uid from public.profiles where handle = h;
    if uid is not null and uid <> actor then
      insert into public.notifications(user_id, type, actor_id, entity) values (uid, ntype, actor, entity);
    end if;
  end loop;
end; $$;

-- ───────────────────────── message triggers ───────────────────
create or replace function public.on_message_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare orig uuid;
begin
  if new.is_system then return new; end if;
  perform public.notify_mentions(new.author_id, 'tag', new.body,
    jsonb_build_object('room_id', new.room_id, 'message_id', new.id));
  if new.reply_to is not null then
    select author_id into orig from public.messages where id = new.reply_to;
    if orig is not null and orig <> new.author_id then
      insert into public.notifications(user_id, type, actor_id, entity)
        values (orig, 'reply', new.author_id, jsonb_build_object('room_id', new.room_id, 'message_id', new.id));
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists trg_message_notify on public.messages;
create trigger trg_message_notify after insert on public.messages
  for each row execute function public.on_message_notify();

-- ───────────────────────── post-like trigger ──────────────────
create or replace function public.on_post_like_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare author uuid;
begin
  select author_id into author from public.posts where id = new.post_id;
  if author is not null and author <> new.user_id then
    insert into public.notifications(user_id, type, actor_id, entity)
      values (author, 'post_like', new.user_id, jsonb_build_object('post_id', new.post_id));
  end if;
  return new;
end; $$;

drop trigger if exists trg_post_like_notify on public.post_likes;
create trigger trg_post_like_notify after insert on public.post_likes
  for each row execute function public.on_post_like_notify();

-- ───────────────────────── user-like trigger ──────────────────
create or replace function public.on_user_like_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, type, actor_id)
    values (new.liked_id, 'like', new.liker_id);
  return new;
end; $$;

drop trigger if exists trg_user_like_notify on public.user_likes;
create trigger trg_user_like_notify after insert on public.user_likes
  for each row execute function public.on_user_like_notify();

-- ───────────────────────── comment trigger ────────────────────
create or replace function public.on_comment_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare author uuid;
begin
  select author_id into author from public.posts where id = new.post_id;
  if author is not null and author <> new.author_id then
    insert into public.notifications(user_id, type, actor_id, entity)
      values (author, 'comment', new.author_id, jsonb_build_object('post_id', new.post_id));
  end if;
  perform public.notify_mentions(new.author_id, 'tag', new.body,
    jsonb_build_object('post_id', new.post_id));
  return new;
end; $$;

drop trigger if exists trg_comment_notify on public.post_comments;
create trigger trg_comment_notify after insert on public.post_comments
  for each row execute function public.on_comment_notify();

-- ───────────────────────── friend triggers ────────────────────
create or replace function public.on_friend_request_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications(user_id, type, actor_id)
      values (new.to_id, 'friend_request', new.from_id);
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status <> 'accepted' then
    insert into public.notifications(user_id, type, actor_id)
      values (new.from_id, 'friend', new.to_id);
  end if;
  return new;
end; $$;

drop trigger if exists trg_friend_req_notify on public.friend_requests;
create trigger trg_friend_req_notify after insert or update on public.friend_requests
  for each row execute function public.on_friend_request_notify();

-- ───────────────────────── moderation audit ───────────────────
create table if not exists public.moderation_actions (
  id         uuid primary key default gen_random_uuid(),
  admin_id   uuid references public.profiles(id) on delete set null,
  action     text not null,
  target_type text,
  target_id  text,
  created_at timestamptz not null default now()
);
alter table public.moderation_actions enable row level security;
drop policy if exists mod_read on public.moderation_actions;
create policy mod_read on public.moderation_actions for select to authenticated
  using (public.is_admin());
drop policy if exists mod_insert on public.moderation_actions;
create policy mod_insert on public.moderation_actions for insert to authenticated
  with check (public.is_admin() and admin_id = auth.uid());

-- ───────────────────────── Realtime ───────────────────────────
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.notifications'; exception when duplicate_object then null; end;
end $$;

-- ───────────────────────── grant founder admin ────────────────
-- is_admin is server-controlled (locked by the identity trigger). Grant it by
-- temporarily disabling that trigger. Edit the handle to your own account.
alter table public.profiles disable trigger trg_lock_identity;
update public.profiles set is_admin = true where handle = 'alex76';
alter table public.profiles enable trigger trg_lock_identity;

-- ═══════════════════════════════════════════════════════════════════════
-- 0007_feature_batch.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0007: feature batch
-- Everyone is Main for now; servers require membership to post (view still open
-- for public); messages can carry media; posts get hashtags; badges. Run after 0006.

-- ── 18: everyone Main (membership hidden for now) ──────────────
alter table public.profiles alter column tier set default 'main';
update public.profiles set tier = 'main' where tier <> 'main';

-- ── 14/15: media on messages (image / video / audio) ──────────
alter table public.messages add column if not exists media_path text;
alter table public.messages add column if not exists media_kind text;

-- 15: allow audio posts too
alter table public.posts drop constraint if exists posts_media_kind_check;
alter table public.posts add constraint posts_media_kind_check
  check (media_kind in ('text','image','video','audio'));

-- ── 12: servers require membership to post (viewing stays open) ─
create or replace function public.room_kind(room uuid)
returns text language sql stable security definer set search_path = public as $$
  select kind from public.rooms where id = room;
$$;

drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.room_readable(room_id)
    and (public.room_kind(room_id) is distinct from 'dm' or public.can_post_dm(room_id))
    and (public.room_kind(room_id) is distinct from 'server' or public.is_member(room_id) or public.is_admin())
  );

-- ── 2/7: hashtags on posts ─────────────────────────────────────
create table if not exists public.post_hashtags (
  post_id uuid references public.posts(id) on delete cascade,
  tag     text,
  primary key (post_id, tag)
);
create index if not exists post_hashtags_tag_idx on public.post_hashtags (tag);

create or replace function public.extract_hashtags()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.post_hashtags where post_id = new.id;
  insert into public.post_hashtags (post_id, tag)
    select distinct new.id, lower((regexp_matches(new.body, '#([a-zA-Z0-9_]+)', 'g'))[1])
  on conflict do nothing;
  return new;
end; $$;

drop trigger if exists trg_extract_hashtags on public.posts;
create trigger trg_extract_hashtags after insert or update of body on public.posts
  for each row execute function public.extract_hashtags();

alter table public.post_hashtags enable row level security;
drop policy if exists ph_read on public.post_hashtags;
create policy ph_read on public.post_hashtags for select to authenticated using (true);

-- ── 19: badges ─────────────────────────────────────────────────
create table if not exists public.badges (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.profiles(id) on delete cascade,
  label      text not null,
  icon       text,
  color      text,
  awarded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists badges_user_idx on public.badges (user_id);

alter table public.badges enable row level security;
drop policy if exists badges_read on public.badges;
create policy badges_read on public.badges for select to authenticated using (true);
drop policy if exists badges_insert on public.badges;
create policy badges_insert on public.badges for insert to authenticated
  with check (public.is_admin() and awarded_by = auth.uid());
drop policy if exists badges_delete on public.badges;
create policy badges_delete on public.badges for delete to authenticated
  using (public.is_admin());

-- ═══════════════════════════════════════════════════════════════════════
-- 0008_traits_reactions.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0008: new traits, avatars, comment threads+hearts, reactions
-- Run after 0007.

-- ── new archetypal traits (old ones kept so existing rows stay valid) ──
insert into public.traits (value, kind) values
  ('Value','goal'),('Stability','goal'),
  ('Chaos','fear'),('Boredom','fear'),('Incompetence','fear')
on conflict (value) do nothing;
-- (Freedom already a goal; Mediocrity, Rejection already fears)

-- seed a global nexus room for every goal trait (Your World / trait nexuses)
insert into public.rooms (kind, slug, title, trait, scope)
  select 'trait', 'trait:'||value, value, value, 'global' from public.traits where kind='goal'
on conflict (slug) do nothing;

-- ── profile picture ──
alter table public.profiles add column if not exists avatar_path text;

-- ── comment threading + hearts ──
alter table public.post_comments add column if not exists parent_id uuid
  references public.post_comments(id) on delete cascade;

create table if not exists public.comment_likes (
  comment_id uuid references public.post_comments(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create index if not exists comment_likes_c_idx on public.comment_likes (comment_id);
alter table public.comment_likes enable row level security;
drop policy if exists cl_read on public.comment_likes;
create policy cl_read on public.comment_likes for select to authenticated using (true);
drop policy if exists cl_insert on public.comment_likes;
create policy cl_insert on public.comment_likes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists cl_delete on public.comment_likes;
create policy cl_delete on public.comment_likes for delete to authenticated using (user_id = auth.uid());

-- ── message emoji reactions ──
create table if not exists public.message_reactions (
  message_id uuid references public.messages(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);
create index if not exists message_reactions_m_idx on public.message_reactions (message_id);
alter table public.message_reactions enable row level security;
drop policy if exists mr_read on public.message_reactions;
create policy mr_read on public.message_reactions for select to authenticated using (true);
drop policy if exists mr_insert on public.message_reactions;
create policy mr_insert on public.message_reactions for insert to authenticated with check (user_id = auth.uid());
drop policy if exists mr_delete on public.message_reactions;
create policy mr_delete on public.message_reactions for delete to authenticated using (user_id = auth.uid());

do $$
begin
  begin execute 'alter publication supabase_realtime add table public.message_reactions'; exception when duplicate_object then null; end;
end $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 0009_post_caption.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0009: post captions
-- Run after 0008. Adds a `caption` column used as the picture-card text for
-- text-only posts, decoupled from the freeform body. Previously the feed just
-- sliced the first ~44 chars of `body` for the card, which cut off mid-word and
-- looked odd. The composer now requires a caption for every new post; existing
-- rows keep working via their old sliced-body fallback in the front end since
-- `caption` is nullable and untouched here.

alter table public.posts add column if not exists caption text;

-- ═══════════════════════════════════════════════════════════════════════
-- 0010_mbti.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0010: MBTI type
-- Run after 0009. Unlike goals/fears, mbti is NOT locked by trg_lock_identity —
-- members can change it anytime from their profile (pick directly or via the
-- in-app mini test). Nullable: most existing rows won't have one yet.

alter table public.profiles add column if not exists mbti text;
alter table public.profiles
  drop constraint if exists profiles_mbti_valid;
alter table public.profiles
  add constraint profiles_mbti_valid
  check (mbti is null or mbti ~ '^[EI][SN][TF][JP]$');

-- ═══════════════════════════════════════════════════════════════════════
-- 0011_enneagram_temperament.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0011: Enneagram (Core+Wing, Tritype) + Four Temperaments
-- Run after 0010. All fields editable anytime (not in trg_lock_identity), and
-- "Unsure" is now a valid value for mbti too, since signup offers it directly.

alter table public.profiles add column if not exists enneagram_core text;
alter table public.profiles add column if not exists enneagram_wing text;
alter table public.profiles add column if not exists enneagram_tritype text;
alter table public.profiles add column if not exists temperament_dominant text;
alter table public.profiles add column if not exists temperament_secondary text;

alter table public.profiles drop constraint if exists profiles_mbti_valid;
alter table public.profiles add constraint profiles_mbti_valid
  check (mbti is null or mbti = 'Unsure' or mbti ~ '^[EI][SN][TF][JP]$');

alter table public.profiles drop constraint if exists profiles_enneagram_core_valid;
alter table public.profiles add constraint profiles_enneagram_core_valid
  check (enneagram_core is null or enneagram_core = 'Unsure' or enneagram_core ~ '^[1-9]$');

alter table public.profiles drop constraint if exists profiles_enneagram_wing_valid;
alter table public.profiles add constraint profiles_enneagram_wing_valid
  check (enneagram_wing is null or enneagram_wing ~ '^[1-9]$');

alter table public.profiles drop constraint if exists profiles_enneagram_tritype_valid;
alter table public.profiles add constraint profiles_enneagram_tritype_valid
  check (enneagram_tritype is null or enneagram_tritype ~ '^[1-9]-[1-9]-[1-9]$');

alter table public.profiles drop constraint if exists profiles_temperament_dominant_valid;
alter table public.profiles add constraint profiles_temperament_dominant_valid
  check (temperament_dominant is null or temperament_dominant in ('Unsure','Sanguine','Choleric','Melancholic','Phlegmatic'));

alter table public.profiles drop constraint if exists profiles_temperament_secondary_valid;
alter table public.profiles add constraint profiles_temperament_secondary_valid
  check (temperament_secondary is null or temperament_secondary in ('Sanguine','Choleric','Melancholic','Phlegmatic'));

-- ═══════════════════════════════════════════════════════════════════════
-- 0012_qol_batch.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0012: QOL / customization / settings / features batch
-- Run after 0011. Adds: profile status line + banner, DM privacy, location
-- visibility, blocks, per-room notification mutes, polls, saved posts, and
-- scheduled events. See apps/maintrix/CLAUDE.md v0.10 note for the front-end
-- side of each.

-- ───────────────────────── profiles: new columns ──────────────
alter table public.profiles add column if not exists status_line text;
alter table public.profiles add column if not exists banner_path text;
alter table public.profiles add column if not exists dm_privacy text not null default 'everyone';
alter table public.profiles add column if not exists loc_visibility text not null default 'exact';

alter table public.profiles drop constraint if exists profiles_status_line_len;
alter table public.profiles add constraint profiles_status_line_len check (status_line is null or char_length(status_line) <= 60);
alter table public.profiles drop constraint if exists profiles_dm_privacy_valid;
alter table public.profiles add constraint profiles_dm_privacy_valid check (dm_privacy in ('everyone','friends','none'));
alter table public.profiles drop constraint if exists profiles_loc_visibility_valid;
alter table public.profiles add constraint profiles_loc_visibility_valid check (loc_visibility in ('exact','country','hidden'));

-- ───────────────────────── blocks ──────────────────────────────
create table if not exists public.blocks (
  blocker_id uuid references public.profiles(id) on delete cascade,
  blocked_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
alter table public.blocks enable row level security;
drop policy if exists blocks_read on public.blocks;
create policy blocks_read on public.blocks for select to authenticated using (blocker_id = auth.uid());
drop policy if exists blocks_insert on public.blocks;
create policy blocks_insert on public.blocks for insert to authenticated with check (blocker_id = auth.uid());
drop policy if exists blocks_delete on public.blocks;
create policy blocks_delete on public.blocks for delete to authenticated using (blocker_id = auth.uid());

create or replace function public.is_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.blocks where blocker_id = a and blocked_id = b);
$$;
grant execute on function public.is_blocked(uuid, uuid) to authenticated;

-- DM privacy + blocks now gate DM initiation (friends always allowed unless privacy='none')
create or replace function public.can_post_dm(room uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare meid uuid := auth.uid(); other uuid; privacy text;
begin
  select user_id into other from public.room_members where room_id = room and user_id <> meid limit 1;
  if other is null then return true; end if;
  if public.is_blocked(meid, other) or public.is_blocked(other, meid) then return false; end if;
  select coalesce(dm_privacy,'everyone') into privacy from public.profiles where id = other;
  if privacy = 'none' then return false; end if;
  if public.are_friends(meid, other) then return true; end if;
  if privacy = 'friends' then return false; end if;
  if exists (select 1 from public.dm_requests where status='accepted'
             and ((from_id=meid and to_id=other) or (from_id=other and to_id=meid))) then return true; end if;
  if exists (select 1 from public.dm_requests where status='denied'
             and ((from_id=meid and to_id=other) or (from_id=other and to_id=meid))) then return false; end if;
  return (select count(*) from public.messages where room_id = room and author_id = meid) = 0;
end; $$;

-- can't friend-request someone who's blocked you (or you've blocked)
drop policy if exists freq_insert on public.friend_requests;
create policy freq_insert on public.friend_requests for insert to authenticated
  with check (from_id = auth.uid() and not public.is_blocked(to_id, from_id) and not public.is_blocked(from_id, to_id));

-- ───────────────────────── per-room notification mutes ────────
create table if not exists public.room_mutes (
  user_id uuid references public.profiles(id) on delete cascade,
  room_id uuid references public.rooms(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, room_id)
);
alter table public.room_mutes enable row level security;
drop policy if exists rmute_read on public.room_mutes;
create policy rmute_read on public.room_mutes for select to authenticated using (user_id = auth.uid());
drop policy if exists rmute_insert on public.room_mutes;
create policy rmute_insert on public.room_mutes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists rmute_delete on public.room_mutes;
create policy rmute_delete on public.room_mutes for delete to authenticated using (user_id = auth.uid());

-- muted rooms no longer fan out @mention / reply notifications for the muter
create or replace function public.notify_mentions(actor uuid, ntype text, body text, entity jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare h text; uid uuid; rid uuid;
begin
  rid := nullif(entity->>'room_id','')::uuid;
  for h in select distinct lower((regexp_matches(body, '@([a-zA-Z0-9_]+)', 'g'))[1]) loop
    select id into uid from public.profiles where handle = h;
    if uid is not null and uid <> actor
       and (rid is null or not exists (select 1 from public.room_mutes where user_id = uid and room_id = rid)) then
      insert into public.notifications(user_id, type, actor_id, entity) values (uid, ntype, actor, entity);
    end if;
  end loop;
end; $$;

create or replace function public.on_message_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare orig uuid;
begin
  if new.is_system then return new; end if;
  perform public.notify_mentions(new.author_id, 'tag', new.body,
    jsonb_build_object('room_id', new.room_id, 'message_id', new.id));
  if new.reply_to is not null then
    select author_id into orig from public.messages where id = new.reply_to;
    if orig is not null and orig <> new.author_id
       and not exists (select 1 from public.room_mutes where user_id = orig and room_id = new.room_id) then
      insert into public.notifications(user_id, type, actor_id, entity)
        values (orig, 'reply', new.author_id, jsonb_build_object('room_id', new.room_id, 'message_id', new.id));
    end if;
  end if;
  return new;
end; $$;

-- ───────────────────────── polls ───────────────────────────────
create table if not exists public.polls (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.rooms(id) on delete cascade,
  author_id  uuid references public.profiles(id) on delete set null,
  question   text not null,
  options    jsonb not null, -- ["Option A","Option B",...]
  created_at timestamptz not null default now()
);
alter table public.messages add column if not exists poll_id uuid references public.polls(id) on delete set null;

create table if not exists public.poll_votes (
  poll_id    uuid references public.polls(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  option_idx int not null,
  created_at timestamptz not null default now(),
  primary key (poll_id, user_id)
);
alter table public.polls      enable row level security;
alter table public.poll_votes enable row level security;
drop policy if exists polls_read on public.polls;
create policy polls_read on public.polls for select to authenticated using (public.room_readable(room_id));
drop policy if exists polls_insert on public.polls;
create policy polls_insert on public.polls for insert to authenticated
  with check (author_id = auth.uid() and public.room_readable(room_id));
drop policy if exists pv_read on public.poll_votes;
create policy pv_read on public.poll_votes for select to authenticated
  using (exists (select 1 from public.polls p where p.id = poll_id and public.room_readable(p.room_id)));
drop policy if exists pv_upsert on public.poll_votes;
create policy pv_upsert on public.poll_votes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists pv_update on public.poll_votes;
create policy pv_update on public.poll_votes for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists pv_delete on public.poll_votes;
create policy pv_delete on public.poll_votes for delete to authenticated using (user_id = auth.uid());

do $$
begin
  begin execute 'alter publication supabase_realtime add table public.poll_votes'; exception when duplicate_object then null; end;
end $$;

-- ───────────────────────── saved posts ─────────────────────────
create table if not exists public.saved_posts (
  post_id    uuid references public.posts(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.saved_posts enable row level security;
drop policy if exists sp_read on public.saved_posts;
create policy sp_read on public.saved_posts for select to authenticated using (user_id = auth.uid());
drop policy if exists sp_insert on public.saved_posts;
create policy sp_insert on public.saved_posts for insert to authenticated with check (user_id = auth.uid());
drop policy if exists sp_delete on public.saved_posts;
create policy sp_delete on public.saved_posts for delete to authenticated using (user_id = auth.uid());

-- ───────────────────────── scheduled events ────────────────────
create table if not exists public.events (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.rooms(id) on delete cascade,
  title      text not null,
  starts_at  timestamptz not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.event_rsvps (
  event_id   uuid references public.events(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
alter table public.events      enable row level security;
alter table public.event_rsvps enable row level security;
drop policy if exists ev_read on public.events;
create policy ev_read on public.events for select to authenticated using (public.room_readable(room_id));
drop policy if exists ev_insert on public.events;
create policy ev_insert on public.events for insert to authenticated
  with check (created_by = auth.uid() and public.room_readable(room_id));
drop policy if exists ev_delete on public.events;
create policy ev_delete on public.events for delete to authenticated
  using (created_by = auth.uid() or public.is_admin());
drop policy if exists evr_read on public.event_rsvps;
create policy evr_read on public.event_rsvps for select to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and public.room_readable(e.room_id)));
drop policy if exists evr_insert on public.event_rsvps;
create policy evr_insert on public.event_rsvps for insert to authenticated with check (user_id = auth.uid());
drop policy if exists evr_delete on public.event_rsvps;
create policy evr_delete on public.event_rsvps for delete to authenticated using (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════
-- 0013_debates_admin_awake.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0013: Debates tab, expanded admin powers, official servers
-- Run after 0012.

-- bans: read-only for the banned user (can still read rooms, can't post/join).
-- Added here, ahead of the debates section below, because msg_insert (which
-- references this column) gets recreated before the "expanded admin powers"
-- section further down would otherwise add it — running this migration fresh
-- errors on "column banned does not exist" without this being first.
alter table public.profiles add column if not exists banned boolean not null default false;

-- ═══════════════════════ Debates ═══════════════════════
-- A debate is a 1-on-1 room (kind='debate', publicly readable so anyone can
-- spectate) that only the two debaters may post into. Spectators vote for
-- whoever they think is winning; the creator (or an admin) can end it anytime.
-- Winner = most votes; equal votes (including 0-0) is a tie (winner_id null).

create table if not exists public.debates (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms(id) on delete cascade,
  title       text not null,
  description text not null,
  creator_id  uuid references public.profiles(id) on delete set null,
  opponent_id uuid references public.profiles(id) on delete set null,
  status      text not null default 'open' check (status in ('open','active','ended')),
  winner_id   uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  ended_at    timestamptz,
  check (opponent_id is null or opponent_id <> creator_id)
);
create index if not exists debates_status_idx on public.debates (status, created_at desc);

create table if not exists public.debate_votes (
  debate_id  uuid references public.debates(id) on delete cascade,
  voter_id   uuid references public.profiles(id) on delete cascade,
  vote_for   uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (debate_id, voter_id)
);

-- 'debate' rooms are readable by everyone (spectating is the point); only the
-- two debaters may post — enforced via is_debate_participant() in msg_insert.
create or replace function public.room_readable(room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.rooms r
    where r.id = room and (
      r.kind in ('world','trait','topic','training','acolyte','commons','debate')
      or (r.kind = 'server' and r.is_public)
      or public.is_member(room)
      or public.is_admin()
    )
  );
$$;

create or replace function public.is_debate_participant(room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.debates d where d.room_id = room and (d.creator_id = auth.uid() or d.opponent_id = auth.uid()));
$$;

drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.room_readable(room_id)
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'dm' or public.can_post_dm(room_id) )
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'debate' or public.is_debate_participant(room_id) )
    and not coalesce((select banned from public.profiles where id = auth.uid()), false)
  );

alter table public.rooms drop constraint if exists rooms_kind_check;
alter table public.rooms add constraint rooms_kind_check check (kind in
  ('world','trait','topic','server','dm','live','training','acolyte','commons','admin','debate'));

create or replace function public.create_debate(p_title text, p_desc text)
returns uuid language plpgsql security definer set search_path = public as $$
declare r_id uuid; d_id uuid;
begin
  insert into public.rooms(kind,title,is_public,owner_id) values ('debate', p_title, true, auth.uid()) returning id into r_id;
  insert into public.room_members(room_id,user_id,rank) values (r_id, auth.uid(), 'Owner');
  insert into public.debates(room_id,title,description,creator_id,status) values (r_id, p_title, p_desc, auth.uid(), 'open') returning id into d_id;
  return d_id;
end; $$;

create or replace function public.join_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.status <> 'open' or d.opponent_id is not null then raise exception 'this debate already has an opponent'; end if;
  if d.creator_id = auth.uid() then raise exception 'you can’t join your own debate'; end if;
  update public.debates set opponent_id = auth.uid(), status = 'active' where id = d_id;
  insert into public.room_members(room_id,user_id) values (d.room_id, auth.uid()) on conflict do nothing;
end; $$;

create or replace function public.end_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d record; c int; o int;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.creator_id <> auth.uid() and not public.is_admin() then raise exception 'only the creator or an admin can end this debate'; end if;
  if d.status = 'ended' then return; end if;
  select count(*) into c from public.debate_votes where debate_id = d_id and vote_for = d.creator_id;
  select count(*) into o from public.debate_votes where debate_id = d_id and d.opponent_id is not null and vote_for = d.opponent_id;
  update public.debates set status = 'ended', ended_at = now(),
    winner_id = case when c > o then d.creator_id when o > c then d.opponent_id else null end
    where id = d_id;
end; $$;

create or replace function public.vote_debate(d_id uuid, for_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.debates where id = d_id;
  if d is null then raise exception 'debate not found'; end if;
  if d.status <> 'active' then raise exception 'this debate isn’t open for voting'; end if;
  if auth.uid() = d.creator_id or auth.uid() = d.opponent_id then raise exception 'debaters can’t vote on their own debate'; end if;
  if for_user <> d.creator_id and for_user <> d.opponent_id then raise exception 'invalid vote target'; end if;
  insert into public.debate_votes(debate_id,voter_id,vote_for) values (d_id, auth.uid(), for_user)
    on conflict (debate_id,voter_id) do update set vote_for = excluded.vote_for, created_at = now();
end; $$;

grant execute on function public.create_debate(text,text) to authenticated;
grant execute on function public.join_debate(uuid) to authenticated;
grant execute on function public.end_debate(uuid) to authenticated;
grant execute on function public.vote_debate(uuid,uuid) to authenticated;

alter table public.debates      enable row level security;
alter table public.debate_votes enable row level security;
drop policy if exists debates_read on public.debates;
create policy debates_read on public.debates for select to authenticated using (true);
drop policy if exists dv_read on public.debate_votes;
create policy dv_read on public.debate_votes for select to authenticated using (true);
-- all writes to debates/debate_votes go through the security-definer RPCs above

do $$
begin
  begin execute 'alter publication supabase_realtime add table public.debates'; exception when duplicate_object then null; end;
  begin execute 'alter publication supabase_realtime add table public.debate_votes'; exception when duplicate_object then null; end;
end $$;

-- ═══════════════════════ Expanded admin powers ═══════════════════════
-- (profiles.banned was already added near the top of this file, ahead of
-- the debates section, since msg_insert below needs it to exist first)

-- allow admins to change is_admin/tier/banned on ANY profile (previously fully
-- locked); everyone else keeps the old locked behavior.
create or replace function public.lock_identity()
returns trigger language plpgsql as $$
begin
  if old.handle is not null and new.handle is distinct from old.handle then
    raise exception 'handle is immutable';
  end if;
  if array_length(old.goals,1) is not null and new.goals is distinct from old.goals then
    raise exception 'goals are locked after signup';
  end if;
  if array_length(old.fears,1) is not null and new.fears is distinct from old.fears then
    raise exception 'fears are locked after signup';
  end if;
  if not public.is_admin() then
    new.tier := old.tier;
    new.is_admin := old.is_admin;
    new.banned := old.banned;
  end if;
  return new;
end;
$$;

create or replace function public.admin_set_admin(target uuid, val boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles set is_admin = val where id = target;
end; $$;

create or replace function public.admin_set_tier(target uuid, val text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  if val not in ('lite','main') then raise exception 'invalid tier'; end if;
  update public.profiles set tier = val where id = target;
end; $$;

create or replace function public.admin_set_banned(target uuid, val boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  if target = auth.uid() then raise exception 'you can’t ban yourself'; end if;
  update public.profiles set banned = val where id = target;
end; $$;

create or replace function public.admin_set_server_official(target_room uuid, val boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.rooms set is_official = val where id = target_room and kind = 'server';
end; $$;

create or replace function public.admin_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  select jsonb_build_object(
    'members', (select count(*) from public.profiles),
    'main_members', (select count(*) from public.profiles where tier = 'main'),
    'banned', (select count(*) from public.profiles where banned),
    'messages', (select count(*) from public.messages),
    'posts', (select count(*) from public.posts),
    'servers', (select count(*) from public.rooms where kind = 'server'),
    'debates_active', (select count(*) from public.debates where status = 'active'),
    'debates_total', (select count(*) from public.debates)
  ) into result;
  return result;
end; $$;

grant execute on function public.admin_set_admin(uuid,boolean) to authenticated;
grant execute on function public.admin_set_tier(uuid,text) to authenticated;
grant execute on function public.admin_set_banned(uuid,boolean) to authenticated;
grant execute on function public.admin_set_server_official(uuid,boolean) to authenticated;
grant execute on function public.admin_stats() to authenticated;

-- room_members insert: banned users can't join new rooms/servers
drop policy if exists rm_join on public.room_members;
create policy rm_join on public.room_members for insert to authenticated
  with check ((user_id = auth.uid() and not coalesce((select banned from public.profiles where id = auth.uid()), false)) or public.is_admin());

-- grant admin to "ret" — adjust the handle below if it doesn't match exactly
update public.profiles set is_admin = true where handle = 'ret';

-- ═══════════════════════ Official servers + themes ═══════════════════════
alter table public.rooms add column if not exists is_official boolean not null default false;
alter table public.rooms add column if not exists theme text;
alter table public.rooms drop constraint if exists rooms_theme_valid;
alter table public.rooms add constraint rooms_theme_valid check (theme is null or theme in ('mono'));

-- seed the official "Awake" server — the only server with the black/white
-- typewriter ("mono") theme.
insert into public.rooms (kind, title, category, is_public, is_official, theme, meta)
select 'server', 'Awake', 'Philosophy', true, true, 'mono', jsonb_build_object('bio','Stay awake. No noise, no color — just the words.','icon','A')
where not exists (select 1 from public.rooms where kind='server' and title='Awake');

-- ═══════════════════════════════════════════════════════════════════════
-- 0014_debate_elo.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0014: Debate ELO / ranks
-- Run after 0013. Winning a debate raises your ELO (K=64, tuned high so ranks
-- move fast — this is a fun gamification layer, not a competitive ladder);
-- losing lowers it by the same amount (zero-sum); a tie nudges both toward
-- the midpoint. Rank names/thresholds live client-side (DEBATE_RANKS in
-- index.html) purely off this number.

alter table public.profiles add column if not exists elo integer not null default 1000;
alter table public.profiles add column if not exists debate_wins integer not null default 0;
alter table public.profiles add column if not exists debate_losses integer not null default 0;
alter table public.profiles add column if not exists debate_ties integer not null default 0;
alter table public.debates add column if not exists elo_delta integer;

create or replace function public.end_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d record; c int; o int;
  celo int; oelo int; expected_c numeric; k constant numeric := 64; delta int;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.creator_id <> auth.uid() and not public.is_admin() then raise exception 'only the creator or an admin can end this debate'; end if;
  if d.status = 'ended' then return; end if;

  select count(*) into c from public.debate_votes where debate_id = d_id and vote_for = d.creator_id;
  select count(*) into o from public.debate_votes where debate_id = d_id and d.opponent_id is not null and vote_for = d.opponent_id;

  if d.opponent_id is not null then
    select elo into celo from public.profiles where id = d.creator_id;
    select elo into oelo from public.profiles where id = d.opponent_id;
    celo := coalesce(celo,1000); oelo := coalesce(oelo,1000);
    expected_c := 1.0 / (1.0 + power(10, (oelo - celo) / 400.0));
    delta := round(k * ((case when c > o then 1.0 when o > c then 0.0 else 0.5 end) - expected_c));

    update public.profiles set
      elo = elo + delta,
      debate_wins   = debate_wins   + (case when c > o then 1 else 0 end),
      debate_losses = debate_losses + (case when o > c then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.creator_id;

    update public.profiles set
      elo = elo - delta,
      debate_wins   = debate_wins   + (case when o > c then 1 else 0 end),
      debate_losses = debate_losses + (case when c > o then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.opponent_id;
  end if;

  update public.debates set status = 'ended', ended_at = now(),
    winner_id = case when c > o then d.creator_id when o > c then d.opponent_id else null end,
    elo_delta = abs(delta)
    where id = d_id;
end; $$;

-- ═══════════════════════════════════════════════════════════════════════
-- 0015_voice_streaks_badges_maintenance.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0015: voice channels, DM notifications, streaks, badge
-- auto-awards, maintenance banner, admin debate deletion, admin grants.
-- Run after 0014.

-- ═══════════════════════ Voice channels (member-creatable, per server) ═══
create table if not exists public.voice_channels (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.rooms(id) on delete cascade,
  name       text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.voice_channels enable row level security;
drop policy if exists vc_read on public.voice_channels;
create policy vc_read on public.voice_channels for select to authenticated
  using (public.room_readable(room_id));
drop policy if exists vc_insert on public.voice_channels;
create policy vc_insert on public.voice_channels for insert to authenticated
  with check (created_by = auth.uid() and (public.is_member(room_id) or public.is_admin()));
drop policy if exists vc_delete on public.voice_channels;
create policy vc_delete on public.voice_channels for delete to authenticated
  using (created_by = auth.uid() or public.is_admin());

-- ═══════════════════════ DM notifications ═══════════════════════════════
-- Every new DM message now notifies the recipient (unless the room is
-- muted) — "dmed you!" or "sent you a picture/video!" client-side, based on
-- media_kind carried in the notification entity. Regular @mention/reply
-- notifications still apply to every other room kind; DMs skip that path
-- since a 1:1 tag/reply notification would just be redundant noise.
create or replace function public.on_message_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare orig uuid; rkind text; other uuid;
begin
  if new.is_system then return new; end if;
  select kind into rkind from public.rooms where id = new.room_id;
  if rkind = 'dm' then
    select user_id into other from public.room_members where room_id = new.room_id and user_id <> new.author_id limit 1;
    if other is not null and not exists (select 1 from public.room_mutes where user_id = other and room_id = new.room_id) then
      insert into public.notifications(user_id, type, actor_id, entity)
        values (other, 'dm', new.author_id, jsonb_build_object('room_id', new.room_id, 'message_id', new.id, 'media_kind', new.media_kind));
    end if;
    return new;
  end if;
  perform public.notify_mentions(new.author_id, 'tag', new.body,
    jsonb_build_object('room_id', new.room_id, 'message_id', new.id));
  if new.reply_to is not null then
    select author_id into orig from public.messages where id = new.reply_to;
    if orig is not null and orig <> new.author_id
       and not exists (select 1 from public.room_mutes where user_id = orig and room_id = new.room_id) then
      insert into public.notifications(user_id, type, actor_id, entity)
        values (orig, 'reply', new.author_id, jsonb_build_object('room_id', new.room_id, 'message_id', new.id));
    end if;
  end if;
  return new;
end; $$;

-- ═══════════════════════ Messaging streaks ═══════════════════════════════
-- A simple per-user daily streak (not per-conversation): sending any message
-- on a new calendar day (UTC) continues your streak; missing a day resets
-- it to 1. Tracked on profiles so it's cheap to read everywhere.
alter table public.profiles add column if not exists streak_count integer not null default 0;
alter table public.profiles add column if not exists streak_last_date date;

create or replace function public.bump_streak()
returns trigger language plpgsql security definer set search_path = public as $$
declare last date; cnt int;
begin
  if new.is_system then return new; end if;
  select streak_last_date, streak_count into last, cnt from public.profiles where id = new.author_id;
  if last is null then cnt := 1;
  elsif last = current_date then return new; -- already counted today
  elsif last = current_date - 1 then cnt := coalesce(cnt,0) + 1;
  else cnt := 1;
  end if;
  update public.profiles set streak_count = cnt, streak_last_date = current_date where id = new.author_id;
  if cnt = 7 then perform public.award_badge_if_missing(new.author_id, 'Week Warrior', 'flame', '#f0663b'); end if;
  if cnt = 30 then perform public.award_badge_if_missing(new.author_id, 'Streak Legend', 'flame', '#ed2e44'); end if;
  return new;
end; $$;

drop trigger if exists trg_bump_streak on public.messages;
create trigger trg_bump_streak after insert on public.messages
  for each row execute function public.bump_streak();

-- ═══════════════════════ Badge auto-awards ═══════════════════════════════
-- badges.icon stores an icon KEY (matched against the client's IC map),
-- not a literal emoji — see index.html's BADGE_ICON_KEYS. Idempotent: never
-- awards the same label twice to the same person.
create or replace function public.award_badge_if_missing(p_uid uuid, p_label text, p_icon text, p_color text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.badges(user_id, label, icon, color, awarded_by)
    select p_uid, p_label, p_icon, p_color, p_uid
    where not exists (select 1 from public.badges where user_id = p_uid and label = p_label);
end; $$;

-- Founding Member — awarded at signup while the community is still small.
create or replace function public.award_founding_member()
returns trigger language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  select count(*) into cnt from public.profiles;
  if cnt <= 100 then
    perform public.award_badge_if_missing(new.id, 'Founding Member', 'sparkle', '#f0b232');
  end if;
  return new;
end; $$;
drop trigger if exists trg_founding_member on public.profiles;
create trigger trg_founding_member after insert on public.profiles
  for each row execute function public.award_founding_member();

-- First Words — your first message anywhere.
create or replace function public.award_first_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  if new.is_system then return new; end if;
  select count(*) into cnt from public.messages where author_id = new.author_id;
  if cnt = 1 then perform public.award_badge_if_missing(new.author_id, 'First Words', 'badge', '#4a9eff'); end if;
  return new;
end; $$;
drop trigger if exists trg_first_message on public.messages;
create trigger trg_first_message after insert on public.messages
  for each row execute function public.award_first_message();

-- First Post — your first post.
create or replace function public.award_first_post()
returns trigger language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  select count(*) into cnt from public.posts where author_id = new.author_id;
  if cnt = 1 then perform public.award_badge_if_missing(new.author_id, 'First Post', 'badge', '#3ba55d'); end if;
  return new;
end; $$;
drop trigger if exists trg_first_post on public.posts;
create trigger trg_first_post after insert on public.posts
  for each row execute function public.award_first_post();

-- Social Butterfly — 10 accepted friends.
create or replace function public.award_social_butterfly()
returns trigger language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  if new.status <> 'accepted' then return new; end if;
  select count(*) into cnt from public.friend_requests where status = 'accepted' and (from_id = new.from_id or to_id = new.from_id);
  if cnt >= 10 then perform public.award_badge_if_missing(new.from_id, 'Social Butterfly', 'handshake', '#a855f7'); end if;
  select count(*) into cnt from public.friend_requests where status = 'accepted' and (from_id = new.to_id or to_id = new.to_id);
  if cnt >= 10 then perform public.award_badge_if_missing(new.to_id, 'Social Butterfly', 'handshake', '#a855f7'); end if;
  return new;
end; $$;
drop trigger if exists trg_social_butterfly on public.friend_requests;
create trigger trg_social_butterfly after update on public.friend_requests
  for each row execute function public.award_social_butterfly();

-- Debate Debut / Debate Champion — hooked into end_debate (0014's version).
create or replace function public.end_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d record; c int; o int;
  celo int; oelo int; expected_c numeric; k constant numeric := 64; delta int;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.creator_id <> auth.uid() and not public.is_admin() then raise exception 'only the creator or an admin can end this debate'; end if;
  if d.status = 'ended' then return; end if;

  select count(*) into c from public.debate_votes where debate_id = d_id and vote_for = d.creator_id;
  select count(*) into o from public.debate_votes where debate_id = d_id and d.opponent_id is not null and vote_for = d.opponent_id;

  if d.opponent_id is not null then
    select elo into celo from public.profiles where id = d.creator_id;
    select elo into oelo from public.profiles where id = d.opponent_id;
    celo := coalesce(celo,1000); oelo := coalesce(oelo,1000);
    expected_c := 1.0 / (1.0 + power(10, (oelo - celo) / 400.0));
    delta := round(k * ((case when c > o then 1.0 when o > c then 0.0 else 0.5 end) - expected_c));

    update public.profiles set
      elo = elo + delta,
      debate_wins   = debate_wins   + (case when c > o then 1 else 0 end),
      debate_losses = debate_losses + (case when o > c then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.creator_id;

    update public.profiles set
      elo = elo - delta,
      debate_wins   = debate_wins   + (case when o > c then 1 else 0 end),
      debate_losses = debate_losses + (case when c > o then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.opponent_id;

    perform public.award_badge_if_missing(d.creator_id, 'Debate Debut', 'fist', '#4a9eff');
    perform public.award_badge_if_missing(d.opponent_id, 'Debate Debut', 'fist', '#4a9eff');
    if (select debate_wins from public.profiles where id = d.creator_id) >= 10 then
      perform public.award_badge_if_missing(d.creator_id, 'Debate Champion', 'trophy', '#f0b232');
    end if;
    if (select debate_wins from public.profiles where id = d.opponent_id) >= 10 then
      perform public.award_badge_if_missing(d.opponent_id, 'Debate Champion', 'trophy', '#f0b232');
    end if;
  end if;

  update public.debates set status = 'ended', ended_at = now(),
    winner_id = case when c > o then d.creator_id when o > c then d.opponent_id else null end,
    elo_delta = abs(delta)
    where id = d_id;
end; $$;

-- Admin can delete any debate outright (room cascade removes its messages).
create or replace function public.admin_delete_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  select room_id into rid from public.debates where id = d_id;
  delete from public.debates where id = d_id;
  if rid is not null then delete from public.rooms where id = rid; end if;
end; $$;
grant execute on function public.admin_delete_debate(uuid) to authenticated;

-- ═══════════════════════ Maintenance banner ═══════════════════════════════
create table if not exists public.app_config (
  id                    int primary key default 1,
  maintenance_enabled   boolean not null default false,
  maintenance_title     text,
  maintenance_details   text,
  updated_at            timestamptz not null default now(),
  check (id = 1)
);
insert into public.app_config (id) values (1) on conflict (id) do nothing;
alter table public.app_config enable row level security;
drop policy if exists app_config_read on public.app_config;
create policy app_config_read on public.app_config for select to authenticated using (true);
-- also readable anonymously so a logged-out visitor sees maintenance state
drop policy if exists app_config_read_anon on public.app_config;
create policy app_config_read_anon on public.app_config for select to anon using (true);

create or replace function public.admin_set_maintenance(enabled boolean, title text, details text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.app_config set maintenance_enabled = enabled, maintenance_title = title, maintenance_details = details, updated_at = now() where id = 1;
end; $$;
grant execute on function public.admin_set_maintenance(boolean,text,text) to authenticated;

-- ═══════════════════════ Admin grants ═══════════════════════════════════
update public.profiles set is_admin = true where handle in ('ret','5');

-- ═══════════════════════════════════════════════════════════════════════
-- 0016_dm_conversations_auto_admin.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0016: DM "message requests" only for strangers, and a
-- standing (not one-time) admin auto-grant for specific handles.
-- Run after 0015.

-- ═══════════════════════ DM gating: only for people you've never talked to ═
-- can_post_dm previously only ever let friends or already-accepted requests
-- through; a message from the OTHER person in the room (i.e. an ongoing,
-- two-way conversation) didn't count for anything, so tightening your
-- dm_privacy setting mid-conversation — or just never having formally
-- "accepted" — could still gate someone you'd already been talking to.
-- Message requests are for strangers who've never exchanged a message; once
-- there's a reply from the other side, the conversation is never gated
-- again, regardless of privacy setting or a stale request status.
create or replace function public.can_post_dm(room uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare meid uuid := auth.uid(); other uuid; privacy text;
begin
  select user_id into other from public.room_members where room_id = room and user_id <> meid limit 1;
  if other is null then return true; end if;
  if public.is_blocked(meid, other) or public.is_blocked(other, meid) then return false; end if;
  if exists (select 1 from public.messages where room_id = room and author_id = other) then return true; end if;
  select coalesce(dm_privacy,'everyone') into privacy from public.profiles where id = other;
  if privacy = 'none' then return false; end if;
  if public.are_friends(meid, other) then return true; end if;
  if privacy = 'friends' then return false; end if;
  if exists (select 1 from public.dm_requests where status='accepted'
             and ((from_id=meid and to_id=other) or (from_id=other and to_id=meid))) then return true; end if;
  if exists (select 1 from public.dm_requests where status='denied'
             and ((from_id=meid and to_id=other) or (from_id=other and to_id=meid))) then return false; end if;
  return (select count(*) from public.messages where room_id = room and author_id = meid) = 0;
end; $$;

-- ═══════════════════════ Standing admin auto-grant ═══════════════════════
-- The one-off `update ... where handle in ('ret','5')` in migration 0013/0015
-- only affects rows that already exist at the moment it runs — as of this
-- writing, production has zero signups at all (auth.users is empty), so it
-- did nothing and was never going to until an account with that exact
-- handle existed. This makes the grant a standing rule instead.
--
-- This can't be a separate trigger on profiles: the handle is actually set
-- via UPDATE during signup (db.profiles.create does an UPDATE against the
-- stub row handle_new_user() already inserted on auth signup, not an
-- INSERT), and lock_identity() already runs BEFORE UPDATE on this table,
-- resetting is_admin back to old.is_admin whenever the acting user isn't
-- already an admin — which they never are yet, mid-signup. A same-event
-- second trigger just introduces alphabetical-firing-order fragility to
-- fight that. Simplest and least fragile: teach lock_identity() itself
-- about these two handles, since it's already the one place with authority
-- over is_admin.
create or replace function public.lock_identity()
returns trigger language plpgsql as $$
begin
  if old.handle is not null and new.handle is distinct from old.handle then
    raise exception 'handle is immutable';
  end if;
  if array_length(old.goals,1) is not null and new.goals is distinct from old.goals then
    raise exception 'goals are locked after signup';
  end if;
  if array_length(old.fears,1) is not null and new.fears is distinct from old.fears then
    raise exception 'fears are locked after signup';
  end if;
  if new.handle in ('ret','5') then
    new.is_admin := true;
  elsif not public.is_admin() then
    new.tier := old.tier;
    new.is_admin := old.is_admin;
    new.banned := old.banned;
  end if;
  return new;
end;
$$;

-- catch anyone who already exists under those handles too (idempotent no-op
-- today, since production has no signups yet)
update public.profiles set is_admin = true where handle in ('ret','5');

-- ═══════════════════════════════════════════════════════════════════════
-- 0017_banner_style.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0017: profile banner style
-- Run after 0016. Backs the new "Profile banner style" picker in Appearance
-- (diagonal/radial/vertical/sunburst gradient treatments built from the
-- user's own color) — needs to be a real column, not local client state,
-- since it's about how a profile looks to OTHER people viewing it.

alter table public.profiles add column if not exists banner_style text;
alter table public.profiles drop constraint if exists profiles_banner_style_valid;
alter table public.profiles add constraint profiles_banner_style_valid
  check (banner_style is null or banner_style in ('diagonal','radial','vertical','sunburst'));

-- ═══════════════════════════════════════════════════════════════════════
-- 0018_read_receipts.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0018: read receipts (DMs)
-- Backs the "seen" avatar shown under the last message a DM partner has
-- actually read. Run after 0017.

create table if not exists public.room_reads (
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
alter table public.room_reads enable row level security;

-- any member of the room can see everyone's read marker in it (that's the
-- whole point of a receipt — the other person needs to see yours)
drop policy if exists rreads_select on public.room_reads;
create policy rreads_select on public.room_reads for select to authenticated
  using (exists (select 1 from public.room_members where room_id = room_reads.room_id and user_id = auth.uid()));

drop policy if exists rreads_insert on public.room_reads;
create policy rreads_insert on public.room_reads for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists rreads_update on public.room_reads;
create policy rreads_update on public.room_reads for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════
-- 0019_admin_reset_debate_leaderboard.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0019: admin reset of the debate leaderboard
-- Run after 0018. Backs the "Reset debate leaderboard" button in
-- Overwatch → Tools. Wipes every member's ELO back to 1000 and zeroes
-- their win/loss/tie counters. Finished debates themselves are kept
-- (history stays readable); only the standings reset.

create or replace function public.admin_reset_debate_leaderboard()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles
     set elo = 1000, debate_wins = 0, debate_losses = 0, debate_ties = 0
   where elo <> 1000 or debate_wins <> 0 or debate_losses <> 0 or debate_ties <> 0;
  get diagnostics n = row_count;
  return n;
end; $$;
grant execute on function public.admin_reset_debate_leaderboard() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 0020_push_notifications.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0020: Web Push notifications
-- Run after 0019.
--
-- How a push happens:
--   any INSERT into public.notifications
--     → trg_notify_push (below) checks the recipient's notif_prefs and whether
--       they have any push_subscriptions, builds title/body/url, and fires a
--       pg_net POST at the send-push Edge Function
--     → send-push loads that user's subscriptions and delivers via the Web
--       Push protocol (VAPID), pruning endpoints that come back 404/410.
--
-- Secrets are NOT in this file. They live in Supabase Vault under the names
-- push_secret / vapid_public / vapid_private (create them once with
-- vault.create_secret(...) in the SQL editor). The trigger reads push_secret
-- to authenticate to the function; the function reads all three through the
-- service-role-only RPC push_secrets(). If the secrets are missing the trigger
-- silently skips — a missing push must never break the underlying insert.

-- ═══════════════════════ notification types ═══════════════════════════════
-- 0006's check list was never widened when 0015 started inserting 'dm'; this
-- recreates it with every type the app now produces.
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('tag','reply','post_like','like','comment','friend_request','friend','dm',
                  'debate_join','debate_end','badge','server_join'));

-- ═══════════════════════ subscriptions + prefs ════════════════════════════
create table if not exists public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;
drop policy if exists push_select on public.push_subscriptions;
create policy push_select on public.push_subscriptions for select to authenticated using (user_id = auth.uid());
drop policy if exists push_insert on public.push_subscriptions;
create policy push_insert on public.push_subscriptions for insert to authenticated with check (user_id = auth.uid());
drop policy if exists push_update on public.push_subscriptions;
create policy push_update on public.push_subscriptions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists push_delete on public.push_subscriptions;
create policy push_delete on public.push_subscriptions for delete to authenticated using (user_id = auth.uid());

-- per-user switches: {"push":true,"dms":true,"mentions":true,"replies":true,
-- "likes":true,"comments":true,"friends":true,"debates":true,"badges":true,
-- "servers":true} — a missing key means true.
alter table public.profiles add column if not exists notif_prefs jsonb not null default '{}'::jsonb;

-- ═══════════════════════ secrets plumbing ═════════════════════════════════
create extension if not exists pg_net;

-- service-role only: the Edge Function calls this to get its keys instead of
-- needing them pasted into function secrets.
create or replace function public.push_secrets()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(name, decrypted_secret), '{}'::jsonb)
    from vault.decrypted_secrets
   where name in ('push_secret','vapid_public','vapid_private');
$$;
revoke all on function public.push_secrets() from public;
revoke all on function public.push_secrets() from anon;
revoke all on function public.push_secrets() from authenticated;
grant execute on function public.push_secrets() to service_role;

-- ═══════════════════════ the trigger ══════════════════════════════════════
create or replace function public.notify_push()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  prefs jsonb; pref_key text; secret text; actor_name text;
  title text; body text; url text; tag text; mk text; preview text;
begin
  pref_key := case new.type
    when 'dm' then 'dms'
    when 'tag' then 'mentions'
    when 'reply' then 'replies'
    when 'post_like' then 'likes'
    when 'like' then 'likes'
    when 'comment' then 'comments'
    when 'friend_request' then 'friends'
    when 'friend' then 'friends'
    when 'debate_join' then 'debates'
    when 'debate_end' then 'debates'
    when 'badge' then 'badges'
    when 'server_join' then 'servers'
    else 'other' end;

  select notif_prefs into prefs from public.profiles where id = new.user_id;
  if coalesce((prefs->>'push')::boolean, true) = false then return new; end if;
  if coalesce((prefs->>pref_key)::boolean, true) = false then return new; end if;
  if not exists (select 1 from public.push_subscriptions where user_id = new.user_id) then return new; end if;

  begin
    select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_secret' limit 1;
  exception when others then secret := null; end;
  if secret is null then return new; end if;

  select coalesce(nullif(name,''), '@' || handle, 'Someone') into actor_name from public.profiles where id = new.actor_id;
  actor_name := coalesce(actor_name, 'Someone');
  mk := new.entity->>'media_kind';
  preview := nullif(left(coalesce(new.entity->>'preview',''), 140), '');

  title := case new.type
    when 'dm' then actor_name
    when 'tag' then actor_name || ' mentioned you'
    when 'reply' then actor_name || ' replied to you'
    when 'post_like' then actor_name || ' liked your post'
    when 'like' then actor_name || ' liked you'
    when 'comment' then actor_name || ' commented on your post'
    when 'friend_request' then actor_name || ' sent a friend request'
    when 'friend' then actor_name || ' accepted your request'
    when 'debate_join' then actor_name || ' joined your debate'
    when 'debate_end' then 'Debate over'
    when 'badge' then 'New badge unlocked'
    when 'server_join' then actor_name || ' joined your server'
    else 'Maintrix' end;

  body := case new.type
    when 'dm' then case mk when 'image' then 'Sent you a picture' when 'video' then 'Sent you a video' when 'audio' then 'Sent you a voice note' else coalesce(preview, 'Sent you a message') end
    when 'tag' then coalesce(preview, 'Tap to see where')
    when 'reply' then coalesce(preview, 'Tap to see the reply')
    when 'comment' then coalesce(preview, 'Tap to read it')
    when 'friend_request' then 'Accept or deny in Connect'
    when 'friend' then 'You are now friends'
    when 'debate_join' then coalesce(new.entity->>'title', 'The debate is on')
    when 'debate_end' then coalesce(new.entity->>'summary', 'See how it ended')
    when 'badge' then coalesce(new.entity->>'label', 'You earned a badge')
    when 'server_join' then coalesce(new.entity->>'title', 'Say hi')
    else 'Tap to open' end;

  url := case
    when new.entity ? 'post_id' then '?post=' || (new.entity->>'post_id')
    when new.entity ? 'room_id' then '?room=' || (new.entity->>'room_id')
    else '?notifs=1' end;
  -- same-room pushes collapse into one notification on the device
  tag := case when new.entity ? 'room_id' then 'room-' || (new.entity->>'room_id') else new.type || '-' || new.id::text end;

  perform net.http_post(
    url := 'https://uwvgfxnwtgnwcwostwxs.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('user_id', new.user_id, 'title', title, 'body', body, 'url', url, 'tag', tag, 'type', new.type),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', secret),
    timeout_milliseconds := 4000
  );
  return new;
exception when others then
  return new;   -- a push failure must never roll back the notification (or the message that caused it)
end; $$;

drop trigger if exists trg_notify_push on public.notifications;
create trigger trg_notify_push after insert on public.notifications
  for each row execute function public.notify_push();

-- ═══════════════════════ message previews in DM / reply / mention notifs ══
-- Same as 0015's version plus a `preview` (first 140 chars of the message) in
-- entity so the push body can show what was said.
create or replace function public.on_message_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare orig uuid; rkind text; other uuid; prev text;
begin
  if new.is_system then return new; end if;
  prev := left(coalesce(new.body,''), 140);
  select kind into rkind from public.rooms where id = new.room_id;
  if rkind = 'dm' then
    select user_id into other from public.room_members where room_id = new.room_id and user_id <> new.author_id limit 1;
    if other is not null and not exists (select 1 from public.room_mutes where user_id = other and room_id = new.room_id) then
      insert into public.notifications(user_id, type, actor_id, entity)
        values (other, 'dm', new.author_id, jsonb_build_object('room_id', new.room_id, 'message_id', new.id, 'media_kind', new.media_kind, 'preview', prev));
    end if;
    return new;
  end if;
  perform public.notify_mentions(new.author_id, 'tag', new.body,
    jsonb_build_object('room_id', new.room_id, 'message_id', new.id, 'preview', prev));
  if new.reply_to is not null then
    select author_id into orig from public.messages where id = new.reply_to;
    if orig is not null and orig <> new.author_id
       and not exists (select 1 from public.room_mutes where user_id = orig and room_id = new.room_id) then
      insert into public.notifications(user_id, type, actor_id, entity)
        values (orig, 'reply', new.author_id, jsonb_build_object('room_id', new.room_id, 'message_id', new.id, 'preview', prev));
    end if;
  end if;
  return new;
end; $$;

-- ═══════════════════════ new producers ════════════════════════════════════
-- opponent joined your debate
create or replace function public.join_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.status <> 'open' or d.opponent_id is not null then raise exception 'this debate already has an opponent'; end if;
  if d.creator_id = auth.uid() then raise exception 'you can’t join your own debate'; end if;
  update public.debates set opponent_id = auth.uid(), status = 'active' where id = d_id;
  insert into public.room_members(room_id,user_id) values (d.room_id, auth.uid()) on conflict do nothing;
  insert into public.notifications(user_id, type, actor_id, entity)
    values (d.creator_id, 'debate_join', auth.uid(), jsonb_build_object('room_id', d.room_id, 'debate_id', d.id, 'title', d.title));
end; $$;

-- debate ended → both debaters get a result push (0015's end_debate + notifications)
create or replace function public.end_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d record; c int; o int;
  celo int; oelo int; expected_c numeric; k constant numeric := 64; delta int := 0;
  c_summary text; o_summary text;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.creator_id <> auth.uid() and not public.is_admin() then raise exception 'only the creator or an admin can end this debate'; end if;
  if d.status = 'ended' then return; end if;

  select count(*) into c from public.debate_votes where debate_id = d_id and vote_for = d.creator_id;
  select count(*) into o from public.debate_votes where debate_id = d_id and d.opponent_id is not null and vote_for = d.opponent_id;

  if d.opponent_id is not null then
    select elo into celo from public.profiles where id = d.creator_id;
    select elo into oelo from public.profiles where id = d.opponent_id;
    celo := coalesce(celo,1000); oelo := coalesce(oelo,1000);
    expected_c := 1.0 / (1.0 + power(10, (oelo - celo) / 400.0));
    delta := round(k * ((case when c > o then 1.0 when o > c then 0.0 else 0.5 end) - expected_c));

    update public.profiles set
      elo = elo + delta,
      debate_wins   = debate_wins   + (case when c > o then 1 else 0 end),
      debate_losses = debate_losses + (case when o > c then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.creator_id;

    update public.profiles set
      elo = elo - delta,
      debate_wins   = debate_wins   + (case when o > c then 1 else 0 end),
      debate_losses = debate_losses + (case when c > o then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.opponent_id;

    perform public.award_badge_if_missing(d.creator_id, 'Debate Debut', 'fist', '#4a9eff');
    perform public.award_badge_if_missing(d.opponent_id, 'Debate Debut', 'fist', '#4a9eff');
    if (select debate_wins from public.profiles where id = d.creator_id) >= 10 then
      perform public.award_badge_if_missing(d.creator_id, 'Debate Champion', 'trophy', '#f0b232');
    end if;
    if (select debate_wins from public.profiles where id = d.opponent_id) >= 10 then
      perform public.award_badge_if_missing(d.opponent_id, 'Debate Champion', 'trophy', '#f0b232');
    end if;

    c_summary := case when c > o then 'You won “' || d.title || '” · +' || delta || ' ELO'
                      when o > c then 'You lost “' || d.title || '” · ' || delta || ' ELO'
                      else 'Tie on “' || d.title || '” · ' || (case when delta >= 0 then '+' else '' end) || delta || ' ELO' end;
    o_summary := case when o > c then 'You won “' || d.title || '” · +' || (-delta) || ' ELO'
                      when c > o then 'You lost “' || d.title || '” · ' || (-delta) || ' ELO'
                      else 'Tie on “' || d.title || '” · ' || (case when -delta >= 0 then '+' else '' end) || (-delta) || ' ELO' end;
    insert into public.notifications(user_id, type, actor_id, entity) values
      (d.creator_id,  'debate_end', auth.uid(), jsonb_build_object('room_id', d.room_id, 'debate_id', d.id, 'summary', c_summary)),
      (d.opponent_id, 'debate_end', auth.uid(), jsonb_build_object('room_id', d.room_id, 'debate_id', d.id, 'summary', o_summary));
  end if;

  update public.debates set status = 'ended', ended_at = now(),
    winner_id = case when c > o then d.creator_id when o > c then d.opponent_id else null end,
    elo_delta = abs(delta)
    where id = d_id;
end; $$;

-- any badge (auto-awarded or admin-given) → tell the person
create or replace function public.on_badge_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, type, actor_id, entity)
    values (new.user_id, 'badge', coalesce(new.awarded_by, new.user_id), jsonb_build_object('badge_id', new.id, 'label', new.label));
  return new;
end; $$;
drop trigger if exists trg_badge_notify on public.badges;
create trigger trg_badge_notify after insert on public.badges
  for each row execute function public.on_badge_notify();

-- someone joined a server you own
create or replace function public.on_server_join_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select kind, owner_id, title into r from public.rooms where id = new.room_id;
  if r.kind = 'server' and r.owner_id is not null and r.owner_id <> new.user_id then
    insert into public.notifications(user_id, type, actor_id, entity)
      values (r.owner_id, 'server_join', new.user_id, jsonb_build_object('room_id', new.room_id, 'title', r.title));
  end if;
  return new;
end; $$;
drop trigger if exists trg_server_join_notify on public.room_members;
create trigger trg_server_join_notify after insert on public.room_members
  for each row execute function public.on_server_join_notify();

-- ═══════════════════════════════════════════════════════════════════════
-- 0021_admin_moderation.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0021: more admin moderation powers
-- Run after 0020. Backs the admin right-click / long-press user menu and the
-- expanded "Manage a member" panel in Overwatch → Tools.

-- ═══════════════════════ timed mute ═══════════════════════════════════════
-- Softer than a ban: can still read everything, can't post until the time
-- passes. Enforced in msg_insert alongside the existing banned check.
alter table public.profiles add column if not exists muted_until timestamptz;

create or replace function public.is_muted(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select muted_until > now() from public.profiles where id = uid), false);
$$;

drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.room_readable(room_id)
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'dm' or public.can_post_dm(room_id) )
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'debate' or public.is_debate_participant(room_id) )
    and not coalesce((select banned from public.profiles where id = auth.uid()), false)
    and not public.is_muted(auth.uid())
  );

create or replace function public.admin_set_muted(target uuid, until_ts timestamptz)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles set muted_until = until_ts where id = target;
end; $$;
grant execute on function public.admin_set_muted(uuid, timestamptz) to authenticated;

-- ═══════════════════════ edit someone's profile ═══════════════════════════
-- name / bio / status_line / avatar_path / banner_path only — never handle,
-- goals, fears, tier, is_admin, banned (those have their own paths).
create or replace function public.admin_edit_profile(target uuid, patch jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles set
    name        = case when patch ? 'name'        then nullif(left(patch->>'name', 20), '') else name end,
    bio         = case when patch ? 'bio'         then coalesce(left(patch->>'bio', 300), 'Becoming.') else bio end,
    status_line = case when patch ? 'status_line' then nullif(left(patch->>'status_line', 60), '') else status_line end,
    avatar_path = case when patch ? 'avatar_path' then nullif(patch->>'avatar_path', '') else avatar_path end,
    banner_path = case when patch ? 'banner_path' then nullif(patch->>'banner_path', '') else banner_path end
  where id = target;
end; $$;
grant execute on function public.admin_edit_profile(uuid, jsonb) to authenticated;

-- ═══════════════════════ wipe a member's messages ═════════════════════════
create or replace function public.admin_delete_user_messages(target uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  delete from public.messages where author_id = target;
  get diagnostics n = row_count;
  return n;
end; $$;
grant execute on function public.admin_delete_user_messages(uuid) to authenticated;

-- ═══════════════════════ reset one member's debate standing ═══════════════
create or replace function public.admin_reset_user_elo(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles set elo = 1000, debate_wins = 0, debate_losses = 0, debate_ties = 0 where id = target;
end; $$;
grant execute on function public.admin_reset_user_elo(uuid) to authenticated;

-- ═══════════════════════ kick from a room ═════════════════════════════════
-- (room_members already lets admins delete any row; this just wraps it so the
-- client has one call that also refuses to kick the owner)
create or replace function public.admin_kick(target uuid, room uuid)
returns void language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  select owner_id into owner from public.rooms where id = room;
  if owner = target then raise exception 'cannot kick the owner'; end if;
  delete from public.room_members where room_id = room and user_id = target;
end; $$;
grant execute on function public.admin_kick(uuid, uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 0022_security_hardening.sql
-- ═══════════════════════════════════════════════════════════════════════
-- Maintrix backend — 0022: security hardening batch
-- Run after 0021.

-- ═══════════════════════ storage: size + mime enforcement ══════════════════
-- Bucket had no limits at all — any authenticated user could upload an
-- arbitrarily large file of any content type into their own folder. Cap size
-- and restrict to real media types (also blocks svg/html uploads into a
-- PUBLIC bucket, which could otherwise be used to host attacker HTML/SVG on
-- a supabase.co URL).
update storage.buckets set
  file_size_limit = 62914560, -- 60MB ceiling (video is the largest legit upload); client enforces tighter per-kind caps
  allowed_mime_types = array[
    'image/png','image/jpeg','image/webp','image/gif',
    'video/mp4','video/webm','video/quicktime',
    'audio/webm','audio/mpeg','audio/mp3','audio/wav','audio/ogg'
  ]
where id = 'media';

-- ═══════════════════════ server-side content length caps ═══════════════════
-- Client-side maxlength attributes are trivially bypassed by anyone calling
-- the REST API directly — none of these had a real ceiling, so an attacker
-- could insert megabyte-sized rows (storage bloat / rendering DoS). Mirrors
-- the pattern already used for profiles.status_line (0012).
alter table public.profiles drop constraint if exists profiles_name_len;
alter table public.profiles add constraint profiles_name_len check (name is null or char_length(name) <= 40);
alter table public.profiles drop constraint if exists profiles_bio_len;
alter table public.profiles add constraint profiles_bio_len check (bio is null or char_length(bio) <= 500);

alter table public.messages drop constraint if exists messages_body_len;
alter table public.messages add constraint messages_body_len check (char_length(body) <= 4000);

alter table public.posts drop constraint if exists posts_body_len;
alter table public.posts add constraint posts_body_len check (body is null or char_length(body) <= 3000);
alter table public.posts drop constraint if exists posts_caption_len;
alter table public.posts add constraint posts_caption_len check (caption is null or char_length(caption) <= 80);

alter table public.post_comments drop constraint if exists post_comments_body_len;
alter table public.post_comments add constraint post_comments_body_len check (char_length(body) <= 1000);

-- ═══════════════════════ rate limiting ══════════════════════════════════════
-- Generic sliding-window limiter. No client access — only trigger functions
-- (security definer) touch this table, so it can't be read or spoofed from
-- the client to defeat its own limits.
create table if not exists public.rate_limits (
  id         bigserial primary key,
  user_id    uuid not null,
  action     text not null,
  created_at timestamptz not null default now()
);
create index if not exists rate_limits_lookup_idx on public.rate_limits (user_id, action, created_at);
alter table public.rate_limits enable row level security;
-- deliberately no policies at all — RLS default-denies every client-side access;
-- only security-definer functions (which bypass RLS) ever touch this table.

create or replace function public.enforce_rate_limit(p_action text, p_max int, p_window interval)
returns void language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  if auth.uid() is null then return; end if;
  delete from public.rate_limits where created_at < now() - interval '1 day';
  select count(*) into cnt from public.rate_limits
    where user_id = auth.uid() and action = p_action and created_at > now() - p_window;
  if cnt >= p_max then
    raise exception 'rate_limited: too many % — slow down', p_action;
  end if;
  insert into public.rate_limits (user_id, action) values (auth.uid(), p_action);
end; $$;

create or replace function public.trg_rate_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.enforce_rate_limit(tg_argv[0], tg_argv[1]::int, tg_argv[2]::interval);
  return new;
end; $$;

drop trigger if exists rl_messages on public.messages;
create trigger rl_messages before insert on public.messages
  for each row execute function public.trg_rate_limit('message', 20, '10 seconds');

drop trigger if exists rl_posts on public.posts;
create trigger rl_posts before insert on public.posts
  for each row execute function public.trg_rate_limit('post', 5, '1 minute');

drop trigger if exists rl_comments on public.post_comments;
create trigger rl_comments before insert on public.post_comments
  for each row execute function public.trg_rate_limit('comment', 20, '1 minute');

drop trigger if exists rl_friend_requests on public.friend_requests;
create trigger rl_friend_requests before insert on public.friend_requests
  for each row execute function public.trg_rate_limit('friend_request', 20, '1 minute');

drop trigger if exists rl_dm_requests on public.dm_requests;
create trigger rl_dm_requests before insert on public.dm_requests
  for each row execute function public.trg_rate_limit('dm_request', 20, '1 minute');

-- ═══════════════════════ admin: delete an account outright ═════════════════
-- profiles.id -> auth.users(id) on delete cascade (0001), and every table
-- that references profiles was set up with its own on-delete behavior, so
-- deleting the auth.users row is the one real "delete this account" op —
-- everything downstream (profile, messages, posts, friendships, etc.)
-- cascades or nulls out from there. Requires the function owner to have
-- privileges on auth.users, same as every other security-definer function
-- in this schema already relies on for its own writes.
create or replace function public.admin_delete_account(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  delete from auth.users where id = target;
end; $$;
grant execute on function public.admin_delete_account(uuid) to authenticated;

