-- Maintrix — second-pass fixes (2026-10-24). Applied live; kept here so a rebuild includes them.
-- Safe to re-run. (Written without DROP statements so it can run through the Supabase MCP.)

-- Profile setup: the app shows its setup questions while handle is empty
alter table profiles alter column handle drop not null;
-- (handle_new_user in schema.sql now leaves handle NULL)

-- Admin "award badge" sends a description
alter table badges add column if not exists description text;

-- DMs: slug dm:<uuid>:<uuid> (the DM list and "who is this DM with" read it),
-- DM privacy + blocks for new conversations, DM requests for non-friends
create or replace function public.get_or_create_dm(other uuid) returns uuid
language plpgsql security definer set search_path to 'public' as $$
declare me uuid := auth.uid(); r uuid; s text; priv text; fr boolean;
begin
  if me is null or other is null or other = me then raise exception 'not allowed'; end if;
  s := 'dm:' || least(me::text, other::text) || ':' || greatest(me::text, other::text);
  select id into r from rooms where slug = s;
  if r is null then
    select rm.room_id into r from room_members rm join rooms ro on ro.id = rm.room_id and ro.kind = 'dm'
    where rm.user_id in (me, other) group by rm.room_id having count(distinct rm.user_id) = 2 limit 1;
    if r is not null then update rooms set slug = s where id = r and slug is null; end if;
  end if;
  if r is not null then return r; end if;
  if exists (select 1 from blocks where (blocker_id = other and blocked_id = me) or (blocker_id = me and blocked_id = other)) then
    raise exception 'not allowed';
  end if;
  select coalesce(dm_privacy, 'everyone') into priv from profiles where id = other;
  if not found then raise exception 'not allowed'; end if;
  fr := exists (select 1 from friendships where (user_a = me and user_b = other) or (user_a = other and user_b = me));
  if not is_admin() then
    if priv = 'none' then raise exception 'This member doesn''t accept messages'; end if;
    if priv = 'friends' and not fr then raise exception 'This member doesn''t accept messages from non-friends'; end if;
  end if;
  insert into rooms (kind, is_public, title, slug) values ('dm', false, 'DM', s)
    on conflict (slug) do nothing returning id into r;
  if r is null then select id into r from rooms where slug = s; end if;
  insert into room_members (room_id, user_id) values (r, me), (r, other) on conflict do nothing;
  if not fr then
    insert into dm_requests (from_id, to_id, status) values (me, other, 'pending') on conflict (from_id, to_id) do nothing;
  end if;
  return r;
end $$;

create or replace function public.guard_dm_message() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare k text; other uuid;
begin
  select kind into k from rooms where id = new.room_id;
  if k is distinct from 'dm' then return new; end if;
  select user_id into other from room_members where room_id = new.room_id and user_id <> new.author_id limit 1;
  if other is null then return new; end if;
  if exists (select 1 from blocks where blocker_id = other and blocked_id = new.author_id) then
    raise exception 'not allowed';
  end if;
  if exists (select 1 from dm_requests where from_id = new.author_id and to_id = other and status = 'denied') then
    raise exception 'This member isn''t accepting your messages';
  end if;
  return new;
end $$;
create or replace trigger guard_dm_message before insert on messages for each row execute function guard_dm_message();

update rooms ro set slug = x.s
from (select rm.room_id, 'dm:' || min(rm.user_id::text) || ':' || max(rm.user_id::text) s
      from room_members rm join rooms r2 on r2.id = rm.room_id and r2.kind = 'dm'
      group by rm.room_id having count(distinct rm.user_id) = 2) x
where ro.id = x.room_id and ro.slug is null and not exists (select 1 from rooms o where o.slug = x.s);

-- Polls / events: everyone who can see the poll/event sees its votes/RSVPs
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='poll_votes' and policyname='poll_votes_read') then
    create policy poll_votes_read on poll_votes for select to authenticated
      using (exists (select 1 from polls p where p.id = poll_votes.poll_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='event_rsvps' and policyname='event_rsvps_read') then
    create policy event_rsvps_read on event_rsvps for select to authenticated
      using (exists (select 1 from events e where e.id = event_rsvps.event_id));
  end if;
end $$;

-- Uploads go only into your own {uid}/ folder (the client always uses that path)
alter policy maintrix_media_insert on storage.objects
  with check (bucket_id = any (array['media','attachments']) and (storage.foldername(name))[1] = (select auth.uid())::text);

-- @everyone from an admin/owner notifies the room's members
create or replace function public.trg_notify_everyone() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare t text;
begin
  if coalesce(new.is_system, false) or coalesce(new.body, '') !~* '(^|\s)@everyone([^a-z0-9_]|$)' then return null; end if;
  if not exists (select 1 from profiles where id = new.author_id and (is_admin or is_owner)) then return null; end if;
  select title into t from rooms where id = new.room_id;
  insert into notifications (user_id, type, kind, actor_id, entity, body)
  select rm.user_id, 'everyone', 'everyone', new.author_id,
         jsonb_build_object('room_id', new.room_id, 'title', t, 'preview', left(new.body, 120)), left(new.body, 120)
  from room_members rm
  where rm.room_id = new.room_id and rm.user_id <> new.author_id
    and not exists (select 1 from room_mutes mu where mu.room_id = new.room_id and mu.user_id = rm.user_id);
  return null;
end $$;
create or replace trigger notify_everyone after insert on messages for each row execute function trg_notify_everyone();

-- "Added you to <group>" notification
create or replace function public.trg_notify_group_added() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare r record; actor uuid := auth.uid();
begin
  select kind, title, owner_id into r from rooms where id = new.room_id;
  if r.kind is distinct from 'group' then return null; end if;
  if actor is null or actor = new.user_id then return null; end if;
  perform notify_user(new.user_id, 'dm', actor,
    jsonb_build_object('room_id', new.room_id, 'group', true, 'title', r.title,
                       'preview', 'Added you to ' || coalesce(r.title, 'a group')));
  return null;
end $$;
create or replace trigger notify_group_added after insert on room_members for each row execute function trg_notify_group_added();

-- Badge checks: throttle window 30s -> 5s (award_badges in phase2-features.sql; interval '5 seconds')
