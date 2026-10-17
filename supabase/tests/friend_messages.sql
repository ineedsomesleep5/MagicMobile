-- Messages between friends (20261017180000_friend_messages.sql), run last by verify-ranked.mjs. Every call is made as
-- an authenticated player.
insert into auth.users(id,aud,role,email) values
 ('e8000000-0000-0000-0000-000000000001','authenticated','authenticated','msg-one@example.invalid'),
 ('e8000000-0000-0000-0000-000000000002','authenticated','authenticated','msg-two@example.invalid'),
 ('e8000000-0000-0000-0000-000000000003','authenticated','authenticated','msg-three@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000001',true);
select public.mm_claim_username('MsgOne');
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000002',true);
select public.mm_claim_username('MsgTwo');
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000003',true);
select public.mm_claim_username('MsgThree');

-- Only friends can message each other; a request isn't enough.
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000001',true);
do $t$ begin
  begin perform public.mm_message_send('MsgTwo', 'hi'); raise exception 'messaged a stranger';
  exception when others then if sqlerrm <> 'not_friends' then raise; end if; end;
  perform public.mm_friend_request('MsgTwo');
  begin perform public.mm_message_send('MsgTwo', 'hi'); raise exception 'messaged before acceptance';
  exception when others then if sqlerrm <> 'not_friends' then raise; end if; end;
  begin perform public.mm_message_thread('MsgTwo'); raise exception 'read a stranger thread';
  exception when others then if sqlerrm <> 'not_friends' then raise; end if; end;
end $t$;
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000002',true);
select public.mm_respond_friend('e8000000-0000-0000-0000-000000000001', true);

-- Sending: trimmed, 1–500 characters, unread for the friend until they open the conversation.
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  begin perform public.mm_message_send('MsgTwo', '   '); raise exception 'blank message accepted';
  exception when others then if sqlerrm <> 'invalid_message' then raise; end if; end;
  begin perform public.mm_message_send('MsgTwo', repeat('x', 501)); raise exception 'long message accepted';
  exception when others then if sqlerrm <> 'invalid_message' then raise; end if; end;
  begin perform public.mm_message_send('MsgOne', 'me'); raise exception 'messaged myself';
  exception when others then if sqlerrm <> 'not_friends' then raise; end if; end;
  r := public.mm_message_send('msgtwo', '  Up for a game?  ');
  if r->>'body' <> 'Up for a game?' or r->>'fromMe' <> 'true' or r->>'read' <> 'false' then raise exception 'send: %', r; end if;
  perform public.mm_message_send('MsgTwo', repeat('y', 500));
  if public.mm_message_unread() <> 0 then raise exception 'sender unread'; end if;
end $t$;

select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; begin
  if public.mm_message_unread() <> 2 then raise exception 'unread before reading: %', public.mm_message_unread(); end if;
  r := public.mm_message_conversations();
  if jsonb_array_length(r) <> 1 or r->0->>'username' <> 'MsgOne' or (r->0->>'unread')::int <> 2
     or r->0->'last'->>'fromMe' <> 'false' or char_length(r->0->'last'->>'body') <> 500 then
    raise exception 'conversations: %', r; end if;
  r := public.mm_message_thread('MsgOne');
  if jsonb_array_length(r->'messages') <> 2 or r->'messages'->0->>'body' <> 'Up for a game?' or r->>'hasMore' <> 'false'
     or r->>'username' <> 'MsgOne' then raise exception 'thread: %', r; end if;
  if public.mm_message_unread() <> 0 then raise exception 'reading the thread left unread'; end if;
  perform public.mm_message_send('MsgOne', 'Sure!');
end $t$;

-- The sender sees their messages read, and the reply.
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000001',true);
do $t$ declare r jsonb; begin
  r := public.mm_message_thread('MsgTwo');
  if r->'messages'->0->>'read' <> 'true' or r->'messages'->2->>'body' <> 'Sure!' or r->'messages'->2->>'fromMe' <> 'false' then
    raise exception 'sender view: %', r; end if;
end $t$;

-- Pages: the newest p_limit oldest-first, then those before a message id.
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000002',true);
do $t$ declare r jsonb; older jsonb; begin
  r := public.mm_message_thread('MsgOne', null, 2);
  if jsonb_array_length(r->'messages') <> 2 or r->>'hasMore' <> 'true' or r->'messages'->1->>'body' <> 'Sure!' then
    raise exception 'page one: %', r; end if;
  older := public.mm_message_thread('MsgOne', (r->'messages'->0->>'id')::bigint, 2);
  if jsonb_array_length(older->'messages') <> 1 or older->'messages'->0->>'body' <> 'Up for a game?' or older->>'hasMore' <> 'false' then
    raise exception 'page two: %', older; end if;
end $t$;

-- Rate limit: 20 a minute.
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000002',true);
do $t$ begin
  for i in 1..19 loop perform public.mm_message_send('MsgOne', 'spam ' || i); end loop;
  begin perform public.mm_message_send('MsgOne', 'one too many'); raise exception 'rate limit missed';
  exception when others then if sqlerrm <> 'too_many_messages' then raise; end if; end;
end $t$;

-- Reports can name a message.
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000001',true);
select public.mm_report('MsgTwo', 'spam 19', 'message');

-- Blocking ends the friendship: the conversation disappears both ways and nothing more can be sent.
select public.mm_block('MsgTwo');
do $t$ begin
  if jsonb_array_length(public.mm_message_conversations()) <> 0 then raise exception 'blocker still sees the conversation'; end if;
  if public.mm_message_unread() <> 0 then raise exception 'blocked sender counts as unread'; end if;
  begin perform public.mm_message_send('MsgTwo', 'hello?'); raise exception 'messaged a blocked player';
  exception when others then if sqlerrm <> 'not_friends' then raise; end if; end;
end $t$;
select set_config('request.jwt.claim.sub','e8000000-0000-0000-0000-000000000002',true);
do $t$ begin
  if jsonb_array_length(public.mm_message_conversations()) <> 0 then raise exception 'blocked player still sees the conversation'; end if;
  begin perform public.mm_message_send('MsgOne', 'why?'); raise exception 'blocked player messaged';
  exception when others then if sqlerrm <> 'not_friends' then raise; end if; end;
  -- No direct access, and the internal helpers stay internal.
  begin perform 1 from public.friend_messages; raise exception 'messages readable';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_message_friend('e8000000-0000-0000-0000-000000000002', 'MsgOne'); raise exception 'helper callable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

set local role anon;
do $t$ begin
  begin perform public.mm_message_unread(); raise exception 'anon read unread count';
  exception when insufficient_privilege then null; end;
  begin perform public.mm_message_send('MsgOne', 'hi'); raise exception 'anon sent';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

-- Deleting an account deletes its messages.
delete from auth.users where id = 'e8000000-0000-0000-0000-000000000002';
do $t$ begin
  if exists (select 1 from public.friend_messages where sender = 'e8000000-0000-0000-0000-000000000002'
                                                     or recipient = 'e8000000-0000-0000-0000-000000000002') then
    raise exception 'messages survived account deletion'; end if;
  if (select context from public.reports where reported_name = 'MsgTwo' order by id desc limit 1) <> 'message' then
    raise exception 'message report missing'; end if;
end $t$;
