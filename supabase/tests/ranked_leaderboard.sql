-- The ranked leaderboard (20261016180000_ranked_leaderboard.sql), run last by verify-ranked.mjs. Rows are set up
-- as the superuser; the leaderboard is read as an authenticated player.
insert into auth.users(id,aud,role,email)
select ('dA000000-0000-0000-0000-00000000000' || n)::uuid, 'authenticated', 'authenticated', 'lb' || n || '@example.invalid'
from unnest(array['1','2','3','4','5','6','7','8','9']) n;
-- 1 viewer (public), 2 public online leader, 3 friends-only friend, 4 friends-only stranger, 5 private,
-- 6 public blocked by the viewer, 7 public who blocked the viewer, 8 public but last season, 9 public with no games.
insert into public.profiles(id, display_name, username, visibility) values
 ('dA000000-0000-0000-0000-000000000001', 'LbViewer', 'LbViewer', 'public'),
 ('dA000000-0000-0000-0000-000000000002', 'LbLeader', 'LbLeader', 'public'),
 ('dA000000-0000-0000-0000-000000000003', 'LbFriend', 'LbFriend', 'friends'),
 ('dA000000-0000-0000-0000-000000000004', 'LbStranger', 'LbStranger', 'friends'),
 ('dA000000-0000-0000-0000-000000000005', 'LbPrivate', 'LbPrivate', 'private'),
 ('dA000000-0000-0000-0000-000000000006', 'LbBlocked', 'LbBlocked', 'public'),
 ('dA000000-0000-0000-0000-000000000007', 'LbBlocker', 'LbBlocker', 'public'),
 ('dA000000-0000-0000-0000-000000000008', 'LbOld', 'LbOld', 'public'),
 ('dA000000-0000-0000-0000-000000000009', 'LbNoGames', 'LbNoGames', 'public');
insert into public.ranked_standings(user_id, season, points, peak_points, wins, losses)
select ('dA000000-0000-0000-0000-00000000000' || n)::uuid,
       case when n = 8 then '2026-01' else to_char(now() at time zone 'utc', 'YYYY-MM') end,
       pts, pts, case when n = 9 then 0 else 3 end, case when n = 9 then 0 else 1 end
from (values (1, 30), (2, 82), (3, 50), (4, 60), (5, 90), (6, 40), (7, 70), (8, 95), (9, 10)) v(n, pts);
insert into public.ranked_profiles(user_id, season, rank_step, pips, peak_step, title, favorite_commander)
values ('dA000000-0000-0000-0000-000000000002', to_char(now() at time zone 'utc', 'YYYY-MM'), 20, 2, 20, 'Archmage', 'Atraxa, Praetors'' Voice');
insert into public.presence(user_id, last_seen_at) values
 ('dA000000-0000-0000-0000-000000000002', now()),
 ('dA000000-0000-0000-0000-000000000003', now() - interval '10 minutes');
insert into public.friendships(requester, addressee, status) values
 ('dA000000-0000-0000-0000-000000000001', 'dA000000-0000-0000-0000-000000000003', 'accepted');
insert into public.blocks(blocker, blocked) values
 ('dA000000-0000-0000-0000-000000000001', 'dA000000-0000-0000-0000-000000000006'),
 ('dA000000-0000-0000-0000-000000000007', 'dA000000-0000-0000-0000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','dA000000-0000-0000-0000-000000000001',true);
do $t$
declare r jsonb; names text;
begin
  r := public.mm_ranked_leaderboard('everyone', 50);
  select string_agg(e->>'username', ',' order by (e->>'position')::int) into names from jsonb_array_elements(r->'entries') e where e->>'username' like 'Lb%';
  if names <> 'LbLeader,LbFriend,LbViewer' then raise exception 'everyone order/visibility: % (%)', names, r; end if;
  -- Other suites' players share the season; this suite only reasons about its own (Lb…) players.
  if (r->>'online')::int <> 1 then raise exception 'online count: %', r; end if;
  if (select count(*) from jsonb_array_elements(r->'entries') e where e->>'username' like 'Lb%' and (e->>'online')::boolean) <> 1
     or (select e->>'online' from jsonb_array_elements(r->'entries') e where e->>'username' = 'LbFriend') <> 'false' then
    raise exception 'online flags: %', r; end if;
  if r->'entries'->0->>'title' <> 'Archmage' or (r->'entries'->0->>'step')::int <> 20 or (r->'entries'->0->>'pips')::int <> 2 then
    raise exception 'leader row: %', r->'entries'->0; end if;
  if r->'me'->>'username' <> 'LbViewer' or r->'me'->>'you' <> 'true' or (r->'me'->>'step')::int <> 7 then raise exception 'me: %', r->'me'; end if;
  r := public.mm_ranked_leaderboard('friends', 50);
  select string_agg(e->>'username', ',' order by (e->>'position')::int) into names from jsonb_array_elements(r->'entries') e where e->>'username' like 'Lb%';
  if names <> 'LbFriend,LbViewer' or (r->'me'->>'position')::int <> 2 or jsonb_array_length(r->'entries') <> 2 then
    raise exception 'friends scope: %', r; end if;
  r := public.mm_ranked_leaderboard('everyone', 1);
  if jsonb_array_length(r->'entries') <> 1 or r->'entries'->0->>'username' <> 'LbLeader' or r->'me'->>'username' <> 'LbViewer'
     or (r->'me'->>'position')::int < 2 then raise exception 'limit keeps me: %', r; end if;
  if jsonb_array_length(public.mm_ranked_leaderboard('everyone', 1000)->'entries') > 100 then raise exception 'limit cap'; end if;
  begin perform public.mm_ranked_leaderboard('world', 10); raise exception 'bad scope accepted';
  exception when others then if sqlerrm <> 'invalid_scope' then raise; end if; end;
  begin perform 1 from public.ranked_standings; raise exception 'standings readable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

-- A friends-only stranger sees the public players (including the one the viewer blocked, and the one who blocked the
-- viewer), never the viewer's friends-only friend or the private player.
set local role authenticated;
select set_config('request.jwt.claim.sub','dA000000-0000-0000-0000-000000000004',true);
do $t$
declare names text;
begin
  select string_agg(e->>'username', ',' order by (e->>'position')::int) into names
    from jsonb_array_elements(public.mm_ranked_leaderboard('everyone', 50)->'entries') e where e->>'username' like 'Lb%';
  if names <> 'LbLeader,LbBlocker,LbStranger,LbBlocked,LbViewer' then raise exception 'stranger view: %', names; end if;
end $t$;
reset role;

set local role anon;
do $t$ begin
  begin perform public.mm_ranked_leaderboard('everyone', 10); raise exception 'anon read the leaderboard';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
