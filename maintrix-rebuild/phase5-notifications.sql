-- Maintrix — notification batch (2026-10-25). Applied live; kept for rebuilds. Safe to re-run.

-- Everyone gets the Feed / posting (the Lite/Main split stays available to admins)
alter table profiles alter column tier set default 'main';
update profiles set tier = 'main' where tier is distinct from 'main';

-- likes / comments carry the post so tapping the notification opens it
create or replace function trg_notify_post_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare p record;
begin
  select author_id, body, caption into p from posts where id = new.post_id;
  perform notify_user(p.author_id, 'post_like', new.user_id,
    jsonb_build_object('post_id', new.post_id, 'preview', left(coalesce(nullif(p.caption, ''), p.body, ''), 100)));
  return new;
end $$;

create or replace function trg_notify_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare post_author uuid; parent_author uuid;
begin
  select author_id into post_author from posts where id = new.post_id;
  perform notify_user(post_author, 'comment', new.author_id, jsonb_build_object('post_id', new.post_id, 'preview', left(new.body, 100)));
  if new.parent_id is not null then
    select author_id into parent_author from post_comments where id = new.parent_id;
    if parent_author is distinct from post_author then
      perform notify_user(parent_author, 'reply', new.author_id, jsonb_build_object('post_id', new.post_id, 'preview', left(new.body, 100)));
    end if;
  end if;
  return new;
end $$;

-- new posts notify everyone else (toggle: notif_prefs.posts_new)
create or replace function trg_notify_post_new() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, type, kind, actor_id, entity, body)
  select p.id, 'post_new', 'post_new', new.author_id,
         jsonb_build_object('post_id', new.id, 'preview', left(coalesce(nullif(new.caption, ''), new.body, ''), 100)),
         left(coalesce(nullif(new.caption, ''), new.body, ''), 100)
  from profiles p
  where p.id <> new.author_id and p.handle is not null and not coalesce(p.banned, false)
    and coalesce(p.notif_prefs -> 'posts_new', 'true'::jsonb) <> 'false'::jsonb;
  return null;
end $$;
create or replace trigger notify_post_new after insert on posts for each row execute function trg_notify_post_new();

-- live debates / ranked matches: on by default (toggle: notif_prefs.debate_live)
create or replace function trg_notify_debate_live() returns trigger
language plpgsql security definer set search_path = public as $$
declare an text; bn text;
begin
  if new.status = 'active' and new.opponent_id is not null
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    select coalesce(name, handle::text) into an from profiles where id = new.creator_id;
    select coalesce(name, handle::text) into bn from profiles where id = new.opponent_id;
    insert into notifications (user_id, type, kind, actor_id, entity, body)
    select p.id, 'debate_live', 'debate_live', new.creator_id,
           jsonb_build_object('debate_id', new.id, 'room_id', new.room_id, 'title', new.title,
                              'ranked', coalesce(new.ranked, false), 'a', an, 'b', bn),
           left(coalesce(new.title, ''), 120)
    from profiles p
    where coalesce(p.notif_prefs -> 'debate_live', 'true'::jsonb) <> 'false'::jsonb
      and p.handle is not null
      and p.id is distinct from new.creator_id and p.id is distinct from new.opponent_id;
  end if;
  return null;
end $$;

-- voice chat started in the Nexus — called by the voice-token function, at most once per 20 min
-- (toggle: notif_prefs.voice)
create table if not exists vc_announcements (room_id uuid primary key, last_at timestamptz not null);
alter table vc_announcements enable row level security;
create or replace function announce_nexus_vc(p_uid uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r uuid; n int := 0;
begin
  select id into r from rooms where slug = 'world' limit 1;
  if r is null or p_uid is null then return 0; end if;
  if exists (select 1 from vc_announcements where room_id = r and last_at > now() - interval '20 minutes') then return 0; end if;
  insert into vc_announcements (room_id, last_at) values (r, now())
    on conflict (room_id) do update set last_at = now();
  insert into notifications (user_id, type, kind, actor_id, entity, body)
  select p.id, 'vc_start', 'vc_start', p_uid, jsonb_build_object('room_id', r, 'title', 'The Nexus'), 'Voice chat in the Nexus'
  from profiles p
  where p.id <> p_uid and p.handle is not null and not coalesce(p.banned, false)
    and coalesce(p.notif_prefs -> 'voice', 'true'::jsonb) <> 'false'::jsonb;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function announce_nexus_vc(uuid) from public, anon, authenticated;
grant execute on function announce_nexus_vc(uuid) to service_role;
