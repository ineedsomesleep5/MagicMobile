-- The server keeps score for ranked (Caleb, 2026-10-14). Until now each phone computed its own rank and
-- published it (mm_ranked_publish stored whatever it was sent), and mm_ranked_report kept each side's
-- claim without comparing them. Now:
--
-- * ranked_standings is the ladder's source of truth. The same rules as RankLadder.swift / Ranked.kt:
--   points = step * 4 + pips (Mythic counts pips past 80), win +1, loss -1 (never below Bronze IV),
--   draws 0; +1 for a third straight win below Gold, +1 for a win with a deck below the tier's opponent
--   brackets; a new UTC month drops one tier (four steps) with empty pips.
-- * A person-vs-person match counts when both sides report matching results (win/loss or draw/draw).
--   Results that disagree change nothing. A lone report settles after an hour (the other side left,
--   which the ladder already treats as a loss). The same two players count at most three matches a day.
-- * A ranked game against the AI starts with a ticket (mm_ranked_ai_start) and ends with one result
--   (mm_ranked_ai_result): a win needs four minutes since the ticket, at most twelve AI wins count per
--   UTC day, and a ticket never answered within twelve hours is a loss (leaving early is a loss).
-- * ranked_profiles stays the public card friends read; the server now writes its rank fields.
--   mm_ranked_publish keeps its signature for older app builds but only sets the title and favourite
--   commander.
--
-- Standings published before this migration are carried over as they were. A player with no standing
-- yet may seed one once from the phone (mm_ranked_seed), capped at Gold IV.
--
-- The phones still run every game, so this does not prove a game happened: it bounds what a modified
-- app can claim. Same rules as the other social tables: RLS on, no direct grants, mm_* functions only.

create table if not exists public.ranked_standings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  season text not null check (season ~ '^[0-9]{4}-[0-9]{2}$'),
  points integer not null default 0 check (points between 0 and 100080),
  peak_points integer not null default 0 check (peak_points between 0 and 100080),
  wins integer not null default 0 check (wins between 0 and 1000000),
  losses integer not null default 0 check (losses between 0 and 1000000),
  draws integer not null default 0 check (draws between 0 and 1000000),
  win_streak integer not null default 0 check (win_streak between 0 and 1000000),
  -- fresh (made by the server), imported (published before this migration) or seeded (mm_ranked_seed)
  origin text not null default 'fresh' check (origin in ('fresh', 'imported', 'seeded')),
  updated_at timestamptz not null default now()
);

create table if not exists public.ranked_season_history (
  user_id uuid not null references public.profiles (id) on delete cascade,
  season text not null check (season ~ '^[0-9]{4}-[0-9]{2}$'),
  final_points integer not null check (final_points between 0 and 100080),
  peak_points integer not null check (peak_points between 0 and 100080),
  wins integer not null check (wins >= 0),
  losses integer not null check (losses >= 0),
  primary key (user_id, season)
);

-- Every change the server made, newest last: what moved and why.
create table if not exists public.ranked_results (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  season text not null,
  source text not null check (source in ('match', 'ai')),
  match_id uuid,
  ai_game uuid,
  outcome text not null check (outcome in ('win', 'loss', 'draw')),
  points_before integer not null,
  points_after integer not null,
  bonuses text[] not null default '{}',
  created_at timestamptz not null default now()
);
create unique index if not exists ranked_results_match_key on public.ranked_results (user_id, match_id) where match_id is not null;
create unique index if not exists ranked_results_ai_key on public.ranked_results (user_id, ai_game) where ai_game is not null;
create index if not exists ranked_results_user_idx on public.ranked_results (user_id, created_at);

create table if not exists public.ranked_ai_games (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  deck_bracket integer not null check (deck_bracket between 1 and 5),
  created_at timestamptz not null default now(),
  result text check (result in ('win', 'loss', 'draw')),
  -- counted, too_soon, capped or abandoned
  settlement text check (settlement in ('counted', 'too_soon', 'capped', 'abandoned')),
  settled_at timestamptz
);
create index if not exists ranked_ai_games_user_idx on public.ranked_ai_games (user_id, created_at);

alter table public.ranked_matches add column if not exists settlement text
  check (settlement in ('counted', 'disputed', 'capped', 'timeout'));
alter table public.ranked_matches add column if not exists settled_at timestamptz;
alter table public.ranked_matches add column if not exists host_reported_at timestamptz;
alter table public.ranked_matches add column if not exists guest_reported_at timestamptz;

alter table public.ranked_standings enable row level security;
alter table public.ranked_season_history enable row level security;
alter table public.ranked_results enable row level security;
alter table public.ranked_ai_games enable row level security;
revoke all on public.ranked_standings, public.ranked_season_history, public.ranked_results, public.ranked_ai_games
  from anon, authenticated;

-- Carry over the standings phones published before this migration.
insert into public.ranked_standings (user_id, season, points, peak_points, wins, losses, origin)
select r.user_id, r.season,
       case when r.rank_step >= 20 then 80 + least(r.pips, 100000) else r.rank_step * 4 + least(r.pips, 3) end,
       greatest(case when r.rank_step >= 20 then 80 + least(r.pips, 100000) else r.rank_step * 4 + least(r.pips, 3) end,
                least(r.peak_step, 20) * 4),
       r.wins, r.losses, 'imported'
from public.ranked_profiles r
on conflict (user_id) do nothing;

create or replace function public.mm_current_season() returns text
language sql stable set search_path = '' as $$ select to_char(now() at time zone 'utc', 'YYYY-MM') $$;

-- Ladder step (0 Bronze IV … 20 Mythic) and pips for a points total.
create or replace function public.mm_rank_points_step(p_points integer) returns integer
language sql immutable set search_path = '' as $$ select least(greatest(p_points, 0) / 4, 20) $$;

create or replace function public.mm_rank_points_pips(p_points integer) returns integer
language sql immutable set search_path = '' as $$
  select case when p_points >= 80 then p_points - 80 else greatest(p_points, 0) % 4 end
$$;

-- The lowest opponent bracket a tier plays (Bronze 2, Silver 2, Gold 2, Platinum 3, Diamond 3, Mythic 4).
create or replace function public.mm_rank_min_bracket(p_points integer) returns integer
language sql immutable set search_path = '' as $$
  select (array[2, 2, 2, 3, 3, 4])[least(public.mm_rank_points_step(p_points) / 4, 5) + 1]
$$;

-- Writes the server's standing onto the public card friends read, keeping the title and commander.
create or replace function public.mm_ranked_mirror(p_uid uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare s public.ranked_standings%rowtype;
begin
  select * into s from public.ranked_standings where user_id = p_uid;
  if not found then return; end if;
  insert into public.ranked_profiles as r (user_id, season, rank_step, pips, peak_step, wins, losses, updated_at)
  values (p_uid, s.season, public.mm_rank_points_step(s.points), public.mm_rank_points_pips(s.points),
          public.mm_rank_points_step(s.peak_points), s.wins, s.losses, now())
  on conflict (user_id) do update set season = excluded.season, rank_step = excluded.rank_step, pips = excluded.pips,
    peak_step = excluded.peak_step, wins = excluded.wins, losses = excluded.losses, updated_at = now();
end $$;

-- The caller's standing row for this season, locked: created fresh if missing, rolled over if a new
-- month began (last season into history, one tier down, empty pips).
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
    v_points := greatest(public.mm_rank_points_step(s.points) - 4, 0) * 4;
    update public.ranked_standings set season = v_season, points = v_points, peak_points = v_points,
      wins = 0, losses = 0, draws = 0, win_streak = 0, updated_at = now()
     where user_id = p_uid returning * into s;
    perform public.mm_ranked_mirror(p_uid);
  end if;
  return s;
end $$;

-- One counted result: the ladder rules, the audit row and the public card.
create or replace function public.mm_ranked_apply(p_uid uuid, p_outcome text, p_deck_bracket integer, p_source text,
                                                  p_match uuid, p_ai_game uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s public.ranked_standings%rowtype := public.mm_ranked_current(p_uid);
  v_delta integer := 0;
  v_streak integer := s.win_streak;
  v_bonuses text[] := '{}';
  v_after integer;
begin
  if p_outcome = 'win' then
    v_delta := 1;
    v_streak := v_streak + 1;
    if public.mm_rank_points_step(s.points) < 8 and v_streak >= 3 then v_delta := v_delta + 1; v_bonuses := array_append(v_bonuses, 'streak'); end if;
    if p_deck_bracket is not null and p_deck_bracket < public.mm_rank_min_bracket(s.points) then
      v_delta := v_delta + 1; v_bonuses := array_append(v_bonuses, 'underdog');
    end if;
  elsif p_outcome = 'loss' then
    v_delta := -1;
    v_streak := 0;
  else
    v_streak := 0;
  end if;
  v_after := least(greatest(s.points + v_delta, 0), 100080);
  update public.ranked_standings set points = v_after, peak_points = greatest(peak_points, v_after),
    wins = wins + (p_outcome = 'win')::int, losses = losses + (p_outcome = 'loss')::int,
    draws = draws + (p_outcome = 'draw')::int, win_streak = v_streak, updated_at = now()
   where user_id = p_uid;
  insert into public.ranked_results (user_id, season, source, match_id, ai_game, outcome, points_before, points_after, bonuses)
  values (p_uid, s.season, p_source, p_match, p_ai_game, p_outcome, s.points, v_after, v_bonuses);
  perform public.mm_ranked_mirror(p_uid);
  return jsonb_build_object('outcome', p_outcome, 'pointsBefore', s.points, 'pointsAfter', v_after, 'bonuses', to_jsonb(v_bonuses));
end $$;

-- Settles a person-vs-person match once both sides reported, or an hour after the only report.
create or replace function public.mm_ranked_settle(p_match uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  m public.ranked_matches%rowtype;
  v_host_bracket integer;
  v_guest_bracket integer;
  v_host text;
  v_guest text;
begin
  select * into m from public.ranked_matches where id = p_match for update;
  if not found or m.settled_at is not null or m.host is null or m.guest is null then return; end if;
  v_host := m.host_result;
  v_guest := m.guest_result;
  if v_host is null or v_guest is null then
    -- One side never reported within the hour: they left, which the ladder counts as their loss.
    if coalesce(m.host_reported_at, m.guest_reported_at) is null
       or coalesce(m.host_reported_at, m.guest_reported_at) > now() - interval '1 hour' then return; end if;
    if v_host is null then v_host := case v_guest when 'win' then 'loss' when 'loss' then 'win' else 'draw' end; end if;
    if v_guest is null then v_guest := case v_host when 'win' then 'loss' when 'loss' then 'win' else 'draw' end; end if;
    update public.ranked_matches set settlement = 'timeout', settled_at = now() where id = p_match;
  elsif not ((v_host = 'win' and v_guest = 'loss') or (v_host = 'loss' and v_guest = 'win') or (v_host = 'draw' and v_guest = 'draw')) then
    update public.ranked_matches set settlement = 'disputed', settled_at = now() where id = p_match;
    return;
  end if;
  -- The same two players count at most three matches a day.
  if (select count(*) from public.ranked_matches o
       where o.id <> m.id and o.settlement in ('counted', 'timeout') and o.settled_at > now() - interval '1 day'
         and ((o.host = m.host and o.guest = m.guest) or (o.host = m.guest and o.guest = m.host))) >= 3 then
    update public.ranked_matches set settlement = 'capped', settled_at = now() where id = p_match;
    return;
  end if;
  update public.ranked_matches set settlement = coalesce(settlement, 'counted'), settled_at = now() where id = p_match;
  select q.deck_bracket into v_host_bracket from public.ranked_queue q where q.match_id = m.id and q.user_id = m.host limit 1;
  select q.deck_bracket into v_guest_bracket from public.ranked_queue q where q.match_id = m.id and q.user_id = m.guest limit 1;
  perform public.mm_ranked_apply(m.host, v_host, v_host_bracket, 'match', m.id, null);
  perform public.mm_ranked_apply(m.guest, v_guest, v_guest_bracket, 'match', m.id, null);
end $$;

-- Each side reports its own result once; the match settles when both have.
create or replace function public.mm_ranked_report(p_match uuid, p_result text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if p_result not in ('win', 'loss', 'draw') then raise exception 'invalid_result' using errcode = '22023'; end if;
  update public.ranked_matches set host_result = coalesce(host_result, p_result), host_reported_at = coalesce(host_reported_at, now())
   where id = p_match and host = v_uid;
  update public.ranked_matches set guest_result = coalesce(guest_result, p_result), guest_reported_at = coalesce(guest_reported_at, now())
   where id = p_match and guest = v_uid;
  perform public.mm_ranked_settle(p_match);
end $$;

-- The caller's standing as JSON, after settling anything of theirs that has waited long enough.
create or replace function public.mm_ranked_standing() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_match uuid;
  v_game uuid;
  s public.ranked_standings%rowtype;
begin
  for v_match in select m.id from public.ranked_matches m
                  where v_uid in (m.host, m.guest) and m.settled_at is null and m.created_at > now() - interval '7 days'
                    and coalesce(m.host_reported_at, m.guest_reported_at) < now() - interval '1 hour'
  loop
    perform public.mm_ranked_settle(v_match);
  end loop;
  -- A ranked AI game never answered within twelve hours was left: a loss.
  for v_game in select g.id from public.ranked_ai_games g
                 where g.user_id = v_uid and g.settled_at is null and g.created_at < now() - interval '12 hours'
                 for update
  loop
    update public.ranked_ai_games set result = 'loss', settlement = 'abandoned', settled_at = now() where id = v_game;
    perform public.mm_ranked_apply(v_uid, 'loss', null, 'ai', null, v_game);
  end loop;
  s := public.mm_ranked_current(v_uid);
  perform public.mm_ranked_mirror(v_uid);
  return jsonb_build_object(
    -- False only for a server-made standing that has never counted a result: the phone may seed it once.
    'seeded', s.origin <> 'fresh' or exists (select 1 from public.ranked_results r where r.user_id = v_uid),
    -- Matches this player reported that the other side hasn't yet: the phone keeps its own count meanwhile.
    'unsettled', (select count(*) from public.ranked_matches m
                   where m.settled_at is null and m.created_at > now() - interval '7 days'
                     and ((m.host = v_uid and m.host_result is not null) or (m.guest = v_uid and m.guest_result is not null))),
    'season', s.season, 'points', s.points, 'peakPoints', s.peak_points,
    'wins', s.wins, 'losses', s.losses, 'draws', s.draws, 'winStreak', s.win_streak,
    'history', coalesce((select jsonb_agg(jsonb_build_object('season', h.season, 'finalPoints', h.final_points,
                                                             'peakPoints', h.peak_points, 'wins', h.wins, 'losses', h.losses)
                                          order by h.season desc)
                         from (select * from public.ranked_season_history where user_id = v_uid order by season desc limit 24) h),
                        '[]'::jsonb));
end $$;

-- Once, for a player with no standing on the server yet: their phone's earlier progress, capped at Gold IV.
create or replace function public.mm_ranked_seed(p_points integer, p_peak_points integer, p_wins integer, p_losses integer)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_points integer := least(greatest(coalesce(p_points, 0), 0), 32);
begin
  perform public.mm_ranked_current(v_uid);
  if not exists (select 1 from public.ranked_results where user_id = v_uid) then
    update public.ranked_standings set points = v_points,
      peak_points = greatest(v_points, least(greatest(coalesce(p_peak_points, 0), 0), 32)),
      wins = least(greatest(coalesce(p_wins, 0), 0), 10000), losses = least(greatest(coalesce(p_losses, 0), 0), 10000),
      origin = 'seeded', updated_at = now()
     where user_id = v_uid and origin = 'fresh';
    perform public.mm_ranked_mirror(v_uid);
  end if;
  return public.mm_ranked_standing();
end $$;

-- A ranked game against the AI begins. At most ten a rolling hour.
create or replace function public.mm_ranked_ai_start(p_deck_bracket integer) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_id uuid;
begin
  if p_deck_bracket is null or p_deck_bracket not between 1 and 5 then
    raise exception 'invalid_bracket' using errcode = '22023';
  end if;
  if (select count(*) from public.ranked_ai_games where user_id = v_uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many_games' using errcode = 'P0001';
  end if;
  delete from public.ranked_ai_games where user_id = v_uid and created_at < now() - interval '30 days';
  insert into public.ranked_ai_games (user_id, deck_bracket) values (v_uid, p_deck_bracket) returning id into v_id;
  return v_id;
end $$;

-- The result of that game, once. Returns the standing and how the result counted.
create or replace function public.mm_ranked_ai_result(p_game uuid, p_result text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  g public.ranked_ai_games%rowtype;
  v_settlement text := 'counted';
  v_change jsonb;
begin
  if p_result not in ('win', 'loss', 'draw') then raise exception 'invalid_result' using errcode = '22023'; end if;
  select * into g from public.ranked_ai_games where id = p_game and user_id = v_uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if g.settled_at is null then
    if p_result = 'win' and g.created_at > now() - interval '4 minutes' then
      v_settlement := 'too_soon';
    elsif p_result = 'win' and (select count(*) from public.ranked_results r
                                 where r.user_id = v_uid and r.source = 'ai' and r.outcome = 'win'
                                   and r.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc') >= 12 then
      v_settlement := 'capped';
    end if;
    update public.ranked_ai_games set result = p_result, settlement = v_settlement, settled_at = now() where id = p_game;
    if v_settlement = 'counted' then
      v_change := public.mm_ranked_apply(v_uid, p_result, g.deck_bracket, 'ai', null, p_game);
    end if;
  else
    v_settlement := g.settlement;
  end if;
  return public.mm_ranked_standing() || jsonb_build_object('settlement', v_settlement, 'change', v_change);
end $$;

-- Kept for older app builds: the title and favourite commander only. Rank numbers sent here are ignored.
create or replace function public.mm_ranked_publish(p_season text, p_rank_step integer, p_pips integer, p_peak_step integer,
                                                    p_wins integer, p_losses integer, p_title text,
                                                    p_favorite_commander text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_profile();
begin
  perform public.mm_ranked_current(v_uid);
  perform public.mm_ranked_mirror(v_uid);
  update public.ranked_profiles set title = left(p_title, 40), favorite_commander = left(p_favorite_commander, 160),
    updated_at = now()
   where user_id = v_uid;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'mm_current_season()', 'mm_rank_points_step(integer)', 'mm_rank_points_pips(integer)', 'mm_rank_min_bracket(integer)',
    'mm_ranked_mirror(uuid)', 'mm_ranked_current(uuid)', 'mm_ranked_apply(uuid, text, integer, text, uuid, uuid)',
    'mm_ranked_settle(uuid)', 'mm_ranked_standing()', 'mm_ranked_seed(integer, integer, integer, integer)',
    'mm_ranked_ai_start(integer)', 'mm_ranked_ai_result(uuid, text)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  -- Internal helpers trust the user id or match they are given.
  foreach f in array array[
    'mm_ranked_mirror(uuid)', 'mm_ranked_current(uuid)', 'mm_ranked_apply(uuid, text, integer, text, uuid, uuid)',
    'mm_ranked_settle(uuid)']
  loop
    execute format('revoke all on function public.%s from authenticated', f);
  end loop;
  foreach f in array array[
    'mm_ranked_standing()', 'mm_ranked_seed(integer, integer, integer, integer)',
    'mm_ranked_ai_start(integer)', 'mm_ranked_ai_result(uuid, text)']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
