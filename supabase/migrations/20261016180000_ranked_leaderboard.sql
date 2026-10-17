-- The ranked leaderboard (roadmap release A, docs/ROADMAP_LATE_2026.md): the season's players by the server's own
-- standing (ranked_standings, kept by the referee, so no phone can claim a rank), for everyone or friends only.
--
-- Privacy follows mm_can_view_profile: a private profile never appears, a friends-only one only to friends, and
-- neither side sees the other across a block. Online status (seen in the last 90 seconds) shows for every player the
-- caller may see, which for public profiles is everyone. Only players with a ranked result this season are listed.

create index if not exists ranked_standings_season_points_idx on public.ranked_standings (season, points desc);

-- p_scope: 'everyone' or 'friends'. p_limit: 1–100 rows (default 50). Returns
-- {season, scope, total, online, entries: [row…], me: row | null}, where a row is
-- {position, username, title, commander, points, step, pips, peakStep, wins, losses, online, you}.
create or replace function public.mm_ranked_leaderboard(p_scope text default 'everyone', p_limit integer default 50)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_season text := public.mm_current_season();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_result jsonb;
begin
  if p_scope is null or p_scope not in ('everyone', 'friends') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;
  -- Roll the caller into the current season first, so their own row is never last month's.
  perform public.mm_ranked_current(v_uid);

  with visible as (
    select s.user_id, s.points, s.peak_points, s.wins, s.losses, s.updated_at, p.username,
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
             'online', k.online, 'you', k.user_id = v_uid) as row
    from ranked k
  )
  select jsonb_build_object(
           'season', v_season,
           'scope', p_scope,
           'total', (select count(*) from visible),
           'online', (select count(*) from visible where online),
           'entries', coalesce((select jsonb_agg(row order by position) from rows where position <= v_limit), '[]'::jsonb),
           'me', (select row from rows where user_id = v_uid))
    into v_result;
  return v_result;
end $$;

revoke all on function public.mm_ranked_leaderboard(text, integer) from public, anon;
grant execute on function public.mm_ranked_leaderboard(text, integer) to authenticated;
