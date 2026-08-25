-- Maintrix backend — 0008: new traits, avatars, comment threads+hearts, reactions
-- Run after 0007.

-- ── new archetypal traits (old ones kept so existing rows stay valid) ──
insert into public.traits (value, kind) values
  ('Value','goal'),('Stability','goal'),
  ('Chaos','fear'),('Boredom','fear'),('Incompetence','fear')
on conflict (value) do nothing;
-- (Freedom already a goal; Mediocrity, Rejection already fears)

-- seed a global nexus room for every goal trait (Your World / trait nexuses)
insert into public.rooms (kind, slug, title, trait, scope)
  select 'trait', 'trait:'||value, value, value, 'global' from public.traits where kind='goal'
on conflict (slug) do nothing;

-- ── profile picture ──
alter table public.profiles add column if not exists avatar_path text;

-- ── comment threading + hearts ──
alter table public.post_comments add column if not exists parent_id uuid
  references public.post_comments(id) on delete cascade;

create table if not exists public.comment_likes (
  comment_id uuid references public.post_comments(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create index if not exists comment_likes_c_idx on public.comment_likes (comment_id);
alter table public.comment_likes enable row level security;
drop policy if exists cl_read on public.comment_likes;
create policy cl_read on public.comment_likes for select to authenticated using (true);
drop policy if exists cl_insert on public.comment_likes;
create policy cl_insert on public.comment_likes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists cl_delete on public.comment_likes;
create policy cl_delete on public.comment_likes for delete to authenticated using (user_id = auth.uid());

-- ── message emoji reactions ──
create table if not exists public.message_reactions (
  message_id uuid references public.messages(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);
create index if not exists message_reactions_m_idx on public.message_reactions (message_id);
alter table public.message_reactions enable row level security;
drop policy if exists mr_read on public.message_reactions;
create policy mr_read on public.message_reactions for select to authenticated using (true);
drop policy if exists mr_insert on public.message_reactions;
create policy mr_insert on public.message_reactions for insert to authenticated with check (user_id = auth.uid());
drop policy if exists mr_delete on public.message_reactions;
create policy mr_delete on public.message_reactions for delete to authenticated using (user_id = auth.uid());

do $$
begin
  begin execute 'alter publication supabase_realtime add table public.message_reactions'; exception when duplicate_object then null; end;
end $$;
