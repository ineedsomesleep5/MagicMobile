-- Ranked AI tuning on the server (20261026200000_ranked_ai_tuning.sql), after the turn rule and the check answer.
do $t$ declare r jsonb; begin
  -- Bronze IV, Gold IV to I, Platinum and Mythic: skill, mistake chance and deck Power target.
  if public.mm_ranked_ai_tuning_for(0) <> '{"aiSkill":1,"aiMistakePercent":15,"aiPower":3.13}'::jsonb then raise exception 'bronze: %', public.mm_ranked_ai_tuning_for(0); end if;
  if public.mm_ranked_ai_tuning_for(32) <> '{"aiSkill":3,"aiMistakePercent":8,"aiPower":5.63}'::jsonb then raise exception 'gold iv: %', public.mm_ranked_ai_tuning_for(32); end if;
  if public.mm_ranked_ai_tuning_for(37)->>'aiMistakePercent' <> '7' or public.mm_ranked_ai_tuning_for(41)->>'aiMistakePercent' <> '6' then raise exception 'gold iii/ii'; end if;
  if public.mm_ranked_ai_tuning_for(47) <> '{"aiSkill":3,"aiMistakePercent":5,"aiPower":6.38}'::jsonb then raise exception 'gold i: %', public.mm_ranked_ai_tuning_for(47); end if;
  if public.mm_ranked_ai_tuning_for(48) <> '{"aiSkill":4,"aiMistakePercent":0,"aiPower":6.13}'::jsonb then raise exception 'platinum iv: %', public.mm_ranked_ai_tuning_for(48); end if;
  if public.mm_ranked_ai_tuning_for(500) <> '{"aiSkill":6,"aiMistakePercent":0,"aiPower":8.5}'::jsonb then raise exception 'mythic: %', public.mm_ranked_ai_tuning_for(500); end if;
end $t$;

insert into auth.users(id,aud,role,email) values
 ('d9200000-0000-0000-0000-000000000001','authenticated','authenticated','tuning@example.invalid');
insert into public.profiles(id, display_name, username) values ('d9200000-0000-0000-0000-000000000001', 'Tuning', 'Tuning');
-- A retune is one row update: Bronze at 12%.
update public.ranked_ai_tuning set mistakes_division_iv = 12, mistakes_division_i = 12 where tier = 0;

set local role authenticated;
select set_config('request.jwt.claim.sub','d9200000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; c text; begin
  r := public.mm_ranked_ai_start2(2);
  if r->>'aiSkill' <> '1' or r->>'aiMistakePercent' <> '12' or r->>'aiPower' <> '3.13' or r->>'seed' is null then raise exception 'start2: %', r; end if;
  perform set_config('test.tuned', r->>'id', true);
  foreach c in array array['standard', 'other'] loop
    perform set_config('test.' || c, public.mm_ranked_ai_start2(2)->>'id', true);
  end loop;
  begin perform 1 from public.ranked_ai_tuning; raise exception 'tuning table readable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
do $t$ begin
  if (select ai_mistakes from public.ranked_ai_games where id = current_setting('test.tuned')::uuid) <> 12
     or (select ai_power from public.ranked_ai_games where id = current_setting('test.tuned')::uuid) <> 3.13 then raise exception 'ticket not stored'; end if;
end $t$;
update public.ranked_ai_games set seed = -4123456789012345678, created_at = now() - interval '30 minutes'
 where user_id = 'd9200000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub','d9200000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  -- The ticket's 12%, and an older app's standard 15%, both count; any other chance does not.
  r := public.mm_ranked_ai_result2(current_setting('test.tuned')::uuid, 'win', (select record from public.test_records where name = 'tuned'));
  if r->>'settlement' <> 'counted' then raise exception 'tuned: %', r; end if;
  r := public.mm_ranked_ai_result2(current_setting('test.standard')::uuid, 'win', (select record from public.test_records where name = 'valid'));
  if r->>'settlement' <> 'counted' then raise exception 'standard: %', r; end if;
  r := public.mm_ranked_ai_result2(current_setting('test.other')::uuid, 'win', (select record from public.test_records where name = 'easier_ai'));
  if r->>'settlement' <> 'unverified' or r->>'check' <> 'ai_settings' then raise exception 'other: %', r; end if;
end $t$;
reset role;
