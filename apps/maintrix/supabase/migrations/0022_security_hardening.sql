-- Maintrix backend — 0022: security hardening batch
-- Run after 0021.

-- ═══════════════════════ storage: size + mime enforcement ══════════════════
-- Bucket had no limits at all — any authenticated user could upload an
-- arbitrarily large file of any content type into their own folder. Cap size
-- and restrict to real media types (also blocks svg/html uploads into a
-- PUBLIC bucket, which could otherwise be used to host attacker HTML/SVG on
-- a supabase.co URL).
update storage.buckets set
  file_size_limit = 62914560, -- 60MB ceiling (video is the largest legit upload); client enforces tighter per-kind caps
  allowed_mime_types = array[
    'image/png','image/jpeg','image/webp','image/gif',
    'video/mp4','video/webm','video/quicktime',
    'audio/webm','audio/mpeg','audio/mp3','audio/wav','audio/ogg'
  ]
where id = 'media';

-- ═══════════════════════ server-side content length caps ═══════════════════
-- Client-side maxlength attributes are trivially bypassed by anyone calling
-- the REST API directly — none of these had a real ceiling, so an attacker
-- could insert megabyte-sized rows (storage bloat / rendering DoS). Mirrors
-- the pattern already used for profiles.status_line (0012).
alter table public.profiles drop constraint if exists profiles_name_len;
alter table public.profiles add constraint profiles_name_len check (name is null or char_length(name) <= 40);
alter table public.profiles drop constraint if exists profiles_bio_len;
alter table public.profiles add constraint profiles_bio_len check (bio is null or char_length(bio) <= 500);

alter table public.messages drop constraint if exists messages_body_len;
alter table public.messages add constraint messages_body_len check (char_length(body) <= 4000);

alter table public.posts drop constraint if exists posts_body_len;
alter table public.posts add constraint posts_body_len check (body is null or char_length(body) <= 3000);
alter table public.posts drop constraint if exists posts_caption_len;
alter table public.posts add constraint posts_caption_len check (caption is null or char_length(caption) <= 80);

alter table public.post_comments drop constraint if exists post_comments_body_len;
alter table public.post_comments add constraint post_comments_body_len check (char_length(body) <= 1000);

-- ═══════════════════════ rate limiting ══════════════════════════════════════
-- Generic sliding-window limiter. No client access — only trigger functions
-- (security definer) touch this table, so it can't be read or spoofed from
-- the client to defeat its own limits.
create table if not exists public.rate_limits (
  id         bigserial primary key,
  user_id    uuid not null,
  action     text not null,
  created_at timestamptz not null default now()
);
create index if not exists rate_limits_lookup_idx on public.rate_limits (user_id, action, created_at);
alter table public.rate_limits enable row level security;
-- deliberately no policies at all — RLS default-denies every client-side access;
-- only security-definer functions (which bypass RLS) ever touch this table.

create or replace function public.enforce_rate_limit(p_action text, p_max int, p_window interval)
returns void language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  if auth.uid() is null then return; end if;
  delete from public.rate_limits where created_at < now() - interval '1 day';
  select count(*) into cnt from public.rate_limits
    where user_id = auth.uid() and action = p_action and created_at > now() - p_window;
  if cnt >= p_max then
    raise exception 'rate_limited: too many % — slow down', p_action;
  end if;
  insert into public.rate_limits (user_id, action) values (auth.uid(), p_action);
end; $$;

create or replace function public.trg_rate_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.enforce_rate_limit(tg_argv[0], tg_argv[1]::int, tg_argv[2]::interval);
  return new;
end; $$;

drop trigger if exists rl_messages on public.messages;
create trigger rl_messages before insert on public.messages
  for each row execute function public.trg_rate_limit('message', 20, '10 seconds');

drop trigger if exists rl_posts on public.posts;
create trigger rl_posts before insert on public.posts
  for each row execute function public.trg_rate_limit('post', 5, '1 minute');

drop trigger if exists rl_comments on public.post_comments;
create trigger rl_comments before insert on public.post_comments
  for each row execute function public.trg_rate_limit('comment', 20, '1 minute');

drop trigger if exists rl_friend_requests on public.friend_requests;
create trigger rl_friend_requests before insert on public.friend_requests
  for each row execute function public.trg_rate_limit('friend_request', 20, '1 minute');

drop trigger if exists rl_dm_requests on public.dm_requests;
create trigger rl_dm_requests before insert on public.dm_requests
  for each row execute function public.trg_rate_limit('dm_request', 20, '1 minute');

-- ═══════════════════════ admin: delete an account outright ═════════════════
-- profiles.id -> auth.users(id) on delete cascade (0001), and every table
-- that references profiles was set up with its own on-delete behavior, so
-- deleting the auth.users row is the one real "delete this account" op —
-- everything downstream (profile, messages, posts, friendships, etc.)
-- cascades or nulls out from there. Requires the function owner to have
-- privileges on auth.users, same as every other security-definer function
-- in this schema already relies on for its own writes.
create or replace function public.admin_delete_account(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  delete from auth.users where id = target;
end; $$;
grant execute on function public.admin_delete_account(uuid) to authenticated;
