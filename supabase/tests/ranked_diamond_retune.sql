-- Diamond retune (20261029220000_ranked_diamond_retune.sql): Diamond plays at skill 6 with Power 8–9, Mythic 8.75–9.75.
do $t$ begin
  if public.mm_ranked_ai_tuning_for(64) <> '{"aiSkill":6,"aiMistakePercent":0,"aiPower":8.13}'::jsonb then raise exception 'diamond iv: %', public.mm_ranked_ai_tuning_for(64); end if;
  if public.mm_ranked_ai_tuning_for(79) <> '{"aiSkill":6,"aiMistakePercent":0,"aiPower":8.88}'::jsonb then raise exception 'diamond i: %', public.mm_ranked_ai_tuning_for(79); end if;
  if public.mm_ranked_ai_tuning_for(500) <> '{"aiSkill":6,"aiMistakePercent":0,"aiPower":9.25}'::jsonb then raise exception 'mythic: %', public.mm_ranked_ai_tuning_for(500); end if;
  -- Tiers without a skill keep the ladder's own.
  if public.mm_ranked_ai_tuning_for(48)->>'aiSkill' <> '4' or public.mm_ranked_ai_tuning_for(32)->>'aiSkill' <> '3' then raise exception 'ladder skill'; end if;
  -- A retune of the skill is one row update.
  update public.ranked_ai_tuning set ai_skill = 5 where tier = 3;
  if public.mm_ranked_ai_tuning_for(48)->>'aiSkill' <> '5' then raise exception 'platinum skill retune'; end if;
  update public.ranked_ai_tuning set ai_skill = null where tier = 3;
  begin update public.ranked_ai_tuning set ai_skill = 11 where tier = 4; raise exception 'skill 11 stored';
  exception when check_violation then null; end;
end $t$;

insert into auth.users(id,aud,role,email) values
 ('d9500000-0000-0000-0000-000000000001','authenticated','authenticated','diamond@example.invalid');
insert into public.profiles(id, display_name, username) values ('d9500000-0000-0000-0000-000000000001', 'Diamond', 'Diamond');
insert into public.ranked_standings(user_id, season, points, peak_points, wins, losses)
values ('d9500000-0000-0000-0000-000000000001', public.mm_season_for(now()), 64, 64, 30, 10);

set local role authenticated;
select set_config('request.jwt.claim.sub','d9500000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_ai_start2(4);
  if r->>'aiSkill' <> '6' or r->>'aiMistakePercent' <> '0' or r->>'aiPower' <> '8.13' then raise exception 'diamond ticket: %', r; end if;
  perform set_config('test.diamond', r->>'id', true);
  perform set_config('test.diamond_old_app', public.mm_ranked_ai_start2(4)->>'id', true);
  perform set_config('test.diamond_easier', public.mm_ranked_ai_start2(4)->>'id', true);
end $t$;
reset role;
do $t$ begin
  if (select ai_skill from public.ranked_ai_games where id = current_setting('test.diamond')::uuid) <> 6 then raise exception 'ticket skill not stored'; end if;
end $t$;
update public.ranked_ai_games set seed = -4123456789012345678, created_at = now() - interval '30 minutes'
 where user_id = 'd9500000-0000-0000-0000-000000000001';

-- An older app still plays Diamond at skill 5: its win counts. Skill 4 is two tiers easier than the ticket: it does not.
set local role authenticated;
select set_config('request.jwt.claim.sub','d9500000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_ai_result2(current_setting('test.diamond_old_app')::uuid, 'win', (select record from public.test_records where name = 'diamond_skill5'));
  if r->>'settlement' <> 'counted' then raise exception 'older app at skill 5: %', r; end if;
  r := public.mm_ranked_ai_result2(current_setting('test.diamond_easier')::uuid, 'win', (select record from public.test_records where name = 'diamond_skill4'));
  if r->>'settlement' <> 'unverified' or r->>'check' <> 'ai_settings' then raise exception 'skill 4 on a Diamond ticket: %', r; end if;
end $t$;
reset role;
