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
