-- Maintrix backend — 0007: feature batch
-- Everyone is Main for now; servers require membership to post (view still open
-- for public); messages can carry media; posts get hashtags; badges. Run after 0006.

-- ── 18: everyone Main (membership hidden for now) ──────────────
alter table public.profiles alter column tier set default 'main';
update public.profiles set tier = 'main' where tier <> 'main';

-- ── 14/15: media on messages (image / video / audio) ──────────
alter table public.messages add column if not exists media_path text;
alter table public.messages add column if not exists media_kind text;

-- 15: allow audio posts too
alter table public.posts drop constraint if exists posts_media_kind_check;
alter table public.posts add constraint posts_media_kind_check
  check (media_kind in ('text','image','video','audio'));

-- ── 12: servers require membership to post (viewing stays open) ─
create or replace function public.room_kind(room uuid)
returns text language sql stable security definer set search_path = public as $$
  select kind from public.rooms where id = room;
$$;

drop policy if exists msg_insert on public.messages;
create policy msg_insert on public.messages for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.room_readable(room_id)
    and (public.room_kind(room_id) is distinct from 'dm' or public.can_post_dm(room_id))
    and (public.room_kind(room_id) is distinct from 'server' or public.is_member(room_id) or public.is_admin())
  );

-- ── 2/7: hashtags on posts ─────────────────────────────────────
create table if not exists public.post_hashtags (
  post_id uuid references public.posts(id) on delete cascade,
  tag     text,
  primary key (post_id, tag)
);
create index if not exists post_hashtags_tag_idx on public.post_hashtags (tag);

create or replace function public.extract_hashtags()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.post_hashtags where post_id = new.id;
  insert into public.post_hashtags (post_id, tag)
    select distinct new.id, lower((regexp_matches(new.body, '#([a-zA-Z0-9_]+)', 'g'))[1])
  on conflict do nothing;
  return new;
end; $$;

drop trigger if exists trg_extract_hashtags on public.posts;
create trigger trg_extract_hashtags after insert or update of body on public.posts
  for each row execute function public.extract_hashtags();

alter table public.post_hashtags enable row level security;
drop policy if exists ph_read on public.post_hashtags;
create policy ph_read on public.post_hashtags for select to authenticated using (true);

-- ── 19: badges ─────────────────────────────────────────────────
create table if not exists public.badges (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.profiles(id) on delete cascade,
  label      text not null,
  icon       text,
  color      text,
  awarded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists badges_user_idx on public.badges (user_id);

alter table public.badges enable row level security;
drop policy if exists badges_read on public.badges;
create policy badges_read on public.badges for select to authenticated using (true);
drop policy if exists badges_insert on public.badges;
create policy badges_insert on public.badges for insert to authenticated
  with check (public.is_admin() and awarded_by = auth.uid());
drop policy if exists badges_delete on public.badges;
create policy badges_delete on public.badges for delete to authenticated
  using (public.is_admin());
