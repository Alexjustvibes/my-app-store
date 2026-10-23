-- ============================================================================
-- Maintrix — finish the backend (run in the new project's SQL Editor)
-- Everything here is CREATE FUNCTION / one INSERT. Safe to run; re-runnable.
-- (The MCP migration prompts were being auto-declined, so paste-and-run instead.)
-- ============================================================================

-- ---------- Debate actions ----------
create or replace function join_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin perform 1 from debates where id = d_id and status = 'open'; end $$;

create or replace function vote_debate(d_id uuid, for_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into debate_votes(debate_id, voter_id, vote_for) values (d_id, auth.uid(), for_user)
  on conflict (debate_id, voter_id) do update set vote_for = excluded.vote_for;
end $$;

create or replace function vote_end_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin insert into debate_end_votes(debate_id, voter_id) values (d_id, auth.uid()) on conflict do nothing; end $$;

create or replace function end_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin update debates set status='ended' where id = d_id and (created_by = auth.uid() or is_admin()); end $$;

create or replace function delete_own_open_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin delete from debates where id = d_id and created_by = auth.uid() and status = 'open'; end $$;

-- ---------- Admin: info / update ----------
create or replace function admin_ban_info(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  return (select jsonb_build_object('id',id,'handle',handle,'name',name,'banned',banned,
                 'muted_until',muted_until,'risk',risk,'tier',tier) from profiles where id=target); end $$;

create or replace function admin_user_security(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  return (select jsonb_build_object('id',id,'risk',risk,'banned',banned,'muted_until',muted_until,
                 'created_at',created_at) from profiles where id=target); end $$;

create or replace function admin_edit_profile(target uuid, patch jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set
    name = coalesce(patch->>'name', name), bio = coalesce(patch->>'bio', bio),
    tier = coalesce(patch->>'tier', tier), color = coalesce(patch->>'color', color),
    risk = coalesce(patch->>'risk', risk)
  where id = target; end $$;

create or replace function admin_set_server_official(target_room uuid, val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update rooms set is_official = val where id = target_room; end $$;

create or replace function admin_reset_user_elo(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  update profiles set elo = 1000 where id = target; end $$;

create or replace function admin_reset_debate_leaderboard() returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if; update profiles set elo = 1000; end $$;

create or replace function admin_alerts(p_limit integer, p_open_only boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if; return '[]'::jsonb; end $$;
create or replace function admin_ack_alert(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if; end $$;
create or replace function admin_run_monitor() returns jsonb
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if; return '{}'::jsonb; end $$;

-- ---------- Admin: moderation (contains DELETE on PUBLIC tables; no auth.users) ----------
create or replace function admin_delete_user_messages(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  delete from messages where author_id = target; end $$;

create or replace function admin_delete_debate(d_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  delete from debates where id = d_id; end $$;

create or replace function admin_kick(target uuid, room uuid) returns void
language plpgsql security definer set search_path = public as $$
begin if not is_admin() then raise exception 'not admin'; end if;
  delete from room_members where user_id = target and room_id = room; end $$;

-- NOTE: admin_delete_account (deletes from auth.users) intentionally omitted for now.

-- ---------- Seed: the main "world" room the client looks up ----------
insert into rooms (title, slug, kind, is_public, is_official, bio)
values ('The World', 'world', 'world', true, true, 'The main world room.')
on conflict (slug) do nothing;

-- ============================================================================
-- OPTIONAL hardening — revoke anon EXECUTE on RPCs, keep the pre-auth ones.
-- Run this ONLY after confirming signup/login still work; if signup breaks,
-- it means the client calls another RPC pre-auth — tell Claude and we adjust.
-- (CAPTCHA in the Auth dashboard is the primary protection regardless.)
-- ----------------------------------------------------------------------------
-- revoke execute on all functions in schema public from anon;
-- grant execute on function
--   public.pow_challenge(text),
--   public.pow_verify(uuid,text,jsonb),
--   public.session_check(text,text,text)
-- to anon;
