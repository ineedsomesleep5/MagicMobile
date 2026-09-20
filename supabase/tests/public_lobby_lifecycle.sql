-- End-to-end database RPC lifecycle, every call made as authenticated user.
begin;
insert into auth.users(id,aud,role,email) values
 ('a4000000-0000-0000-0000-000000000001','authenticated','authenticated','lifecycle-one@example.invalid'),
 ('a4000000-0000-0000-0000-000000000002','authenticated','authenticated','lifecycle-two@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000001',true);
do $test$
declare r record;
begin
  select * into r from public.matchmaking_status();
  if r.state<>'idle' or r.match_id is not null then raise exception 'New player status not idle'; end if;
  select * into r from public.matchmaking_create_lobby('One','ios','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,2::smallint,0);
  if r.state<>'matched' or r.match_status<>'waiting' or not r.is_host then raise exception 'Create result invalid'; end if;
  perform set_config('test.match_id',r.match_id::text,true);
  perform set_config('test.match_code',r.join_code,true);
end;
$test$;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000002',true);
do $test$
declare r record;
begin
  select * into r from public.matchmaking_join_lobby(current_setting('test.match_code'),
    'Two','android','0.1.1','adapter-A','test-upstream','test-catalogue-hash',1,0);
  if r.match_id<>current_setting('test.match_id')::uuid or r.is_host then raise exception 'Join result invalid'; end if;
  select * into r from public.matchmaking_set_ready(current_setting('test.match_id')::uuid,true);
  if r.match_status<>'waiting' then raise exception 'One ready participant prematurely readied lobby'; end if;
end;
$test$;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000001',true);
do $test$
declare r record;
begin
  select * into r from public.matchmaking_set_ready(current_setting('test.match_id')::uuid,true);
  if r.match_status<>'ready' then raise exception 'Both ready participants did not ready lobby'; end if;
  select * into r from public.matchmaking_start(current_setting('test.match_id')::uuid);
  if r.state<>'active' or r.match_status<>'active' then raise exception 'Start did not activate lobby'; end if;
end;
$test$;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000002',true);
do $test$
declare r record;
begin
  select * into r from public.matchmaking_status();
  if r.state<>'active' or r.is_host then raise exception 'Nonhost status invalid'; end if;
  perform public.matchmaking_leave_match(current_setting('test.match_id')::uuid);
  select * into r from public.matchmaking_status();
  if r.state<>'idle' or r.match_id is not null then raise exception 'Departed nonhost not idle'; end if;
end;
$test$;
select set_config('request.jwt.claim.sub','a4000000-0000-0000-0000-000000000001',true);
do $test$
declare r record;
begin
  select * into r from public.matchmaking_status();
  if r.state<>'idle' or r.match_id is not null then raise exception 'Host remained active after nonhost departure'; end if;
end;
$test$;
reset role;
do $test$
begin
  if exists(select 1 from matchmaking_private.match_transport where match_id=current_setting('test.match_id')::uuid) then
    raise exception 'Public lifecycle retained ended game transport';
  end if;
end;
$test$;
rollback;
