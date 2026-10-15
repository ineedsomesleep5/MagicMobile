-- Ranked AI wins checked against the engine's game record (program Phase 5, R3; docs/cloud/game-record.md).
--
-- mm_ranked_ai_start2 issues the ticket with a server seed and remembers the tier's AI skill. The app passes the seed
-- to the engine's `create`, and with a result sends the game record (mm_ranked_ai_result2). Before a win counts, the
-- cheap checks below run in SQL: the hash chain, the seed, a released engine build, two seats, the tier's AI settings,
-- an end that says the human won, the turn marks, the entry grammar and the time since the ticket. A win that fails
-- them settles as `unverified` (no rank change) and its record is kept for review. Losses and draws always count.
--
-- What this cannot prove (the doc's "What these checks cannot prove"): a modified app can write a consistent record by
-- hand, and the AI's choices are recorded, not recomputed. Tickets from mm_ranked_ai_start (older builds, no seed) keep
-- today's rules until those builds are retired.

alter table public.ranked_ai_games add column if not exists seed bigint;
-- The tier's AI skill when the ticket was issued (null on older tickets).
alter table public.ranked_ai_games add column if not exists ai_skill integer check (ai_skill between 1 and 10);
-- Why a win settled as unverified.
alter table public.ranked_ai_games add column if not exists record_check text;
alter table public.ranked_ai_games drop constraint if exists ranked_ai_games_settlement_check;
alter table public.ranked_ai_games add constraint ranked_ai_games_settlement_check
  check (settlement in ('counted', 'too_soon', 'capped', 'abandoned', 'unverified'));

-- Engine builds whose records count: each release adds its EngineBuildIdentity (scripts/engine_build_identity.py).
create table if not exists public.ranked_engine_builds (
  engine_build text primary key check (engine_build ~ '^sha256:[0-9a-f]{64}$'),
  label text not null,
  added_at timestamptz not null default now()
);

-- The record sent with a ranked AI win, kept with the game (deleted with it after 30 days).
create table if not exists public.ranked_ai_records (
  game_id uuid primary key references public.ranked_ai_games (id) on delete cascade,
  head text not null,
  engine_build text,
  record jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.ranked_engine_builds enable row level security;
alter table public.ranked_ai_records enable row level security;
revoke all on public.ranked_engine_builds, public.ranked_ai_records from anon, authenticated;

-- The AI skill for a ladder position: Bronze 1 to Mythic 6 (RankTier.aiSkill on both apps).
create or replace function public.mm_rank_ai_skill(p_points integer) returns integer
language sql immutable set search_path = '' as $$ select least(public.mm_rank_points_step(p_points) / 4, 5) + 1 $$;

-- The search depth and mistake chance the engine plays a skill with (AIDifficulty.java; C3's tuning). Keep in step.
create or replace function public.mm_ai_engine_depth(p_skill integer) returns integer
language sql immutable set search_path = '' as $$
  select case when p_skill <= 2 then p_skill + 1 else greatest(4, p_skill) end $$;
create or replace function public.mm_ai_engine_mistakes(p_skill integer) returns integer
language sql immutable set search_path = '' as $$
  select case p_skill when 1 then 15 when 2 then 15 when 3 then 10 else 0 end $$;

-- A ranked game against the AI begins: the ticket, its seed (as text: JSON numbers lose precision past 2^53) and skill.
create or replace function public.mm_ranked_ai_start2(p_deck_bracket integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_id uuid := public.mm_ranked_ai_start(p_deck_bracket);
  -- 64 bits from gen_random_uuid's strong randomness.
  v_seed bigint := ('x' || left(md5(gen_random_uuid()::text || gen_random_uuid()::text), 16))::bit(64)::bigint;
  v_skill integer := public.mm_rank_ai_skill((public.mm_ranked_current(v_uid)).points);
begin
  update public.ranked_ai_games set seed = v_seed, ai_skill = v_skill where id = v_id;
  return jsonb_build_object('id', v_id, 'seed', v_seed::text, 'aiSkill', v_skill);
end $$;

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

  -- 7. Bounds: a 40-life Commander win takes at least four turns, and the turns took time.
  if v_turn < 4 then return 'too_short'; end if;
  if now() - p_game.created_at < make_interval(secs => v_turn * 5) then return 'too_fast'; end if;
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
    if p_result = 'win' and g.created_at > now() - interval '4 minutes' then
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

create or replace function public.mm_ranked_ai_result(p_game uuid, p_result text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  return public.mm_ranked_ai_settle(public.mm_require_profile(), p_game, p_result, null);
end $$;

create or replace function public.mm_ranked_ai_result2(p_game uuid, p_result text, p_record jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  return public.mm_ranked_ai_settle(public.mm_require_profile(), p_game, p_result, p_record);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'mm_rank_ai_skill(integer)', 'mm_ai_engine_depth(integer)', 'mm_ai_engine_mistakes(integer)',
    'mm_ranked_ai_start2(integer)', 'mm_ranked_ai_record_check(public.ranked_ai_games, jsonb)',
    'mm_ranked_ai_settle(uuid, uuid, text, jsonb)', 'mm_ranked_ai_result(uuid, text)', 'mm_ranked_ai_result2(uuid, text, jsonb)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  foreach f in array array['mm_ranked_ai_record_check(public.ranked_ai_games, jsonb)', 'mm_ranked_ai_settle(uuid, uuid, text, jsonb)']
  loop
    execute format('revoke all on function public.%s from authenticated', f);
  end loop;
  foreach f in array array['mm_ranked_ai_start2(integer)', 'mm_ranked_ai_result(uuid, text)', 'mm_ranked_ai_result2(uuid, text, jsonb)']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
