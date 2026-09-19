-- Maintrix backend — 0024: crowd-sourced debate ending
-- Run after 0023.
--
-- The creator could previously end their own debate anytime, which is a bad
-- mechanic — a debater has every incentive to end early while winning and
-- never end while losing. Neither the creator nor the opponent may end a
-- debate anymore. Only an admin (moderation) or the spectating audience via
-- a majority vote-to-end can.

create table if not exists public.debate_end_votes (
  debate_id  uuid references public.debates(id) on delete cascade,
  voter_id   uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (debate_id, voter_id)
);
alter table public.debate_end_votes enable row level security;
drop policy if exists dev_read on public.debate_end_votes;
create policy dev_read on public.debate_end_votes for select to authenticated using (true);
-- no insert/update/delete policy — only vote_end_debate() below writes here.

-- Shared ending logic (winner + ELO), pulled out of end_debate() so both the
-- admin path and the crowd vote-to-end path finalize a debate identically.
-- Deliberately NOT granted execute to authenticated — it's an internal
-- helper only callable from within another security-definer function,
-- which runs as the function owner rather than the original caller.
create or replace function public.finalize_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d record; c int; o int;
  celo int; oelo int; expected_c numeric; k constant numeric := 64; delta int := 0;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null or d.status = 'ended' then return; end if;

  select count(*) into c from public.debate_votes where debate_id = d_id and vote_for = d.creator_id;
  select count(*) into o from public.debate_votes where debate_id = d_id and d.opponent_id is not null and vote_for = d.opponent_id;

  if d.opponent_id is not null then
    select elo into celo from public.profiles where id = d.creator_id;
    select elo into oelo from public.profiles where id = d.opponent_id;
    celo := coalesce(celo,1000); oelo := coalesce(oelo,1000);
    expected_c := 1.0 / (1.0 + power(10, (oelo - celo) / 400.0));
    delta := round(k * ((case when c > o then 1.0 when o > c then 0.0 else 0.5 end) - expected_c));

    update public.profiles set
      elo = elo + delta,
      debate_wins   = debate_wins   + (case when c > o then 1 else 0 end),
      debate_losses = debate_losses + (case when o > c then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.creator_id;

    update public.profiles set
      elo = elo - delta,
      debate_wins   = debate_wins   + (case when o > c then 1 else 0 end),
      debate_losses = debate_losses + (case when c > o then 1 else 0 end),
      debate_ties   = debate_ties   + (case when c = o then 1 else 0 end)
      where id = d.opponent_id;
  end if;

  update public.debates set status = 'ended', ended_at = now(),
    winner_id = case when c > o then d.creator_id when o > c then d.opponent_id else null end,
    elo_delta = abs(delta)
    where id = d_id;
end; $$;

-- Admin-only now — see note above.
create or replace function public.end_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'only an admin can end a debate directly — everyone else votes to end it'; end if;
  perform public.finalize_debate(d_id);
end; $$;

-- Spectators vote to end early. Quorum scales with how many people have
-- actually engaged with the debate (cast a side vote): majority of that
-- audience, floor of 2, so a handful of early spectators can still end a
-- dead debate without needing a huge crowd.
create or replace function public.vote_end_debate(d_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d record; audience int; required int; n_end int;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.status <> 'active' then raise exception 'this debate isn''t open for voting'; end if;
  if auth.uid() = d.creator_id or auth.uid() = d.opponent_id then raise exception 'debaters can''t vote to end their own debate'; end if;

  insert into public.debate_end_votes(debate_id, voter_id) values (d_id, auth.uid())
    on conflict (debate_id, voter_id) do nothing;

  select count(distinct voter_id) into audience from public.debate_votes where debate_id = d_id;
  required := greatest(2, ceil(audience / 2.0));
  select count(*) into n_end from public.debate_end_votes where debate_id = d_id;

  if n_end >= required then
    perform public.finalize_debate(d_id);
  end if;

  return jsonb_build_object('votes', n_end, 'required', required, 'ended', n_end >= required);
end; $$;

grant execute on function public.end_debate(uuid) to authenticated;
grant execute on function public.vote_end_debate(uuid) to authenticated;

do $$
begin
  begin execute 'alter publication supabase_realtime add table public.debate_end_votes'; exception when duplicate_object then null; end;
end $$;
