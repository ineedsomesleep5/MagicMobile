-- Crushing losses (20261026220000_ranked_crushing_loss.sql): two pips when the AI kept 30 of its 40 life.
insert into auth.users(id,aud,role,email) values
 ('d9400000-0000-0000-0000-000000000001','authenticated','authenticated','crushed@example.invalid');
insert into public.profiles(id, display_name, username) values ('d9400000-0000-0000-0000-000000000001', 'Crushed', 'Crushed');

-- A Bronze loss is free even when crushed.
do $t$ begin
  if (public.mm_ranked_apply('d9400000-0000-0000-0000-000000000001', 'loss', 2, 'ai', null, null, true)->>'pointsAfter')::int <> 0 then
    raise exception 'bronze crushed loss cost pips'; end if;
end $t$;
-- Eleven wins: Silver, 22 points (above its floor of 16).
do $t$ declare i int; begin
  for i in 1..11 loop perform public.mm_ranked_apply('d9400000-0000-0000-0000-000000000001', 'win', 2, 'ai', null, null); end loop;
  if (public.mm_ranked_current('d9400000-0000-0000-0000-000000000001')).points <> 22 then raise exception 'setup points'; end if;
end $t$;

set local role authenticated;
select set_config('request.jwt.claim.sub','d9400000-0000-0000-0000-000000000001',true);
do $t$ declare c text; begin
  foreach c in array array['crushed', 'close', 'bare'] loop
    perform set_config('test.loss_' || c, public.mm_ranked_ai_start2(2)->>'id', true);
  end loop;
end $t$;
reset role;
update public.ranked_ai_games set seed = -4123456789012345678, created_at = now() - interval '30 minutes'
 where user_id = 'd9400000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub','d9400000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_ranked_ai_result2(current_setting('test.loss_crushed')::uuid, 'loss', (select record from public.test_records where name = 'crushed'));
  if (r->'change'->>'pointsBefore')::int - (r->'change'->>'pointsAfter')::int <> 2 or r->'change'->>'crushed' <> 'true' then
    raise exception 'crushed: %', r; end if;
  r := public.mm_ranked_ai_result2(current_setting('test.loss_close')::uuid, 'loss', (select record from public.test_records where name = 'close_loss'));
  if (r->'change'->>'pointsBefore')::int - (r->'change'->>'pointsAfter')::int <> 1 or r->'change' ? 'crushed' then
    raise exception 'close: %', r; end if;
  r := public.mm_ranked_ai_result2(current_setting('test.loss_bare')::uuid, 'loss', null);
  if (r->'change'->>'pointsBefore')::int - (r->'change'->>'pointsAfter')::int <> 1 then raise exception 'bare: %', r; end if;
end $t$;
reset role;
do $t$ begin
  if (select ai_life_left from public.ranked_ai_games where id = current_setting('test.loss_crushed')::uuid) <> 34
     or (select ai_life_left from public.ranked_ai_games where id = current_setting('test.loss_bare')::uuid) is not null then
    raise exception 'ai life not kept'; end if;
  if (public.mm_ranked_current('d9400000-0000-0000-0000-000000000001')).points <> 18 then raise exception 'final points'; end if;
end $t$;
