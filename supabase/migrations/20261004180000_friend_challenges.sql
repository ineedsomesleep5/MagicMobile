-- Friend challenges: a player challenges a friend to a Quick Match or a Ranked game from the friends
-- list. The challenger opens a two-seat relay table first and sends its code; the friend sees the
-- challenge, accepts and joins that table. Ranked challenges need both players in the same tier
-- (Gold with Gold; Caleb, 2026-10-04) and count like any ranked game: accepting makes a
-- ranked_matches row so both sides report through mm_ranked_report.
--
-- Tiers follow the phones' ladder (RankLadder): steps 0-19 are Bronze IV .. Diamond I, four per tier,
-- and 20 is Mythic. The phones send their own current step; the server checks the friend's published
-- one when sending and the friend's fresh one again when accepting.
--
-- Same rules as the other social tables: RLS on, no direct grants, everything through mm_* functions
-- (security definer, fixed search_path). A challenge lasts two minutes.

create table if not exists public.friend_challenges (
  id uuid primary key default gen_random_uuid(),
  challenger uuid not null references public.profiles (id) on delete cascade,
  challenged uuid not null references public.profiles (id) on delete cascade,
  mode text not null check (mode in ('quick', 'ranked')),
  -- The relay identity: only phones that can share a table can play.
  protocol text not null check (char_length(protocol) between 1 and 200),
  challenger_step integer not null check (challenger_step between 0 and 20),
  table_code text not null check (table_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  match_id uuid references public.ranked_matches (id) on delete set null,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (challenger <> challenged)
);
create index if not exists friend_challenges_incoming_idx on public.friend_challenges (challenged, created_at) where status = 'pending';
create unique index if not exists friend_challenges_one_pending_key on public.friend_challenges (challenger) where status = 'pending';

alter table public.friend_challenges enable row level security;
revoke all on public.friend_challenges from anon, authenticated;

-- A rank step's tier: 0 Bronze .. 4 Diamond, 5 Mythic.
create or replace function public.mm_rank_tier(p_step integer) returns integer
language sql immutable set search_path = '' as $$
  select least(5, greatest(0, p_step) / 4);
$$;

-- A player's published step as of this season: a standing from an earlier season has rolled over
-- (one tier down, as on the phones); no standing is a fresh Bronze IV.
create or replace function public.mm_current_rank_step(p_uid uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when r.season = to_char(now() at time zone 'utc', 'YYYY-MM') then r.rank_step
                               else greatest(0, r.rank_step - 4) end
                   from public.ranked_profiles r where r.user_id = p_uid), 0);
$$;

-- What either side may know about a challenge.
create or replace function public.mm_challenge_view(p_uid uuid, p_challenge uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', c.id, 'mode', c.mode, 'status',
    case when c.status = 'pending' and c.created_at < now() - interval '2 minutes' then 'expired' else c.status end,
    'role', case when c.challenger = p_uid then 'challenger' else 'challenged' end,
    'challenger', (select p.username from public.profiles p where p.id = c.challenger),
    'challenged', (select p.username from public.profiles p where p.id = c.challenged),
    'challengerStep', c.challenger_step,
    'protocol', c.protocol,
    'tableCode', case when c.challenged = p_uid and c.status <> 'accepted' then null else c.table_code end,
    'matchId', c.match_id,
    'createdAt', c.created_at)
  from public.friend_challenges c
  where c.id = p_challenge and p_uid in (c.challenger, c.challenged);
$$;

-- Sends a challenge to a friend, with the table the challenger already opened. One pending
-- challenge per challenger: a new one replaces the old.
create or replace function public.mm_challenge_send(p_username text, p_mode text, p_protocol text, p_rank_step integer,
                                                    p_table_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_target uuid := public.mm_visible_profile(v_uid, p_username);
  v_id uuid;
begin
  if p_mode not in ('quick', 'ranked') or p_protocol is null or char_length(p_protocol) not between 1 and 200
     or p_rank_step is null or p_rank_step not between 0 and 20
     or p_table_code is null or p_table_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'invalid_challenge' using errcode = '22023';
  end if;
  if v_target is null or v_target = v_uid then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.friendships f
                  where f.status = 'accepted'
                    and ((f.requester = v_uid and f.addressee = v_target) or (f.requester = v_target and f.addressee = v_uid))) then
    raise exception 'not_friends' using errcode = '42501';
  end if;
  if p_mode = 'ranked' and public.mm_rank_tier(p_rank_step) <> public.mm_rank_tier(public.mm_current_rank_step(v_target)) then
    raise exception 'rank_mismatch' using errcode = '22023';
  end if;
  update public.friend_challenges set status = 'cancelled', responded_at = now() where challenger = v_uid and status = 'pending';
  delete from public.friend_challenges where created_at < now() - interval '1 day';
  insert into public.friend_challenges (challenger, challenged, mode, protocol, challenger_step, table_code)
  values (v_uid, v_target, p_mode, p_protocol, p_rank_step, p_table_code) returning id into v_id;
  return public.mm_challenge_view(v_uid, v_id);
end $$;

-- Challenges waiting for the caller, newest first (polled while the menu is open).
create or replace function public.mm_challenge_incoming() returns jsonb
language sql stable security definer set search_path = '' as $$
  with me as (select public.mm_require_user() as uid)
  select coalesce(jsonb_agg(public.mm_challenge_view(me.uid, c.id) order by c.created_at desc), '[]'::jsonb)
  from me join public.friend_challenges c on c.challenged = me.uid
  where c.status = 'pending' and c.created_at > now() - interval '2 minutes'
    and not exists (select 1 from public.blocks b
                     where (b.blocker = me.uid and b.blocked = c.challenger) or (b.blocker = c.challenger and b.blocked = me.uid));
$$;

-- Polled by the challenger while waiting for an answer.
create or replace function public.mm_challenge_status(p_challenge uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  return coalesce(public.mm_challenge_view(v_uid, p_challenge), jsonb_build_object('status', 'cancelled'));
end $$;

-- Accepts: hands over the table code. A ranked challenge rechecks both tiers with the caller's own
-- current step and makes the ranked match both sides report to.
create or replace function public.mm_challenge_accept(p_challenge uuid, p_protocol text, p_rank_step integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_challenge public.friend_challenges%rowtype;
  v_match uuid;
begin
  select * into v_challenge from public.friend_challenges
   where id = p_challenge and challenged = v_uid for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_challenge.status <> 'pending' or v_challenge.created_at < now() - interval '2 minutes' then
    raise exception 'challenge_closed' using errcode = '22023';
  end if;
  if p_protocol is distinct from v_challenge.protocol then raise exception 'protocol_mismatch' using errcode = '22023'; end if;
  if v_challenge.mode = 'ranked' then
    if p_rank_step is null or p_rank_step not between 0 and 20
       or public.mm_rank_tier(p_rank_step) <> public.mm_rank_tier(v_challenge.challenger_step) then
      raise exception 'rank_mismatch' using errcode = '22023';
    end if;
    insert into public.ranked_matches (host, guest, table_code) values (v_challenge.challenger, v_uid, v_challenge.table_code)
    returning id into v_match;
  end if;
  update public.friend_challenges set status = 'accepted', responded_at = now(), match_id = v_match where id = p_challenge;
  return public.mm_challenge_view(v_uid, p_challenge);
end $$;

create or replace function public.mm_challenge_decline(p_challenge uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  update public.friend_challenges set status = 'declined', responded_at = now()
   where id = p_challenge and challenged = v_uid and status = 'pending';
end $$;

-- The challenger withdraws (or gave up waiting). An accepted challenge stays accepted.
create or replace function public.mm_challenge_cancel(p_challenge uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  update public.friend_challenges set status = 'cancelled', responded_at = now()
   where id = p_challenge and challenger = v_uid and status = 'pending';
  return coalesce(public.mm_challenge_view(v_uid, p_challenge), jsonb_build_object('status', 'cancelled'));
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'mm_rank_tier(integer)', 'mm_current_rank_step(uuid)', 'mm_challenge_view(uuid, uuid)',
    'mm_challenge_send(text, text, text, integer, text)', 'mm_challenge_incoming()', 'mm_challenge_status(uuid)',
    'mm_challenge_accept(uuid, text, integer)', 'mm_challenge_decline(uuid)', 'mm_challenge_cancel(uuid)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  -- Internal helpers trust the user id they are given.
  revoke all on function public.mm_current_rank_step(uuid) from authenticated;
  revoke all on function public.mm_challenge_view(uuid, uuid) from authenticated;
  foreach f in array array[
    'mm_challenge_send(text, text, text, integer, text)', 'mm_challenge_incoming()', 'mm_challenge_status(uuid)',
    'mm_challenge_accept(uuid, text, integer)', 'mm_challenge_decline(uuid)', 'mm_challenge_cancel(uuid)']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
