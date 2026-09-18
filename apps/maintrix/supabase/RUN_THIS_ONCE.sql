-- Maintrix — ONE-TIME CATCH-UP SCRIPT
-- ═══════════════════════════════════════════════════════════════
-- Migrations 0009 through 0018, concatenated in order. 0009-0017 have
-- already been run against production as of this writing; 0018 (read
-- receipts) is still pending. This file is idempotent, so running the
-- whole thing again is always safe.
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- migrations/0009_post_caption.sql
-- ═══════════════════════════════════════════════════════════════
-- Maintrix backend — 0009: post captions
-- Run after 0008. Adds a `caption` column used as the picture-card text for
-- text-only posts, decoupled from the freeform body. Previously the feed just
-- sliced the first ~44 chars of `body` for the card, which cut off mid-word and
-- looked odd. The composer now requires a caption for every new post; existing
-- rows keep working via their old sliced-body fallback in the front end since
-- `caption` is nullable and untouched here.

alter table public.posts add column if not exists caption text;

-- ═══════════════════════════════════════════════════════════════
-- migrations/0010_mbti.sql
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- migrations/0011_enneagram_temperament.sql
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- migrations/0012_qol_batch.sql
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- migrations/0013_debates_admin_awake.sql
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- migrations/0014_debate_elo.sql
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- migrations/0015_voice_streaks_badges_maintenance.sql
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- migrations/0016_dm_conversations_auto_admin.sql
-- ═══════════════════════════════════════════════════════════════
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

-- ═══════════════════════════════════════════════════════════════
-- migrations/0017_banner_style.sql
-- ═══════════════════════════════════════════════════════════════
-- Maintrix backend — 0017: profile banner style
-- Run after 0016. Backs the new "Profile banner style" picker in Appearance
-- (diagonal/radial/vertical/sunburst gradient treatments built from the
-- user's own color) — needs to be a real column, not local client state,
-- since it's about how a profile looks to OTHER people viewing it.

alter table public.profiles add column if not exists banner_style text;
alter table public.profiles drop constraint if exists profiles_banner_style_valid;
alter table public.profiles add constraint profiles_banner_style_valid
  check (banner_style is null or banner_style in ('diagonal','radial','vertical','sunburst'));

-- ═══════════════════════════════════════════════════════════════
-- migrations/0018_read_receipts.sql
-- ═══════════════════════════════════════════════════════════════
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

