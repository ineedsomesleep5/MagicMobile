-- Placement matches (20261101120000_ranked_placements.sql).
insert into auth.users(id,aud,role,email) values
 ('d9700000-0000-0000-0000-000000000001','authenticated','authenticated','newcomer@example.invalid'),
 ('d9700000-0000-0000-0000-000000000002','authenticated','authenticated','mythic@example.invalid'),
 ('d9700000-0000-0000-0000-000000000003','authenticated','authenticated','diamond@example.invalid');
insert into public.profiles(id, display_name, username) values
 ('d9700000-0000-0000-0000-000000000001', 'Newcomer', 'Newcomer'),
 ('d9700000-0000-0000-0000-000000000002', 'Mythical', 'Mythical'),
 ('d9700000-0000-0000-0000-000000000003', 'Diamonds', 'Diamonds');

create function public.test_apply(p_uid uuid, p_results text[]) returns void language plpgsql as $f$
declare r text; begin
  foreach r in array p_results loop perform public.mm_ranked_apply(p_uid, r, 2, 'ai', null, null); end loop;
end $f$;

-- A new player places: five wins reach Gold II, and the sixth game is an ordinary ladder game.
do $t$ declare s public.ranked_standings; u uuid := 'd9700000-0000-0000-0000-000000000001'; begin
  s := public.mm_ranked_current(u);
  if s.points <> 0 or s.placement_left <> 5 then raise exception 'new player: % left %', s.points, s.placement_left; end if;
  perform public.test_apply(u, array['win', 'win', 'win', 'win']);
  s := public.mm_ranked_current(u);
  if s.points <> 32 or s.placement_left <> 1 then raise exception 'four wins: % left %', s.points, s.placement_left; end if;
  if (public.mm_ranked_apply(u, 'win', 2, 'ai', null, null)->>'placementLeft')::int <> 0 then raise exception 'last game'; end if;
  s := public.mm_ranked_current(u);
  if s.points <> 40 or s.placement_left <> 0 then raise exception 'five wins: % left %', s.points, s.placement_left; end if;
  if public.mm_ranked_apply(u, 'win', 3, 'ai', null, null) ? 'placementLeft' then raise exception 'after placing'; end if;
  if (public.mm_ranked_current(u)).points <> 42 then raise exception 'ladder after placing'; end if;
end $t$;

-- Losses and draws change nothing and still use a game. No loss below the start, no crushing loss, no underdog pip.
do $t$ declare s public.ranked_standings; u uuid := 'd9700000-0000-0000-0000-000000000003'; begin
  perform public.mm_ranked_apply(u, 'loss', 2, 'ai', null, null, true);
  perform public.test_apply(u, array['draw', 'loss']);
  perform public.mm_ranked_apply(u, 'win', 1, 'ai', null, null);
  s := public.mm_ranked_current(u);
  if s.points <> 8 or s.placement_left <> 1 then raise exception 'mixed: % left %', s.points, s.placement_left; end if;
end $t$;

-- Nobody shows on the leaderboard until they've placed.
set local role authenticated;
select set_config('request.jwt.claim.sub','d9700000-0000-0000-0000-000000000001',true);
do $t$ declare board jsonb := public.mm_ranked_leaderboard('everyone', 50); begin
  if not board->'entries' @> '[{"username":"Newcomer"}]' then raise exception 'placed player missing: %', board; end if;
  if board->'entries' @> '[{"username":"Diamonds"}]' then raise exception 'placing player shown: %', board; end if;
end $t$;
reset role;

-- A new season no longer drops one tier: a Diamond starts over, and only Mythic starts two divisions higher.
select public.mm_ranked_current('d9700000-0000-0000-0000-000000000002');
update public.ranked_standings set season = '2026-02', points = 64, peak_points = 79, wins = 9, losses = 3, placement_left = 0
 where user_id = 'd9700000-0000-0000-0000-000000000003';
update public.ranked_standings set season = '2026-02', points = 66, peak_points = 80, wins = 40, losses = 3, placement_left = 0
 where user_id = 'd9700000-0000-0000-0000-000000000002';
do $t$ declare s public.ranked_standings; begin
  s := public.mm_ranked_current('d9700000-0000-0000-0000-000000000003');
  if s.points <> 0 or s.peak_points <> 0 or s.placement_left <> 5 then raise exception 'diamond: %', s; end if;
  s := public.mm_ranked_current('d9700000-0000-0000-0000-000000000002');
  if s.points <> 8 or s.peak_points <> 8 or s.placement_left <> 5 then raise exception 'mythic: %', s; end if;
  perform public.test_apply('d9700000-0000-0000-0000-000000000002', array['win', 'win', 'win', 'win', 'win']);
  if (public.mm_ranked_current('d9700000-0000-0000-0000-000000000002')).points <> 48 then raise exception 'mythic five wins'; end if;
  if not exists (select 1 from public.ranked_season_history where user_id = 'd9700000-0000-0000-0000-000000000002' and peak_points = 80)
    then raise exception 'history lost'; end if;
end $t$;

-- A phone can't seed its way past placements, and the standing says how many are left.
insert into auth.users(id,aud,role,email) values ('d9700000-0000-0000-0000-000000000004','authenticated','authenticated','seed@example.invalid');
insert into public.profiles(id, display_name, username) values ('d9700000-0000-0000-0000-000000000004', 'Seeder', 'Seeder');
set local role authenticated;
select set_config('request.jwt.claim.sub','d9700000-0000-0000-0000-000000000004',true);
do $t$ declare r jsonb := public.mm_ranked_seed(32, 32, 9, 1); begin
  if (r->>'points')::int <> 0 or (r->>'placementLeft')::int <> 5 or (r->>'seeded')::boolean is not true then raise exception 'seed: %', r; end if;
end $t$;
reset role;
drop function public.test_apply(uuid, text[]);
