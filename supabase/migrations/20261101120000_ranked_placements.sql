-- Placement matches (Caleb, 2026-11-01). Every season, and every new player, starts with five placement matches
-- instead of dropping one tier. A placement win climbs two divisions and a loss or draw changes nothing, so five wins
-- reach Gold II. Making Mythic last season starts you two divisions higher, so five wins reach Platinum IV. The points
-- move during placements, which is what makes the AI harder as you win, but nothing is shown until the fifth game.
--
-- A win held back from the ladder (unverified, too soon) doesn't reach mm_ranked_apply, so it doesn't use up a game.

alter table public.ranked_standings add column if not exists placement_left smallint not null default 5
  check (placement_left between 0 and 5);

-- Those already playing this season keep their place. Anyone who rolled into it without playing a game places.
update public.ranked_standings s set placement_left = 0
 where s.season = public.mm_current_season() and s.wins + s.losses + s.draws > 0;

update public.ranked_standings s
   set points = v.start, peak_points = v.start, updated_at = now()
  from (select x.user_id,
               case when coalesce((select h.peak_points from public.ranked_season_history h
                                    where h.user_id = x.user_id order by h.season desc limit 1), 0) >= 80
                    then 8 else 0 end as start
          from public.ranked_standings x
         where x.season = public.mm_current_season() and x.wins + x.losses + x.draws = 0) v
 where s.user_id = v.user_id;

do $$
declare v_uid uuid;
begin
  for v_uid in select user_id from public.ranked_standings where season = public.mm_current_season()
                                                             and wins + losses + draws = 0
  loop
    perform public.mm_ranked_mirror(v_uid);
  end loop;
end $$;

-- A new season: last season into history, then five placement matches.
create or replace function public.mm_ranked_current(p_uid uuid) returns public.ranked_standings
language plpgsql security definer set search_path = '' as $$
declare
  s public.ranked_standings%rowtype;
  v_season text := public.mm_current_season();
  v_points integer;
begin
  insert into public.ranked_standings (user_id, season) values (p_uid, v_season) on conflict (user_id) do nothing;
  select * into s from public.ranked_standings where user_id = p_uid for update;
  if s.season <> v_season then
    if s.wins + s.losses + s.draws > 0 then
      insert into public.ranked_season_history (user_id, season, final_points, peak_points, wins, losses)
      values (p_uid, s.season, s.points, s.peak_points, s.wins, s.losses)
      on conflict (user_id, season) do nothing;
    end if;
    v_points := case when s.peak_points >= 80 then 8 else 0 end;
    update public.ranked_standings set season = v_season, points = v_points, peak_points = v_points,
      wins = 0, losses = 0, draws = 0, win_streak = 0, placement_left = 5, updated_at = now()
     where user_id = p_uid returning * into s;
    perform public.mm_ranked_mirror(p_uid);
  end if;
  return s;
end $$;

create or replace function public.mm_ranked_apply(p_uid uuid, p_outcome text, p_deck_bracket integer, p_source text,
                                                  p_match uuid, p_ai_game uuid, p_crushed boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s public.ranked_standings%rowtype := public.mm_ranked_current(p_uid);
  -- 0 Bronze … 4 Diamond, 5 Mythic
  v_tier integer := least(public.mm_rank_points_step(s.points) / 4, 5);
  v_placing boolean := s.placement_left > 0;
  v_delta integer := 0;
  v_streak integer := s.win_streak;
  v_bonuses text[] := '{}';
  v_after integer;
begin
  if p_outcome = 'win' then
    v_streak := v_streak + 1;
    if v_placing then
      v_delta := 8;
    else
      v_delta := (array[2, 2, 2, 1, 1, 1])[v_tier + 1];
      if p_deck_bracket is not null and p_deck_bracket < public.mm_rank_min_bracket(s.points) then
        v_delta := v_delta + 1; v_bonuses := array_append(v_bonuses, 'underdog');
      end if;
    end if;
  elsif p_outcome = 'loss' then
    -- A crushing loss (mm_ranked_ai_settle: the AI kept 30 of its 40 life) costs two pips above Bronze.
    if not v_placing then
      v_delta := -(array[0, 1, 1, 1, 1, 1])[v_tier + 1] * (case when p_crushed and v_tier > 0 then 2 else 1 end);
    end if;
    v_streak := 0;
  else
    v_streak := 0;
  end if;
  -- The floor: division IV of this tier, Diamond IV at most (so Mythic can fall back to Diamond).
  v_after := least(greatest(s.points + v_delta, least(v_tier, 4) * 16), 100080);
  update public.ranked_standings set points = v_after, peak_points = greatest(peak_points, v_after),
    wins = wins + (p_outcome = 'win')::int, losses = losses + (p_outcome = 'loss')::int,
    draws = draws + (p_outcome = 'draw')::int, win_streak = v_streak,
    placement_left = greatest(placement_left - 1, 0), updated_at = now()
   where user_id = p_uid;
  insert into public.ranked_results (user_id, season, source, match_id, ai_game, outcome, points_before, points_after, bonuses)
  values (p_uid, s.season, p_source, p_match, p_ai_game, p_outcome, s.points, v_after, v_bonuses);
  perform public.mm_ranked_mirror(p_uid);
  -- `crushed` and `placementLeft` ride beside `bonuses` (older apps decode only what they know).
  return jsonb_build_object('outcome', p_outcome, 'pointsBefore', s.points, 'pointsAfter', v_after, 'bonuses', to_jsonb(v_bonuses))
    || case when p_outcome = 'loss' and p_crushed and v_tier > 0 and not v_placing then jsonb_build_object('crushed', true) else '{}'::jsonb end
    || case when v_placing then jsonb_build_object('placementLeft', s.placement_left - 1) else '{}'::jsonb end;
end $$;
revoke all on function public.mm_ranked_apply(uuid, text, integer, text, uuid, uuid, boolean) from public, anon, authenticated;

-- A phone's earlier progress can't skip placements: the player places like everyone else.
create or replace function public.mm_ranked_seed(p_points integer, p_peak_points integer, p_wins integer, p_losses integer)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_profile();
begin
  perform public.mm_ranked_current(v_uid);
  update public.ranked_standings set origin = 'seeded', updated_at = now() where user_id = v_uid and origin = 'fresh';
  return public.mm_ranked_standing();
end $$;

-- The standing's answer gains `placementLeft`, whatever else it says.
do $$
declare
  v_def text := pg_get_functiondef('public.mm_ranked_standing()'::regprocedure);
  v_old text := '''season'', s.season, ''points'', s.points,';
begin
  if position(v_old in v_def) = 0 then raise exception 'mm_ranked_standing changed'; end if;
  execute replace(v_def, v_old, '''placementLeft'', s.placement_left, ' || v_old);
end $$;

-- Nobody on the leaderboard until they've placed.
do $$
declare
  v_def text := pg_get_functiondef('public.mm_ranked_leaderboard(text, integer)'::regprocedure);
  v_old text := 'and s.wins + s.losses + s.draws > 0';
begin
  if position(v_old in v_def) = 0 then raise exception 'mm_ranked_leaderboard changed'; end if;
  execute replace(v_def, v_old, 'and s.placement_left = 0 and s.wins + s.losses + s.draws > 0');
end $$;
