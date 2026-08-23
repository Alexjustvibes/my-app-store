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
