-- Disposable/local schema only. Live production execution is not authorized.
begin;
insert into auth.users(id,aud,role,email) values
 ('a2000000-0000-0000-0000-000000000001','authenticated','authenticated','identity-one@example.invalid'),
 ('a2000000-0000-0000-0000-000000000002','authenticated','authenticated','identity-two@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','a2000000-0000-0000-0000-000000000001',true);
select set_config('test.match_code',join_code,true) from public.matchmaking_create_lobby(
 'One','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,2::smallint,0);
select set_config('request.jwt.claim.sub','a2000000-0000-0000-0000-000000000002',true);
do $test$
begin
  begin
    perform public.matchmaking_join_lobby(current_setting('test.match_code'),
      'Two','android','0.1.1','adapter-B','test-upstream','test-catalogue-hash',1,0);
    raise exception 'Mismatched adapter was accepted';
  exception when raise_exception then
    if sqlerrm not like '%do not match this lobby%' then raise; end if;
  end;
  perform public.matchmaking_join_lobby(current_setting('test.match_code'),
    'Two','android','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,0);
end;
$test$;
reset role;
do $test$
begin
  if (select count(*) from public.match_players mp join public.matches m on m.id=mp.match_id
    where m.join_code=current_setting('test.match_code') and mp.left_at is null and mp.engine_build='adapter-A')<>2 then
    raise exception 'Compatible cross-platform lobby did not admit both users';
  end if;
end;
$test$;
delete from public.matches where join_code=current_setting('test.match_code');

set local role authenticated;
select set_config('request.jwt.claim.sub','a2000000-0000-0000-0000-000000000001',true);
select * from public.matchmaking_enqueue('One','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,2::smallint,0);
select set_config('request.jwt.claim.sub','a2000000-0000-0000-0000-000000000002',true);
do $test$
declare r record;
begin
  select * into r from public.matchmaking_enqueue('Two','android','0.1.1','adapter-B','test-upstream','test-catalogue-hash',1,2::smallint,0);
  if r.state<>'queued' or r.match_id is not null then raise exception 'Different adapters were matched'; end if;
end;
$test$;
select set_config('request.jwt.claim.sub','a2000000-0000-0000-0000-000000000001',true);
do $test$
declare r record;
begin
  select * into r from public.matchmaking_enqueue('One','ios','0.1.1','adapter-B','test-upstream','test-catalogue-hash',1,2::smallint,0);
  if r.state<>'matched' or r.match_id is null then raise exception 'Matching adapters did not match'; end if;
end;
$test$;
reset role;
do $test$
begin
  if exists(select 1 from public.match_players where user_id in
    ('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000002') and engine_build<>'adapter-B') then
    raise exception 'Matched pod contains incompatible adapter';
  end if;
end;
$test$;
delete from public.matches where created_by in
 ('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000002');

set local role authenticated;
select * from public.matchmaking_enqueue('One','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,4::smallint,0);
reset role;
update matchmaking_private.quick_queue set joined_at=now()-interval '2 minutes'
 where user_id='a2000000-0000-0000-0000-000000000001';
set local role authenticated;
select * from public.matchmaking_enqueue('One','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,4::smallint,0);
reset role;
do $test$
begin
  if not exists(select 1 from matchmaking_private.quick_queue where user_id='a2000000-0000-0000-0000-000000000001'
    and joined_at=now()-interval '2 minutes') then raise exception 'Compatible queue refresh lost its place'; end if;
end;
$test$;
set local role authenticated;
select * from public.matchmaking_enqueue('One','ios','0.1.1','adapter-B','test-upstream','test-catalogue-hash',1,4::smallint,0);
reset role;
do $test$
begin
  if not exists(select 1 from matchmaking_private.quick_queue where user_id='a2000000-0000-0000-0000-000000000001'
    and joined_at=now() and engine_build='adapter-B') then raise exception 'Changed adapter retained incompatible queue tenure'; end if;
end;
$test$;
rollback;
