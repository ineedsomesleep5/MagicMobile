-- Quarterly ranked seasons (Caleb, 2026-10-26). October 2026 was a month; from November 2026 a season is three months,
-- named by its first month: "2026-11" runs November to January, then "2027-02", "2027-05", "2027-08". The apps compute
-- the same (RankLadder.season on iOS, Android and web; parity/ranked-cases.json). Apps that still count months agree
-- until December 1, 2026, so the app releases carrying this rule go out before then.

create or replace function public.mm_season_for(p_at timestamptz) returns text
language sql immutable set search_path = '' as $$
  select case when m < 2026 * 12 + 10 then to_char(p_at at time zone 'utc', 'YYYY-MM')
              else to_char(make_date((2026 * 12 + 10 + (m - (2026 * 12 + 10)) / 3 * 3) / 12,
                                     (2026 * 12 + 10 + (m - (2026 * 12 + 10)) / 3 * 3) % 12 + 1, 1), 'YYYY-MM') end
    from (select extract(year from p_at at time zone 'utc')::int * 12 + extract(month from p_at at time zone 'utc')::int - 1 as m) s
$$;

create or replace function public.mm_current_season() returns text
language sql stable set search_path = '' as $$ select public.mm_season_for(now()) $$;

-- A published rank from an earlier season counts one tier lower.
create or replace function public.mm_current_rank_step(p_uid uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when r.season = public.mm_current_season() then r.rank_step
                               else greatest(0, r.rank_step - 4) end
                   from public.ranked_profiles r where r.user_id = p_uid), 0);
$$;

-- A ranked game played this season takes the standing's points (the month comparison, rewritten in place).
do $$
declare
  v_def text := pg_get_functiondef('public.mm_record_game(uuid, timestamp with time zone, text, text, text, text[], text[], jsonb, integer, integer, integer)'::regprocedure);
  v_old text := 'to_char(p_played_at at time zone ''utc'', ''YYYY-MM'') = public.mm_current_season()';
begin
  if position(v_old in v_def) = 0 then raise exception 'mm_record_game changed; update this migration'; end if;
  execute replace(v_def, v_old, 'public.mm_season_for(p_played_at) = public.mm_current_season()');
end $$;
