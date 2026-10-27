-- The leaderboard's streaks, season end and champions (20261027000000_leaderboard_streaks_champions.sql), run after
-- ranked_leaderboard.sql by verify-ranked.mjs with its Lb… players. Last season's rows are set up as the superuser.
update public.ranked_standings set win_streak = 4
 where user_id = 'dA000000-0000-0000-0000-000000000002' and season = public.mm_current_season();
-- Last season: the leader and the friend finished on top; the friends-only stranger finished higher but the viewer can't
-- see them; the private player too. Points near the cap, so other suites' rows never come between.
insert into public.ranked_season_history(user_id, season, final_points, peak_points, wins, losses)
select ('dA000000-0000-0000-0000-00000000000' || n)::uuid, public.mm_season_before(public.mm_current_season()), pts, pts, 9, 2
from (values (2, 100070), (3, 100060), (4, 100079), (5, 100078), (1, 100050)) v(n, pts);

-- Players can't call the season helpers here; the check reads last season's name from a setting.
select set_config('test.last_season', public.mm_season_before(public.mm_current_season()), true);
set local role authenticated;
select set_config('request.jwt.claim.sub','dA000000-0000-0000-0000-000000000001',true);
do $t$
declare r jsonb; names text;
begin
  r := public.mm_ranked_leaderboard('everyone', 50);
  if (select (e->>'streak')::int from jsonb_array_elements(r->'entries') e where e->>'username' = 'LbLeader') <> 4
     or (select (e->>'streak')::int from jsonb_array_elements(r->'entries') e where e->>'username' = 'LbFriend') <> 0 then
    raise exception 'streaks: %', r->'entries'; end if;
  if (r->>'seasonEnds')::timestamptz <= now() or extract(day from (r->>'seasonEnds')::timestamptz at time zone 'utc') <> 1 then
    raise exception 'season end: %', r->>'seasonEnds'; end if;
  if r->'champions'->>'season' <> current_setting('test.last_season') then raise exception 'champions season: %', r->'champions'; end if;
  select string_agg(e->>'username', ',' order by (e->>'position')::int) into names from jsonb_array_elements(r->'champions'->'entries') e;
  if names <> 'LbLeader,LbFriend,LbViewer' then raise exception 'champions: %', r->'champions'; end if;
  if (r->'champions'->'entries'->2->>'you')::boolean is not true or (r->'champions'->'entries'->0->>'step')::int < 20 then
    raise exception 'champion rows: %', r->'champions'; end if;
end $t$;
reset role;

-- When seasons end: October 2026 was one month, then three.
do $t$ begin
  if public.mm_season_ends('2026-10') <> timestamptz '2026-11-01 00:00:00+00'
     or public.mm_season_ends('2026-11') <> timestamptz '2027-02-01 00:00:00+00'
     or public.mm_season_before('2026-11') <> '2026-10' or public.mm_season_before('2027-02') <> '2026-11'
     or public.mm_season_before('2026-10') <> '2026-09' then
    raise exception 'season bounds: % % % % %', public.mm_season_ends('2026-10'), public.mm_season_ends('2026-11'),
      public.mm_season_before('2026-11'), public.mm_season_before('2027-02'), public.mm_season_before('2026-10'); end if;
end $t$;
