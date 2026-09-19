-- Maintrix backend — 0023: DM chat streaks (Snapchat-style, per conversation pair)
-- Run after 0022.
--
-- This is intentionally separate from the existing per-user daily streak
-- (profiles.streak_count/streak_last_date, added in 0015) — that one tracks
-- "did you send any message anywhere today" per person. This one tracks
-- "did BOTH sides of a specific DM send a message today", per room, which is
-- the feature actually being asked for here (a flame next to a DM that only
-- keeps climbing while the conversation itself stays daily on both ends).

create table if not exists public.dm_streaks (
  room_id          uuid primary key references public.rooms(id) on delete cascade,
  user_a           uuid not null references public.profiles(id) on delete cascade,
  user_b           uuid not null references public.profiles(id) on delete cascade,
  streak_count     int not null default 0,
  last_streak_date date,
  a_sent_date      date,
  b_sent_date      date,
  updated_at       timestamptz not null default now(),
  check (user_a < user_b)
);
create index if not exists dm_streaks_users_idx on public.dm_streaks (user_a, user_b);
alter table public.dm_streaks enable row level security;

drop policy if exists dm_streaks_read on public.dm_streaks;
create policy dm_streaks_read on public.dm_streaks for select to authenticated
  using (user_a = auth.uid() or user_b = auth.uid());
-- deliberately no insert/update/delete policy — only the trigger below
-- (security definer, bypasses RLS) ever writes to this table.

create or replace function public.on_dm_message_streak()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  k text; other uuid; ua uuid; ub uuid; today date := current_date; y date := current_date - 1;
  rec public.dm_streaks;
begin
  select kind into k from public.rooms where id = new.room_id;
  if k is distinct from 'dm' then return new; end if;

  select user_id into other from public.room_members where room_id = new.room_id and user_id <> new.author_id limit 1;
  if other is null then return new; end if;

  ua := least(new.author_id, other);
  ub := greatest(new.author_id, other);

  insert into public.dm_streaks (room_id, user_a, user_b)
    values (new.room_id, ua, ub)
    on conflict (room_id) do nothing;

  select * into rec from public.dm_streaks where room_id = new.room_id for update;

  if new.author_id = ua then
    rec.a_sent_date := today;
  else
    rec.b_sent_date := today;
  end if;

  if rec.a_sent_date = today and rec.b_sent_date = today then
    if rec.last_streak_date is null or rec.last_streak_date < y then
      rec.streak_count := 1;
    elsif rec.last_streak_date = y then
      rec.streak_count := rec.streak_count + 1;
    end if; -- last_streak_date = today already: same-day second message, no change
    rec.last_streak_date := today;
  end if;

  update public.dm_streaks set
    a_sent_date      = rec.a_sent_date,
    b_sent_date      = rec.b_sent_date,
    streak_count     = rec.streak_count,
    last_streak_date = rec.last_streak_date,
    updated_at       = now()
  where room_id = new.room_id;

  return new;
end; $$;

drop trigger if exists trg_dm_message_streak on public.messages;
create trigger trg_dm_message_streak after insert on public.messages
  for each row execute function public.on_dm_message_streak();
