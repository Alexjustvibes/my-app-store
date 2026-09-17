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
