-- Ranked AI tuning on the server (Caleb, 2026-10-26: "make this server side so we can do this without making build
-- updates"). Each tier's AI deck Power band and the AI's mistake chance from its lowest division (IV) to its highest (I).
-- A ranked ticket (mm_ranked_ai_start2) now carries the game's AI skill, mistake chance and deck Power target; apps that
-- read them pick the AI deck by that Power and pass aiMistakePercent to the engine. Older apps keep their bundled values
-- (ai-decks.json's rankedTiers, AIDifficulty's mistakes), which the record check still accepts.
--
-- First tuning (same day, Gold looked easy: 59-72% player wins against skills 1-3 over 14 days): Gold's Power band
-- 5-6 -> 5.5-6.5 and its mistakes 10% -> 8% at Gold IV down to 5% at Gold I. Every other tier keeps today's values.
-- Retune with an update to this table; no app build. Review Gold after about 50 games.

create table if not exists public.ranked_ai_tuning (
  tier smallint primary key check (tier between 0 and 5),
  power_low numeric(4, 2) not null check (power_low between 1 and 10),
  power_high numeric(4, 2) not null check (power_high between 1 and 10 and power_high >= power_low),
  mistakes_division_iv smallint not null check (mistakes_division_iv between 0 and 100),
  mistakes_division_i smallint not null check (mistakes_division_i between 0 and 100),
  updated_at timestamptz not null default now()
);
alter table public.ranked_ai_tuning enable row level security;
revoke all on public.ranked_ai_tuning from anon, authenticated;

-- Bronze 0 to Mythic 5 (Mythic has no divisions and takes the band's middle and division IV's mistakes).
insert into public.ranked_ai_tuning (tier, power_low, power_high, mistakes_division_iv, mistakes_division_i) values
  (0, 3, 4, 15, 15), (1, 4, 5, 15, 15), (2, 5.5, 6.5, 8, 5), (3, 6, 7, 0, 0), (4, 7, 8, 0, 0), (5, 8, 9, 0, 0)
on conflict (tier) do update set power_low = excluded.power_low, power_high = excluded.power_high,
  mistakes_division_iv = excluded.mistakes_division_iv, mistakes_division_i = excluded.mistakes_division_i, updated_at = now();

-- What a ticket issued, so its record is checked against it.
alter table public.ranked_ai_games add column if not exists ai_mistakes smallint, add column if not exists ai_power numeric(4, 2);

-- The AI for a ladder position: skill (mm_rank_ai_skill), mistake chance and deck Power target. The Power rises through
-- the tier like the apps' AIDeckPool.rankedTarget: division IV at 1/8 of the band, I at 7/8, Mythic in the middle.
create or replace function public.mm_ranked_ai_tuning_for(p_points integer) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'aiSkill', public.mm_rank_ai_skill(p_points),
    'aiMistakePercent', case when s.step >= 20 then t.mistakes_division_iv
      else round(t.mistakes_division_iv + (t.mistakes_division_i - t.mistakes_division_iv) * (s.step % 4) / 3.0)::int end,
    'aiPower', round(case when s.step >= 20 then (t.power_low + t.power_high) / 2
      else t.power_low + (t.power_high - t.power_low) * ((s.step % 4) + 0.5) / 4 end, 2))
  from (select public.mm_rank_points_step(p_points) as step) s
  join public.ranked_ai_tuning t on t.tier = least(s.step / 4, 5) $$;
revoke all on function public.mm_ranked_ai_tuning_for(integer) from public, anon, authenticated;

-- A ranked game against the AI begins: the ticket, its seed (as text: JSON numbers lose precision past 2^53), and the AI
-- this game plays (skill, mistake chance, deck Power target).
create or replace function public.mm_ranked_ai_start2(p_deck_bracket integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_id uuid := public.mm_ranked_ai_start(p_deck_bracket);
  -- 64 bits from gen_random_uuid's strong randomness.
  v_seed bigint := ('x' || left(md5(gen_random_uuid()::text || gen_random_uuid()::text), 16))::bit(64)::bigint;
  v_ai jsonb := public.mm_ranked_ai_tuning_for((public.mm_ranked_current(v_uid)).points);
begin
  update public.ranked_ai_games
     set seed = v_seed, ai_skill = (v_ai->>'aiSkill')::int, ai_mistakes = (v_ai->>'aiMistakePercent')::int,
         ai_power = (v_ai->>'aiPower')::numeric
   where id = v_id;
  return jsonb_build_object('id', v_id, 'seed', v_seed::text) || v_ai;
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

  -- 3. A released engine build, two seats (one human, one AI) and the tier's AI settings: the ticket's mistake chance, or the
  --    skill's standard one (apps that predate ranked_ai_tuning).
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
       or (v_ai->>'aiMistakePercent')::int not in (coalesce(p_game.ai_mistakes, -1), public.mm_ai_engine_mistakes((v_ai->>'aiSkill')::int)) then
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
