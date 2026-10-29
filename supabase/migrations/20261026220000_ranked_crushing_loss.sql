-- Crushing losses cost two pips (Caleb, 2026-10-26: "maybe that you can lose 2 pips in a game if you lost pretty bad",
-- to balance faster climbing now the daily win cap is gone). A ranked AI loss where the AI still had at least 30 of its
-- 40 life costs two pips instead of one, from Silver up (Bronze losses stay free; the tier floor still holds). The
-- apps already send the game record with a loss; a loss without one (older tickets, an unreadable record) costs one.
-- The AI's life at the end is kept on the ticket (ai_life_left) for tuning.

alter table public.ranked_ai_games add column if not exists ai_life_left smallint;

-- The AI seat's life when this ticket's game ended, from its record; null without a usable record for this seed.
create or replace function public.mm_ranked_ai_life_left(p_game public.ranked_ai_games, p_record jsonb) returns integer
language plpgsql stable set search_path = '' as $$
declare
  v_setup jsonb;
  v_end jsonb;
  v_ai text;
begin
  if p_record is null or octet_length(p_record::text) > 524288 then return null; end if;
  v_setup := (p_record->>'setup')::jsonb;
  v_end := (p_record->>'end')::jsonb;
  if p_game.seed is null or v_setup->>'seed' is distinct from p_game.seed::text or v_end->>'state' is distinct from 'ended' then
    return null;
  end if;
  select s->>'seatId' into v_ai from jsonb_array_elements(v_setup->'seats') s where s->>'controller' = 'ai' limit 1;
  return (select (s->>'life')::int from jsonb_array_elements(v_end->'seats') s where s->>'seatId' = v_ai limit 1);
exception when others then return null;
end $$;
revoke all on function public.mm_ranked_ai_life_left(public.ranked_ai_games, jsonb) from public, anon, authenticated;

-- One result on the ladder (ladder option B), with a crushing loss costing two pips.
create or replace function public.mm_ranked_apply(p_uid uuid, p_outcome text, p_deck_bracket integer, p_source text,
                                                  p_match uuid, p_ai_game uuid, p_crushed boolean) returns jsonb
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
    -- A crushing loss (mm_ranked_ai_settle: the AI kept 30 of its 40 life) costs two pips above Bronze.
    v_delta := -(array[0, 1, 1, 1, 1, 1])[v_tier + 1] * (case when p_crushed and v_tier > 0 then 2 else 1 end);
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
  -- `crushed` rides beside `bonuses` (older apps decode only the bonuses they know).
  return jsonb_build_object('outcome', p_outcome, 'pointsBefore', s.points, 'pointsAfter', v_after, 'bonuses', to_jsonb(v_bonuses))
    || case when p_outcome = 'loss' and p_crushed and v_tier > 0 then jsonb_build_object('crushed', true) else '{}'::jsonb end;
end $$;
revoke all on function public.mm_ranked_apply(uuid, text, integer, text, uuid, uuid, boolean) from public, anon, authenticated;

-- The six-argument form (human matches, hand credits) is an ordinary result.
create or replace function public.mm_ranked_apply(p_uid uuid, p_outcome text, p_deck_bracket integer, p_source text,
                                                  p_match uuid, p_ai_game uuid) returns jsonb
language sql security definer set search_path = '' as $$
  select public.mm_ranked_apply(p_uid, p_outcome, p_deck_bracket, p_source, p_match, p_ai_game, false) $$;
revoke all on function public.mm_ranked_apply(uuid, text, integer, text, uuid, uuid) from public, anon, authenticated;

create or replace function public.mm_ranked_ai_settle(p_uid uuid, p_game uuid, p_result text, p_record jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  g public.ranked_ai_games%rowtype;
  v_settlement text := 'counted';
  v_check text;
  v_build text;
  v_change jsonb;
  v_ai_life integer;
begin
  if p_result not in ('win', 'loss', 'draw') then raise exception 'invalid_result' using errcode = '22023'; end if;
  select * into g from public.ranked_ai_games where id = p_game and user_id = p_uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if g.settled_at is null then
    -- Only tickets without a seed (older builds, no game record to count turns from) keep a clock floor.
    if p_result = 'win' and g.seed is null and g.created_at > now() - interval '2 minutes' then
      v_settlement := 'too_soon';
    elsif p_result = 'win' and g.seed is not null then
      v_check := public.mm_ranked_ai_record_check(g, p_record);
      if v_check is not null then v_settlement := 'unverified'; end if;
    end if;
    if p_result = 'win' and p_record is not null and octet_length(p_record::text) <= 524288 then
      begin
        v_build := left((p_record->>'setup')::jsonb->'engine'->>'engineBuild', 80);
      exception when others then v_build := null;
      end;
      insert into public.ranked_ai_records (game_id, head, engine_build, record)
      values (p_game, left(coalesce(p_record->>'head', ''), 64), v_build, p_record)
      on conflict (game_id) do nothing;
    end if;
    update public.ranked_ai_games set result = p_result, settlement = v_settlement, settled_at = now(), record_check = v_check
     where id = p_game;
    if p_result = 'loss' then
      v_ai_life := public.mm_ranked_ai_life_left(g, p_record);
      update public.ranked_ai_games set ai_life_left = v_ai_life where id = p_game;
    end if;
    if v_settlement = 'counted' then
      v_change := public.mm_ranked_apply(p_uid, p_result, g.deck_bracket, 'ai', null, p_game, coalesce(v_ai_life >= 30, false));
    end if;
  else
    v_settlement := g.settlement;
    v_check := g.record_check;
  end if;
  -- `check` says why a win settled unverified (too_short, no_record, …), so the app can tell the player.
  return public.mm_ranked_standing() || jsonb_build_object('settlement', v_settlement, 'change', v_change, 'check', v_check);
end $$;
