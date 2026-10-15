-- The server keeps score for ranked (20261015120000_ranked_referee.sql). Calls are made as authenticated
-- players; timestamps are moved back as the superuser to stand in for waiting.
-- d7…0005 published Platinum IV with 2 pips (peak Platinum III) before the migration (ranked_referee_before.sql).
begin;
insert into auth.users(id,aud,role,email) values
 ('d7000000-0000-0000-0000-000000000001','authenticated','authenticated','ref-one@example.invalid'),
 ('d7000000-0000-0000-0000-000000000002','authenticated','authenticated','ref-two@example.invalid'),
 ('d7000000-0000-0000-0000-000000000003','authenticated','authenticated','ref-three@example.invalid'),
 ('d7000000-0000-0000-0000-000000000004','authenticated','authenticated','ref-four@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
select public.mm_claim_username('RefOne');
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000002',true);
select public.mm_claim_username('RefTwo');
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000003',true);
select public.mm_claim_username('RefThree');
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000004',true);
select public.mm_claim_username('RefFour');

-- A standing published before the migration carries over as it was.
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000005',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_standing();
  if (r->>'points')::int <> 50 or (r->>'peakPoints')::int <> 52 or (r->>'wins')::int <> 7 or (r->>'seeded')::boolean is not true then
    raise exception 'imported standing wrong: %', r; end if;
  -- Publishing rank numbers no longer changes them; the title still sets.
  perform public.mm_ranked_publish(to_char(now() at time zone 'utc', 'YYYY-MM'), 20, 50, 20, 99, 0, 'Champion', 'Atraxa');
  r := public.mm_profile_card('RefFive');
  if (r->>'rankStep')::int <> 12 or (r->>'pips')::int <> 2 or (r->>'wins')::int <> 7 or r->>'title' <> 'Champion' then
    raise exception 'publish changed the rank: %', r; end if;
end $t$;

-- A fresh player may seed once, capped at Gold IV.
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000004',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_standing();
  if (r->>'seeded')::boolean or (r->>'points')::int <> 0 then raise exception 'fresh standing wrong: %', r; end if;
  r := public.mm_ranked_seed(70, 75, 12, 3);
  if (r->>'points')::int <> 32 or (r->>'peakPoints')::int <> 32 or (r->>'wins')::int <> 12 or not (r->>'seeded')::boolean then
    raise exception 'seed not capped: %', r; end if;
  r := public.mm_ranked_seed(10, 10, 0, 0);
  if (r->>'points')::int <> 32 then raise exception 'seeded twice: %', r; end if;
end $t$;

-- Person vs person: RefOne waits, RefTwo is matched and hosts. Matching reports count for both.
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
select public.mm_ranked_enqueue('relay-1', 0, 2);
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 0, 2);
  if r->>'role' <> 'host' then raise exception 'not matched: %', r; end if;
  perform set_config('test.match1', r->>'matchId', true);
  perform public.mm_ranked_report((r->>'matchId')::uuid, 'win');
  -- Only one side so far: nothing counted yet, and the reporter is told one match is unsettled.
  r := public.mm_ranked_standing();
  if (r->>'points')::int <> 0 or (r->>'unsettled')::int <> 1 then raise exception 'counted before both reported: %', r; end if;
end $t$;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  perform public.mm_ranked_report(current_setting('test.match1')::uuid, 'loss');
  r := public.mm_ranked_standing();
  if (r->>'points')::int <> 0 or (r->>'losses')::int <> 1 then raise exception 'loser wrong (Bronze IV cannot fall): %', r; end if;
  -- Reporting again changes nothing.
  perform public.mm_ranked_report(current_setting('test.match1')::uuid, 'win');
  r := public.mm_ranked_standing();
  if (r->>'losses')::int <> 1 or (r->>'wins')::int <> 0 then raise exception 'second report counted: %', r; end if;
end $t$;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_standing();
  if (r->>'points')::int <> 1 or (r->>'wins')::int <> 1 or (r->>'winStreak')::int <> 1 or (r->>'unsettled')::int <> 0 then
    raise exception 'winner wrong: %', r; end if;
  r := public.mm_profile_card('RefTwo');
  if (r->>'rankStep')::int <> 0 or (r->>'pips')::int <> 1 or (r->>'wins')::int <> 1 then raise exception 'card not mirrored: %', r; end if;
end $t$;

-- Both claim the win: disputed, nothing changes.
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
select public.mm_ranked_enqueue('relay-1', 0, 2);
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 1, 2);
  perform set_config('test.match2', r->>'matchId', true);
  perform public.mm_ranked_report((r->>'matchId')::uuid, 'win');
end $t$;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
select public.mm_ranked_report(current_setting('test.match2')::uuid, 'win');
reset role;
do $t$ begin
  if (select settlement from public.ranked_matches where id = current_setting('test.match2')::uuid) <> 'disputed' then
    raise exception 'disagreement not disputed'; end if;
  if (select points from public.ranked_standings where user_id = 'd7000000-0000-0000-0000-000000000002') <> 1 then
    raise exception 'disputed match counted'; end if;
end $t$;

-- A lone report settles after an hour: the side that never reported left, a loss.
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
select public.mm_ranked_enqueue('relay-1', 0, 2);
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 1, 2);
  perform set_config('test.match3', r->>'matchId', true);
  perform public.mm_ranked_report((r->>'matchId')::uuid, 'win');
end $t$;
reset role;
update public.ranked_matches set host_reported_at = now() - interval '2 hours' where id = current_setting('test.match3')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_standing();
  if (r->>'losses')::int <> 2 then raise exception 'timeout not settled for the absent side: %', r; end if;
end $t$;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_standing();
  if (r->>'points')::int <> 2 or (r->>'wins')::int <> 2 then raise exception 'timeout win missing: %', r; end if;
end $t$;

-- The same pair counts at most three matches a day: a fourth agreed match today is capped.
reset role;
insert into public.ranked_matches (host, guest, host_result, guest_result, settlement, settled_at)
values ('d7000000-0000-0000-0000-000000000002', 'd7000000-0000-0000-0000-000000000001', 'win', 'loss', 'counted', now());
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
select public.mm_ranked_enqueue('relay-1', 0, 2);
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 2, 2);
  perform set_config('test.match4', r->>'matchId', true);
  perform public.mm_ranked_report((r->>'matchId')::uuid, 'win');
end $t$;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000001',true);
select public.mm_ranked_report(current_setting('test.match4')::uuid, 'loss');
reset role;
do $t$ begin
  if (select settlement from public.ranked_matches where id = current_setting('test.match4')::uuid) <> 'capped' then
    raise exception 'fourth match of the day not capped'; end if;
  if (select points from public.ranked_standings where user_id = 'd7000000-0000-0000-0000-000000000002') <> 2 then
    raise exception 'capped match counted'; end if;
end $t$;

-- Against the AI: a ticket, then one result. A win needs four minutes; streak and underdog bonuses apply.
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000003',true);
do $t$ declare g uuid; r jsonb; begin
  g := public.mm_ranked_ai_start(2);
  r := public.mm_ranked_ai_result(g, 'win');
  if r->>'settlement' <> 'too_soon' or (r->>'points')::int <> 0 then raise exception 'instant win counted: %', r; end if;
  r := public.mm_ranked_ai_result(g, 'win');
  if r->>'settlement' <> 'too_soon' then raise exception 'ticket answered twice: %', r; end if;
  begin perform public.mm_ranked_ai_result(gen_random_uuid(), 'win'); raise exception 'unknown ticket accepted';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  begin perform public.mm_ranked_ai_start(9); raise exception 'bad bracket accepted';
  exception when others then if sqlerrm <> 'invalid_bracket' then raise; end if; end;
  -- A loss counts at once.
  g := public.mm_ranked_ai_start(2);
  r := public.mm_ranked_ai_result(g, 'loss');
  if r->>'settlement' <> 'counted' or (r->>'losses')::int <> 1 then raise exception 'loss not counted: %', r; end if;
  -- Three tickets for wins, plus one with a Bracket 1 deck (below Bronze's opponents: underdog).
  perform set_config('test.g1', public.mm_ranked_ai_start(2)::text, true);
  perform set_config('test.g2', public.mm_ranked_ai_start(2)::text, true);
  perform set_config('test.g3', public.mm_ranked_ai_start(2)::text, true);
  perform set_config('test.g4', public.mm_ranked_ai_start(1)::text, true);
end $t$;
reset role;
update public.ranked_ai_games set created_at = now() - interval '30 minutes'
 where user_id = 'd7000000-0000-0000-0000-000000000003' and settled_at is null;
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000003',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_ai_result(current_setting('test.g1')::uuid, 'win');
  if (r->>'points')::int <> 1 then raise exception 'first win wrong: %', r; end if;
  r := public.mm_ranked_ai_result(current_setting('test.g2')::uuid, 'win');
  if (r->>'points')::int <> 2 then raise exception 'second win wrong: %', r; end if;
  -- Third straight win below Gold: +2.
  r := public.mm_ranked_ai_result(current_setting('test.g3')::uuid, 'win');
  if (r->>'points')::int <> 4 or not (r->'change'->'bonuses') ? 'streak' then raise exception 'streak bonus missing: %', r; end if;
  -- Fourth straight with a Bracket 1 deck: streak + underdog, +3. Bronze III has one division left to fill.
  r := public.mm_ranked_ai_result(current_setting('test.g4')::uuid, 'win');
  if (r->>'points')::int <> 7 or not (r->'change'->'bonuses') ? 'underdog' then raise exception 'underdog bonus missing: %', r; end if;
end $t$;

-- At most twelve AI wins count a day.
reset role;
insert into public.ranked_results (user_id, season, source, outcome, points_before, points_after)
select 'd7000000-0000-0000-0000-000000000003', public.mm_current_season(), 'ai', 'win', 7, 7 from generate_series(1, 8);
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000003',true);
select set_config('test.g5', public.mm_ranked_ai_start(2)::text, true);
reset role;
update public.ranked_ai_games set created_at = now() - interval '30 minutes' where id = current_setting('test.g5')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000003',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_ai_result(current_setting('test.g5')::uuid, 'win');
  if r->>'settlement' <> 'capped' or (r->>'points')::int <> 7 then raise exception 'thirteenth AI win counted: %', r; end if;
  -- A ticket never answered within twelve hours is a loss.
  perform set_config('test.g6', public.mm_ranked_ai_start(2)::text, true);
end $t$;
reset role;
update public.ranked_ai_games set created_at = now() - interval '13 hours' where id = current_setting('test.g6')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000003',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_standing();
  if (r->>'points')::int <> 6 or (r->>'losses')::int <> 2 or (r->>'winStreak')::int <> 0 then raise exception 'abandoned game not a loss: %', r; end if;
end $t$;

-- A new month: last season into history, one tier down with empty pips.
reset role;
update public.ranked_standings set season = '2026-01', points = 50, peak_points = 53
 where user_id = 'd7000000-0000-0000-0000-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000003',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_standing();
  if r->>'season' <> to_char(now() at time zone 'utc', 'YYYY-MM') or (r->>'points')::int <> 32 or (r->>'wins')::int <> 0
     or r->'history'->0->>'season' <> '2026-01' or (r->'history'->0->>'finalPoints')::int <> 50 then
    raise exception 'rollover wrong: %', r; end if;
end $t$;

-- No direct table access, no internal helpers, nothing for signed-out callers.
do $t$ begin
  begin perform 1 from public.ranked_standings limit 1; raise exception 'standings readable';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.ranked_ai_games limit 1; raise exception 'AI tickets readable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_ranked_apply('d7000000-0000-0000-0000-000000000003', 'win', 1, 'ai', null, null); raise exception 'apply callable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_ranked_settle(gen_random_uuid()); raise exception 'settle callable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
set local role anon;
do $t$ begin
  begin perform public.mm_ranked_standing(); raise exception 'anon read a standing';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

-- Deleting an account removes its standing, history, results and tickets.
delete from auth.users where id = 'd7000000-0000-0000-0000-000000000003';
do $t$ begin
  if exists (select 1 from public.ranked_standings where user_id = 'd7000000-0000-0000-0000-000000000003')
     or exists (select 1 from public.ranked_results where user_id = 'd7000000-0000-0000-0000-000000000003')
     or exists (select 1 from public.ranked_ai_games where user_id = 'd7000000-0000-0000-0000-000000000003')
     or exists (select 1 from public.ranked_season_history where user_id = 'd7000000-0000-0000-0000-000000000003') then
    raise exception 'ranked rows kept after deletion'; end if;
end $t$;
rollback;
