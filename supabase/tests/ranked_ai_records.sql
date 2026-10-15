-- Ranked AI wins backed by game records (20261016120000_ranked_ai_records.sql), run last by verify-ranked.mjs. The
-- records in public.test_records are built there with node's SHA-256. Calls are made as an authenticated player;
-- seeds, skills and timestamps are set as the superuser to stand in for the server's random seed and for waiting.
insert into auth.users(id,aud,role,email) values
 ('d9100000-0000-0000-0000-000000000001','authenticated','authenticated','records@example.invalid');
insert into public.profiles(id, display_name, username) values ('d9100000-0000-0000-0000-000000000001', 'Records', 'Records');
insert into public.ranked_engine_builds(engine_build, label) values ('sha256:' || repeat('ab', 32), 'test build');

-- The ticket named p_case: its result with that case's record (null: none).
create function pg_temp.settle(p_case text, p_record text, p_result text default 'win') returns jsonb language sql as $$
  select public.mm_ranked_ai_result2(current_setting('test.' || p_case)::uuid, p_result,
                                     (select record from public.test_records where name = p_record)) $$;
create function pg_temp.check_of(p_case text) returns text language sql security definer as $$
  select coalesce(record_check, settlement) from public.ranked_ai_games where id = current_setting('test.' || p_case)::uuid $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','d9100000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; c text; begin
  r := public.mm_ranked_ai_start2(2);
  if r->>'aiSkill' <> '1' or r->>'seed' !~ '^-?[0-9]+$' or (r->>'id')::uuid is null then raise exception 'start2: %', r; end if;
  perform set_config('test.valid', r->>'id', true);
  foreach c in array array['skill_two', 'tampered', 'reseeded', 'unknown_build', 'easier_ai', 'wrong_winner', 'ai_conceded', 'short'] loop
    perform set_config('test.' || c, public.mm_ranked_ai_start2(2)->>'id', true);
  end loop;
end $t$;
reset role;
update public.ranked_ai_games set created_at = now() - interval '2 hours' where user_id = 'd9100000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','d9100000-0000-0000-0000-000000000001',true);
do $t$ declare c text; begin
  foreach c in array array['broken', 'long', 'missing', 'old_entry', 'too_low', 'lagging', 'loss'] loop
    perform set_config('test.' || c, public.mm_ranked_ai_start2(2)->>'id', true);
  end loop;
  -- An older build's ticket: no seed, today's rules.
  perform set_config('test.unseeded', public.mm_ranked_ai_start(2)::text, true);
end $t$;
reset role;
-- Every seeded ticket gets the records' seed; two tiers stand in for a player who has moved up.
update public.ranked_ai_games set seed = -4123456789012345678 where user_id = 'd9100000-0000-0000-0000-000000000001' and seed is not null;
update public.ranked_ai_games set created_at = now() - interval '30 minutes'
 where user_id = 'd9100000-0000-0000-0000-000000000001' and created_at > now() - interval '1 hour';
update public.ranked_ai_games set ai_skill = 3 where id = current_setting('test.too_low')::uuid;
update public.ranked_ai_games set ai_skill = 2 where id = current_setting('test.lagging')::uuid;
-- Sixty turns since a ticket 4.5 minutes old is too fast (5 s a turn).
update public.ranked_ai_games set created_at = now() - interval '270 seconds' where id = current_setting('test.long')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub','d9100000-0000-0000-0000-000000000001',true);
do $t$
declare
  r jsonb;
  c record;
begin
  r := pg_temp.settle('valid', 'valid');
  if r->>'settlement' <> 'counted' or (r->>'points')::int <> 2 then raise exception 'valid record not counted: %', r; end if;
  r := pg_temp.settle('valid', 'tampered');
  if r->>'settlement' <> 'counted' or (r->>'points')::int <> 2 then raise exception 're-send changed the result: %', r; end if;
  r := pg_temp.settle('skill_two', 'skill_two');
  if r->>'settlement' <> 'counted' or (r->>'points')::int <> 4 then raise exception 'a harder AI did not count: %', r; end if;
  r := pg_temp.settle('lagging', 'valid');
  if r->>'settlement' <> 'counted' then raise exception 'a tier''s lag was refused: %', r; end if;
  for c in select * from (values
    ('tampered', 'tampered', 'hash'), ('reseeded', 'reseeded', 'seed'), ('unknown_build', 'unknown_build', 'engine_build'),
    ('easier_ai', 'easier_ai', 'ai_settings'), ('too_low', 'valid', 'ai_settings'), ('wrong_winner', 'wrong_winner', 'end'),
    ('ai_conceded', 'ai_conceded', 'grammar'), ('short', 'short', 'too_short'), ('broken', 'broken', 'broken'),
    ('long', 'long', 'too_fast'), ('missing', null, 'no_record')
  ) v(game, record, reason)
  loop
    r := pg_temp.settle(c.game, c.record);
    if r->>'settlement' <> 'unverified' or pg_temp.check_of(c.game) <> c.reason or (r->>'points')::int <> 6 then
      raise exception 'case % settled % (%), points %', c.game, r->>'settlement', pg_temp.check_of(c.game), r->>'points'; end if;
  end loop;
  -- The older function cannot skip the record on a seeded ticket.
  r := public.mm_ranked_ai_result(current_setting('test.old_entry')::uuid, 'win');
  if r->>'settlement' <> 'unverified' or pg_temp.check_of('old_entry') <> 'no_record' then raise exception 'old entry: %', r; end if;
  -- Losses need no record; an older ticket keeps today's rules.
  r := pg_temp.settle('loss', null, 'loss');
  if r->>'settlement' <> 'counted' or (r->>'losses')::int <> 1 then raise exception 'loss: %', r; end if;
  r := public.mm_ranked_ai_result(current_setting('test.unseeded')::uuid, 'win');
  if r->>'settlement' <> 'counted' or (r->>'points')::int <> 8 then raise exception 'unseeded ticket: %', r; end if;
  -- No direct access to records, builds or the check.
  begin perform 1 from public.ranked_ai_records; raise exception 'records readable';
  exception when insufficient_privilege then null; end;
  begin insert into public.ranked_engine_builds values ('sha256:' || repeat('00', 32), 'mine'); raise exception 'builds writable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_ranked_ai_record_check(null::public.ranked_ai_games, null); raise exception 'check callable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

-- Records are kept for review with their head and build, one per win sent with one.
do $t$ begin
  if (select count(*) from public.ranked_ai_records r join public.ranked_ai_games g on g.id = r.game_id
       where g.user_id = 'd9100000-0000-0000-0000-000000000001') <> 13 then raise exception 'records not kept'; end if;
  if (select engine_build from public.ranked_ai_records where game_id = current_setting('test.unknown_build')::uuid)
     <> 'sha256:' || repeat('cd', 32) then raise exception 'record build not kept'; end if;
end $t$;

set local role anon;
do $t$ begin
  begin perform public.mm_ranked_ai_start2(2); raise exception 'anon started a ticket';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
