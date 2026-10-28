-- The leaderboard tells more (Caleb, 2026-10-26: "make the leaderboard look a little better"). Each row gains the
-- player's current win streak; the board gains when the season ends and last season's top three (the champions).
-- Fields only: older apps ignore what they don't read.

-- When a season (its first month, "YYYY-MM") ends: October 2026 was one month; seasons since are three (mm_season_for).
create or replace function public.mm_season_ends(p_season text) returns timestamptz
language sql immutable set search_path = '' as $$
  select (case when to_date(p_season || '-01', 'YYYY-MM-DD') < date '2026-11-01'
               then to_date(p_season || '-01', 'YYYY-MM-DD') + interval '1 month'
               else to_date(p_season || '-01', 'YYYY-MM-DD') + interval '3 months' end)::timestamp at time zone 'utc' $$;

-- The season before this one.
create or replace function public.mm_season_before(p_season text) returns text
language sql immutable set search_path = '' as $$
  select public.mm_season_for((to_date(p_season || '-01', 'YYYY-MM-DD') - 1)::timestamp at time zone 'utc') $$;

create or replace function public.mm_ranked_leaderboard(p_scope text default 'everyone', p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_season text := public.mm_current_season();
  v_last text := public.mm_season_before(public.mm_current_season());
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_result jsonb;
begin
  if p_scope is null or p_scope not in ('everyone', 'friends') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;
  -- Roll the caller into the current season first, so their own row is never last month's.
  perform public.mm_ranked_current(v_uid);

  with visible as (
    select s.user_id, s.points, s.peak_points, s.wins, s.losses, s.win_streak, s.updated_at, p.username,
           r.title, r.favorite_commander,
           coalesce(pr.last_seen_at > now() - interval '90 seconds', false) as online
    from public.ranked_standings s
    join public.profiles p on p.id = s.user_id
    left join public.ranked_profiles r on r.user_id = s.user_id
    left join public.presence pr on pr.user_id = s.user_id
    where s.season = v_season
      and s.wins + s.losses + s.draws > 0
      and p.username is not null
      and public.mm_can_view_profile(v_uid, s.user_id)
      and (p_scope = 'everyone' or s.user_id = v_uid or exists (
            select 1 from public.friendships f
             where f.status = 'accepted'
               and least(f.requester, f.addressee) = least(v_uid, s.user_id)
               and greatest(f.requester, f.addressee) = greatest(v_uid, s.user_id)))
  ), ranked as (
    select v.*, row_number() over (order by v.points desc, v.peak_points desc, v.updated_at, lower(v.username)) as position
    from visible v
  ), rows as (
    select k.position, k.user_id, jsonb_build_object(
             'position', k.position, 'username', k.username, 'title', k.title, 'commander', k.favorite_commander,
             'points', k.points, 'step', public.mm_rank_points_step(k.points), 'pips', public.mm_rank_points_pips(k.points),
             'peakStep', public.mm_rank_points_step(k.peak_points), 'wins', k.wins, 'losses', k.losses,
             'streak', k.win_streak, 'online', k.online, 'you', k.user_id = v_uid) as row
    from ranked k
  ), finished as (
    -- Last season's final standings: kept in history once a player rolls into the new season, still in their standing until then.
    select h.user_id, h.final_points as points, h.peak_points, h.wins, h.losses from public.ranked_season_history h where h.season = v_last
    union all
    select s.user_id, s.points, s.peak_points, s.wins, s.losses from public.ranked_standings s
     where s.season = v_last and s.wins + s.losses + s.draws > 0
  ), champions as (
    -- Last season's top three everyone may see, by where they finished.
    select row_number() over (order by f.points desc, f.peak_points desc, lower(p.username)) as position,
           p.username, f.points, f.wins, f.losses, r.favorite_commander, f.user_id
    from finished f
    join public.profiles p on p.id = f.user_id
    left join public.ranked_profiles r on r.user_id = f.user_id
    where p.username is not null
      and public.mm_can_view_profile(v_uid, f.user_id)
  )
  select jsonb_build_object(
           'season', v_season,
           'seasonEnds', public.mm_season_ends(v_season),
           'scope', p_scope,
           'total', (select count(*) from visible),
           'online', (select count(*) from visible where online),
           'entries', coalesce((select jsonb_agg(row order by position) from rows where position <= v_limit), '[]'::jsonb),
           'me', (select row from rows where user_id = v_uid),
           'champions', jsonb_build_object('season', v_last, 'entries', coalesce((
             select jsonb_agg(jsonb_build_object('position', c.position, 'username', c.username,
                                                 'step', public.mm_rank_points_step(c.points), 'pips', public.mm_rank_points_pips(c.points),
                                                 'wins', c.wins, 'losses', c.losses, 'commander', c.favorite_commander,
                                                 'you', c.user_id = v_uid) order by c.position)
               from champions c where c.position <= 3), '[]'::jsonb)))
    into v_result;
  return v_result;
end $$;
revoke all on function public.mm_ranked_leaderboard(text, integer) from public, anon;
grant execute on function public.mm_ranked_leaderboard(text, integer) to authenticated;
