-- Run ONLY on a disposable/local copy of the complete deployed schema after the
-- migration. Everything rolls back. Do not run against production without review.
begin;

do $test$
declare f record; count_locked integer := 0;
begin
  if has_function_privilege('anon','public.matchmaking_leave_match(uuid)','EXECUTE') then
    raise exception 'Anonymous users can execute leave';
  end if;
  if not has_function_privilege('authenticated','public.matchmaking_leave_match(uuid)','EXECUTE') then
    raise exception 'Authenticated wrapper privilege missing';
  end if;
  if not has_function_privilege('authenticated','matchmaking_private.leave_match_impl(uuid)','EXECUTE') then
    raise exception 'Invoker wrapper cannot reach private implementation';
  end if;
  if exists(select 1 from pg_proc where oid='public.matchmaking_leave_match(uuid)'::regprocedure and prosecdef) then
    raise exception 'Public wrapper must remain invoker';
  end if;
  for f in select p.proname,p.prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='matchmaking_private' and p.proname in
      ('create_lobby_impl','join_lobby_impl','enqueue_impl','cleanup','state_impl',
       'start_impl','set_ready_impl','finish_impl','cancel_impl','leave_impl','leave_match_impl')
  loop
    if strpos(f.prosrc,'pg_advisory_xact_lock(1936028278, 1)')=0 then
      raise exception 'Mutation path bypasses coordination: %',f.proname;
    end if;
    count_locked := count_locked+1;
  end loop;
  if count_locked<>11 then raise exception 'Unexpected lock coverage: %',count_locked; end if;
end;
$test$;

insert into auth.users(id,aud,role,email) values
 ('a1000000-0000-0000-0000-000000000001','authenticated','authenticated','leave-test-one@example.invalid'),
 ('a1000000-0000-0000-0000-000000000002','authenticated','authenticated','leave-test-two@example.invalid');
insert into public.matches(id,topic,kind,format,player_count,status,join_code,created_by,host_user_id,
 protocol_version,engine_build,upstream,catalogue_hash,expires_at) values
 ('b1000000-0000-0000-0000-000000000001','match:b1000000-0000-0000-0000-000000000001:lobby','private','commander',2,'waiting','ZZZZZ2',
  'a1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',1,'test-build','test-upstream','test-catalogue-hash',now()+interval '1 hour');
insert into public.match_players(match_id,user_id,seat,display_name,platform,app_version,engine_build,protocol_version,upstream,catalogue_hash) values
 ('b1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',0,'One','ios','0.1.1','test-build',1,'test-upstream','test-catalogue-hash'),
 ('b1000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002',1,'Two','android','0.1.1','test-build',1,'test-upstream','test-catalogue-hash');

set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
do $test$
begin
  begin
    perform public.matchmaking_leave_match('b1000000-0000-0000-0000-000000000001');
    raise exception 'Missing UID accepted';
  exception when insufficient_privilege then null;
  end;
end;
$test$;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
do $test$
begin
  begin
    perform public.matchmaking_leave_match('b1000000-0000-0000-0000-000000000099');
    raise exception 'Wrong expected match accepted';
  exception when insufficient_privilege then null;
  end;
  perform public.matchmaking_leave_match('b1000000-0000-0000-0000-000000000001');
  perform public.matchmaking_leave_match('b1000000-0000-0000-0000-000000000001');
end;
$test$;
reset role;
do $test$
begin
  if not exists(select 1 from public.matches where id='b1000000-0000-0000-0000-000000000001'
    and status='waiting' and host_user_id='a1000000-0000-0000-0000-000000000002') then
    raise exception 'Waiting host election failed';
  end if;
end;
$test$;

-- Restore fixture membership and start an active match, then let the NONHOST leave.
update public.match_players set left_at=null,ready=true where match_id='b1000000-0000-0000-0000-000000000001';
update public.matches set status='active' where id='b1000000-0000-0000-0000-000000000001';
insert into matchmaking_private.match_transport(match_id,transport_key)
 values('b1000000-0000-0000-0000-000000000001','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select public.matchmaking_leave_match('b1000000-0000-0000-0000-000000000001');
select public.matchmaking_leave_match('b1000000-0000-0000-0000-000000000001');
reset role;
do $test$
begin
  if not exists(select 1 from public.matches where id='b1000000-0000-0000-0000-000000000001' and status='abandoned')
    or exists(select 1 from public.match_players where match_id='b1000000-0000-0000-0000-000000000001' and (left_at is null or ready))
    or exists(select 1 from matchmaking_private.match_transport where match_id='b1000000-0000-0000-0000-000000000001') then
    raise exception 'Active leave did not retire whole match and transport';
  end if;
end;
$test$;

-- The deployed legacy wrapper must share whole-game retirement behavior too.
update public.match_players set left_at=null,ready=true where match_id='b1000000-0000-0000-0000-000000000001';
update public.matches set status='active',ended_at=null where id='b1000000-0000-0000-0000-000000000001';
set local role authenticated;
select * from public.matchmaking_leave();
reset role;
do $test$
begin
  if not exists(select 1 from public.matches where id='b1000000-0000-0000-0000-000000000001' and status='abandoned')
    or exists(select 1 from public.match_players where match_id='b1000000-0000-0000-0000-000000000001' and left_at is null) then
    raise exception 'Legacy leave bypassed whole-game retirement';
  end if;
end;
$test$;

rollback;
