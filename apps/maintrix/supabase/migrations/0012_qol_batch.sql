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
