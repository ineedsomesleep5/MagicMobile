-- Instant profiles, friends and presence for the apps (anonymous Supabase Auth users).
--
-- A profile is a unique username, used as the player's name at every table. Friends see
-- each other's presence and the code of a table a friend is hosting, so they can join it
-- with one tap. Players can block and report each other.
--
-- Every read and write goes through the mm_* functions below (security definer, fixed
-- search_path). The new tables have RLS on and no policies: nothing reads them directly.

-- Usernames: 3–20 letters, digits or underscores, unique ignoring case. The existing
-- display_name mirrors it for the old own-profile policies.
alter table public.profiles add column if not exists username text;
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username is null or username ~ '^[A-Za-z0-9_]{3,20}$');
create unique index if not exists profiles_username_lower_key on public.profiles (lower(username));

create table if not exists public.presence (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  platform text check (platform in ('ios', 'android')),
  hosting_code text check (hosting_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'),
  hosting_open_seats integer check (hosting_open_seats between 0 and 3),
  hosting_updated_at timestamptz
);

create table if not exists public.friendships (
  requester uuid not null references public.profiles (id) on delete cascade,
  addressee uuid not null references public.profiles (id) on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create unique index if not exists friendships_pair_key
  on public.friendships (least(requester, addressee), greatest(requester, addressee));
create index if not exists friendships_addressee_idx on public.friendships (addressee);

create table if not exists public.blocks (
  blocker uuid not null references public.profiles (id) on delete cascade,
  blocked uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create index if not exists blocks_blocked_idx on public.blocks (blocked);

-- Reviewed by the developer in the dashboard; kept when either account is deleted.
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter uuid references public.profiles (id) on delete set null,
  reported uuid references public.profiles (id) on delete set null,
  reported_name text not null check (char_length(reported_name) between 1 and 40),
  message text check (char_length(message) <= 400),
  context text not null check (context in ('chat', 'profile')),
  created_at timestamptz not null default now()
);
create index if not exists reports_reporter_time_idx on public.reports (reporter, created_at);

alter table public.presence enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
revoke all on public.presence, public.friendships, public.blocks, public.reports from anon, authenticated;

-- The signed-in user, or an error. Anonymous users count: they are the app's instant profiles.
create or replace function public.mm_require_user() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  return v_uid;
end $$;

-- The caller's profile id with a username, or an error.
create or replace function public.mm_require_profile() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if not exists (select 1 from public.profiles where id = v_uid and username is not null) then
    raise exception 'no_username' using errcode = 'P0001';
  end if;
  return v_uid;
end $$;

-- The profile named, if neither side has blocked the other.
create or replace function public.mm_visible_profile(p_viewer uuid, p_username text) returns uuid
language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p
  where p_username is not null and lower(p.username) = lower(p_username)
    and not exists (select 1 from public.blocks b
                    where (b.blocker = p_viewer and b.blocked = p.id) or (b.blocker = p.id and b.blocked = p_viewer));
$$;

create or replace function public.mm_profile() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', public.mm_require_user(),
                            'username', (select username from public.profiles where id = auth.uid()));
$$;

create or replace function public.mm_claim_username(p_username text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if p_username is null or p_username !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'invalid_username' using errcode = '22023';
  end if;
  begin
    insert into public.profiles (id, display_name, username) values (v_uid, p_username, p_username)
    on conflict (id) do update set username = excluded.username, display_name = excluded.display_name, updated_at = now();
  exception when unique_violation then
    raise exception 'username_taken' using errcode = '23505';
  end;
  return jsonb_build_object('id', v_uid, 'username', p_username);
end $$;

-- Called about once a minute while the app is open. A table the player hosts is shared with
-- friends until it fills, starts or closes (the app then sends null).
create or replace function public.mm_heartbeat(p_platform text, p_hosting_code text default null,
                                               p_open_seats integer default null) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if not exists (select 1 from public.profiles where id = v_uid and username is not null) then return; end if;
  if p_platform is not null and p_platform not in ('ios', 'android') then raise exception 'invalid_platform' using errcode = '22023'; end if;
  if p_hosting_code is not null and p_hosting_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'invalid_code' using errcode = '22023';
  end if;
  insert into public.presence as pr (user_id, last_seen_at, platform, hosting_code, hosting_open_seats, hosting_updated_at)
  values (v_uid, now(), p_platform, p_hosting_code,
          case when p_hosting_code is null then null else greatest(0, least(3, coalesce(p_open_seats, 1))) end,
          case when p_hosting_code is null then null else now() end)
  on conflict (user_id) do update set last_seen_at = now(), platform = excluded.platform,
    hosting_code = excluded.hosting_code, hosting_open_seats = excluded.hosting_open_seats,
    hosting_updated_at = excluded.hosting_updated_at;
end $$;

-- 'requested', 'accepted' (they had already asked you) or 'already_friends'.
create or replace function public.mm_friend_request(p_username text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_target uuid := public.mm_visible_profile(v_uid, p_username);
  v_row public.friendships%rowtype;
begin
  if v_target is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_target = v_uid then raise exception 'self' using errcode = '22023'; end if;
  select * into v_row from public.friendships
   where least(requester, addressee) = least(v_uid, v_target) and greatest(requester, addressee) = greatest(v_uid, v_target);
  if found then
    if v_row.status = 'accepted' then return 'already_friends'; end if;
    if v_row.requester = v_target then
      update public.friendships set status = 'accepted' where requester = v_target and addressee = v_uid;
      return 'accepted';
    end if;
    return 'requested';
  end if;
  if (select count(*) from public.friendships where requester = v_uid and status = 'pending') >= 50 then
    raise exception 'too_many_requests' using errcode = 'P0001';
  end if;
  insert into public.friendships (requester, addressee, status) values (v_uid, v_target, 'pending');
  return 'requested';
end $$;

create or replace function public.mm_respond_friend(p_requester uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if p_accept then
    update public.friendships set status = 'accepted'
     where requester = p_requester and addressee = v_uid and status = 'pending';
  else
    delete from public.friendships where requester = p_requester and addressee = v_uid and status = 'pending';
  end if;
end $$;

-- Removes a friend, or cancels a request either way.
create or replace function public.mm_remove_friend(p_other uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.friendships
   where (requester = public.mm_require_user() and addressee = p_other)
      or (requester = p_other and addressee = public.mm_require_user());
$$;

-- Friends and requests. Presence and a hosted table show for accepted friends only:
-- online means seen in the last 90 seconds; a hosted table is shared for 30 minutes at most.
create or replace function public.mm_friends()
returns table (id uuid, username text, relation text, online boolean, last_seen_at timestamptz,
               platform text, hosting_code text, hosting_open_seats integer)
language sql stable security definer set search_path = '' as $$
  with me as (select public.mm_require_user() as uid)
  select p.id, p.username,
         case when f.status = 'accepted' then 'friend' when f.requester = me.uid then 'outgoing' else 'incoming' end,
         coalesce(f.status = 'accepted' and pr.last_seen_at > now() - interval '90 seconds', false),
         case when f.status = 'accepted' then pr.last_seen_at end,
         case when f.status = 'accepted' then pr.platform end,
         case when f.status = 'accepted' and pr.last_seen_at > now() - interval '90 seconds'
                   and pr.hosting_updated_at > now() - interval '30 minutes' then pr.hosting_code end,
         case when f.status = 'accepted' and pr.last_seen_at > now() - interval '90 seconds'
                   and pr.hosting_updated_at > now() - interval '30 minutes' then pr.hosting_open_seats end
  from me
  join public.friendships f on me.uid in (f.requester, f.addressee)
  join public.profiles p on p.id = case when f.requester = me.uid then f.addressee else f.requester end
  left join public.presence pr on pr.user_id = p.id
  order by 3, 4 desc, lower(p.username);
$$;

create or replace function public.mm_block(p_username text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_user();
  v_target uuid := (select id from public.profiles where p_username is not null and lower(username) = lower(p_username));
begin
  if v_target is null or v_target = v_uid then return; end if;
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'no_username' using errcode = 'P0001';
  end if;
  insert into public.blocks (blocker, blocked) values (v_uid, v_target) on conflict do nothing;
  delete from public.friendships
   where least(requester, addressee) = least(v_uid, v_target) and greatest(requester, addressee) = greatest(v_uid, v_target);
end $$;

create or replace function public.mm_unblock(p_username text) returns void
language sql security definer set search_path = '' as $$
  delete from public.blocks
   where blocker = public.mm_require_user()
     and blocked = (select id from public.profiles where lower(username) = lower(p_username));
$$;

create or replace function public.mm_blocked() returns table (username text)
language sql stable security definer set search_path = '' as $$
  select p.username from public.blocks b join public.profiles p on p.id = b.blocked
   where b.blocker = public.mm_require_user() order by lower(p.username);
$$;

-- A report of another player's name or chat message. At most 20 an hour per player.
create or replace function public.mm_report(p_username text, p_message text, p_context text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if p_context not in ('chat', 'profile') or p_username is null or char_length(p_username) not between 1 and 40 then
    raise exception 'invalid_report' using errcode = '22023';
  end if;
  if (select count(*) from public.reports where reporter = v_uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'too_many_reports' using errcode = 'P0001';
  end if;
  insert into public.reports (reporter, reported, reported_name, message, context)
  values ((select id from public.profiles where id = v_uid),
          (select id from public.profiles where lower(username) = lower(p_username)),
          p_username, left(p_message, 400), p_context);
end $$;

-- Deletes the caller's account and everything tied to it (App Store account deletion).
create or replace function public.mm_delete_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from auth.users where id = public.mm_require_user();
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'mm_require_user()', 'mm_require_profile()', 'mm_visible_profile(uuid, text)', 'mm_profile()',
    'mm_claim_username(text)', 'mm_heartbeat(text, text, integer)', 'mm_friend_request(text)',
    'mm_respond_friend(uuid, boolean)', 'mm_remove_friend(uuid)', 'mm_friends()', 'mm_block(text)',
    'mm_unblock(text)', 'mm_blocked()', 'mm_report(text, text, text)', 'mm_delete_account()']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  -- Internal helpers stay callable only from the functions above.
  foreach f in array array['mm_require_user()', 'mm_require_profile()', 'mm_visible_profile(uuid, text)'] loop
    execute format('revoke all on function public.%s from authenticated', f);
  end loop;
  foreach f in array array[
    'mm_profile()', 'mm_claim_username(text)', 'mm_heartbeat(text, text, integer)', 'mm_friend_request(text)',
    'mm_respond_friend(uuid, boolean)', 'mm_remove_friend(uuid)', 'mm_friends()', 'mm_block(text)',
    'mm_unblock(text)', 'mm_blocked()', 'mm_report(text, text, text)', 'mm_delete_account()']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
