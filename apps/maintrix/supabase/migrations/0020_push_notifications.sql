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
