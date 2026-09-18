-- Maintrix backend — 0017: profile banner style
-- Run after 0016. Backs the new "Profile banner style" picker in Appearance
-- (diagonal/radial/vertical/sunburst gradient treatments built from the
-- user's own color) — needs to be a real column, not local client state,
-- since it's about how a profile looks to OTHER people viewing it.

alter table public.profiles add column if not exists banner_style text;
alter table public.profiles drop constraint if exists profiles_banner_style_valid;
alter table public.profiles add constraint profiles_banner_style_valid
  check (banner_style is null or banner_style in ('diagonal','radial','vertical','sunburst'));
