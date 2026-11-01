-- Trophies from the server (Caleb, 2026-11-01: "more trophies and the ability to add more over the server"). A trophy is an
-- award with `shelf` set: it stands on the profile's Trophies shelf, dark until earned, so a new one needs only a row. Rules
-- can now read a player's games, not just their ranked standing. docs/SERVER_CONTROLS.md "Trophies".

alter table public.awards add column if not exists shelf boolean not null default false;
alter table public.awards add column if not exists shelf_order integer not null default 100;

-- Games matching a rule's filters. Every filter is optional: mode, result, maxTurns, minTurns, maxSeconds, minColors, human.
create or replace function public.mm_award_games(p_user uuid, p_rule jsonb) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.player_games g
   where g.user_id = p_user
     and (p_rule ->> 'mode' is null or g.mode = p_rule ->> 'mode')
     and (p_rule ->> 'result' is null or g.result = p_rule ->> 'result')
     and (p_rule ->> 'maxTurns' is null or g.turns between 1 and (p_rule ->> 'maxTurns')::integer)
     and (p_rule ->> 'minTurns' is null or g.turns >= (p_rule ->> 'minTurns')::integer)
     and (p_rule ->> 'maxSeconds' is null or g.duration_seconds between 1 and (p_rule ->> 'maxSeconds')::integer)
     and (p_rule ->> 'minColors' is null or cardinality(g.colors) >= (p_rule ->> 'minColors')::integer)
     and (coalesce((p_rule ->> 'human')::boolean, false) = false
          or exists (select 1 from jsonb_array_elements(g.opponents) o where o ->> 'ai' = 'false'))
$$;

-- Different commanders a player has won with.
create or replace function public.mm_award_commanders(p_user uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select count(distinct c)::integer from public.player_games g, unnest(g.commanders) c
   where g.user_id = p_user and g.result = 'win'
$$;

-- Wins in the season's five placement matches, once they're done.
create or replace function public.mm_award_placement_wins(s public.ranked_standings) returns integer
language sql stable security definer set search_path = '' as $$
  select case when s.placement_left > 0 then 0 else
    (select count(*)::integer from (select r.outcome from public.ranked_results r
                                     where r.user_id = s.user_id and r.season = s.season
                                     order by r.created_at, r.id limit 5) f where f.outcome = 'win') end
$$;

-- Gives the awards whose rule the player now meets. p_only limits it to one award; p_at backdates it.
create or replace function public.mm_awards_check(p_user uuid, p_only text default null, p_at timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.ranked_standings%rowtype;
  a public.awards%rowtype;
  v_peak integer := 0;
  v_first integer;
  v_met boolean;
begin
  select * into s from public.ranked_standings where user_id = p_user;
  if found then
    select greatest(s.peak_points, coalesce(max(h.peak_points), 0)) into v_peak
      from public.ranked_season_history h where h.user_id = p_user;
  end if;
  for a in select w.* from public.awards w
            where w.active and w.rule is not null and (p_only is null or w.id = p_only)
              and not exists (select 1 from public.player_awards p where p.user_id = p_user and p.award_id = w.id)
  loop
    v_met := case a.rule ->> 'kind'
      when 'peak_step' then s.user_id is not null and public.mm_rank_points_step(v_peak) >= (a.rule ->> 'step')::integer
      when 'season_wins' then s.user_id is not null and s.wins >= (a.rule ->> 'count')::integer
      when 'win_streak' then s.user_id is not null and s.win_streak >= (a.rule ->> 'count')::integer
      when 'games' then public.mm_award_games(p_user, a.rule) >= (a.rule ->> 'count')::integer
      when 'commanders' then public.mm_award_commanders(p_user) >= (a.rule ->> 'count')::integer
      when 'placement_wins' then s.user_id is not null and public.mm_award_placement_wins(s) >= (a.rule ->> 'count')::integer
      else false end;
    if not v_met then continue; end if;
    v_first := (a.rule ->> 'first')::integer;
    if v_first is not null then
      -- Two players finishing together can't both be first.
      perform pg_advisory_xact_lock(hashtext('award:' || a.id));
      if (select count(*) from public.player_awards p where p.award_id = a.id) >= v_first then continue; end if;
    end if;
    perform public.mm_award_insert(p_user, a.id, null, p_at);
  end loop;
end $$;

-- Hands out a new rule's award to whoever already earned it, in the order they did. Games count too, so this looks
-- at everyone who has played, not only those with a ranked standing.
create or replace function public.mm_awards_backfill(p_award text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_rule jsonb;
  v_points integer;
  v_row record;
  v_before integer;
begin
  select rule into v_rule from public.awards where id = p_award;
  if v_rule is null then raise exception 'award has no rule'; end if;
  select count(*) into v_before from public.player_awards where award_id = p_award;
  v_points := case when v_rule ->> 'kind' = 'peak_step' then (v_rule ->> 'step')::integer * 4 end;
  for v_row in
    select u.user_id, f.reached_at
      from (select user_id from public.ranked_standings union select user_id from public.player_games) u
      left join public.ranked_standings s on s.user_id = u.user_id
      left join lateral (select min(r.created_at) as reached_at from public.ranked_results r
                          where r.user_id = u.user_id and r.points_after >= v_points) f on true
     order by f.reached_at nulls last, s.updated_at
  loop
    perform public.mm_awards_check(v_row.user_id, p_award, v_row.reached_at);
  end loop;
  return (select count(*) from public.player_awards where award_id = p_award) - v_before;
end $$;

-- A saved game must land whatever an award does.
create or replace function public.mm_awards_on_game() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    perform public.mm_awards_check(new.user_id);
  exception when others then
    raise warning 'award check failed: %', sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists player_games_awards on public.player_games;
create trigger player_games_awards after insert on public.player_games for each row
  execute function public.mm_awards_on_game();

-- Placements are read from the results, and the standing moves before its result is saved, so this waits for the result.
drop trigger if exists ranked_results_awards on public.ranked_results;
create trigger ranked_results_awards after insert on public.ranked_results for each row
  execute function public.mm_awards_on_game();

-- The whole shelf for the caller: every trophy, with `awardedAt` on the ones they hold.
create or replace function public.mm_trophies() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_profile();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'description', a.description,
                                                       'imageUrl', a.image_url, 'tint', a.tint, 'rarity', a.rarity,
                                                       'awardedAt', p.awarded_at) order by a.shelf_order, a.created_at, a.id)
                     from public.awards a left join public.player_awards p on p.award_id = a.id and p.user_id = v_uid
                    where a.active and a.shelf), '[]'::jsonb);
end $$;

revoke all on function public.mm_award_games(uuid, jsonb), public.mm_award_commanders(uuid),
  public.mm_award_placement_wins(public.ranked_standings), public.mm_awards_on_game() from public, anon, authenticated;
revoke all on function public.mm_trophies() from public, anon;
grant execute on function public.mm_trophies() to authenticated;

-- Trophies leave the Awards row, since they have a shelf of their own.
do $$
declare
  v_def text := pg_get_functiondef('public.mm_my_awards()'::regprocedure);
  v_old text := 'public.mm_award_row(a, p)';
begin
  if position(v_old in v_def) = 0 then raise exception 'mm_my_awards changed'; end if;
  execute replace(v_def, v_old, 'public.mm_award_row(a, p) || jsonb_build_object(''shelf'', a.shelf)');
end $$;

-- The first dozen, given to everyone who has already earned them.
insert into public.awards (id, name, description, image_url, tint, rarity, rule, shelf, shelf_order)
select v.id, v.name, v.description, 'https://raw.githubusercontent.com/ineedsomesleep5/MagicMobile/main/design/awards/' || v.id || '.png',
       v.tint, v.rarity, v.rule::jsonb, true, v.position
  from (values
    ('regular', 'Regular', 'Play 100 games.', '#C9A15A', 1, '{"kind": "games", "count": 100}', 10),
    ('lifer', 'Lifer', 'Play 500 games.', '#FFCC5C', 2, '{"kind": "games", "count": 500}', 20),
    ('hundred-wins', 'Hundred Victories', 'Win 100 games.', '#FFCC5C', 2, '{"kind": "games", "count": 100, "result": "win"}', 30),
    ('ladder-climber', 'Ladder Climber', 'Play 50 ranked games.', '#7FB6FF', 1, '{"kind": "games", "count": 50, "mode": "ranked"}', 40),
    ('flawless', 'Flawless Placement', 'Win all five placement matches in a season.', '#FF9A3C', 3, '{"kind": "placement_wins", "count": 5}', 50),
    ('lightning', 'Lightning Strike', 'Win a game by turn 8.', '#FFE36B', 2, '{"kind": "games", "count": 1, "result": "win", "maxTurns": 8}', 60),
    ('swift-justice', 'Swift Justice', 'Win a game in under five minutes.', '#9FE8FF', 1, '{"kind": "games", "count": 1, "result": "win", "maxSeconds": 300}', 70),
    ('marathon', 'Marathon', 'Win a game that lasts 30 turns or more.', '#7BD88F', 2, '{"kind": "games", "count": 1, "result": "win", "minTurns": 30}', 80),
    ('collector', 'Collector', 'Win with 5 different commanders.', '#C79BFF', 1, '{"kind": "commanders", "count": 5}', 90),
    ('grand-collector', 'Grand Collector', 'Win with 15 different commanders.', '#C79BFF', 3, '{"kind": "commanders", "count": 15}', 100),
    ('five-colors', 'Five Colors', 'Win with a five-color deck.', '#FF7DBB', 2, '{"kind": "games", "count": 1, "result": "win", "minColors": 5}', 110),
    ('table-captain', 'Table Captain', 'Beat other players 10 times.', '#FF6B4A', 2, '{"kind": "games", "count": 10, "result": "win", "human": true}', 120)
  ) as v(id, name, description, tint, rarity, rule, position)
on conflict (id) do nothing;

do $$
declare v_id text;
begin
  for v_id in select id from public.awards where shelf order by shelf_order loop
    perform public.mm_awards_backfill(v_id);
  end loop;
  -- They wait unseen on the phones until the apps can show them, so nobody gets twelve ceremonies at once.
  update public.player_awards p set seen_at = now() from public.awards a
   where a.id = p.award_id and a.shelf and p.seen_at is null;
end $$;
