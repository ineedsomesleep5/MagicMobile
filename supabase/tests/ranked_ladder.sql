-- Ranked queue, matches and ranked cards, every call made as an authenticated player.
begin;
insert into auth.users(id,aud,role,email) values
 ('b5000000-0000-0000-0000-000000000001','authenticated','authenticated','ranked-one@example.invalid'),
 ('b5000000-0000-0000-0000-000000000002','authenticated','authenticated','ranked-two@example.invalid'),
 ('b5000000-0000-0000-0000-000000000003','authenticated','authenticated','ranked-three@example.invalid'),
 ('b5000000-0000-0000-0000-000000000004','authenticated','authenticated','ranked-four@example.invalid');
set local role authenticated;
-- Usernames first: the queue is for profiles.
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000001',true);
do $t$ begin
  begin perform public.mm_ranked_enqueue('relay-1', 8, 2); raise exception 'queue without a username';
  exception when others then if sqlerrm <> 'no_username' then raise; end if; end;
  perform public.mm_claim_username('RankOne');
end $t$;
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000002',true);
select public.mm_claim_username('RankTwo');
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000003',true);
select public.mm_claim_username('RankThree');
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000004',true);
select public.mm_claim_username('RankFour');

-- One waits; a far-off rank, another protocol and a blocked player are never paired with them.
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 8, 2);
  if r->>'status' <> 'waiting' or r->>'role' is not null then raise exception 'first ticket not waiting: %', r; end if;
  perform set_config('test.ticket1', r->>'ticket', true);
  begin perform public.mm_ranked_enqueue('relay-1', 21, 2); raise exception 'bad rank accepted';
  exception when others then if sqlerrm <> 'invalid_ticket' then raise; end if; end;
  -- The failed call rolled back nothing that matters: re-queue.
  r := public.mm_ranked_enqueue('relay-1', 8, 2);
  perform set_config('test.ticket1', r->>'ticket', true);
  perform public.mm_block('RankFour');
end $t$;
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000003',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 16, 2);
  if r->>'status' <> 'waiting' then raise exception 'rank 16 matched rank 8: %', r; end if;
  r := public.mm_ranked_cancel((r->>'ticket')::uuid);
  if r->>'status' <> 'cancelled' then raise exception 'cancel failed: %', r; end if;
  r := public.mm_ranked_enqueue('relay-2', 8, 2);
  if r->>'status' <> 'waiting' then raise exception 'other protocol matched: %', r; end if;
  perform public.mm_ranked_cancel((r->>'ticket')::uuid);
  r := public.mm_ranked_enqueue('relay-1', 8, 4);
  if r->>'status' <> 'waiting' then raise exception 'bracket 4 matched bracket 2: %', r; end if;
  perform public.mm_ranked_cancel((r->>'ticket')::uuid);
end $t$;
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000004',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 8, 2);
  if r->>'status' <> 'waiting' then raise exception 'blocked player matched: %', r; end if;
  perform public.mm_ranked_cancel((r->>'ticket')::uuid);
end $t$;

-- A suitable player is matched at once and hosts; the waiting player learns of it and the table code.
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_enqueue('relay-1', 10, 3);
  if r->>'status' <> 'matched' or r->>'role' <> 'host' or r->>'opponent' <> 'RankOne' or (r->>'opponentStep')::int <> 8 then
    raise exception 'host match wrong: %', r; end if;
  perform set_config('test.match', r->>'matchId', true);
  perform public.mm_ranked_set_table((r->>'matchId')::uuid, 'ABCDEF');
  begin perform public.mm_ranked_set_table((r->>'matchId')::uuid, 'bad'); raise exception 'bad code accepted';
  exception when others then if sqlerrm <> 'invalid_code' then raise; end if; end;
end $t$;
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_poll(current_setting('test.ticket1')::uuid);
  if r->>'status' <> 'matched' or r->>'role' <> 'guest' or r->>'tableCode' <> 'ABCDEF' or r->>'opponent' <> 'RankTwo' then
    raise exception 'guest poll wrong: %', r; end if;
  -- Cancelling after the match keeps the match.
  r := public.mm_ranked_cancel(current_setting('test.ticket1')::uuid);
  if r->>'status' <> 'matched' then raise exception 'late cancel undid match: %', r; end if;
  -- The guest can't set the table.
  begin perform public.mm_ranked_set_table(current_setting('test.match')::uuid, 'GHJKLM'); raise exception 'guest set table';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  perform public.mm_ranked_report(current_setting('test.match')::uuid, 'loss');
  perform public.mm_ranked_report(current_setting('test.match')::uuid, 'win');
end $t$;
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  perform public.mm_ranked_report(current_setting('test.match')::uuid, 'win');
  -- Another player's ticket reads as cancelled, never as theirs.
  r := public.mm_ranked_poll(current_setting('test.ticket1')::uuid);
  if r->>'status' <> 'cancelled' or r ? 'opponent' then raise exception 'foreign ticket leaked: %', r; end if;
end $t$;

-- Ranked cards: published standings are visible to friends and on a card, never to blocked players.
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; n int; begin
  perform public.mm_ranked_publish('2026-10', 9, 37, 10, 4, 2, 'Rising Star', 'Krenko, Mob Boss');
  begin perform public.mm_ranked_publish('2026-10', 30, 37, 10, 4, 2, null, null); raise exception 'bad step accepted';
  exception when others then if sqlerrm <> 'invalid_rank' then raise; end if; end;
  perform public.mm_friend_request('RankTwo');
  r := public.mm_profile_card('RankTwo');
  if r->>'username' <> 'RankTwo' or r->>'rankStep' is not null then raise exception 'unranked card wrong: %', r; end if;
end $t$;
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; n int; begin
  perform public.mm_friend_request('RankOne');
  select count(*) into n from public.mm_friend_ranks() where username = 'RankOne' and rank_step = 9 and title = 'Rising Star';
  if n <> 1 then raise exception 'friend rank missing'; end if;
  r := public.mm_profile_card('rankone');
  if (r->>'rankStep')::int <> 9 or (r->>'wins')::int <> 4 or r->>'favoriteCommander' <> 'Krenko, Mob Boss' then
    raise exception 'card wrong: %', r; end if;
end $t$;
select set_config('request.jwt.claim.sub','b5000000-0000-0000-0000-000000000004',true);
do $t$ begin
  begin perform public.mm_profile_card('RankOne'); raise exception 'blocked card visible';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
end $t$;
-- No direct table access.
do $t$ begin
  begin perform 1 from public.ranked_queue limit 1; raise exception 'queue readable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_ranked_ticket('b5000000-0000-0000-0000-000000000001', gen_random_uuid()); raise exception 'ticket helper callable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
-- Deleting an account removes its tickets and card; matches keep the other side.
delete from auth.users where id = 'b5000000-0000-0000-0000-000000000002';
do $t$ begin
  if exists (select 1 from public.ranked_queue where user_id = 'b5000000-0000-0000-0000-000000000002') then raise exception 'tickets kept'; end if;
  if not exists (select 1 from public.ranked_matches where id = current_setting('test.match')::uuid and host is null and guest is not null) then
    raise exception 'match not kept'; end if;
end $t$;
rollback;
