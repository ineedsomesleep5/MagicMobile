-- A ranked AI result also says why a win didn't count (`check`: too_short, no_record, …), so the result screen and the
-- game history can tell the player instead of a win quietly adding nothing.

-- The result of a ticket, once, with the game record (required for a win on a seeded ticket). Shared by both entry points.
create or replace function public.mm_ranked_ai_settle(p_uid uuid, p_game uuid, p_result text, p_record jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  g public.ranked_ai_games%rowtype;
  v_settlement text := 'counted';
  v_check text;
  v_build text;
  v_change jsonb;
begin
  if p_result not in ('win', 'loss', 'draw') then raise exception 'invalid_result' using errcode = '22023'; end if;
  select * into g from public.ranked_ai_games where id = p_game and user_id = p_uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if g.settled_at is null then
    -- Only tickets without a seed (older builds, no game record to count turns from) keep a clock floor.
    if p_result = 'win' and g.seed is null and g.created_at > now() - interval '2 minutes' then
      v_settlement := 'too_soon';
    elsif p_result = 'win' and (select count(*) from public.ranked_results r
                                 where r.user_id = p_uid and r.source = 'ai' and r.outcome = 'win'
                                   and r.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc') >= 12 then
      v_settlement := 'capped';
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
    if v_settlement = 'counted' then
      v_change := public.mm_ranked_apply(p_uid, p_result, g.deck_bracket, 'ai', null, p_game);
    end if;
  else
    v_settlement := g.settlement;
    v_check := g.record_check;
  end if;
  -- `check` says why a win settled unverified (too_short, no_record, …), so the app can tell the player.
  return public.mm_ranked_standing() || jsonb_build_object('settlement', v_settlement, 'change', v_change, 'check', v_check);
end $$;
