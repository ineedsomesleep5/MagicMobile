-- Season badges (Caleb, 2026-10-26): a public profile lists the player's finished seasons, so others see the badge each
-- earned (its peak tier; October 2026, the first season, carries a founder ribbon). From ranked_season_history, which
-- mm_ranked_current fills when a standing rolls into a new season.
do $$
declare
  v_def text := pg_get_functiondef('public.mm_public_profile(text)'::regprocedure);
  v_old text := '''title'', r.title, ''favoriteCommander'', r.favorite_commander,';
begin
  if position(v_old in v_def) = 0 then raise exception 'mm_public_profile changed; update this migration'; end if;
  execute replace(v_def, v_old,
    '''seasons'', (select coalesce(jsonb_agg(jsonb_build_object(''season'', h.season, ''peakPoints'', h.peak_points,
                                                     ''finalPoints'', h.final_points) order by h.season desc), ''[]''::jsonb)
                    from (select s.season, s.peak_points, s.final_points from public.ranked_season_history s
                           where s.user_id = v_target order by s.season desc limit 24) h),
      ' || v_old);
end $$;
