-- Maintrix backend — 0005: let members set their own tier (instant unlock)
-- Payments are deferred, so membership is still "instant unlock" in-app. The
-- 0001 identity trigger froze `tier`, which made is_main() always false and
-- blocked posting. Redefine the trigger to keep handle/traits/is_admin locked
-- but allow `tier` to change. Run after 0004.

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
  -- is_admin is still server-controlled; tier is user-settable for now (no payments yet)
  new.is_admin := old.is_admin;
  return new;
end;
$$;
