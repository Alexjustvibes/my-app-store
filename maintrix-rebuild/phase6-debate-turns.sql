-- Phase 6 — debate turn system (applied live 2026-10-26).
--   * Debates start held: nobody can talk or type until BOTH debaters press "I'm ready".
--   * Between turns the debate holds again: the next speaker presses "I'm ready" to start their clock.
--   * Only the floor holder can type (messages trigger) or transmit voice (debate-floor edge function).
--   * The next speaker gets a 'debate_turn' notification when the floor passes to them.
--   * Pausing the clock is turned off; leaving a debate forfeits it.
-- No secrets here: the floor-sync trigger reads the hook secret from Vault.

alter table debates add column if not exists ready_creator boolean not null default false;
alter table debates add column if not exists ready_opponent boolean not null default false;

CREATE OR REPLACE FUNCTION public.trg_debate_hold_start()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  if new.status = 'active' and new.opponent_id is not null
     and (tg_op = 'INSERT' or old.status is distinct from 'active') then
    new.paused_at := now();
    new.paused_by := null;
    new.paused_left := nullif(new.turn_secs, 0);
    new.turn_ends_at := null;
    new.ready_creator := false;
    new.ready_opponent := false;
  end if;
  return new;
end $function$;

create or replace trigger a_debate_hold_start BEFORE INSERT OR UPDATE OF status ON public.debates
  FOR EACH ROW EXECUTE FUNCTION trg_debate_hold_start();

CREATE OR REPLACE FUNCTION public.debate_resume(p_debate uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare d debates; me uuid := auth.uid(); started boolean;
begin
  select * into d from debates where id = p_debate for update;
  if not found then raise exception 'Debate not found'; end if;
  if d.paused_at is null or d.status <> 'active' then return to_jsonb(d); end if;
  started := d.ready_creator and d.ready_opponent;
  if started then
    if me is distinct from d.turn_holder and not is_admin() then raise exception 'It''s not your turn yet'; end if;
  else
    if not (me in (d.creator_id, d.opponent_id) or is_admin()) then raise exception 'Only the debaters can start the debate'; end if;
    if me = d.creator_id then d.ready_creator := true; end if;
    if me = d.opponent_id then d.ready_opponent := true; end if;
    if not (d.ready_creator and d.ready_opponent) and not (is_admin() and me not in (d.creator_id, d.opponent_id)) then
      update debates set ready_creator = d.ready_creator, ready_opponent = d.ready_opponent where id = p_debate returning * into d;
      return to_jsonb(d);
    end if;
  end if;
  update debates set ready_creator = true, ready_opponent = true,
    turn_ends_at = case when d.paused_left is null then null else now() + make_interval(secs => d.paused_left) end,
    turn_started_at = now(), paused_at = null, paused_by = null, paused_left = null
  where id = p_debate returning * into d;
  return to_jsonb(d);
end $function$;

CREATE OR REPLACE FUNCTION public.debate_pause(p_debate uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  raise exception 'Pausing the clock has been turned off';
end $function$;

CREATE OR REPLACE FUNCTION public._debate_next_turn(p_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare d debates; nxt uuid; total integer; t integer;
begin
  select * into d from debates where id = p_id for update;
  if not found or d.status <> 'active' then return; end if;
  t := nullif(d.turn_secs, 0);
  if d.stage_guest is not null then
    update debates set turn_holder = d.stage_return, stage_guest = null, stage_return = null,
      turn_started_at = null, turn_ends_at = null,
      paused_at = now(), paused_by = null, paused_left = t
    where id = p_id;
    return;
  end if;
  total := greatest(d.rounds, 1) * 2;
  if d.turn_no >= total then
    update debates set turn_holder = null, turn_started_at = null, turn_ends_at = null, turn_no = total + 1,
      paused_at = null, paused_by = null, paused_left = null
    where id = p_id;
    return;
  end if;
  nxt := case when d.turn_holder = d.creator_id then d.opponent_id else d.creator_id end;
  update debates set turn_no = d.turn_no + 1, turn_holder = nxt,
    turn_started_at = null, turn_ends_at = null,
    paused_at = now(), paused_by = null, paused_left = t
  where id = p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.guard_debate_message()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare d record;
begin
  if coalesce(new.is_system, false) then return new; end if;
  select id, creator_id, opponent_id, turn_holder, paused_at into d
  from debates where status = 'active' and (room_id = new.room_id or chat_room_id = new.room_id) limit 1;
  if d.id is null or new.author_id is distinct from d.creator_id and new.author_id is distinct from d.opponent_id then
    return new;
  end if;
  if d.paused_at is not null then
    raise exception 'not_ready';
  end if;
  if d.turn_holder is not null and d.turn_holder is distinct from new.author_id then
    raise exception 'not_your_turn';
  end if;
  return new;
end $function$;

create or replace trigger guard_debate_message BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION guard_debate_message();

CREATE OR REPLACE FUNCTION public.trg_notify_debate_turn()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare other uuid;
begin
  if new.status = 'active' and new.turn_holder is not null
     and ((old.turn_holder is distinct from new.turn_holder and new.ready_creator and new.ready_opponent)
          or (old.paused_at is not null and new.paused_at is null and not (old.ready_creator and old.ready_opponent))) then
    other := case when new.turn_holder = new.creator_id then new.opponent_id else new.creator_id end;
    perform notify_user(new.turn_holder, 'debate_turn', other,
      jsonb_build_object('debate_id', new.id, 'room_id', new.room_id, 'title', new.title));
  end if;
  return null;
end $function$;

create or replace trigger notify_debate_turn AFTER UPDATE OF turn_holder, paused_at ON public.debates
  FOR EACH ROW EXECUTE FUNCTION trg_notify_debate_turn();

CREATE OR REPLACE FUNCTION public.trg_debate_floor_sync()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare sec text;
begin
  if new.opponent_id is null then return null; end if;
  if old.turn_holder is not distinct from new.turn_holder and old.paused_at is not distinct from new.paused_at
     and old.status is not distinct from new.status and old.stage_guest is not distinct from new.stage_guest then
    return null;
  end if;
  select decrypted_secret into sec from vault.decrypted_secrets where name = 'push_hook_secret' limit 1;
  if sec is null then return null; end if;
  perform net.http_post(
    url := 'https://dvrcrwyjqlrowsnevduz.supabase.co/functions/v1/debate-floor',
    body := jsonb_build_object('id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', sec),
    timeout_milliseconds := 8000);
  return null;
exception when others then
  return null;
end $function$;

create or replace trigger debate_floor_sync AFTER UPDATE OF turn_holder, paused_at, status, stage_guest ON public.debates
  FOR EACH ROW EXECUTE FUNCTION trg_debate_floor_sync();

CREATE OR REPLACE FUNCTION public.leave_debate(d_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare d debates; me uuid := auth.uid(); w uuid; ra integer; rb integer; ea double precision; sa double precision; delta integer := 0;
begin
  select * into d from debates where id = d_id for update;
  if not found or d.status = 'ended' then return; end if;
  if me is null or (me is distinct from d.creator_id and me is distinct from d.opponent_id) then
    raise exception 'Only the debaters can leave this debate';
  end if;
  if d.opponent_id is null then
    update debates set status = 'ended', ended_at = now(), turn_holder = null, turn_ends_at = null where id = d_id;
    return;
  end if;
  -- leaving forfeits: the other debater wins
  w := case when me = d.creator_id then d.opponent_id else d.creator_id end;
  if d.ranked then
    select elo into ra from profiles where id = d.creator_id;
    select elo into rb from profiles where id = d.opponent_id;
    ea := 1.0 / (1.0 + power(10.0, (coalesce(rb, 1000) - coalesce(ra, 1000)) / 400.0));
    sa := case when w = d.creator_id then 1.0 else 0.0 end;
    delta := round(32 * (sa - ea));
    update profiles set elo = elo + delta where id = d.creator_id;
    update profiles set elo = elo - delta where id = d.opponent_id;
  end if;
  update profiles set
    debate_wins   = debate_wins   + case when id = w then 1 else 0 end,
    debate_losses = debate_losses + case when id <> w then 1 else 0 end
  where id in (d.creator_id, d.opponent_id);
  update debates set status = 'ended', ended_at = now(), winner_id = w,
    turn_holder = null, turn_ends_at = null, paused_at = null, paused_by = null, paused_left = null,
    elo_delta = case when d.ranked then abs(delta) end,
    elo_gain  = case when d.ranked then abs(delta) end,
    elo_loss  = case when d.ranked then abs(delta) end
  where id = d_id;
  update ranked_matches set status = 'ended', ended_reason = 'forfeit', updated_at = now() where debate_id = d_id;
  perform notify_user(w, 'debate_end', me, jsonb_build_object('room_id', d.room_id, 'debate_id', d.id, 'title', d.title, 'forfeit', true));
end $function$;

CREATE OR REPLACE FUNCTION public.ranked_respond(m_id uuid, p_agree boolean, p_reason text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare m ranked_matches; me uuid := auth.uid(); other uuid; r uuid; d uuid; t integer;
begin
  select * into m from ranked_matches where id = m_id for update;
  if not found or me not in (m.a, m.b) then raise exception 'Match not found'; end if;
  if m.status <> 'review' then return to_jsonb(m); end if;
  if m.proposer = me then raise exception 'Waiting on your opponent'; end if;
  if coalesce(p_agree, false) then
    insert into rooms (kind, title, is_public, owner_id) values ('debate', left(m.topic_title, 120), true, m.proposer) returning id into r;
    insert into room_members (room_id, user_id, rank) values (r, m.proposer, 'Owner'), (r, me, 'Initiate') on conflict do nothing;
    t := nullif(m.turn_secs, 0);
    insert into debates (title, "desc", description, created_by, creator_id, opponent_id, status, room_id, chat_room_id,
                         ranked, rounds, turn_secs, started_at, turn_no, turn_holder, turn_started_at, turn_ends_at)
    values (m.topic_title, m.topic_desc, m.topic_desc, m.proposer, m.proposer, me, 'active', r, r,
            true, coalesce(m.turns, 3), coalesce(m.turn_secs, 60), now(), 1, m.proposer, now(),
            case when t is null then null else now() + make_interval(secs => t) end)
    returning id into d;
    update ranked_matches set status = 'live', debate_id = d, updated_at = now() where id = m_id returning * into m;
    perform notify_user(m.proposer, 'ranked_live', me, jsonb_build_object('match_id', m.id, 'debate_id', d, 'room_id', r, 'title', m.topic_title));
  else
    update ranked_matches set rejects = rejects + 1, last_reason = left(coalesce(p_reason, ''), 200),
      topic_title = null, topic_desc = null, status = 'topic',
      proposer = case when rejects + 1 >= 3 then me else proposer end, updated_at = now()
    where id = m_id returning * into m;
    other := case when m.a = me then m.b else m.a end;
    perform notify_user(case when m.proposer = me then other else m.proposer end, 'ranked_turn', me, jsonb_build_object('match_id', m.id));
  end if;
  return to_jsonb(m);
end $function$;
