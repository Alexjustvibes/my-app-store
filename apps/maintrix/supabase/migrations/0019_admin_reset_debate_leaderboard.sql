-- Maintrix backend — 0019: admin reset of the debate leaderboard
-- Run after 0018. Backs the "Reset debate leaderboard" button in
-- Overwatch → Tools. Wipes every member's ELO back to 1000 and zeroes
-- their win/loss/tie counters. Finished debates themselves are kept
-- (history stays readable); only the standings reset.

create or replace function public.admin_reset_debate_leaderboard()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'not authorized'; end if;
  update public.profiles
     set elo = 1000, debate_wins = 0, debate_losses = 0, debate_ties = 0
   where elo <> 1000 or debate_wins <> 0 or debate_losses <> 0 or debate_ties <> 0;
  get diagnostics n = row_count;
  return n;
end; $$;
grant execute on function public.admin_reset_debate_leaderboard() to authenticated;
