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
