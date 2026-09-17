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
