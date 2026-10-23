-- ============================================================================
-- Fix messaging in PUBLIC rooms (403 RLS). Run in the SQL Editor.
-- Before: posting/reading required room membership → public "world" chat was
-- blocked because users aren't members. Now: public rooms are open to any
-- signed-in user; private rooms (DMs, private servers) still require membership.
-- ============================================================================

-- READ: messages in public rooms, or rooms you're a member of
drop policy if exists msg_read on messages;
create policy msg_read on messages for select to authenticated
using (
  exists (select 1 from rooms r where r.id = room_id and (r.is_public or is_member(room_id)))
);

-- INSERT: post as yourself, in a public room or one you're a member of
drop policy if exists msg_insert on messages;
create policy msg_insert on messages for insert to authenticated
with check (
  author_id = auth.uid()
  and exists (select 1 from rooms r where r.id = room_id and (r.is_public or is_member(room_id)))
);

notify pgrst, 'reload schema';
