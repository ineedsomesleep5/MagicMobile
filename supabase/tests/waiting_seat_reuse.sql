-- Disposable/local schema only. Left membership rows remain for prior participants.
begin;
insert into auth.users(id,aud,role,email) values
 ('a3000000-0000-0000-0000-000000000001','authenticated','authenticated','seat-one@example.invalid'),
 ('a3000000-0000-0000-0000-000000000002','authenticated','authenticated','seat-two@example.invalid'),
 ('a3000000-0000-0000-0000-000000000003','authenticated','authenticated','seat-three@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','a3000000-0000-0000-0000-000000000001',true);
select set_config('test.match_id',match_id::text,true),set_config('test.match_code',join_code,true)
 from public.matchmaking_create_lobby('One','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,2::smallint,0);
select set_config('request.jwt.claim.sub','a3000000-0000-0000-0000-000000000002',true);
select * from public.matchmaking_join_lobby(current_setting('test.match_code'),
 'Two','android','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,0);
select set_config('request.jwt.claim.sub','a3000000-0000-0000-0000-000000000001',true);
select public.matchmaking_leave_match(current_setting('test.match_id')::uuid);
select set_config('request.jwt.claim.sub','a3000000-0000-0000-0000-000000000003',true);
select * from public.matchmaking_join_lobby(current_setting('test.match_code'),
 'Three','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,0);
reset role;
do $test$
begin
  if not exists(select 1 from public.match_players where match_id=current_setting('test.match_id')::uuid
    and user_id='a3000000-0000-0000-0000-000000000001' and left_at is not null and seat=0) then
    raise exception 'Replacement removed the departed participant history';
  end if;
  if not exists(select 1 from public.match_players where match_id=current_setting('test.match_id')::uuid
    and user_id='a3000000-0000-0000-0000-000000000003' and left_at is null and seat=0) then
    raise exception 'Replacement did not reuse the free seat';
  end if;
  begin
    update public.match_players set left_at=null where match_id=current_setting('test.match_id')::uuid
      and user_id='a3000000-0000-0000-0000-000000000001';
    raise exception 'Two active participants can occupy the same seat';
  exception when unique_violation then null;
  end;
end;
$test$;
set local role authenticated;
select set_config('request.jwt.claim.sub','a3000000-0000-0000-0000-000000000003',true);
select public.matchmaking_leave_match(current_setting('test.match_id')::uuid);
select set_config('request.jwt.claim.sub','a3000000-0000-0000-0000-000000000001',true);
select * from public.matchmaking_join_lobby(current_setting('test.match_code'),
 'One again','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,0);
reset role;
do $test$
begin
  if (select count(*) from public.match_players where match_id=current_setting('test.match_id')::uuid and left_at is null)<>2
    or not exists(select 1 from public.match_players where match_id=current_setting('test.match_id')::uuid
      and user_id='a3000000-0000-0000-0000-000000000001' and left_at is null and display_name='One again') then
    raise exception 'Returning participant could not rejoin using existing primary key';
  end if;
end;
$test$;
rollback;
