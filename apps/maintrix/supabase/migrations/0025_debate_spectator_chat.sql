-- Maintrix backend — 0025: debate spectator chat + self-delete an unstarted debate
-- Run after 0024.

-- ═══════════════════════ spectator chat room ═══════════════════════════════
-- A second room per debate where the audience discusses who's winning —
-- readable by everyone (debaters included), but only spectators may post.
-- Kept as its own room/kind rather than reusing the debate room itself,
-- since that room's whole point is "only the two debaters can post" — this
-- is the exact opposite rule, so it needs its own space, not a toggle.
alter table public.debates add column if not exists chat_room_id uuid references public.rooms(id) on delete set null;

alter table public.rooms drop constraint if exists rooms_kind_check;
alter table public.rooms add constraint rooms_kind_check check (kind in
  ('world','trait','topic','server','dm','live','training','acolyte','commons','admin','debate','debate_chat'));

create or replace function public.room_readable(room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.rooms r
    where r.id = room and (
      r.kind in ('world','trait','topic','training','acolyte','commons','debate','debate_chat')
      or (r.kind = 'server' and r.is_public)
      or public.is_member(room)
      or public.is_admin()
    )
  );
$$;

-- The inverse of is_debate_participant(): true for anyone who is NOT one of
-- the two debaters on the debate this chat room belongs to (i.e. everyone
-- else — spectators don't need to have voted or joined anything first).
create or replace function public.can_post_debate_chat(room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from public.debates d
    where d.chat_room_id = room and (d.creator_id = auth.uid() or d.opponent_id = auth.uid())
  );
$$;

drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.room_readable(room_id)
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'dm' or public.can_post_dm(room_id) )
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'debate' or public.is_debate_participant(room_id) )
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'debate_chat' or public.can_post_debate_chat(room_id) )
    and not coalesce((select banned from public.profiles where id = auth.uid()), false)
    and not public.is_muted(auth.uid())
  );

create or replace function public.create_debate(p_title text, p_desc text)
returns uuid language plpgsql security definer set search_path = public as $$
declare r_id uuid; chat_id uuid; d_id uuid;
begin
  insert into public.rooms(kind,title,is_public,owner_id) values ('debate', p_title, true, auth.uid()) returning id into r_id;
  insert into public.room_members(room_id,user_id,rank) values (r_id, auth.uid(), 'Owner');
  insert into public.rooms(kind,title,is_public,owner_id) values ('debate_chat', p_title, true, auth.uid()) returning id into chat_id;
  insert into public.debates(room_id,title,description,creator_id,status,chat_room_id) values (r_id, p_title, p_desc, auth.uid(), 'open', chat_id) returning id into d_id;
  return d_id;
end; $$;

-- ═══════════════════════ self-delete an unstarted debate ═══════════════════
-- The creator can pull their own debate while it's still waiting for an
-- opponent (status='open') — once someone's joined, it's no longer just
-- theirs to remove; use admin_delete_debate for that instead.
create or replace function public.delete_own_open_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d record;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.creator_id <> auth.uid() then raise exception 'only the creator can delete this debate'; end if;
  if d.status <> 'open' then raise exception 'this debate has already started'; end if;
  delete from public.debates where id = d_id;
  delete from public.rooms where id = d.room_id;
  if d.chat_room_id is not null then delete from public.rooms where id = d.chat_room_id; end if;
end; $$;

grant execute on function public.delete_own_open_debate(uuid) to authenticated;
