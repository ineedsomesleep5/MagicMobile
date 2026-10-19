-- Ladder option B (Caleb's choice, 2026-10-15; migration 20261015200000_ladder_option_b.sql), run last by
-- verify-ranked.mjs. The cases match the `ladder` array in apps/android/core/src/test/resources/parity/ranked-cases.json.
insert into auth.users(id,aud,role,email) values
 ('d9000000-0000-0000-0000-000000000001','authenticated','authenticated','ladder-b@example.invalid');
insert into public.profiles(id, display_name, username) values ('d9000000-0000-0000-0000-000000000001', 'LadderB', 'LadderB');

-- One result from a given standing: points before, streak before, outcome, deck bracket.
create function pg_temp.ladder_case(p_points integer, p_streak integer, p_outcome text, p_bracket integer) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  perform public.mm_ranked_current('d9000000-0000-0000-0000-000000000001');
  update public.ranked_standings set points = p_points, peak_points = p_points, win_streak = p_streak
   where user_id = 'd9000000-0000-0000-0000-000000000001';
  r := public.mm_ranked_apply('d9000000-0000-0000-0000-000000000001', p_outcome, p_bracket, 'ai', null, null);
  return r || jsonb_build_object('streakAfter', (select win_streak from public.ranked_standings
                                                  where user_id = 'd9000000-0000-0000-0000-000000000001'));
end $$;

do $t$
declare
  c record;
  r jsonb;
begin
  for c in select * from (values
    -- name, points before, streak, outcome, deck bracket, points after, streak after, bonuses
    ('a Bronze win earns two pips',                      0, 0, 'win',  2,  2, 1, '[]'),
    ('no streak bonus: the third straight win is +2',    2, 2, 'win',  2,  4, 3, '[]'),
    ('a Bronze loss costs nothing',                      6, 1, 'loss', 2,  6, 0, '[]'),
    ('Bronze IV with no pips can''t fall',               0, 1, 'loss', 2,  0, 0, '[]'),
    ('a Silver win can carry into the next division',   27, 0, 'win',  2, 29, 1, '[]'),
    ('Silver I''s last pip carries into Gold',          31, 0, 'win',  2, 33, 1, '[]'),
    ('a Gold loss empties a pip',                       38, 4, 'loss', 3, 37, 0, '[]'),
    ('Gold IV with no pips holds at the floor',         32, 0, 'loss', 2, 32, 0, '[]'),
    ('Silver underdog win: +2 and +1',                  16, 2, 'win',  1, 19, 3, '["underdog"]'),
    ('Platinum win is one pip, underdog one more',      49, 5, 'win',  2, 51, 6, '["underdog"]'),
    ('a Platinum loss drops a division within the tier', 52, 0, 'loss', 3, 51, 0, '[]'),
    ('Diamond I''s fourth pip reaches Mythic',          79, 0, 'win',  4, 80, 1, '[]'),
    ('Diamond IV with no pips holds at the floor',      64, 0, 'loss', 4, 64, 0, '[]'),
    ('Mythic counts up',                                85, 0, 'win',  3, 87, 1, '["underdog"]'),
    ('a loss at Mythic 0 falls to Diamond I',           80, 0, 'loss', 4, 79, 0, '[]'),
    ('a draw changes nothing and ends the streak',      21, 2, 'draw', 2, 21, 0, '[]')
  ) v(name, before, streak, outcome, bracket, after, streak_after, bonuses)
  loop
    r := pg_temp.ladder_case(c.before, c.streak, c.outcome, c.bracket);
    if (r->>'pointsAfter')::int <> c.after or (r->>'streakAfter')::int <> c.streak_after or r->'bonuses' <> c.bonuses::jsonb then
      raise exception 'option B case "%": %', c.name, r; end if;
  end loop;
end $t$;

-- The public card follows: Mythic 0 → Diamond I with 3 pips.
do $t$ begin
  perform pg_temp.ladder_case(80, 0, 'loss', 4);
  if (select (rank_step, pips) from public.ranked_profiles where user_id = 'd9000000-0000-0000-0000-000000000001')
     is distinct from (19, 3) then raise exception 'card not mirrored under option B'; end if;
end $t$;

-- Still internal: signed-in players can't call it.
set local role authenticated;
select set_config('request.jwt.claim.sub','d9000000-0000-0000-0000-000000000001',true);
do $t$ begin
  begin perform public.mm_ranked_apply('d9000000-0000-0000-0000-000000000001', 'win', 1, 'ai', null, null); raise exception 'apply callable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;
