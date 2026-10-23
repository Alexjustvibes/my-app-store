-- ============================================================================
-- Fix message/post sending — add the media & reply columns the client sends.
-- Run in the new project's SQL Editor. Safe / re-runnable (IF NOT EXISTS).
-- Root cause: POST /rest/v1/messages returned 400 because the client's insert
-- payload includes columns the reconstructed table didn't have.
-- ============================================================================

alter table messages
  add column if not exists reply_to    uuid references messages(id) on delete set null,
  add column if not exists pinned      boolean not null default false,
  add column if not exists is_system   boolean not null default false,
  add column if not exists media_path  text,
  add column if not exists media_kind  text,
  add column if not exists media_bucket text default 'media',
  add column if not exists poll_id     uuid references polls(id) on delete set null;

alter table posts
  add column if not exists media_kind  text,
  add column if not exists media_path  text,
  add column if not exists media_bucket text default 'media',
  add column if not exists color       text;

-- Reload PostgREST's schema cache so the new columns are usable immediately
notify pgrst, 'reload schema';
