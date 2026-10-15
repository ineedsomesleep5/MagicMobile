-- PENDING CALEB'S CHOICE: NOT A MIGRATION YET. Do not apply.
--
-- Ladder option B from docs/cloud/ladder-options.md (C1's recommendation): Arena's Bo1 steps per tier and a floor at
-- each tier. It lives outside supabase/migrations so `supabase db push` cannot pick it up. If Caleb chooses B, the
-- Mac session moves it to supabase/migrations/<timestamp>_ladder_option_b.sql (a later timestamp than every
-- migration already applied), ships the same rules in RankLadder.swift / Ranked.kt / ranked-cases.json in the same
-- release, and applies it live with Caleb's OK. Test: `npm run test:ranked-pending --prefix supabase/tests`.
--
-- The rules (shared with the apps):
-- * A win earns 2 pips in Bronze, Silver and Gold, 1 in Platinum, Diamond and Mythic. A loss costs nothing in
--   Bronze and 1 pip elsewhere.
-- * A loss never takes you below division IV of the tier you are in. You can't fall out of a tier, so that is
--   also the highest tier reached this season. Mythic is the exception: it can fall back to Diamond (never below
--   Diamond IV), as on Arena.
-- * The underdog bonus stays (+1 per win with a deck below the tier's opponent brackets). The streak bonus ends:
--   two-pip wins replace it. win_streak still counts for the profile.
-- * Draws, the points encoding (step * 4 + pips), the monthly rollover (one tier down, empty pips), the AI and
--   pair caps and everything else are unchanged. Only mm_ranked_apply changes.

create or replace function public.mm_ranked_apply(p_uid uuid, p_outcome text, p_deck_bracket integer, p_source text,
                                                  p_match uuid, p_ai_game uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s public.ranked_standings%rowtype := public.mm_ranked_current(p_uid);
  -- 0 Bronze … 4 Diamond, 5 Mythic
  v_tier integer := least(public.mm_rank_points_step(s.points) / 4, 5);
  v_delta integer := 0;
  v_streak integer := s.win_streak;
  v_bonuses text[] := '{}';
  v_after integer;
begin
  if p_outcome = 'win' then
    v_delta := (array[2, 2, 2, 1, 1, 1])[v_tier + 1];
    v_streak := v_streak + 1;
    if p_deck_bracket is not null and p_deck_bracket < public.mm_rank_min_bracket(s.points) then
      v_delta := v_delta + 1; v_bonuses := array_append(v_bonuses, 'underdog');
    end if;
  elsif p_outcome = 'loss' then
    v_delta := -(array[0, 1, 1, 1, 1, 1])[v_tier + 1];
    v_streak := 0;
  else
    v_streak := 0;
  end if;
  -- The floor: division IV of this tier, Diamond IV at most (so Mythic can fall back to Diamond).
  v_after := least(greatest(s.points + v_delta, least(v_tier, 4) * 16), 100080);
  update public.ranked_standings set points = v_after, peak_points = greatest(peak_points, v_after),
    wins = wins + (p_outcome = 'win')::int, losses = losses + (p_outcome = 'loss')::int,
    draws = draws + (p_outcome = 'draw')::int, win_streak = v_streak, updated_at = now()
   where user_id = p_uid;
  insert into public.ranked_results (user_id, season, source, match_id, ai_game, outcome, points_before, points_after, bonuses)
  values (p_uid, s.season, p_source, p_match, p_ai_game, p_outcome, s.points, v_after, v_bonuses);
  perform public.mm_ranked_mirror(p_uid);
  return jsonb_build_object('outcome', p_outcome, 'pointsBefore', s.points, 'pointsAfter', v_after, 'bonuses', to_jsonb(v_bonuses));
end $$;

-- Unchanged access: an internal helper, callable by neither signed-in players nor anonymous callers.
revoke all on function public.mm_ranked_apply(uuid, text, integer, text, uuid, uuid) from public, anon, authenticated;
