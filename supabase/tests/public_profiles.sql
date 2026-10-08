-- Public profiles: visibility, live search, recorded games and the profile others open, every call made
-- as an authenticated player (anon and direct table access are checked at the end).
begin;
insert into auth.users(id,aud,role,email)
select ('f7000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', 'profile-' || n || '@example.invalid'
from generate_series(1, 11) n;
-- 15 more players whose names share a prefix, for the result limit.
insert into auth.users(id,aud,role,email)
select ('f7100000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated', 'mass-' || n || '@example.invalid'
from generate_series(1, 15) n;
insert into public.profiles(id, display_name, username)
select ('f7100000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'Mass' || lpad(n::text, 2, '0'), 'Mass' || lpad(n::text, 2, '0')
from generate_series(1, 15) n;

set local role authenticated;
-- 1 Viewer1, 2 DaAlpha, 3 DaBeta_, 4 Da_x, 5 DaFriend, 6 DaPrivate, 7 DaFriendsOnly, 8 DaBlocked, 9 DaBlocker,
-- 10 DaPending, 11 DaIncoming
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ begin
  -- A player without a name can't search, open profiles or record games.
  begin perform public.mm_search_players('da'); raise exception 'searched without a name';
  exception when others then if sqlerrm <> 'no_username' then raise; end if; end;
  begin perform public.mm_public_profile('x'); raise exception 'opened a profile without a name';
  exception when others then if sqlerrm <> 'no_username' then raise; end if; end;
  begin perform public.mm_set_visibility('private'); raise exception 'set visibility without a name';
  exception when others then if sqlerrm <> 'no_username' then raise; end if; end;
  perform public.mm_claim_username('Viewer1');
end $t$;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000002',true);
select public.mm_claim_username('DaAlpha');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000003',true);
select public.mm_claim_username('DaBeta_');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000004',true);
select public.mm_claim_username('Da_x');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000005',true);
select public.mm_claim_username('DaFriend');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000006',true);
select public.mm_claim_username('DaPrivate');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000007',true);
select public.mm_claim_username('DaFriendsOnly');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000008',true);
select public.mm_claim_username('DaBlocked');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000009',true);
select public.mm_claim_username('DaBlocker');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000010',true);
select public.mm_claim_username('DaPending');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000011',true);
select public.mm_claim_username('DaIncoming');

-- Profiles are public until the player says otherwise; the choice is validated and reported by mm_profile.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_profile();
  if r->>'visibility' <> 'public' or r->>'username' <> 'Viewer1' then raise exception 'default profile wrong: %', r; end if;
  begin perform public.mm_set_visibility('secret'); raise exception 'bad visibility accepted';
  exception when others then if sqlerrm <> 'invalid_visibility' then raise; end if; end;
  begin perform public.mm_set_visibility(null); raise exception 'null visibility accepted';
  exception when others then if sqlerrm <> 'invalid_visibility' then raise; end if; end;
  if public.mm_set_visibility('friends') <> 'friends' then raise exception 'visibility not echoed'; end if;
  r := public.mm_profile();
  if r->>'visibility' <> 'friends' then raise exception 'visibility not set: %', r; end if;
  perform public.mm_set_visibility('public');
end $t$;

-- Relationships: DaFriend is a friend, DaPending was asked, DaIncoming asked the viewer; the viewer blocked
-- DaBlocked and DaBlocker blocked the viewer.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ begin
  perform public.mm_friend_request('DaFriend');
  perform public.mm_friend_request('DaPending');
  perform public.mm_block('DaBlocked');
end $t$;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000005',true);
select public.mm_respond_friend('f7000000-0000-0000-0000-000000000001', true);
select public.mm_heartbeat('ios');
select public.mm_ranked_publish(to_char(now() at time zone 'utc', 'YYYY-MM'), 9, 2, 9, 5, 1, 'Rising Star', 'Edgar Markov');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000011',true);
select public.mm_friend_request('Viewer1');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000009',true);
select public.mm_block('Viewer1');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000002',true);
select public.mm_heartbeat('android');
select public.mm_ranked_publish(to_char(now() at time zone 'utc', 'YYYY-MM'), 13, 1, 14, 9, 3, null, 'Krenko, Mob Boss');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000006',true);
select public.mm_ranked_publish(to_char(now() at time zone 'utc', 'YYYY-MM'), 7, 0, 7, 2, 2, null, 'Atraxa, Praetors'' Voice');
select public.mm_set_visibility('private');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000007',true);
select public.mm_ranked_publish(to_char(now() at time zone 'utc', 'YYYY-MM'), 5, 0, 5, 1, 0, null, 'Ghave, Guru of Spores');
select public.mm_set_visibility('friends');

-- Search: two or more characters of a name, from the start, case-insensitive, never the caller, blocked or private.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ declare n integer; first_name text; r record; begin
  select count(*) into n from public.mm_search_players('d'); if n <> 0 then raise exception 'one character searched: %', n; end if;
  select count(*) into n from public.mm_search_players(''); if n <> 0 then raise exception 'empty searched'; end if;
  select count(*) into n from public.mm_search_players(null); if n <> 0 then raise exception 'null searched'; end if;
  select count(*) into n from public.mm_search_players('da%'); if n <> 0 then raise exception 'wildcard searched'; end if;
  select count(*) into n from public.mm_search_players('da x'); if n <> 0 then raise exception 'space searched'; end if;
  select count(*) into n from public.mm_search_players(repeat('a', 21)); if n <> 0 then raise exception 'long prefix searched'; end if;
  select count(*) into n from public.mm_search_players('Alpha'); if n <> 0 then raise exception 'searched the middle of a name'; end if;
  -- DaAlpha, DaBeta_, Da_x, DaFriend, DaFriendsOnly, DaPending, DaIncoming: not DaPrivate, DaBlocked, DaBlocker, nor the caller.
  select count(*) into n from public.mm_search_players('da'); if n <> 7 then raise exception 'da found % players', n; end if;
  select count(*) into n from public.mm_search_players('  DA '); if n <> 7 then raise exception 'DA found % players', n; end if;
  if exists (select 1 from public.mm_search_players('da') where username in ('DaPrivate', 'DaBlocked', 'DaBlocker')) then
    raise exception 'private or blocked player found'; end if;
  -- An underscore is a letter here, not a wildcard.
  select count(*) into n from public.mm_search_players('da_'); if n <> 1 then raise exception 'da_ found % players', n; end if;
  if not exists (select 1 from public.mm_search_players('da_') where username = 'Da_x') then raise exception 'Da_x missing'; end if;
  -- Friends come first, relations are right, presence only for friends.
  select s.username into first_name from public.mm_search_players('da') s limit 1;
  if first_name <> 'DaFriend' then raise exception 'friend not first: %', first_name; end if;
  select * into r from public.mm_search_players('da') where username = 'DaFriend';
  if r.relation <> 'friend' or r.online is not true or r.rank_step <> 9 or r.favorite_commander <> 'Edgar Markov' then
    raise exception 'friend row wrong: %', r; end if;
  select * into r from public.mm_search_players('da') where username = 'DaPending';
  if r.relation <> 'outgoing' or r.online is not null then raise exception 'pending row wrong: %', r; end if;
  select * into r from public.mm_search_players('da') where username = 'DaIncoming';
  if r.relation <> 'incoming' then raise exception 'incoming row wrong: %', r; end if;
  -- A stranger who is online shows no presence; their public rank shows.
  select * into r from public.mm_search_players('da') where username = 'DaAlpha';
  if r.relation <> 'none' or r.online is not null or r.rank_step <> 13 or r.visibility <> 'public' then raise exception 'stranger row wrong: %', r; end if;
  -- A friends-only profile can be found, with no rank or commander.
  select * into r from public.mm_search_players('da') where username = 'DaFriendsOnly';
  if r.visibility <> 'friends' or r.rank_step is not null or r.favorite_commander is not null then raise exception 'friends-only row wrong: %', r; end if;
  -- The exact name comes first.
  select s.username into first_name from public.mm_search_players('dabeta_') s limit 1;
  if first_name <> 'DaBeta_' then raise exception 'exact name missing: %', first_name; end if;
  select s.username into first_name from public.mm_search_players('Da_x') s limit 1;
  if first_name <> 'Da_x' then raise exception 'exact Da_x missing: %', first_name; end if;
  -- At most 12 of 15.
  select count(*) into n from public.mm_search_players('mass'); if n <> 12 then raise exception 'mass found % players', n; end if;
end $t$;
-- The caller is never in their own results, and a blocker can't be found nor find the one they blocked.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000002',true);
do $t$ declare n integer; begin
  select count(*) into n from public.mm_search_players('da') where username = 'DaAlpha'; if n <> 0 then raise exception 'found myself'; end if;
  -- Everyone but themselves and the private profile (DaBlocked and DaBlocker only blocked the viewer).
  select count(*) into n from public.mm_search_players('da'); if n <> 8 then raise exception 'DaAlpha found % players', n; end if;
end $t$;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000009',true);
do $t$ declare n integer; begin
  select count(*) into n from public.mm_search_players('viewer'); if n <> 0 then raise exception 'blocker found the blocked'; end if;
end $t$;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000008',true);
do $t$ declare n integer; begin
  select count(*) into n from public.mm_search_players('viewer'); if n <> 0 then raise exception 'blocked found the blocker'; end if;
end $t$;

-- Recording games: validation, duplicates, unknown fields dropped.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; ok boolean; begin
  -- Five games, oldest first: three wins, a loss, a win. Ranked ones carry the standing afterwards.
  ok := public.mm_record_game('a0000000-0000-0000-0000-000000000001', now() - interval '10 days', 'ranked', 'win', 'Krenko Goblins',
          array['Krenko, Mob Boss'], array['R'], '[{"name":"Bot One","commander":"Edgar Markov","ai":true}]'::jsonb, 9, 1800, 20);
  if ok is not true then raise exception 'first game not stored'; end if;
  perform public.mm_record_game('a0000000-0000-0000-0000-000000000002', now() - interval '9 days', 'ranked', 'win', 'Krenko Goblins',
          array['Krenko, Mob Boss'], array['R'], '[{"name":"Bot Two","ai":true}]'::jsonb, 11, 2400, 21);
  perform public.mm_record_game('a0000000-0000-0000-0000-000000000003', now() - interval '8 days', 'ranked', 'win', 'Gruul',
          array['Krenko, Mob Boss'], array['G','R','R','X'], '[{"name":"Bot Three","commander":"Atraxa","ai":true}]'::jsonb, 7, null, 22);
  perform public.mm_record_game('a0000000-0000-0000-0000-000000000004', now() - interval '2 days', 'ranked', 'loss', 'Krenko Goblins',
          array['Krenko, Mob Boss'], array['R'], '[{"name":"Bot Four","ai":true}]'::jsonb, 5, 1200, 21);
  -- Two human opponents, one of whom the viewer blocked; an unknown field and a long name are cleaned.
  perform public.mm_record_game('a0000000-0000-0000-0000-000000000005', now() - interval '1 day', 'casual', 'win', 'Edgar',
          array['Edgar Markov'], array['W','B','R'],
          ('[{"name":"DaBlocked","ai":false,"evil":"<script>"},{"name":"DaFriend","commander":"Edgar Markov","ai":false},{"name":"' || repeat('n', 70) || '","ai":true}]')::jsonb, 12, 3600, null);
  -- The same game again is stored once.
  ok := public.mm_record_game('a0000000-0000-0000-0000-000000000001', now() - interval '10 days', 'ranked', 'win', 'Krenko Goblins',
          array['Krenko, Mob Boss'], array['R'], '[]'::jsonb, 9, 1800, 20);
  if ok is not false then raise exception 'duplicate stored'; end if;
  -- Bad input.
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'duel', 'win', 'D', array['A'], array['R'], '[]'::jsonb); raise exception 'bad mode';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'won', 'D', array['A'], array['R'], '[]'::jsonb); raise exception 'bad result';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now() + interval '3 days', 'quick', 'win', 'D', array['A'], array['R'], '[]'::jsonb); raise exception 'future game';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now() - interval '2 years', 'quick', 'win', 'D', array['A'], array['R'], '[]'::jsonb); raise exception 'ancient game';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(null, now(), 'quick', 'win', 'D', array['A'], array['R'], '[]'::jsonb); raise exception 'no client id';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', repeat('d', 81), array['A'], array['R'], '[]'::jsonb); raise exception 'long deck name';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'D', array['A','B','C','D','E'], array['R'], '[]'::jsonb); raise exception 'five commanders';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'D', array['A'], array['R'],
          '[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"}]'::jsonb); raise exception 'four opponents';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'D', array['A'], array['R'], '[{"name":""}]'::jsonb); raise exception 'nameless opponent';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'D', array['A'], array['R'], '{"name":"x"}'::jsonb); raise exception 'object opponents';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'D', array['A'], array['R'], '["x"]'::jsonb); raise exception 'string opponent';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'ranked', 'win', 'D', array['A'], array['R'], '[]'::jsonb, 5, null, 200000); raise exception 'huge rank';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'D', array['A'], array['R'], '[]'::jsonb, 5000); raise exception 'huge turns';
  exception when others then if sqlerrm <> 'invalid_game' then raise; end if; end;
end $t$;

-- The public profile: what another player sees.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; g jsonb; sum_games integer; begin
  r := public.mm_public_profile('daalpha');
  if r->>'username' <> 'DaAlpha' or (r->>'restricted')::boolean or r->>'relation' <> 'none' or r->>'visibility' <> 'public' then
    raise exception 'profile header wrong: %', r; end if;
  if jsonb_typeof(r->'online') <> 'null' then raise exception 'stranger online shown: %', r->'online'; end if;
  if (r#>>'{rank,step}')::int <> 13 or (r#>>'{rank,peakStep}')::int <> 14 or r->>'favoriteCommander' <> 'Krenko, Mob Boss' then
    raise exception 'rank wrong: %', r->'rank'; end if;
  if (r#>>'{stats,games}')::int <> 5 or (r#>>'{stats,wins}')::int <> 4 or (r#>>'{stats,losses}')::int <> 1 or (r#>>'{stats,draws}')::int <> 0
     or (r#>>'{stats,bestStreak}')::int <> 3 or (r#>>'{stats,currentStreak}')::int <> 1 or (r#>>'{stats,avgTurns}')::numeric <> 8.8 then
    raise exception 'stats wrong: %', r->'stats'; end if;
  -- Rank history: the four ranked games, oldest first, as ladder points.
  if jsonb_array_length(r->'rankHistory') <> 4 or (r#>>'{rankHistory,0,points}')::int <> 20 or (r#>>'{rankHistory,2,points}')::int <> 22
     or (r#>>'{rankHistory,3,points}')::int <> 21 then raise exception 'rank history wrong: %', r->'rankHistory'; end if;
  if r#>>'{commanders,0,name}' <> 'Krenko, Mob Boss' or (r#>>'{commanders,0,games}')::int <> 4 or (r#>>'{commanders,0,wins}')::int <> 3
     or r#>>'{commanders,1,name}' <> 'Edgar Markov' then raise exception 'commanders wrong: %', r->'commanders'; end if;
  -- Colors in W U B R G order, repeats and unknown symbols dropped: W B R G -> W:1 B:1 R:5 G:1.
  if r#>>'{colors,0,color}' <> 'W' or r#>>'{colors,1,color}' <> 'B' or r#>>'{colors,2,color}' <> 'R' or (r#>>'{colors,2,games}')::int <> 5
     or r#>>'{colors,3,color}' <> 'G' or jsonb_array_length(r->'colors') <> 4 then raise exception 'colors wrong: %', r->'colors'; end if;
  -- Eight weeks, the last of them this week, adding up to the five games.
  select sum((w->>'games')::int) into sum_games from jsonb_array_elements(r->'weekly') w;
  if jsonb_array_length(r->'weekly') <> 8 or sum_games <> 5 then raise exception 'weekly wrong: %', r->'weekly'; end if;
  -- Games: newest first, opponents named; the blocked one is hidden, unknown fields and long names are cut.
  if jsonb_array_length(r->'games') <> 5 or r#>>'{games,0,mode}' <> 'casual' or r#>>'{games,4,deckName}' <> 'Krenko Goblins' then
    raise exception 'games wrong: %', r->'games'; end if;
  g := r#>'{games,0,opponents}';
  if jsonb_array_length(g) <> 3 or g#>>'{0,name}' <> 'Hidden player' or (g#>'{0,hidden}') <> 'true'::jsonb or g#>>'{1,name}' <> 'DaFriend'
     or (g#>>'{1,commander}') <> 'Edgar Markov' or char_length(g#>>'{2,name}') <> 60 or g->0 ? 'evil' then
    raise exception 'opponents wrong: %', g; end if;
  if r#>>'{games,4,opponents,0,commander}' <> 'Edgar Markov' or (r#>'{games,4,opponents,0,ai}') <> 'true'::jsonb then
    raise exception 'AI opponent wrong: %', r#>'{games,4,opponents}'; end if;
  -- A friend's presence shows to friends; a profile with no games is empty, not an error.
  r := public.mm_public_profile('DaFriend');
  if r->>'relation' <> 'friend' or (r->>'online')::boolean is not true or (r#>>'{stats,games}')::int <> 0
     or jsonb_array_length(r->'games') <> 0 or jsonb_array_length(r->'weekly') <> 8 or (r#>>'{stats,currentStreak}')::int <> 0 then
    raise exception 'friend profile wrong: %', r; end if;
end $t$;

-- Visibility: public for everyone, friends-only for friends, private for the owner alone.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_public_profile('DaPrivate');
  if not (r->>'restricted')::boolean or r->>'visibility' <> 'private' or r ? 'stats' or r ? 'games' or r ? 'rank' then
    raise exception 'private profile open: %', r; end if;
  r := public.mm_public_profile('DaFriendsOnly');
  if not (r->>'restricted')::boolean or r->>'visibility' <> 'friends' or r->>'relation' <> 'none' or r ? 'stats' then
    raise exception 'friends-only profile open to a stranger: %', r; end if;
  -- Blocked either way, or unknown: not found.
  begin perform public.mm_public_profile('DaBlocked'); raise exception 'blocked profile open';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  begin perform public.mm_public_profile('DaBlocker'); raise exception 'blocker profile open';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  begin perform public.mm_public_profile('NoSuchPlayer'); raise exception 'unknown profile open';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  begin perform public.mm_public_profile(null); raise exception 'null profile open';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  -- Ranked cards follow the same rule, and a private friend drops out of the friends' ranks.
  r := public.mm_profile_card('DaPrivate');
  if r->>'username' <> 'DaPrivate' or r->>'rankStep' is not null or r->>'favoriteCommander' is not null then raise exception 'private card open: %', r; end if;
  r := public.mm_profile_card('DaFriendsOnly');
  if r->>'rankStep' is not null then raise exception 'friends-only card open to a stranger: %', r; end if;
  r := public.mm_profile_card('DaAlpha');
  if (r->>'rankStep')::int <> 13 then raise exception 'public card hidden: %', r; end if;
  if not exists (select 1 from public.mm_friend_ranks() where username = 'DaFriend') then raise exception 'friend rank missing'; end if;
  -- The viewer befriends DaFriendsOnly: now the profile opens.
  perform public.mm_friend_request('DaFriendsOnly');
end $t$;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000007',true);
select public.mm_respond_friend('f7000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_public_profile('DaFriendsOnly');
  if (r->>'restricted')::boolean or r->>'relation' <> 'friend' or (r#>>'{rank,step}')::int <> 5 then raise exception 'friends-only profile closed to a friend: %', r; end if;
  r := public.mm_profile_card('DaFriendsOnly');
  if (r->>'rankStep')::int <> 5 then raise exception 'friends-only card closed to a friend: %', r; end if;
end $t$;
-- Going private hides everything again, including from friends; the owner still sees their own profile.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000005',true);
select public.mm_set_visibility('private');
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_public_profile('DaFriend');
  if not (r->>'restricted')::boolean or r->>'relation' <> 'friend' or r ? 'stats' then raise exception 'private friend open: %', r; end if;
  if exists (select 1 from public.mm_friend_ranks() where username = 'DaFriend') then raise exception 'private friend rank shown'; end if;
  if exists (select 1 from public.mm_search_players('dafriend') where username = 'DaFriend') then raise exception 'private friend found'; end if;
end $t$;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000005',true);
do $t$ declare r jsonb; begin
  r := public.mm_public_profile('DaFriend');
  if (r->>'restricted')::boolean or r->>'relation' <> 'self' or r->>'visibility' <> 'private' then raise exception 'own profile closed: %', r; end if;
  perform public.mm_set_visibility('public');
end $t$;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_public_profile('DaFriend');
  if (r->>'restricted')::boolean then raise exception 'public again but closed: %', r; end if;
end $t$;
-- Blocking after the fact closes the profile at once.
do $t$ begin
  perform public.mm_block('DaAlpha');
  begin perform public.mm_public_profile('DaAlpha'); raise exception 'blocked after viewing';
  exception when others then if sqlerrm <> 'not_found' then raise; end if; end;
  perform public.mm_unblock('DaAlpha');
  perform public.mm_public_profile('DaAlpha');
end $t$;

-- Limits: 100 new games an hour per player.
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000003',true);
do $t$ declare i integer; begin
  for i in 1..100 loop
    perform public.mm_record_game(gen_random_uuid(), now() - i * interval '1 minute', 'quick', 'win', 'Deck', array['A'], array['R'], '[]'::jsonb);
  end loop;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'Deck', array['A'], array['R'], '[]'::jsonb); raise exception 'rate limit ignored';
  exception when others then if sqlerrm <> 'too_many_games' then raise; end if; end;
  -- Re-sending a stored game is not a new game.
  if (select count(*) from public.mm_public_profile('DaBeta_') p, jsonb_array_elements(p->'games')) <> 30 then raise exception 'games not capped at 30'; end if;
end $t$;

-- The newest 500 games are kept.
reset role;
insert into public.player_games(user_id, client_id, played_at, mode, result, created_at)
select 'f7000000-0000-0000-0000-000000000004', gen_random_uuid(), now() - interval '30 days' - n * interval '1 hour', 'quick', 'win', now() - interval '2 days'
from generate_series(1, 505) n;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000004',true);
select public.mm_record_game(gen_random_uuid(), now(), 'quick', 'loss', 'Newest', array['Edgar Markov'], array['B'], '[]'::jsonb);
reset role;
do $t$ declare n integer; begin
  select count(*) into n from public.player_games where user_id = 'f7000000-0000-0000-0000-000000000004';
  if n <> 500 then raise exception 'kept % games', n; end if;
  if not exists (select 1 from public.player_games where user_id = 'f7000000-0000-0000-0000-000000000004' and deck_name = 'Newest') then raise exception 'newest game lost'; end if;
  if exists (select 1 from public.player_games where user_id = 'f7000000-0000-0000-0000-000000000004' and played_at < now() - interval '30 days' - 499 * interval '1 hour') then
    raise exception 'oldest games kept'; end if;
end $t$;

-- Search stays on the prefix index (the table here is tiny, so sequential scans are switched off).
do $t$ declare plan text := ''; line text; begin
  set local enable_seqscan = off;
  for line in execute 'explain select 1 from public.profiles where username is not null and lower(username) like ''da%''' loop plan := plan || line; end loop;
  if plan !~ 'profiles_username_prefix_idx' then raise exception 'prefix search skips its index: %', plan; end if;
  plan := '';
  for line in execute 'explain select 1 from public.profiles where username is not null and lower(username) like ''da\_%''' loop plan := plan || line; end loop;
  if plan !~ 'profiles_username_prefix_idx' then raise exception 'escaped prefix search skips its index: %', plan; end if;
end $t$;

-- No direct table access, no internal helper, nothing for anon.
set local role authenticated;
select set_config('request.jwt.claim.sub','f7000000-0000-0000-0000-000000000001',true);
do $t$ begin
  begin perform 1 from public.player_games limit 1; raise exception 'games readable';
  exception when insufficient_privilege then null; end;
  begin insert into public.player_games(user_id, client_id, played_at, mode, result) values ('f7000000-0000-0000-0000-000000000001', gen_random_uuid(), now(), 'quick', 'win');
    raise exception 'games writable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_can_view_profile('f7000000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000002'); raise exception 'viewer check callable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
set local role anon;
do $t$ begin
  begin perform public.mm_search_players('da'); raise exception 'anon search';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_public_profile('DaAlpha'); raise exception 'anon profile';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_record_game(gen_random_uuid(), now(), 'quick', 'win', 'D', array['A'], array['R'], '[]'::jsonb); raise exception 'anon record';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_set_visibility('private'); raise exception 'anon visibility';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

-- Deleting an account removes its games.
delete from auth.users where id = 'f7000000-0000-0000-0000-000000000002';
do $t$ begin
  if exists (select 1 from public.player_games where user_id = 'f7000000-0000-0000-0000-000000000002') then raise exception 'games kept after account deletion'; end if;
  if not exists (select 1 from public.player_games where user_id = 'f7000000-0000-0000-0000-000000000004') then raise exception 'other games removed'; end if;
end $t$;
rollback;
