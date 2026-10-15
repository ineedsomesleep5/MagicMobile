-- The rank history comes from the server's ladder, not the phone (C1, Game improvement program Phase 1).
--
-- mm_record_game used to store p_rank_points as the phone sent it, so a modified app could draw any rank history
-- on its public profile even though the server keeps score (20261015120000_ranked_referee.sql). Now:
--
-- * A ranked game stores the caller's server points (ranked_standings.points, after the season rollover) at the
--   moment it is recorded. p_rank_points is ignored: never stored and never checked, so older app builds that
--   still send it keep working.
-- * A ranked game played in an earlier season (UTC month) than the current one stores no points: the standing has
--   rolled over since, so today's points would be wrong for it.
-- * A ranked game recorded while the server standing is still unseeded (made by the server, nothing counted yet,
--   so mm_ranked_seed may still bring the phone's earlier progress) stores no points either: the server does not
--   know that player's rank yet. The phones send their backlog before they seed.
-- * Quick and casual games store no points, whatever the phone sends.
--
-- The points are the standing when the game is recorded, so the phone should send a ranked game after its result
-- (mm_ranked_ai_result or the second mm_ranked_report). A game sent before that stores the points from before it;
-- a person-vs-person match the other side has not reported yet does the same. The signature, the grants and every
-- other check are unchanged.

create or replace function public.mm_record_game(
  p_client_id uuid, p_played_at timestamptz, p_mode text, p_result text, p_deck_name text, p_commanders text[],
  p_colors text[], p_opponents jsonb, p_turns integer default null, p_duration_seconds integer default null,
  p_rank_points integer default null) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_commanders text[];
  v_colors text[];
  v_opponents jsonb := '[]'::jsonb;
  v_standing public.ranked_standings%rowtype;
  v_rank_points integer;
  v_id bigint;
begin
  if p_client_id is null or p_played_at is null
     or p_played_at > now() + interval '1 day' or p_played_at < now() - interval '1 year'
     or coalesce(p_mode, '') not in ('quick', 'ranked', 'casual') or coalesce(p_result, '') not in ('win', 'loss', 'draw')
     or char_length(p_deck_name) > 80
     or p_turns not between 0 and 1000 or p_duration_seconds not between 0 and 86400
     or cardinality(p_commanders) > 4 or cardinality(p_colors) > 10 then
    raise exception 'invalid_game' using errcode = '22023';
  end if;

  select coalesce(array_agg(left(btrim(c.name), 160) order by c.ord), '{}')
    into v_commanders from unnest(coalesce(p_commanders, '{}'::text[])) with ordinality c(name, ord)
   where btrim(c.name) <> '' and c.name !~ '[[:cntrl:]]';
  select coalesce(array_agg(k order by array_position(array['W', 'U', 'B', 'R', 'G']::text[], k)), '{}')
    into v_colors from (select distinct c as k from unnest(coalesce(p_colors, '{}'::text[])) c where c in ('W', 'U', 'B', 'R', 'G')) s;

  if p_opponents is not null then
    if jsonb_typeof(p_opponents) <> 'array' or jsonb_array_length(p_opponents) > 3 then
      raise exception 'invalid_game' using errcode = '22023';
    end if;
    -- Rebuilt from the fields we know: nothing else a phone sends is kept.
    select coalesce(jsonb_agg(jsonb_build_object(
             'name', left(btrim(o.value ->> 'name'), 60),
             'commander', case when jsonb_typeof(o.value -> 'commander') = 'string' and btrim(o.value ->> 'commander') <> ''
                               then to_jsonb(left(btrim(o.value ->> 'commander'), 160)) else null end,
             'ai', coalesce((o.value -> 'ai') <> 'false'::jsonb, true)) order by o.ord), '[]'::jsonb)
      into v_opponents from jsonb_array_elements(p_opponents) with ordinality o(value, ord);
    if exists (select 1 from jsonb_array_elements(p_opponents) o(value)
                where jsonb_typeof(o.value) <> 'object' or jsonb_typeof(o.value -> 'name') <> 'string'
                   or btrim(o.value ->> 'name') = '' or (o.value ->> 'name') ~ '[[:cntrl:]]') then
      raise exception 'invalid_game' using errcode = '22023';
    end if;
  end if;

  if (select count(*) from public.player_games where user_id = v_uid and created_at > now() - interval '1 hour') >= 100 then
    raise exception 'too_many_games' using errcode = 'P0001';
  end if;

  -- The server's standing, never the phone's: mm_ranked_current creates it or rolls it into this season first.
  -- A standing the phone may still seed (fresh, nothing counted yet) is not a rank yet: no points.
  if p_mode = 'ranked' and to_char(p_played_at at time zone 'utc', 'YYYY-MM') = public.mm_current_season() then
    v_standing := public.mm_ranked_current(v_uid);
    if v_standing.origin <> 'fresh' or exists (select 1 from public.ranked_results r where r.user_id = v_uid) then
      v_rank_points := v_standing.points;
    end if;
  end if;

  insert into public.player_games (user_id, client_id, played_at, mode, result, deck_name, commanders, colors, opponents,
                                   turns, duration_seconds, rank_points)
  values (v_uid, p_client_id, p_played_at, p_mode, p_result, nullif(btrim(p_deck_name), ''), v_commanders, v_colors, v_opponents,
          p_turns, p_duration_seconds, v_rank_points)
  on conflict (user_id, client_id) do nothing
  returning id into v_id;

  if v_id is not null then
    delete from public.player_games
     where user_id = v_uid
       and id in (select g.id from public.player_games g where g.user_id = v_uid order by g.played_at desc, g.id desc offset 500);
  end if;
  return v_id is not null;
end $$;

-- Unchanged access (create or replace keeps it; stated again so this file stands alone): signed-in players only.
revoke all on function public.mm_record_game(uuid, timestamptz, text, text, text, text[], text[], jsonb, integer, integer, integer)
  from public, anon;
grant execute on function public.mm_record_game(uuid, timestamptz, text, text, text, text[], text[], jsonb, integer, integer, integer)
  to authenticated;

notify pgrst, 'reload schema';
