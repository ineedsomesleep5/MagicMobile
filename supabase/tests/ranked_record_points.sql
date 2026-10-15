-- The rank history comes from the server (20261015180000_ranked_record_points.sql): mm_record_game stores the
-- caller's ranked_standings.points for a ranked game and ignores p_rank_points. Calls are made as authenticated
-- players; standings and tickets are moved as the superuser to stand in for waiting and for a new month.
-- d7…0005 (RefFive) carried Platinum IV with 2 pips (50 points) over from before the referee (ranked_referee_before.sql).
begin;
insert into auth.users(id,aud,role,email) values
 ('d8000000-0000-0000-0000-000000000001','authenticated','authenticated','points-one@example.invalid'),
 ('d8000000-0000-0000-0000-000000000002','authenticated','authenticated','points-two@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','d8000000-0000-0000-0000-000000000001',true);
select public.mm_claim_username('PointsOne');
select set_config('request.jwt.claim.sub','d8000000-0000-0000-0000-000000000002',true);
select public.mm_claim_username('PointsTwo');

-- A standing the phone may still seed has no rank yet: nothing stored, whatever the phone claims.
select set_config('request.jwt.claim.sub','d8000000-0000-0000-0000-000000000001',true);
do $t$ begin
  if not public.mm_record_game('e8000000-0000-0000-0000-000000000001', now() - interval '5 minutes', 'ranked', 'win', 'Krenko',
                               array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, null, 79) then
    raise exception 'unseeded ranked game not stored'; end if;
end $t$;

-- Seeded at 20 (Silver IV): the server's points are stored, not the phone's. An out-of-range claim no longer
-- rejects the game: it is ignored.
do $t$ declare r jsonb; begin
  r := public.mm_ranked_seed(20, 22, 4, 1);
  if (r->>'points')::int <> 20 then raise exception 'seed wrong: %', r; end if;
  perform public.mm_record_game('e8000000-0000-0000-0000-000000000002', now() - interval '4 minutes', 'ranked', 'win', 'Krenko',
                                array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, null, 79);
  perform public.mm_record_game('e8000000-0000-0000-0000-000000000003', now() - interval '3 minutes', 'ranked', 'loss', 'Krenko',
                                array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, null, 200000);
  -- Quick and casual games keep no points even when the phone sends some.
  perform public.mm_record_game('e8000000-0000-0000-0000-000000000004', now() - interval '2 minutes', 'quick', 'win', 'Krenko',
                                array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, null, 64);
  perform public.mm_record_game('e8000000-0000-0000-0000-000000000005', now() - interval '2 minutes', 'casual', 'win', 'Krenko',
                                array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, null, 64);
  -- A ranked game from an earlier month: the standing has rolled over since, so no points.
  perform public.mm_record_game('e8000000-0000-0000-0000-000000000006',
                                date_trunc('month', now() at time zone 'utc') at time zone 'utc' - interval '1 hour',
                                'ranked', 'win', 'Krenko', array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, null, 64);
  -- A ranked AI win counted by the server moves the stored points with it.
  perform set_config('test.ticket', public.mm_ranked_ai_start(2)::text, true);
end $t$;
reset role;
update public.ranked_ai_games set created_at = now() - interval '30 minutes' where id = current_setting('test.ticket')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','d8000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_ai_result(current_setting('test.ticket')::uuid, 'win');
  if (r->>'points')::int <> 21 then raise exception 'AI win not counted: %', r; end if;
  perform public.mm_record_game('e8000000-0000-0000-0000-000000000007', now() - interval '1 minute', 'ranked', 'win', 'Krenko',
                                array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 11, null, 0);
  -- Sending a game again changes nothing, its points included.
  if public.mm_record_game('e8000000-0000-0000-0000-000000000002', now() - interval '4 minutes', 'ranked', 'win', 'Krenko',
                           array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, null, 3) then
    raise exception 'game stored twice'; end if;
end $t$;
reset role;
do $t$ declare v jsonb; begin
  select jsonb_object_agg(client_id::text, coalesce(to_jsonb(rank_points), 'null'::jsonb)) into v
    from public.player_games where user_id = 'd8000000-0000-0000-0000-000000000001';
  if v <> jsonb_build_object('e8000000-0000-0000-0000-000000000001', null, 'e8000000-0000-0000-0000-000000000002', 20,
                             'e8000000-0000-0000-0000-000000000003', 20, 'e8000000-0000-0000-0000-000000000004', null,
                             'e8000000-0000-0000-0000-000000000005', null, 'e8000000-0000-0000-0000-000000000006', null,
                             'e8000000-0000-0000-0000-000000000007', 21) then
    raise exception 'stored rank points wrong: %', v; end if;
end $t$;

-- The public rank history shows the server's points, oldest first, and none of the phone's claims.
set local role authenticated;
select set_config('request.jwt.claim.sub','d8000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_public_profile('PointsOne');
  if (select jsonb_agg(h->'points') from jsonb_array_elements(r->'rankHistory') h) <> '[20, 20, 21]'::jsonb then
    raise exception 'rank history wrong: %', r->'rankHistory'; end if;
end $t$;

-- A standing carried over from before the referee is a rank: RefFive's 50 points are stored.
select set_config('request.jwt.claim.sub','d7000000-0000-0000-0000-000000000005',true);
select public.mm_record_game('e8000000-0000-0000-0000-000000000008', now(), 'ranked', 'loss', 'Atraxa', array['Atraxa'], array['W','U','B','G'],
                             '[{"name":"Krenko","commander":"Krenko, Mob Boss","ai":true}]'::jsonb, 14, null, 99);
reset role;
do $t$ begin
  if (select rank_points from public.player_games where client_id = 'e8000000-0000-0000-0000-000000000008') is distinct from 50 then
    raise exception 'imported standing not stored'; end if;
end $t$;

-- A new month: the standing rolls over before its points are read (Platinum III with 2 pips, 54, drops a tier to
-- Gold III, 36).
insert into public.ranked_standings (user_id, season, points, peak_points, wins)
values ('d8000000-0000-0000-0000-000000000002', '2026-01', 54, 55, 1);
insert into public.ranked_results (user_id, season, source, outcome, points_before, points_after)
values ('d8000000-0000-0000-0000-000000000002', '2026-01', 'ai', 'win', 53, 54);
set local role authenticated;
select set_config('request.jwt.claim.sub','d8000000-0000-0000-0000-000000000002',true);
select public.mm_record_game('e8000000-0000-0000-0000-000000000009', now(), 'ranked', 'win', 'Edgar', array['Edgar Markov'], array['W','B','R'],
                             '[]'::jsonb, 10, null, 99);
reset role;
do $t$ begin
  if (select rank_points from public.player_games where client_id = 'e8000000-0000-0000-0000-000000000009') is distinct from 36 then
    raise exception 'rollover not applied before storing: %',
      (select rank_points from public.player_games where client_id = 'e8000000-0000-0000-0000-000000000009'); end if;
  if not exists (select 1 from public.ranked_season_history where user_id = 'd8000000-0000-0000-0000-000000000002'
                  and season = '2026-01' and final_points = 54) then
    raise exception 'rolled-over season not kept'; end if;
end $t$;

-- Signed-out callers still can't record games.
set local role anon;
do $t$ begin
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'ranked', 'win', 'D', array['A'], array['R'], '[]'::jsonb); raise exception 'anon recorded a game';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
rollback;
