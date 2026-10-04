-- Ranked 1v1 for the apps: a queue that pairs players who are searching right now, the matches it
-- makes, and each player's public ranked card (standing, record, title) that friends can see.
--
-- The phones compute ranks (an AI opponent takes the seat when nobody is queued, and those games
-- never reach the server). The server only pairs people, hands the host's table code to the guest,
-- keeps both sides' reported results, and shares the standing each player publishes.
--
-- Same rules as the social tables: RLS on, no direct grants, everything through mm_* functions
-- (security definer, fixed search_path).

create table if not exists public.ranked_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- The relay identity: only phones that can share a table are paired.
  protocol text not null check (char_length(protocol) between 1 and 200),
  rank_step integer not null check (rank_step between 0 and 20),
  deck_bracket integer not null check (deck_bracket between 1 and 5),
  status text not null default 'waiting' check (status in ('waiting', 'matched', 'cancelled')),
  match_id uuid,
  created_at timestamptz not null default now(),
  heartbeat_at timestamptz not null default now()
);
create index if not exists ranked_queue_waiting_idx on public.ranked_queue (protocol, created_at) where status = 'waiting';
create unique index if not exists ranked_queue_one_waiting_key on public.ranked_queue (user_id) where status = 'waiting';

create table if not exists public.ranked_matches (
  id uuid primary key default gen_random_uuid(),
  host uuid references public.profiles (id) on delete set null,
  guest uuid references public.profiles (id) on delete set null,
  table_code text check (table_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'),
  host_result text check (host_result in ('win', 'loss', 'draw')),
  guest_result text check (guest_result in ('win', 'loss', 'draw')),
  created_at timestamptz not null default now()
);

create table if not exists public.ranked_profiles (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  season text not null check (season ~ '^[0-9]{4}-[0-9]{2}$'),
  rank_step integer not null check (rank_step between 0 and 20),
  pips integer not null check (pips between 0 and 100000),
  peak_step integer not null check (peak_step between 0 and 20),
  wins integer not null default 0 check (wins between 0 and 1000000),
  losses integer not null default 0 check (losses between 0 and 1000000),
  title text check (char_length(title) <= 40),
  favorite_commander text check (char_length(favorite_commander) <= 160),
  updated_at timestamptz not null default now()
);

alter table public.ranked_queue enable row level security;
alter table public.ranked_matches enable row level security;
alter table public.ranked_profiles enable row level security;
revoke all on public.ranked_queue, public.ranked_matches, public.ranked_profiles from anon, authenticated;

-- What a ticket's owner may know about it: status, the match, their role, the table and opponent.
create or replace function public.mm_ranked_ticket(p_uid uuid, p_ticket uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'ticket', q.id, 'status', q.status, 'matchId', q.match_id,
    'role', case when m.id is null then null when m.host = p_uid then 'host' else 'guest' end,
    'tableCode', m.table_code,
    'opponent', (select p.username from public.profiles p
                  where p.id = case when m.host = p_uid then m.guest else m.host end),
    'opponentStep', (select o.rank_step from public.ranked_queue o
                      where o.match_id = m.id and o.user_id <> p_uid limit 1))
  from public.ranked_queue q
  left join public.ranked_matches m on m.id = q.match_id
  where q.id = p_ticket and q.user_id = p_uid;
$$;

-- Joins the queue. With someone suitable already waiting (searched in the last 20 seconds, within
-- one tier and one bracket, neither blocking the other) the caller is matched at once and hosts.
create or replace function public.mm_ranked_enqueue(p_protocol text, p_rank_step integer, p_deck_bracket integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_other public.ranked_queue%rowtype;
  v_match uuid;
  v_ticket uuid;
begin
  if p_protocol is null or char_length(p_protocol) not between 1 and 200
     or p_rank_step is null or p_rank_step not between 0 and 20
     or p_deck_bracket is null or p_deck_bracket not between 1 and 5 then
    raise exception 'invalid_ticket' using errcode = '22023';
  end if;
  -- One search at a time; old rows go after a day.
  update public.ranked_queue set status = 'cancelled' where user_id = v_uid and status = 'waiting';
  delete from public.ranked_queue where created_at < now() - interval '1 day';
  select q.* into v_other from public.ranked_queue q
   where q.status = 'waiting' and q.protocol = p_protocol and q.user_id <> v_uid
     and abs(q.rank_step - p_rank_step) <= 4 and abs(q.deck_bracket - p_deck_bracket) <= 1
     and q.heartbeat_at > now() - interval '20 seconds'
     and not exists (select 1 from public.blocks b
                      where (b.blocker = v_uid and b.blocked = q.user_id) or (b.blocker = q.user_id and b.blocked = v_uid))
   order by abs(q.rank_step - p_rank_step), q.created_at
   limit 1
   for update skip locked;
  if found then
    insert into public.ranked_matches (host, guest) values (v_uid, v_other.user_id) returning id into v_match;
    update public.ranked_queue set status = 'matched', match_id = v_match where id = v_other.id;
    insert into public.ranked_queue (user_id, protocol, rank_step, deck_bracket, status, match_id)
    values (v_uid, p_protocol, p_rank_step, p_deck_bracket, 'matched', v_match) returning id into v_ticket;
  else
    insert into public.ranked_queue (user_id, protocol, rank_step, deck_bracket)
    values (v_uid, p_protocol, p_rank_step, p_deck_bracket) returning id into v_ticket;
  end if;
  return public.mm_ranked_ticket(v_uid, v_ticket);
end $$;

-- Polled every couple of seconds while searching: keeps the ticket fresh and reports a match.
create or replace function public.mm_ranked_poll(p_ticket uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  update public.ranked_queue set heartbeat_at = now() where id = p_ticket and user_id = v_uid and status = 'waiting';
  return coalesce(public.mm_ranked_ticket(v_uid, p_ticket), jsonb_build_object('status', 'cancelled'));
end $$;

-- Stops searching. A ticket that was matched meanwhile stays matched: the game goes ahead.
create or replace function public.mm_ranked_cancel(p_ticket uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  update public.ranked_queue set status = 'cancelled' where id = p_ticket and user_id = v_uid and status = 'waiting';
  return coalesce(public.mm_ranked_ticket(v_uid, p_ticket), jsonb_build_object('status', 'cancelled'));
end $$;

-- The host shares its relay table's code with the guest.
create or replace function public.mm_ranked_set_table(p_match uuid, p_code text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if p_code is null or p_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'invalid_code' using errcode = '22023';
  end if;
  update public.ranked_matches set table_code = p_code where id = p_match and host = v_uid;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;

-- Each side reports its own result once.
create or replace function public.mm_ranked_report(p_match uuid, p_result text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if p_result not in ('win', 'loss', 'draw') then raise exception 'invalid_result' using errcode = '22023'; end if;
  update public.ranked_matches set host_result = coalesce(host_result, p_result) where id = p_match and host = v_uid;
  update public.ranked_matches set guest_result = coalesce(guest_result, p_result) where id = p_match and guest = v_uid;
end $$;

-- The caller's standing, as their phone computed it, for friends to see.
create or replace function public.mm_ranked_publish(p_season text, p_rank_step integer, p_pips integer, p_peak_step integer,
                                                    p_wins integer, p_losses integer, p_title text,
                                                    p_favorite_commander text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_profile();
begin
  insert into public.ranked_profiles as r (user_id, season, rank_step, pips, peak_step, wins, losses, title, favorite_commander, updated_at)
  values (v_uid, p_season, p_rank_step, p_pips, p_peak_step, p_wins, p_losses, left(p_title, 40), left(p_favorite_commander, 160), now())
  on conflict (user_id) do update set season = excluded.season, rank_step = excluded.rank_step, pips = excluded.pips,
    peak_step = excluded.peak_step, wins = excluded.wins, losses = excluded.losses, title = excluded.title,
    favorite_commander = excluded.favorite_commander, updated_at = now();
exception when check_violation then
  raise exception 'invalid_rank' using errcode = '22023';
end $$;

-- A player's public ranked card (friends list, table names). Blocked either way reads as not found.
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
          from public.profiles p left join public.ranked_profiles r on r.user_id = p.id where p.id = v_target);
end $$;

-- Friends' standings, for the badges in the friends list.
create or replace function public.mm_friend_ranks()
returns table (username text, season text, rank_step integer, pips integer, title text)
language sql stable security definer set search_path = '' as $$
  with me as (select public.mm_require_user() as uid)
  select p.username, r.season, r.rank_step, r.pips, r.title
  from me
  join public.friendships f on me.uid in (f.requester, f.addressee) and f.status = 'accepted'
  join public.profiles p on p.id = case when f.requester = me.uid then f.addressee else f.requester end
  join public.ranked_profiles r on r.user_id = p.id
  order by lower(p.username);
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'mm_ranked_ticket(uuid, uuid)', 'mm_ranked_enqueue(text, integer, integer)', 'mm_ranked_poll(uuid)',
    'mm_ranked_cancel(uuid)', 'mm_ranked_set_table(uuid, text)', 'mm_ranked_report(uuid, text)',
    'mm_ranked_publish(text, integer, integer, integer, integer, integer, text, text)',
    'mm_profile_card(text)', 'mm_friend_ranks()']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  -- The ticket reader is internal: it trusts the user id it is given.
  revoke all on function public.mm_ranked_ticket(uuid, uuid) from authenticated;
  foreach f in array array[
    'mm_ranked_enqueue(text, integer, integer)', 'mm_ranked_poll(uuid)', 'mm_ranked_cancel(uuid)',
    'mm_ranked_set_table(uuid, text)', 'mm_ranked_report(uuid, text)',
    'mm_ranked_publish(text, integer, integer, integer, integer, integer, text, text)',
    'mm_profile_card(text)', 'mm_friend_ranks()']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
