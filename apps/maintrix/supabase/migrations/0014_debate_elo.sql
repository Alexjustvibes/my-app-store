-- Maintrix backend — 0014: Debate ELO / ranks
-- Run after 0013. Winning a debate raises your ELO (K=64, tuned high so ranks
-- move fast — this is a fun gamification layer, not a competitive ladder);
-- losing lowers it by the same amount (zero-sum); a tie nudges both toward
-- the midpoint. Rank names/thresholds live client-side (DEBATE_RANKS in
-- index.html) purely off this number.

alter table public.profiles add column if not exists elo integer not null default 1000;
alter table public.profiles add column if not exists debate_wins integer not null default 0;
alter table public.profiles add column if not exists debate_losses integer not null default 0;
alter table public.profiles add column if not exists debate_ties integer not null default 0;
alter table public.debates add column if not exists elo_delta integer;

create or replace function public.end_debate(d_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d record; c int; o int;
  celo int; oelo int; expected_c numeric; k constant numeric := 64; delta int;
begin
  select * into d from public.debates where id = d_id for update;
  if d is null then raise exception 'debate not found'; end if;
  if d.creator_id <> auth.uid() and not public.is_admin() then raise exception 'only the creator or an admin can end this debate'; end if;
  if d.status = 'ended' then return; end if;

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
