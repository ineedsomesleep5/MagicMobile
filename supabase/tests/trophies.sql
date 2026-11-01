-- Trophies from the server (20261101180000_trophies.sql).
insert into auth.users(id,aud,role,email) values
 ('d9800000-0000-0000-0000-000000000001','authenticated','authenticated','trophy@example.invalid'),
 ('d9800000-0000-0000-0000-000000000002','authenticated','authenticated','casual@example.invalid');
insert into public.profiles(id, display_name, username) values
 ('d9800000-0000-0000-0000-000000000001', 'Trophy', 'Trophy'),
 ('d9800000-0000-0000-0000-000000000002', 'Casual', 'Casual');

create function public.test_game(p_uid uuid, p_mode text, p_result text, p_turns int, p_seconds int, p_commander text, p_colors text[], p_ai boolean) returns void
language sql as $f$
  insert into public.player_games (user_id, client_id, played_at, mode, result, commanders, colors, opponents, turns, duration_seconds)
  values (p_uid, gen_random_uuid(), now(), p_mode, p_result, array[p_commander], p_colors,
          jsonb_build_array(jsonb_build_object('name', 'Foe', 'commander', null, 'ai', p_ai)), p_turns, p_seconds) $f$;
create function public.test_has(p_uid uuid, p_award text) returns boolean language sql as $f$
  select exists (select 1 from public.player_awards where user_id = p_uid and award_id = p_award) $f$;

-- A player with no ranked standing earns from games alone, and only what the game meets.
do $t$ declare u uuid := 'd9800000-0000-0000-0000-000000000002'; begin
  perform public.test_game(u, 'quick', 'win', 7, 280, 'Krenko, Mob Boss', array['R'], true);
  if not public.test_has(u, 'lightning') then raise exception 'lightning not given'; end if;
  if not public.test_has(u, 'swift-justice') then raise exception 'swift justice not given'; end if;
  if public.test_has(u, 'marathon') or public.test_has(u, 'five-colors') then raise exception 'wrong trophy given'; end if;
  perform public.test_game(u, 'casual', 'loss', 40, 3000, 'Krenko, Mob Boss', array['R'], true);
  if public.test_has(u, 'marathon') then raise exception 'a lost marathon counted'; end if;
  perform public.test_game(u, 'casual', 'win', 31, 3000, 'The Ur-Dragon', array['W','U','B','R','G'], true);
  if not public.test_has(u, 'marathon') or not public.test_has(u, 'five-colors') then raise exception 'marathon or colors'; end if;
end $t$;

-- Counts: different commanders, and wins over people only.
do $t$ declare u uuid := 'd9800000-0000-0000-0000-000000000001'; i int; begin
  for i in 1..4 loop perform public.test_game(u, 'quick', 'win', 12, 900, 'Commander ' || i, array['G'], true); end loop;
  perform public.test_game(u, 'quick', 'win', 12, 900, 'Commander 1', array['G'], true);
  if public.test_has(u, 'collector') then raise exception 'collector counted a repeat'; end if;
  perform public.test_game(u, 'quick', 'win', 12, 900, 'Commander 5', array['G'], true);
  if not public.test_has(u, 'collector') then raise exception 'collector not given'; end if;
  for i in 1..9 loop perform public.test_game(u, 'casual', 'win', 12, 900, 'Commander 1', array['G'], false); end loop;
  if public.test_has(u, 'table-captain') then raise exception 'table captain too early'; end if;
  perform public.test_game(u, 'casual', 'win', 12, 900, 'Commander 1', array['G'], false);
  if not public.test_has(u, 'table-captain') then raise exception 'table captain not given'; end if;
end $t$;

-- Five placement wins earn Flawless; four and a loss don't.
do $t$ declare u uuid := 'd9800000-0000-0000-0000-000000000001'; i int; begin
  for i in 1..4 loop perform public.mm_ranked_apply(u, 'win', 2, 'ai', null, null); end loop;
  if public.test_has(u, 'flawless') then raise exception 'flawless too early'; end if;
  perform public.mm_ranked_apply(u, 'win', 2, 'ai', null, null);
  if not public.test_has(u, 'flawless') then raise exception 'flawless not given'; end if;
end $t$;
do $t$ declare u uuid := 'd9800000-0000-0000-0000-000000000002'; i int; begin
  for i in 1..4 loop perform public.mm_ranked_apply(u, 'win', 2, 'ai', null, null); end loop;
  perform public.mm_ranked_apply(u, 'loss', 2, 'ai', null, null);
  if public.test_has(u, 'flawless') then raise exception 'flawless with a loss'; end if;
end $t$;

-- The caller's shelf: every trophy in order, with earnedAt on theirs. A row added later just appears.
insert into public.awards (id, name, description, rule, shelf, shelf_order) values ('test-new', 'Added Later', 'A new row.', '{"kind": "games", "count": 1}', true, 999);
set local role authenticated;
select set_config('request.jwt.claim.sub','d9800000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb := public.mm_trophies(); begin
  if jsonb_array_length(r) <> 13 then raise exception 'shelf: %', jsonb_array_length(r); end if;
  if r -> 0 ->> 'id' <> 'regular' or r -> 12 ->> 'id' <> 'test-new' then raise exception 'order: %', r; end if;
  if (select e ->> 'awardedAt' from jsonb_array_elements(r) e where e ->> 'id' = 'lightning') is null then raise exception 'earned missing'; end if;
  if (select e ->> 'awardedAt' from jsonb_array_elements(r) e where e ->> 'id' = 'grand-collector') is not null then raise exception 'locked shown earned'; end if;
  if not (public.mm_my_awards() -> 0 ? 'shelf') then raise exception 'mm_my_awards has no shelf flag'; end if;
end $t$;
reset role;
do $t$ begin
  if public.mm_awards_backfill('test-new') < 2 then raise exception 'backfill missed players without a standing'; end if;
end $t$;
delete from public.awards where id = 'test-new';
drop function public.test_game(uuid, text, text, int, int, text, text[], boolean);
drop function public.test_has(uuid, text);
