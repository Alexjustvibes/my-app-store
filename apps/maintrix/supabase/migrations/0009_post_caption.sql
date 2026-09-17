-- Maintrix backend — 0009: post captions
-- Run after 0008. Adds a `caption` column used as the picture-card text for
-- text-only posts, decoupled from the freeform body. Previously the feed just
-- sliced the first ~44 chars of `body` for the card, which cut off mid-word and
-- looked odd. The composer now requires a caption for every new post; existing
-- rows keep working via their old sliced-body fallback in the front end since
-- `caption` is nullable and untouched here.

alter table public.posts add column if not exists caption text;
