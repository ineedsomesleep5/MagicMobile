-- Platinum retune (Caleb, 2026-10-28, from 254DADDY's report that leaving Platinum is too hard). Since the 2026-10-26
-- tuning, Platinum brought Diamond's decks (Power 7–8) with no AI mistakes, and a crushing loss cost two pips while a
-- Platinum win earns one: he won 45 of 82 Platinum games and still finished two pips down.
--
-- 1. Platinum's AI now runs on from Gold I to Diamond IV: Power 6.75–7.75 (divisions IV → I: 6.88, 7.13, 7.38, 7.63)
--    with 2 → 0 mistakes in a hundred (2, 1, 1, 0).
-- 2. A crushing loss costs one pip in Platinum, like any loss there. It still costs two from Silver to Gold, where a win
--    earns two, and from Diamond up.

update public.ranked_ai_tuning
   set power_low = 6.75, power_high = 7.75, mistakes_division_iv = 2, mistakes_division_i = 0, updated_at = now()
 where tier = 3;

create or replace function public.mm_ranked_ai_settle(p_uid uuid, p_game uuid, p_result text, p_record jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  g public.ranked_ai_games%rowtype;
  v_settlement text := 'counted';
  v_check text;
  v_build text;
  v_change jsonb;
  v_ai_life integer;
  v_platinum boolean;
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
      -- Platinum (steps 12–15) wins earn one pip, so a crushing loss there costs one too.
      v_platinum := public.mm_rank_points_step((public.mm_ranked_current(p_uid)).points) / 4 = 3;
      v_change := public.mm_ranked_apply(p_uid, p_result, g.deck_bracket, 'ai', null, p_game,
                                         coalesce(v_ai_life >= 30, false) and not v_platinum);
    end if;
  else
    v_settlement := g.settlement;
    v_check := g.record_check;
  end if;
  -- `check` says why a win settled unverified (too_short, no_record, …), so the app can tell the player.
  return public.mm_ranked_standing() || jsonb_build_object('settlement', v_settlement, 'change', v_change, 'check', v_check);
end $function$;
