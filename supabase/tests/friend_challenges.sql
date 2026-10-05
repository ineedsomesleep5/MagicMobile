-- Friend challenges, every call made as an authenticated player.
begin;
insert into auth.users(id,aud,role,email) values
 ('c6000000-0000-0000-0000-000000000001','authenticated','authenticated','challenge-one@example.invalid'),
 ('c6000000-0000-0000-0000-000000000002','authenticated','authenticated','challenge-two@example.invalid'),
 ('c6000000-0000-0000-0000-000000000003','authenticated','authenticated','challenge-three@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000001',true);
select public.mm_claim_username('DuelOne');
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000002',true);
select public.mm_claim_username('DuelTwo');
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000003',true);
select public.mm_claim_username('DuelThree');

-- Only friends can be challenged.
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000001',true);
do $t$ begin
  begin perform public.mm_challenge_send('DuelTwo', 'quick', 'relay-1', 8, 'ABCDEF'); raise exception 'challenged a stranger';
  exception when others then if sqlerrm <> 'not_friends' then raise; end if; end;
  perform public.mm_friend_request('DuelTwo');
  perform public.mm_friend_request('DuelThree');
end $t$;
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000002',true);
select public.mm_respond_friend('c6000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000003',true);
select public.mm_respond_friend('c6000000-0000-0000-0000-000000000001', true);

-- DuelTwo is Gold (step 8-11) this season; DuelThree published Gold last season, so is Silver now.
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000002',true);
select public.mm_ranked_publish(to_char(now() at time zone 'utc', 'YYYY-MM'), 9, 2, 9, 3, 1, null, null);
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000003',true);
select public.mm_ranked_publish('2020-01', 9, 2, 9, 3, 1, null, null);

select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  -- Bad input.
  begin perform public.mm_challenge_send('DuelTwo', 'casual', 'relay-1', 8, 'ABCDEF'); raise exception 'bad mode accepted';
  exception when others then if sqlerrm <> 'invalid_challenge' then raise; end if; end;
  begin perform public.mm_challenge_send('DuelTwo', 'quick', 'relay-1', 8, 'abc'); raise exception 'bad code accepted';
  exception when others then if sqlerrm <> 'invalid_challenge' then raise; end if; end;
  -- Ranked needs the same tier: Silver (4) can't challenge Gold, and Gold can't challenge last season's Gold.
  begin perform public.mm_challenge_send('DuelTwo', 'ranked', 'relay-1', 4, 'ABCDEF'); raise exception 'silver challenged gold';
  exception when others then if sqlerrm <> 'rank_mismatch' then raise; end if; end;
  begin perform public.mm_challenge_send('DuelThree', 'ranked', 'relay-1', 8, 'ABCDEF'); raise exception 'rollover ignored';
  exception when others then if sqlerrm <> 'rank_mismatch' then raise; end if; end;
  -- Quick needs no rank match.
  r := public.mm_challenge_send('DuelThree', 'quick', 'relay-1', 8, 'GHJKLM');
  if r->>'status' <> 'pending' or r->>'mode' <> 'quick' or r->>'role' <> 'challenger' or r->>'tableCode' <> 'GHJKLM' then
    raise exception 'quick challenge wrong: %', r; end if;
  perform set_config('test.quick', r->>'id', true);
  -- A new challenge replaces the pending one.
  r := public.mm_challenge_send('DuelTwo', 'ranked', 'relay-1', 11, 'ABCDEF');
  if r->>'status' <> 'pending' or r->>'mode' <> 'ranked' then raise exception 'ranked challenge wrong: %', r; end if;
  perform set_config('test.ranked', r->>'id', true);
  r := public.mm_challenge_status(current_setting('test.quick')::uuid);
  if r->>'status' <> 'cancelled' then raise exception 'old challenge not replaced: %', r; end if;
end $t$;

-- The replaced challenge no longer shows; the friend sees the new one without its code until they accept.
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000003',true);
do $t$ declare r jsonb; begin
  r := public.mm_challenge_incoming();
  if jsonb_array_length(r) <> 0 then raise exception 'replaced challenge still incoming: %', r; end if;
  begin perform public.mm_challenge_accept(current_setting('test.ranked')::uuid, 'relay-1', 8); raise exception 'stranger accepted';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  if public.mm_challenge_status(current_setting('test.ranked')::uuid)->>'status' <> 'cancelled' then
    raise exception 'someone else read the challenge'; end if;
end $t$;
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  r := public.mm_challenge_incoming();
  if jsonb_array_length(r) <> 1 or r->0->>'challenger' <> 'DuelOne' or r->0->>'mode' <> 'ranked' or r->0->>'tableCode' is not null then
    raise exception 'incoming wrong: %', r; end if;
  -- Another relay build or a tier change since the challenge can't accept.
  begin perform public.mm_challenge_accept(current_setting('test.ranked')::uuid, 'relay-2', 9); raise exception 'other build accepted';
  exception when others then if sqlerrm <> 'protocol_mismatch' then raise; end if; end;
  begin perform public.mm_challenge_accept(current_setting('test.ranked')::uuid, 'relay-1', 12); raise exception 'platinum accepted gold';
  exception when others then if sqlerrm <> 'rank_mismatch' then raise; end if; end;
  r := public.mm_challenge_accept(current_setting('test.ranked')::uuid, 'relay-1', 9);
  if r->>'status' <> 'accepted' or r->>'tableCode' <> 'ABCDEF' or r->>'matchId' is null or r->>'role' <> 'challenged' then
    raise exception 'accept wrong: %', r; end if;
  perform set_config('test.match', r->>'matchId', true);
  -- Accepting twice fails; the ranked match takes both reports.
  begin perform public.mm_challenge_accept(current_setting('test.ranked')::uuid, 'relay-1', 9); raise exception 'accepted twice';
  exception when others then if sqlerrm <> 'challenge_closed' then raise; end if; end;
  perform public.mm_ranked_report(current_setting('test.match')::uuid, 'loss');
end $t$;
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_challenge_status(current_setting('test.ranked')::uuid);
  if r->>'status' <> 'accepted' or r->>'matchId' <> current_setting('test.match') then raise exception 'challenger status wrong: %', r; end if;
  -- Cancelling after the accept keeps the game.
  r := public.mm_challenge_cancel(current_setting('test.ranked')::uuid);
  if r->>'status' <> 'accepted' then raise exception 'late cancel undid accept: %', r; end if;
  perform public.mm_ranked_report(current_setting('test.match')::uuid, 'win');
end $t$;
reset role;
do $t$ begin
  if (select host_result || '/' || guest_result from public.ranked_matches where id = current_setting('test.match')::uuid) <> 'win/loss' then
    raise exception 'friend ranked reports not stored'; end if;
end $t$;
set local role authenticated;

-- Declines, expiry and blocks.
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_challenge_send('DuelTwo', 'quick', 'relay-1', 8, 'NPQRST');
  perform set_config('test.declined', r->>'id', true);
end $t$;
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000002',true);
select public.mm_challenge_decline(current_setting('test.declined')::uuid);
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_challenge_status(current_setting('test.declined')::uuid);
  if r->>'status' <> 'declined' then raise exception 'decline not seen: %', r; end if;
  r := public.mm_challenge_send('DuelTwo', 'quick', 'relay-1', 8, 'UVWXYZ');
  perform set_config('test.old', r->>'id', true);
end $t$;
reset role;
update public.friend_challenges set created_at = now() - interval '3 minutes' where id = current_setting('test.old')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  if jsonb_array_length(public.mm_challenge_incoming()) <> 0 then raise exception 'expired challenge incoming'; end if;
  begin perform public.mm_challenge_accept(current_setting('test.old')::uuid, 'relay-1', 9); raise exception 'expired accepted';
  exception when others then if sqlerrm <> 'challenge_closed' then raise; end if; end;
  if public.mm_challenge_status(current_setting('test.old')::uuid)->>'status' <> 'expired' then raise exception 'expiry not shown'; end if;
  perform public.mm_block('DuelOne');
end $t$;
select set_config('request.jwt.claim.sub','c6000000-0000-0000-0000-000000000001',true);
do $t$ begin
  begin perform public.mm_challenge_send('DuelTwo', 'quick', 'relay-1', 8, 'ABCDEF'); raise exception 'challenged a blocker';
  exception when others then if sqlerrm not in ('not_found', 'not_friends') then raise; end if; end;
end $t$;

-- No direct table access, no internal helpers, nothing for signed-out callers.
do $t$ begin
  begin perform 1 from public.friend_challenges; raise exception 'table readable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_challenge_view('c6000000-0000-0000-0000-000000000001', gen_random_uuid()); raise exception 'view helper callable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_current_rank_step('c6000000-0000-0000-0000-000000000001'); raise exception 'rank helper callable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
set local role anon;
do $t$ begin
  begin perform public.mm_challenge_incoming(); raise exception 'anon read challenges';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

-- Account deletion removes their challenges.
delete from auth.users where id = 'c6000000-0000-0000-0000-000000000001';
do $t$ begin
  if exists (select 1 from public.friend_challenges) then raise exception 'challenges outlived the account'; end if;
end $t$;
rollback;
