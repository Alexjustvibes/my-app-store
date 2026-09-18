-- Maintrix backend — 0021: more admin moderation powers
-- Run after 0020. Backs the admin right-click / long-press user menu and the
-- expanded "Manage a member" panel in Overwatch → Tools.

-- ═══════════════════════ timed mute ═══════════════════════════════════════
-- Softer than a ban: can still read everything, can't post until the time
-- passes. Enforced in msg_insert alongside the existing banned check.
alter table public.profiles add column if not exists muted_until timestamptz;

create or replace function public.is_muted(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select muted_until > now() from public.profiles where id = uid), false);
$$;

drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.room_readable(room_id)
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'dm' or public.can_post_dm(room_id) )
    and ( (select kind from public.rooms r where r.id = room_id) is distinct from 'debate' or public.is_debate_participant(room_id) )
    and not coalesce((select banned from public.profiles where id = auth.uid()), false)
    and not public.is_muted(auth.uid())
  );

create or replace function public.admin_set_muted(target uuid, until_ts timestamptz)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles set muted_until = until_ts where id = target;
end; $$;
grant execute on function public.admin_set_muted(uuid, timestamptz) to authenticated;

-- ═══════════════════════ edit someone's profile ═══════════════════════════
-- name / bio / status_line / avatar_path / banner_path only — never handle,
-- goals, fears, tier, is_admin, banned (those have their own paths).
create or replace function public.admin_edit_profile(target uuid, patch jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles set
    name        = case when patch ? 'name'        then nullif(left(patch->>'name', 20), '') else name end,
    bio         = case when patch ? 'bio'         then coalesce(left(patch->>'bio', 300), 'Becoming.') else bio end,
    status_line = case when patch ? 'status_line' then nullif(left(patch->>'status_line', 60), '') else status_line end,
    avatar_path = case when patch ? 'avatar_path' then nullif(patch->>'avatar_path', '') else avatar_path end,
    banner_path = case when patch ? 'banner_path' then nullif(patch->>'banner_path', '') else banner_path end
  where id = target;
end; $$;
grant execute on function public.admin_edit_profile(uuid, jsonb) to authenticated;

-- ═══════════════════════ wipe a member's messages ═════════════════════════
create or replace function public.admin_delete_user_messages(target uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  delete from public.messages where author_id = target;
  get diagnostics n = row_count;
  return n;
end; $$;
grant execute on function public.admin_delete_user_messages(uuid) to authenticated;

-- ═══════════════════════ reset one member's debate standing ═══════════════
create or replace function public.admin_reset_user_elo(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles set elo = 1000, debate_wins = 0, debate_losses = 0, debate_ties = 0 where id = target;
end; $$;
grant execute on function public.admin_reset_user_elo(uuid) to authenticated;

-- ═══════════════════════ kick from a room ═════════════════════════════════
-- (room_members already lets admins delete any row; this just wraps it so the
-- client has one call that also refuses to kick the owner)
create or replace function public.admin_kick(target uuid, room uuid)
returns void language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  select owner_id into owner from public.rooms where id = room;
  if owner = target then raise exception 'cannot kick the owner'; end if;
  delete from public.room_members where room_id = room and user_id = target;
end; $$;
grant execute on function public.admin_kick(uuid, uuid) to authenticated;
