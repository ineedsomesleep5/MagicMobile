-- Diamond retune (Caleb, 2026-10-29: "improve diamond server side"), from 254DADDY's ranked games: his best deck won
-- 27 of 39 against Platinum's AI and 15 of 21 against Diamond's, so Diamond played no harder than Platinum.
--
-- 1. ranked_ai_tuning gains ai_skill: the AI skill a tier's tickets carry (null keeps the ladder's own, Bronze 1 to
--    Mythic 6). Apps from TestFlight 63 / Android 41 and the web play the ticket's skill; older apps keep their own,
--    which the record check still accepts (one tier's lag).
-- 2. Diamond's AI plays at skill 6, Mythic's: search depth 6 and up to 18 s a decision, against 5 and 15 s. On the Core
--    pool skill 6 beat skill 4 in 59% of 160 games, where skill 5 beat it in 53% (docs/cloud/reports/c4.md).
-- 3. Diamond brings decks of Power 8–9 (divisions IV → I: 8.13, 8.38, 8.63, 8.88), and Mythic 8.75–9.75 (9.25), so
--    Mythic stays above Diamond I. The deck ratings now count games against people too (docs/DECK_POWER.md); apps rated
--    by the older ratings pick their nearest decks to the same targets.

alter table public.ranked_ai_tuning
  add column if not exists ai_skill smallint check (ai_skill between 1 and 10);

create or replace function public.mm_ranked_ai_tuning_for(p_points integer) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'aiSkill', coalesce(t.ai_skill::int, public.mm_rank_ai_skill(p_points)),
    'aiMistakePercent', case when s.step >= 20 then t.mistakes_division_iv
      else round(t.mistakes_division_iv + (t.mistakes_division_i - t.mistakes_division_iv) * (s.step % 4) / 3.0)::int end,
    'aiPower', round(case when s.step >= 20 then (t.power_low + t.power_high) / 2
      else t.power_low + (t.power_high - t.power_low) * ((s.step % 4) + 0.5) / 4 end, 2))
  from (select public.mm_rank_points_step(p_points) as step) s
  join public.ranked_ai_tuning t on t.tier = least(s.step / 4, 5) $$;
revoke all on function public.mm_ranked_ai_tuning_for(integer) from public, anon, authenticated;

update public.ranked_ai_tuning
   set power_low = 8, power_high = 9, mistakes_division_iv = 0, mistakes_division_i = 0, ai_skill = 6, updated_at = now()
 where tier = 4;
update public.ranked_ai_tuning
   set power_low = 8.75, power_high = 9.75, updated_at = now()
 where tier = 5;
