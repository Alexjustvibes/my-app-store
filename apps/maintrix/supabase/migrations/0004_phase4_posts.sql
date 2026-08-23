-- Maintrix backend — Phase 4: Posts, media, comments, post-likes
-- Run after 0003. Adds posts / post_comments / post_likes, a public "media"
-- Storage bucket, RLS (posts are Main-gated), and helper is_main().
-- See apps/maintrix/BACKEND.md.

-- ───────────────────────── membership helper ──────────────────
create or replace function public.is_main()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select tier = 'main' from public.profiles where id = auth.uid()), false);
$$;

-- ───────────────────────── posts ──────────────────────────────
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  author_id  uuid references public.profiles(id) on delete cascade,
  body       text not null default '',
  media_kind text not null default 'text' check (media_kind in ('text','image','video')),
  media_path text,
  color      text,
  created_at timestamptz not null default now()
);
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists posts_author_idx  on public.posts (author_id);

-- ───────────────────────── comments ───────────────────────────
create table if not exists public.post_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid references public.posts(id) on delete cascade,
  author_id  uuid references public.profiles(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);
create index if not exists post_comments_post_idx on public.post_comments (post_id, created_at);

-- ───────────────────────── post likes ─────────────────────────
create table if not exists public.post_likes (
  post_id    uuid references public.posts(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists post_likes_post_idx on public.post_likes (post_id);

-- ───────────────────────── RLS ────────────────────────────────
alter table public.posts         enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_likes    enable row level security;

-- posts: Main can read & create; author or admin can delete
drop policy if exists posts_read on public.posts;
create policy posts_read on public.posts for select to authenticated using (public.is_main());
drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts for insert to authenticated
  with check (author_id = auth.uid() and public.is_main());
drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- comments: Main can read & create; author or admin can delete
drop policy if exists pc_read on public.post_comments;
create policy pc_read on public.post_comments for select to authenticated using (public.is_main());
drop policy if exists pc_insert on public.post_comments;
create policy pc_insert on public.post_comments for insert to authenticated
  with check (author_id = auth.uid() and public.is_main());
drop policy if exists pc_delete on public.post_comments;
create policy pc_delete on public.post_comments for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- post_likes: counts are public; you write only your own
drop policy if exists pl_read on public.post_likes;
create policy pl_read on public.post_likes for select to authenticated using (true);
drop policy if exists pl_insert on public.post_likes;
create policy pl_insert on public.post_likes for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists pl_delete on public.post_likes;
create policy pl_delete on public.post_likes for delete to authenticated
  using (user_id = auth.uid());

-- realtime for comments (nice-to-have live comments)
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.post_comments'; exception when duplicate_object then null; end;
end $$;

-- ───────────────────────── Storage (media bucket) ─────────────
insert into storage.buckets (id, name, public)
  values ('media', 'media', true)
on conflict (id) do nothing;

-- Public read; authenticated users may write/delete only inside their own
-- uid-named folder (path like "<uid>/<file>"). NOTE: files in a public bucket
-- are readable by URL — post *discovery* is still Main-gated by posts RLS.
drop policy if exists media_read on storage.objects;
create policy media_read on storage.objects for select
  using (bucket_id = 'media');
drop policy if exists media_insert on storage.objects;
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists media_delete on storage.objects;
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = auth.uid()::text);
