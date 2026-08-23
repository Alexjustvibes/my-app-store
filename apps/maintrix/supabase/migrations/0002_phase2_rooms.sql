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
