-- Maintrix backend — 0011: Enneagram (Core+Wing, Tritype) + Four Temperaments
-- Run after 0010. All fields editable anytime (not in trg_lock_identity), and
-- "Unsure" is now a valid value for mbti too, since signup offers it directly.

alter table public.profiles add column if not exists enneagram_core text;
alter table public.profiles add column if not exists enneagram_wing text;
alter table public.profiles add column if not exists enneagram_tritype text;
alter table public.profiles add column if not exists temperament_dominant text;
alter table public.profiles add column if not exists temperament_secondary text;

alter table public.profiles drop constraint if exists profiles_mbti_valid;
alter table public.profiles add constraint profiles_mbti_valid
  check (mbti is null or mbti = 'Unsure' or mbti ~ '^[EI][SN][TF][JP]$');

alter table public.profiles drop constraint if exists profiles_enneagram_core_valid;
alter table public.profiles add constraint profiles_enneagram_core_valid
  check (enneagram_core is null or enneagram_core = 'Unsure' or enneagram_core ~ '^[1-9]$');

alter table public.profiles drop constraint if exists profiles_enneagram_wing_valid;
alter table public.profiles add constraint profiles_enneagram_wing_valid
  check (enneagram_wing is null or enneagram_wing ~ '^[1-9]$');

alter table public.profiles drop constraint if exists profiles_enneagram_tritype_valid;
alter table public.profiles add constraint profiles_enneagram_tritype_valid
  check (enneagram_tritype is null or enneagram_tritype ~ '^[1-9]-[1-9]-[1-9]$');

alter table public.profiles drop constraint if exists profiles_temperament_dominant_valid;
alter table public.profiles add constraint profiles_temperament_dominant_valid
  check (temperament_dominant is null or temperament_dominant in ('Unsure','Sanguine','Choleric','Melancholic','Phlegmatic'));

alter table public.profiles drop constraint if exists profiles_temperament_secondary_valid;
alter table public.profiles add constraint profiles_temperament_secondary_valid
  check (temperament_secondary is null or temperament_secondary in ('Sanguine','Choleric','Melancholic','Phlegmatic'));
