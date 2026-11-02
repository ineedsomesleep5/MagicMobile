-- Heat reports (20261102120000_game_heat.sql).
insert into auth.users(id,aud,role,email) values
 ('d9900000-0000-0000-0000-000000000001','authenticated','authenticated','heat@example.invalid'),
 ('d9900000-0000-0000-0000-000000000002','authenticated','authenticated','noname@example.invalid');
insert into public.profiles(id, display_name, username) values
 ('d9900000-0000-0000-0000-000000000001', 'Heat', 'Heat');
insert into public.profiles(id, display_name) values
 ('d9900000-0000-0000-0000-000000000002', 'NoName');

create function public.test_heat(p_id uuid, p_stats jsonb, p_board text default 'arena', p_device text default 'iPhone17,2', p_mode text default 'ranked')
returns boolean language sql as $f$
  select public.mm_game_heat(p_id, now(), 'ios', 78, p_device, '27.0', p_mode, p_stats, 6, p_board, 'volcano', 'full', 'full')
$f$;
grant execute on function public.test_heat(uuid, jsonb, text, text, text) to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','d9900000-0000-0000-0000-000000000001',true);
do $t$
declare
  game uuid := gen_random_uuid();
  raised boolean;
begin
  if not public.test_heat(game, '{"minutes": 12.5, "hottest": 2, "cpu": 41, "charging": false, "name": "Heat", "cpuAI": "lots", "lowPower": 3}') then
    raise exception 'report refused';
  end if;
  if public.test_heat(game, '{"minutes": 12.5}') then raise exception 'stored twice'; end if;
  -- A row can't be read back by a player, and nothing but a known number reached it (checked below as the owner).
  begin
    perform 1 from public.game_heat;
    raise exception 'a player read the table';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.game_heat_summary;
    raise exception 'a player read the summary';
  exception when insufficient_privilege then null;
  end;
  -- Bad reports stop at the door.
  raised := false;
  begin perform public.test_heat(gen_random_uuid(), '[]'); exception when others then raised := sqlerrm = 'invalid_report'; end;
  if not raised then raise exception 'stats that are not an object'; end if;
  raised := false;
  begin perform public.test_heat(gen_random_uuid(), '{}', 'Not A Board'); exception when others then raised := sqlerrm = 'invalid_report'; end;
  if not raised then raise exception 'an odd board name'; end if;
  raised := false;
  begin perform public.test_heat(gen_random_uuid(), '{}', 'arena', E'iPhone\n'); exception when others then raised := sqlerrm = 'invalid_report'; end;
  if not raised then raise exception 'a control character in the device'; end if;
  raised := false;
  begin perform public.test_heat(gen_random_uuid(), '{}', 'arena', 'iPhone17,2', ''); exception when others then raised := sqlerrm = 'invalid_report'; end;
  if not raised then raise exception 'an empty mode'; end if;
end $t$;

-- No player name yet: nothing is stored.
select set_config('request.jwt.claim.sub','d9900000-0000-0000-0000-000000000002',true);
do $t$
begin
  perform public.test_heat(gen_random_uuid(), '{}');
  raise exception 'a report without a player name';
exception when others then
  if sqlerrm <> 'no_username' then raise; end if;
end $t$;
reset role;

do $t$
declare
  u uuid := 'd9900000-0000-0000-0000-000000000001';
  s jsonb;
  i int;
  r record;
begin
  select stats into s from public.game_heat where user_id = u;
  if s <> '{"minutes": 12.5, "hottest": 2, "cpu": 41, "charging": false}'::jsonb then raise exception 'stats kept: %', s; end if;

  -- The summary leaves out short games, games on a charger and phones already hot.
  insert into public.game_heat (user_id, client_id, played_at, platform, build, device, mode, table_name, motion, stats) values
    (u, gen_random_uuid(), now(), 'ios', 78, 'iPhone17,2', 'ranked', 'volcano', 'full', '{"minutes": 1, "hottest": 3}'),
    (u, gen_random_uuid(), now(), 'ios', 78, 'iPhone17,2', 'ranked', 'volcano', 'full', '{"minutes": 20, "hottest": 3, "charging": true}'),
    (u, gen_random_uuid(), now(), 'ios', 78, 'iPhone17,2', 'ranked', 'volcano', 'full', '{"minutes": 20, "hottest": 3, "startThermal": 2}'),
    (u, gen_random_uuid(), now(), 'ios', 78, 'iPhone17,2', 'ranked', 'volcano', 'full', '{"minutes": 7.5, "hottest": 1, "cpu": 21}');
  select * into r from public.game_heat_summary where build = 78;
  if r.games <> 2 or r.serious_pct <> 50 or r.minutes <> 10 or r.cpu <> 31 then raise exception 'summary: %', row_to_json(r); end if;

  -- Each player's newest 500 stay.
  delete from public.game_heat where user_id = u;
  insert into public.game_heat (user_id, client_id, played_at, platform, build, device, mode, stats, created_at)
    select u, gen_random_uuid(), now() - (n || ' hours')::interval - interval '1 day', 'ios', 78, 'iPhone17,2', 'quick', '{}', now() - interval '1 day'
      from generate_series(1, 500) n;
  perform set_config('request.jwt.claim.sub', u::text, true);
  if not public.test_heat(gen_random_uuid(), '{}') then raise exception 'report 501'; end if;
  i := (select count(*) from public.game_heat where user_id = u);
  if i <> 500 then raise exception 'kept %', i; end if;

  -- A hundred an hour, then a clear no.
  update public.game_heat set created_at = now() where user_id = u and id in (select id from public.game_heat where user_id = u limit 100);
  begin
    perform public.test_heat(gen_random_uuid(), '{}');
    raise exception 'no rate limit';
  exception when others then
    if sqlerrm <> 'too_many_reports' then raise; end if;
  end;

  -- Deleting a profile deletes its rows.
  delete from public.profiles where id = u;
  if exists (select 1 from public.game_heat where user_id = u) then raise exception 'rows outlived the profile'; end if;
end $t$;

drop function public.test_heat(uuid, jsonb, text, text, text);
delete from public.profiles where id = 'd9900000-0000-0000-0000-000000000002';
delete from auth.users where id in ('d9900000-0000-0000-0000-000000000001', 'd9900000-0000-0000-0000-000000000002');
