-- Ranked AI wins judged by turns, not minutes (Caleb, 2026-10-26). A seeded win no longer needs four minutes since the
-- ticket: its game record's turn count decides, by bracket (mm_ranked_ai_record_check step 7). Tickets without a seed
-- keep a two-minute floor. Seeded wins the old rule held back are re-settled
-- when their records pass (on 2026-10-26: Caleb's two, turns 11 and 13).

-- Null when the record backs a win on this ticket, otherwise why not.
create or replace function public.mm_ranked_ai_record_check(p_game public.ranked_ai_games, p_record jsonb) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_setup jsonb;
  v_end jsonb;
  v_setup_text text := p_record->>'setup';
  v_end_text text := p_record->>'end';
  v_entries jsonb := p_record->'entries';
  v_marks jsonb := p_record->'marks';
  v_count integer;
  v_hash bytea;
  v_entry text;
  v_human text;
  v_human_index integer;
  v_ai jsonb;
  v_ai_index integer;
  v_turn integer;
  v_last_turn integer := 0;
  v_last_index integer := -1;
  v_mark text[];
  v_min_turn integer := case when coalesce(p_game.deck_bracket, 1) >= 5 then 3 else 5 end;
begin
  if p_record is null then return 'no_record'; end if;
  if octet_length(p_record::text) > 524288 then return 'too_large'; end if;
  if p_record->>'format' is distinct from 'magicmobile-game-record' or p_record->'version' is distinct from '1'::jsonb
     or jsonb_typeof(v_entries) is distinct from 'array' or jsonb_typeof(v_marks) is distinct from 'array'
     or v_setup_text is null or v_end_text is null or p_record->>'head' !~ '^[0-9a-f]{64}$' then
    return 'format';
  end if;
  if p_record ? 'broken' then return 'broken'; end if;
  begin
    v_setup := v_setup_text::jsonb;
    v_end := v_end_text::jsonb;
  exception when others then return 'format';
  end;

  -- 1. Integrity: h0 = SHA-256(setup), hi = SHA-256(hi-1 ‖ "\n" ‖ entry), head = SHA-256(hn ‖ "\n" ‖ end).
  v_count := jsonb_array_length(v_entries);
  if v_count > 20000 then return 'entries'; end if;
  v_hash := sha256(convert_to(v_setup_text, 'UTF8'));
  for v_entry in select e.value from jsonb_array_elements_text(v_entries) with ordinality e(value, n) order by e.n loop
    v_hash := sha256(v_hash || '\x0a'::bytea || convert_to(v_entry, 'UTF8'));
  end loop;
  v_hash := sha256(v_hash || '\x0a'::bytea || convert_to(v_end_text, 'UTF8'));
  if encode(v_hash, 'hex') <> p_record->>'head' then return 'hash'; end if;

  -- 2. This ticket's seed, so one seed is one game.
  if p_game.seed is null or v_setup->>'seed' is distinct from p_game.seed::text then return 'seed'; end if;

  -- 3. A released engine build, two seats (one human, one AI) and the tier's AI settings.
  if not exists (select 1 from public.ranked_engine_builds b where b.engine_build = v_setup->'engine'->>'engineBuild') then
    return 'engine_build';
  end if;
  if jsonb_typeof(v_setup->'seats') is distinct from 'array' or jsonb_array_length(v_setup->'seats') <> 2 then return 'seats'; end if;
  select s.value->>'seatId', s.n - 1 into v_human, v_human_index
    from jsonb_array_elements(v_setup->'seats') with ordinality s(value, n) where s.value->>'controller' = 'human';
  select s.value, s.n - 1 into v_ai, v_ai_index
    from jsonb_array_elements(v_setup->'seats') with ordinality s(value, n) where s.value->>'controller' = 'ai';
  if v_human is null or v_ai is null then return 'seats'; end if;
  begin
    -- A tier's lag of one (a loss the server has not applied yet) is allowed; a harder AI always is.
    if (v_ai->>'aiSkill')::int < coalesce(p_game.ai_skill, 1) - 1
       or (v_ai->>'aiSearchDepth')::int <> public.mm_ai_engine_depth((v_ai->>'aiSkill')::int)
       or (v_ai->>'aiMistakePercent')::int <> public.mm_ai_engine_mistakes((v_ai->>'aiSkill')::int) then
      return 'ai_settings';
    end if;
  exception when others then return 'ai_settings';
  end;

  -- 4. The end says the human won and the AI lost, after every entry.
  begin
    if v_end->>'state' is distinct from 'ended' or (v_end->>'entries')::int <> v_count
       or v_end->'winners' <> jsonb_build_array(v_human)
       or not exists (select 1 from jsonb_array_elements(v_end->'seats') s
                       where s->>'seatId' = v_ai->>'seatId' and (s->>'lost')::boolean) then
      return 'end';
    end if;
    v_turn := (v_end->>'turn')::int;
  exception when others then return 'end';
  end;

  -- 5. Marks start at turn 1, entry 0; turns and indexes only increase; the last is the final turn.
  for v_entry in select m.value from jsonb_array_elements_text(v_marks) with ordinality m(value, n) order by m.n loop
    v_mark := regexp_match(v_entry, '^([0-9]{1,4}) ([0-9]{1,5}) [0-9a-f]{8}$');
    if v_mark is null or v_mark[1]::int <= v_last_turn or v_mark[2]::int < v_last_index or v_mark[2]::int >= greatest(v_count, 1)
       or (v_last_turn = 0 and (v_mark[1]::int <> 1 or v_mark[2]::int <> 0)) then
      return 'marks';
    end if;
    v_last_turn := v_mark[1]::int;
    v_last_index := v_mark[2]::int;
  end loop;
  if v_last_turn <> v_turn then return 'marks'; end if;

  -- 6. Every entry is "<seat><op>[ args]" for these two seats (or a restore point), and nobody conceded:
  --    an AI never concedes, and a human concede means the human lost.
  if exists (select 1 from jsonb_array_elements_text(v_entries) e
              where e !~ '^(-R|[01][A-Za-z]( .*)?)$' or e ~ '^[01]c( |$)') then
    return 'grammar';
  end if;

  -- 7. Bounds by bracket (Caleb, 2026-10-26): a win inside the first two rounds (turn 4 or earlier; XMage counts each
  --    player's turn) is suspect up to bracket 4; bracket 5 may win from round two. Clock time is no measure: a fast
  --    deck can win in a minute, so the only time check is four seconds a turn.
  if v_turn < v_min_turn then return 'too_short'; end if;
  if now() - p_game.created_at < make_interval(secs => v_turn * 4) then return 'too_fast'; end if;
  return null;
end $$;

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
  end if;
  return public.mm_ranked_standing() || jsonb_build_object('settlement', v_settlement, 'change', v_change);
end $$;

-- Re-settle the wins the four-minute rule held back, where the record now passes. Oldest first, so the ladder applies
-- them in order.
do $$
declare
  g public.ranked_ai_games%rowtype;
begin
  for g in select * from public.ranked_ai_games
            where result = 'win' and settlement = 'too_soon' and seed is not null
            order by created_at loop
    if public.mm_ranked_ai_record_check(g, (select r.record from public.ranked_ai_records r where r.game_id = g.id)) is null then
      update public.ranked_ai_games set settlement = 'counted' where id = g.id;
      perform public.mm_ranked_apply(g.user_id, 'win', g.deck_bracket, 'ai', null, g.id);
    end if;
  end loop;
end $$;
