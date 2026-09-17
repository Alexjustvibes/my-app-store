-- Maintrix backend — 0010: MBTI type
-- Run after 0009. Unlike goals/fears, mbti is NOT locked by trg_lock_identity —
-- members can change it anytime from their profile (pick directly or via the
-- in-app mini test). Nullable: most existing rows won't have one yet.

alter table public.profiles add column if not exists mbti text;
alter table public.profiles
  drop constraint if exists profiles_mbti_valid;
alter table public.profiles
  add constraint profiles_mbti_valid
  check (mbti is null or mbti ~ '^[EI][SN][TF][JP]$');
