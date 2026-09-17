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
