-- Maintrix backend — Phase 1: Identity & auth
-- Run this in the Supabase SQL editor (or `supabase db push`).
-- Covers: traits lookup + seed, profiles table, immutability of traits/handle,
-- auto-create stub profile on signup, and Row-Level Security.
-- See apps/maintrix/BACKEND.md for the full plan.

-- ───────────────────────── extensions ─────────────────────────
create extension if not exists citext;

-- ───────────────────────── traits lookup ──────────────────────
-- Fixed set the signup test chooses from. `kind` = goal | fear.
create table if not exists public.traits (
  value text primary key,
  kind  text not null check (kind in ('goal','fear'))
);

insert into public.traits (value, kind) values
  ('Discipline','goal'),('Wealth','goal'),('Mastery','goal'),('Courage','goal'),
  ('Focus','goal'),('Health','goal'),('Creativity','goal'),('Leadership','goal'),
  ('Purpose','goal'),('Freedom','goal'),
  ('Wasted potential','fear'),('Irrelevance','fear'),('Failure','fear'),
  ('Rejection','fear'),('Mediocrity','fear'),('Being forgotten','fear'),
  ('Running out of time','fear'),('Loneliness','fear')
on conflict (value) do nothing;

-- ───────────────────────── profiles ───────────────────────────
-- One row per auth user. handle + traits are LOCKED after signup.
-- Nullable until the identity test fills them in (a stub row is created on signup).
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  handle     citext unique,                               -- immutable @handle
  name       text,                                        -- changeable display name
  goals      text[] not null default '{}',
  fears      text[] not null default '{}',
  bio        text,
  color      text default '#ed2e44',
  like_icon  text default 'heart',
  country    text,
  region     text,
  tier       text not null default 'lite' check (tier in ('lite','main')),
  is_admin   boolean not null default false,
  created_at timestamptz not null default now()
);

-- handle format: 3–20 chars, lowercase letters/digits/underscore
alter table public.profiles
  drop constraint if exists profiles_handle_format;
alter table public.profiles
  add constraint profiles_handle_format
  check (handle is null or handle ~ '^[a-z0-9_]{3,20}$');

-- match people by shared traits (Your World / trait nexuses)
create index if not exists profiles_goals_gin on public.profiles using gin (goals);
create index if not exists profiles_fears_gin on public.profiles using gin (fears);

-- ─────────────────── immutability of traits + handle ──────────
-- Once set (non-null / non-empty), handle and traits can never change.
create or replace function public.lock_identity()
returns trigger
language plpgsql
as $$
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
  -- tier and is_admin are never set by the user directly (server/webhook only)
  new.tier := old.tier;
  new.is_admin := old.is_admin;
  return new;
end;
$$;

drop trigger if exists trg_lock_identity on public.profiles;
create trigger trg_lock_identity
  before update on public.profiles
  for each row execute function public.lock_identity();

-- ─────────────── auto-create a stub profile on signup ─────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────── validate traits ───────────────────
-- Reject goals/fears that aren't in the fixed list, and wrong-kind values.
create or replace function public.validate_traits()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from unnest(new.goals) g
             where g not in (select value from public.traits where kind='goal')) then
    raise exception 'invalid goal value';
  end if;
  if exists (select 1 from unnest(new.fears) f
             where f not in (select value from public.traits where kind='fear')) then
    raise exception 'invalid fear value';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_traits on public.profiles;
create trigger trg_validate_traits
  before insert or update on public.profiles
  for each row execute function public.validate_traits();

-- ───────────────────────── Row-Level Security ────────────────
alter table public.profiles enable row level security;
alter table public.traits   enable row level security;

-- traits: readable by anyone signed in
drop policy if exists traits_read on public.traits;
create policy traits_read on public.traits
  for select to authenticated using (true);

-- profiles: all identities are public to signed-in users
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (true);

-- profiles: you may only insert/update your own row
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (auth.uid() = id);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- (no delete policy — profiles are removed via auth.users cascade only)
