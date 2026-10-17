-- Messages between friends (roadmap release B, docs/ROADMAP_LATE_2026.md), beside the in-game table chat.
--
-- Only accepted friends can message each other and see their conversation; blocking ends the friendship, so it hides
-- the conversation both ways (the messages stay, and come back if the two become friends again). Deleting an account
-- deletes its messages. The apps poll: the unread count with the heartbeat, a conversation every few seconds while it
-- is open. Same rules as the other social tables: RLS on, no direct grants, everything through mm_* functions
-- (security definer, fixed search_path).

create table if not exists public.friend_messages (
  id bigint generated always as identity primary key,
  sender uuid not null references public.profiles (id) on delete cascade,
  recipient uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  sent_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender <> recipient)
);
create index if not exists friend_messages_pair_idx
  on public.friend_messages (least(sender, recipient), greatest(sender, recipient), id desc);
create index if not exists friend_messages_unread_idx on public.friend_messages (recipient) where read_at is null;
create index if not exists friend_messages_sender_time_idx on public.friend_messages (sender, sent_at);

alter table public.friend_messages enable row level security;
revoke all on public.friend_messages from anon, authenticated;

-- Reports can name a message from a conversation.
alter table public.reports drop constraint if exists reports_context_check;
alter table public.reports add constraint reports_context_check check (context in ('chat', 'profile', 'message'));

create or replace function public.mm_report(p_username text, p_message text, p_context text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := public.mm_require_user();
begin
  if p_context not in ('chat', 'profile', 'message') or p_username is null or char_length(p_username) not between 1 and 40 then
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

-- The friend named, if the two are accepted friends (and so neither has blocked the other).
create or replace function public.mm_message_friend(p_uid uuid, p_username text) returns uuid
language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p
  join public.friendships f on f.status = 'accepted'
   and least(f.requester, f.addressee) = least(p_uid, p.id) and greatest(f.requester, f.addressee) = greatest(p_uid, p.id)
  where p_username is not null and lower(p.username) = lower(p_username) and p.id <> p_uid;
$$;

create or replace function public.mm_message_row(p_uid uuid, m public.friend_messages) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', m.id, 'body', m.body, 'sentAt', m.sent_at, 'fromMe', m.sender = p_uid,
                            'read', m.read_at is not null);
$$;

-- Sends a message to a friend. The text is trimmed; 1–500 characters. At most 20 a minute and 500 a day per sender.
create or replace function public.mm_message_send(p_username text, p_body text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_friend uuid := public.mm_message_friend(v_uid, p_username);
  v_body text := btrim(coalesce(p_body, ''));
  v_row public.friend_messages%rowtype;
begin
  if char_length(v_body) not between 1 and 500 then raise exception 'invalid_message' using errcode = '22023'; end if;
  if v_friend is null then raise exception 'not_friends' using errcode = '42501'; end if;
  if (select count(*) from public.friend_messages where sender = v_uid and sent_at > now() - interval '1 minute') >= 20
     or (select count(*) from public.friend_messages where sender = v_uid and sent_at > now() - interval '1 day') >= 500 then
    raise exception 'too_many_messages' using errcode = 'P0001';
  end if;
  insert into public.friend_messages (sender, recipient, body) values (v_uid, v_friend, v_body) returning * into v_row;
  return public.mm_message_row(v_uid, v_row);
end $$;

-- The caller's conversations with friends, newest first: the last message and how many are unread.
create or replace function public.mm_message_conversations() returns jsonb
language sql stable security definer set search_path = '' as $$
  with me as (select public.mm_require_user() as uid),
  friends as (
    select p.id, p.username from me
    join public.friendships f on f.status = 'accepted' and me.uid in (f.requester, f.addressee)
    join public.profiles p on p.id = case when f.requester = me.uid then f.addressee else f.requester end
  ),
  convo as (
    select fr.username,
           (select m from public.friend_messages m
             where least(m.sender, m.recipient) = least(me.uid, fr.id) and greatest(m.sender, m.recipient) = greatest(me.uid, fr.id)
             order by m.id desc limit 1) as last,
           (select count(*) from public.friend_messages m where m.sender = fr.id and m.recipient = me.uid and m.read_at is null) as unread
    from me, friends fr
  )
  select coalesce(jsonb_agg(jsonb_build_object('username', c.username, 'unread', c.unread,
                                               'last', public.mm_message_row((select uid from me), c.last))
                            order by (c.last).id desc), '[]'::jsonb)
  -- (c.last).id, not c.last: a row value IS NOT NULL only when every field is, and read_at often isn't.
  from convo c where (c.last).id is not null;
$$;

-- One conversation, oldest first: the newest p_limit messages (1–100, default 50), or those before message p_before.
-- Reading the newest page marks the friend's messages read.
create or replace function public.mm_message_thread(p_username text, p_before bigint default null, p_limit integer default 50)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_friend uuid := public.mm_message_friend(v_uid, p_username);
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_rows jsonb;
  v_more boolean;
begin
  if v_friend is null then raise exception 'not_friends' using errcode = '42501'; end if;
  if p_before is null then
    update public.friend_messages set read_at = now()
     where sender = v_friend and recipient = v_uid and read_at is null;
  end if;
  with page as (
    select m from public.friend_messages m
     where least(m.sender, m.recipient) = least(v_uid, v_friend) and greatest(m.sender, m.recipient) = greatest(v_uid, v_friend)
       and (p_before is null or m.id < p_before)
     order by m.id desc limit v_limit + 1
  ), numbered as (select m, row_number() over (order by (m).id desc) as n from page)
  select coalesce(jsonb_agg(public.mm_message_row(v_uid, m) order by (m).id) filter (where n <= v_limit), '[]'::jsonb),
         count(*) > v_limit
    into v_rows, v_more
    from numbered;
  return jsonb_build_object('username', (select username from public.profiles where id = v_friend),
                            'messages', v_rows, 'hasMore', v_more);
end $$;

-- Unread messages from friends: the badge on the Friends button (polled with the heartbeat).
create or replace function public.mm_message_unread() returns integer
language sql stable security definer set search_path = '' as $$
  with me as (select public.mm_require_user() as uid)
  select count(*)::integer from me
  join public.friend_messages m on m.recipient = me.uid and m.read_at is null
  where exists (select 1 from public.friendships f
                 where f.status = 'accepted'
                   and least(f.requester, f.addressee) = least(me.uid, m.sender)
                   and greatest(f.requester, f.addressee) = greatest(me.uid, m.sender));
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'mm_report(text, text, text)', 'mm_message_friend(uuid, text)', 'mm_message_row(uuid, public.friend_messages)',
    'mm_message_send(text, text)', 'mm_message_conversations()', 'mm_message_thread(text, bigint, integer)',
    'mm_message_unread()']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  -- Internal helpers trust the user id they are given.
  revoke all on function public.mm_message_friend(uuid, text) from authenticated;
  revoke all on function public.mm_message_row(uuid, public.friend_messages) from authenticated;
  foreach f in array array[
    'mm_report(text, text, text)', 'mm_message_send(text, text)', 'mm_message_conversations()',
    'mm_message_thread(text, bigint, integer)', 'mm_message_unread()']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
