-- Public profiles: live player search, a privacy setting, game summaries kept on the server and a
-- profile other players can open (their rank, rank history, favourite commanders and recent games).
--
-- Additive and safe on the live database: one new column with a default, one new table, new functions,
-- and three existing functions replaced with the same signatures (mm_profile, mm_profile_card,
-- mm_friend_ranks). Apps that predate this migration keep working: the replaced functions still return
-- everything they returned before (mm_profile only gains a field).
--
-- Rules (Caleb, 2026-10-06):
--   * Profiles are public by default. A player can choose 'friends' (only accepted friends can open it)
--     or 'private' (only the player). Nobody can open the profile of someone who blocked them, or whom
--     they blocked: it reads as not found, as everywhere else.
--   * A public profile shows the opponents' player names in the game history.
--   * Search matches the start of a player name, never private profiles, never blocked players.
--
-- Same rules as the other social tables: RLS on, no direct grants, everything through mm_* functions
-- (security definer, fixed search_path), nothing callable by anon.

-- ---------------------------------------------------------------------------------------------
-- Privacy setting and prefix search index
-- ---------------------------------------------------------------------------------------------

alter table public.profiles add column if not exists visibility text not null default 'public';
alter table public.profiles drop constraint if exists profiles_visibility_check;
alter table public.profiles add constraint profiles_visibility_check check (visibility in ('public', 'friends', 'private'));

-- The unique index on lower(username) cannot serve LIKE 'da%' (collation), this one can.
create index if not exists profiles_username_prefix_idx on public.profiles (lower(username) text_pattern_ops)
  where username is not null;

-- ---------------------------------------------------------------------------------------------
-- Game summaries: one row per finished game, as the player's phone reported it
-- ---------------------------------------------------------------------------------------------

create table if not exists public.player_games (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- The phone's own id for the game (MatchRecord.id): sending a game twice stores it once.
  client_id uuid not null,
  played_at timestamptz not null,
  mode text not null check (mode in ('quick', 'ranked', 'casual')),
  result text not null check (result in ('win', 'loss', 'draw')),
  deck_name text check (char_length(deck_name) <= 80),
  commanders text[] not null default '{}'
    check (cardinality(commanders) <= 4 and char_length(array_to_string(commanders, '|')) <= 640),
  -- W U B R G
  colors text[] not null default '{}' check (colors <@ array['W', 'U', 'B', 'R', 'G']::text[]),
  -- [{name, commander, ai}] for up to three opponents. Human opponents are named by their player name.
  opponents jsonb not null default '[]'
    check (jsonb_typeof(opponents) = 'array' and jsonb_array_length(opponents) <= 3),
  turns integer check (turns between 0 and 1000),
  duration_seconds integer check (duration_seconds between 0 and 86400),
  -- A ranked game's standing afterwards as one number: ladder step * 4 + pips. The rank history is these.
  rank_points integer check (rank_points between 0 and 100100),
  created_at timestamptz not null default now(),
  unique (user_id, client_id)
);
create index if not exists player_games_user_time_idx on public.player_games (user_id, played_at desc, id desc);

alter table public.player_games enable row level security;
revoke all on public.player_games from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Who may open a profile
-- ---------------------------------------------------------------------------------------------

-- Internal. The owner always; otherwise a public profile (or a friends-only one for a friend) unless
-- either side blocked the other. It trusts the ids it is given.
create or replace function public.mm_can_view_profile(p_viewer uuid, p_target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_viewer = p_target or (
    exists (select 1 from public.profiles p
             where p.id = p_target
               and (p.visibility = 'public'
                    or (p.visibility = 'friends' and exists (
                          select 1 from public.friendships f
                           where f.status = 'accepted'
                             and least(f.requester, f.addressee) = least(p_viewer, p_target)
                             and greatest(f.requester, f.addressee) = greatest(p_viewer, p_target)))))
    and not exists (select 1 from public.blocks b
                     where (b.blocker = p_viewer and b.blocked = p_target) or (b.blocker = p_target and b.blocked = p_viewer)));
$$;

-- The caller's profile, now with the privacy choice. (Same signature as before; one more field.)
create or replace function public.mm_profile() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', public.mm_require_user(),
                            'username', (select username from public.profiles where id = auth.uid()),
                            'visibility', coalesce((select visibility from public.profiles where id = auth.uid()), 'public'));
$$;

create or replace function public.mm_set_visibility(p_visibility text) returns text
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_profile();
begin
  if p_visibility is null or p_visibility not in ('public', 'friends', 'private') then
    raise exception 'invalid_visibility' using errcode = '22023';
  end if;
  update public.profiles set visibility = p_visibility, updated_at = now() where id = v_uid;
  return p_visibility;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Search: the start of a player name, as it is typed
-- ---------------------------------------------------------------------------------------------

-- At least two characters of a player name (letters, digits, underscore), matched case-insensitively
-- at the start of the name; anything else returns nothing. At most 12 players, the exact name first,
-- then friends, then alphabetical. Never the caller, anyone blocked either way, or a private profile.
-- A friends-only profile can be found (so you can send a request) but shows no rank or commander.
-- Presence shows for accepted friends only.
create or replace function public.mm_search_players(p_prefix text)
returns table (username text, favorite_commander text, season text, rank_step integer, pips integer,
               visibility text, relation text, online boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_prefix text := lower(btrim(p_prefix));
begin
  if v_prefix is null or v_prefix !~ '^[a-z0-9_]{2,20}$' then return; end if;
  return query
  select c.username, r.favorite_commander, r.season, r.rank_step, r.pips, c.visibility,
         case when c.friendship = 'accepted' then 'friend'
              when c.friendship = 'pending' and c.requester = v_uid then 'outgoing'
              when c.friendship = 'pending' then 'incoming'
              else 'none' end,
         case when c.friendship = 'accepted' then coalesce(pr.last_seen_at > now() - interval '90 seconds', false) end
  from (
    select p.id, p.username, p.visibility, f.status as friendship, f.requester
    from public.profiles p
    left join public.friendships f
      on least(f.requester, f.addressee) = least(v_uid, p.id) and greatest(f.requester, f.addressee) = greatest(v_uid, p.id)
    where p.username is not null and p.id <> v_uid
      and lower(p.username) like replace(v_prefix, '_', '\_') || '%'
      and p.visibility <> 'private'
      and not exists (select 1 from public.blocks b
                       where (b.blocker = v_uid and b.blocked = p.id) or (b.blocker = p.id and b.blocked = v_uid))
    order by (lower(p.username) = v_prefix) desc, (f.status = 'accepted') desc nulls last, lower(p.username)
    limit 12
  ) c
  left join public.ranked_profiles r on r.user_id = c.id and public.mm_can_view_profile(v_uid, c.id)
  left join public.presence pr on pr.user_id = c.id
  order by (lower(c.username) = v_prefix) desc, (c.friendship = 'accepted') desc nulls last, lower(c.username);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Recording games
-- ---------------------------------------------------------------------------------------------

-- Called by the phone after each finished game, once it is signed in (and again later for a game it
-- could not send). Returns true when the game was stored, false when it was already there. At most
-- 100 new games an hour per player, and the newest 500 are kept.
--   p_opponents: [{name, commander, ai}] (up to three); human opponents are named by their player name.
--   p_rank_points: for a ranked game, the standing afterwards as ladder step * 4 + pips.
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
  v_id bigint;
begin
  if p_client_id is null or p_played_at is null
     or p_played_at > now() + interval '1 day' or p_played_at < now() - interval '1 year'
     or coalesce(p_mode, '') not in ('quick', 'ranked', 'casual') or coalesce(p_result, '') not in ('win', 'loss', 'draw')
     or char_length(p_deck_name) > 80
     or p_turns not between 0 and 1000 or p_duration_seconds not between 0 and 86400
     or p_rank_points not between 0 and 100100
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

  insert into public.player_games (user_id, client_id, played_at, mode, result, deck_name, commanders, colors, opponents,
                                   turns, duration_seconds, rank_points)
  values (v_uid, p_client_id, p_played_at, p_mode, p_result, nullif(btrim(p_deck_name), ''), v_commanders, v_colors, v_opponents,
          p_turns, p_duration_seconds, p_rank_points)
  on conflict (user_id, client_id) do nothing
  returning id into v_id;

  if v_id is not null then
    delete from public.player_games
     where user_id = v_uid
       and id in (select g.id from public.player_games g where g.user_id = v_uid order by g.played_at desc, g.id desc offset 500);
  end if;
  return v_id is not null;
end $$;

-- ---------------------------------------------------------------------------------------------
-- The public profile
-- ---------------------------------------------------------------------------------------------

-- Another player's profile (or the caller's own, as others see it). Not found when either side blocked
-- the other. A profile the caller may not open returns only {username, restricted: true, visibility,
-- relation}. Otherwise: rank, rank history (ladder points over time), totals, streaks, favourite
-- commanders, colour shares, games per week for the last 8 weeks and the 30 latest games with their
-- opponents' names (a human opponent who blocked or was blocked by the caller reads "Hidden player").
create or replace function public.mm_public_profile(p_username text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_target uuid := public.mm_visible_profile(v_uid, p_username);
  v_visibility text;
  v_name text;
  v_relation text;
  v_total integer;
  v_best integer;
  v_current integer;
begin
  if v_target is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  select p.visibility, p.username into v_visibility, v_name from public.profiles p where p.id = v_target;
  v_relation := case when v_target = v_uid then 'self' else coalesce((
      select case when f.status = 'accepted' then 'friend' when f.requester = v_uid then 'outgoing' else 'incoming' end
        from public.friendships f
       where least(f.requester, f.addressee) = least(v_uid, v_target) and greatest(f.requester, f.addressee) = greatest(v_uid, v_target)),
      'none') end;
  if not public.mm_can_view_profile(v_uid, v_target) then
    return jsonb_build_object('username', v_name, 'restricted', true, 'visibility', v_visibility, 'relation', v_relation);
  end if;

  select count(*) into v_total from public.player_games where user_id = v_target;
  -- Streaks: runs of equal results, numbered by their position (gaps and islands).
  select coalesce(max(runs.n) filter (where runs.result = 'win'), 0),
         coalesce(max(runs.n) filter (where runs.result = 'win' and runs.last_rn = v_total), 0)
    into v_best, v_current
    from (select s.result, count(*) as n, max(s.rn) as last_rn
            from (select g.result,
                         row_number() over (order by g.played_at, g.id) as rn,
                         row_number() over (partition by g.result order by g.played_at, g.id) as rr
                    from public.player_games g where g.user_id = v_target) s
           group by s.result, s.rn - s.rr) runs;

  return (
    select jsonb_build_object(
      'username', p.username, 'restricted', false, 'visibility', p.visibility, 'relation', v_relation,
      'online', case when v_relation = 'friend' then coalesce(pr.last_seen_at > now() - interval '90 seconds', false) end,
      'title', r.title, 'favoriteCommander', r.favorite_commander,
      'rank', case when r.user_id is null then null else jsonb_build_object(
                'season', r.season, 'step', r.rank_step, 'pips', r.pips, 'peakStep', r.peak_step,
                'wins', r.wins, 'losses', r.losses) end,
      'stats', (select jsonb_build_object(
                  'games', v_total,
                  'wins', count(*) filter (where g.result = 'win'),
                  'losses', count(*) filter (where g.result = 'loss'),
                  'draws', count(*) filter (where g.result = 'draw'),
                  'avgTurns', round(avg(g.turns) filter (where g.turns > 0), 1),
                  'bestStreak', v_best, 'currentStreak', v_current)
                from public.player_games g where g.user_id = v_target),
      'rankHistory', (select coalesce(jsonb_agg(jsonb_build_object('at', h.played_at, 'points', h.rank_points)
                                                order by h.played_at, h.id), '[]'::jsonb)
                        from (select g.played_at, g.id, g.rank_points from public.player_games g
                               where g.user_id = v_target and g.rank_points is not null
                               order by g.played_at desc, g.id desc limit 60) h),
      'commanders', (select coalesce(jsonb_agg(jsonb_build_object('name', x.name, 'games', x.games, 'wins', x.wins)
                                               order by x.games desc, x.name), '[]'::jsonb)
                       from (select u.name, count(*) as games, count(*) filter (where g.result = 'win') as wins
                               from public.player_games g, unnest(g.commanders) as u(name)
                              where g.user_id = v_target group by u.name order by 2 desc, 1 limit 6) x),
      'colors', (select coalesce(jsonb_agg(jsonb_build_object('color', x.color, 'games', x.games, 'wins', x.wins)
                                           order by array_position(array['W', 'U', 'B', 'R', 'G']::text[], x.color)), '[]'::jsonb)
                   from (select u.color, count(*) as games, count(*) filter (where g.result = 'win') as wins
                           from public.player_games g, unnest(g.colors) as u(color)
                          where g.user_id = v_target group by u.color) x),
      'weekly', (select coalesce(jsonb_agg(jsonb_build_object('week', to_char(w.week, 'YYYY-MM-DD'),
                                                              'games', coalesce(c.games, 0), 'wins', coalesce(c.wins, 0))
                                           order by w.week), '[]'::jsonb)
                   from generate_series(date_trunc('week', now() at time zone 'utc') - interval '7 weeks',
                                        date_trunc('week', now() at time zone 'utc'), interval '1 week') as w(week)
                   left join (select date_trunc('week', g.played_at at time zone 'utc') as wk, count(*) as games,
                                     count(*) filter (where g.result = 'win') as wins
                                from public.player_games g where g.user_id = v_target group by 1) c on c.wk = w.week),
      'games', (select coalesce(jsonb_agg(jsonb_build_object(
                          'id', l.client_id, 'playedAt', l.played_at, 'mode', l.mode, 'result', l.result,
                          'deckName', l.deck_name, 'commanders', to_jsonb(l.commanders), 'colors', to_jsonb(l.colors),
                          'turns', l.turns, 'durationSeconds', l.duration_seconds,
                          'opponents', (select coalesce(jsonb_agg(
                                 case when (o.value -> 'ai') = 'false'::jsonb and exists (
                                        select 1 from public.profiles op
                                        join public.blocks b on (b.blocker = v_uid and b.blocked = op.id) or (b.blocker = op.id and b.blocked = v_uid)
                                       where lower(op.username) = lower(o.value ->> 'name'))
                                      then jsonb_build_object('name', 'Hidden player', 'commander', o.value -> 'commander', 'ai', false, 'hidden', true)
                                      else o.value end order by o.ord), '[]'::jsonb)
                                  from jsonb_array_elements(l.opponents) with ordinality o(value, ord)))
                        order by l.played_at desc, l.id desc), '[]'::jsonb)
                  from (select g.* from public.player_games g where g.user_id = v_target
                         order by g.played_at desc, g.id desc limit 30) l)
    )
    from public.profiles p
    left join public.ranked_profiles r on r.user_id = p.id
    left join public.presence pr on pr.user_id = p.id
    where p.id = v_target);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Ranked cards respect the privacy choice (same signatures and fields as before)
-- ---------------------------------------------------------------------------------------------

-- A player's ranked card (friends list, table names). Blocked either way reads as not found. When the
-- caller may not open the profile, the card has the name and no standing, like a player who is unranked.
create or replace function public.mm_profile_card(p_username text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_user();
  v_target uuid := public.mm_visible_profile(v_uid, p_username);
begin
  if v_target is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  return (select jsonb_build_object('username', p.username, 'season', r.season, 'rankStep', r.rank_step, 'pips', r.pips,
                                    'peakStep', r.peak_step, 'wins', r.wins, 'losses', r.losses, 'title', r.title,
                                    'favoriteCommander', r.favorite_commander)
          from public.profiles p
          left join public.ranked_profiles r on r.user_id = p.id and public.mm_can_view_profile(v_uid, p.id)
          where p.id = v_target);
end $$;

-- Friends' standings for the badges in the friends list: not for a friend whose profile is private.
create or replace function public.mm_friend_ranks()
returns table (username text, season text, rank_step integer, pips integer, title text)
language sql stable security definer set search_path = '' as $$
  with me as (select public.mm_require_user() as uid)
  select p.username, r.season, r.rank_step, r.pips, r.title
  from me
  join public.friendships f on me.uid in (f.requester, f.addressee) and f.status = 'accepted'
  join public.profiles p on p.id = case when f.requester = me.uid then f.addressee else f.requester end
  join public.ranked_profiles r on r.user_id = p.id
  where p.visibility <> 'private'
  order by lower(p.username);
$$;

-- ---------------------------------------------------------------------------------------------
-- Access: signed-in players only
-- ---------------------------------------------------------------------------------------------

do $$
declare f text;
begin
  foreach f in array array[
    'mm_can_view_profile(uuid, uuid)', 'mm_profile()', 'mm_set_visibility(text)', 'mm_search_players(text)',
    'mm_record_game(uuid, timestamptz, text, text, text, text[], text[], jsonb, integer, integer, integer)',
    'mm_public_profile(text)', 'mm_profile_card(text)', 'mm_friend_ranks()']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  -- The viewer check is internal: it trusts the ids it is given.
  revoke all on function public.mm_can_view_profile(uuid, uuid) from authenticated;
  foreach f in array array[
    'mm_profile()', 'mm_set_visibility(text)', 'mm_search_players(text)',
    'mm_record_game(uuid, timestamptz, text, text, text, text[], text[], jsonb, integer, integer, integer)',
    'mm_public_profile(text)', 'mm_profile_card(text)', 'mm_friend_ranks()']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
