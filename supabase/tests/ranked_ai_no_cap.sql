-- No daily cap on ranked AI wins (20261026210000_ranked_ai_no_cap.sql): a thirteenth win in a day counts.
insert into auth.users(id,aud,role,email) values
 ('d9300000-0000-0000-0000-000000000001','authenticated','authenticated','nocap@example.invalid');
insert into public.profiles(id, display_name, username) values ('d9300000-0000-0000-0000-000000000001', 'NoCap', 'NoCap');

set local role authenticated;
select set_config('request.jwt.claim.sub','d9300000-0000-0000-0000-000000000001',true);
-- Ten tickets an hour at most (a spam limit, kept), so the first eight are aged two hours before the rest.
do $t$ declare i int; begin
  for i in 1..8 loop perform set_config('test.nocap' || i, public.mm_ranked_ai_start(2)::text, true); end loop;
end $t$;
reset role;
update public.ranked_ai_games set created_at = now() - interval '2 hours' where user_id = 'd9300000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','d9300000-0000-0000-0000-000000000001',true);
do $t$ declare i int; begin
  for i in 9..13 loop perform set_config('test.nocap' || i, public.mm_ranked_ai_start(2)::text, true); end loop;
end $t$;
reset role;
-- Older builds' unseeded tickets: past the two-minute floor, a win needs no record.
update public.ranked_ai_games set created_at = now() - interval '10 minutes'
 where user_id = 'd9300000-0000-0000-0000-000000000001' and created_at > now() - interval '1 hour';
set local role authenticated;
select set_config('request.jwt.claim.sub','d9300000-0000-0000-0000-000000000001',true);
do $t$ declare i int; r jsonb; begin
  for i in 1..13 loop
    r := public.mm_ranked_ai_result(current_setting('test.nocap' || i)::uuid, 'win');
    if r->>'settlement' <> 'counted' then raise exception 'win % of the day: %', i, r; end if;
  end loop;
end $t$;
reset role;
