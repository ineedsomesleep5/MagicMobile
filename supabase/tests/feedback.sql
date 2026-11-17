-- mm_send_feedback and mm_feedback_summary (20261117180000_feedback.sql).
-- Clients can add a row only through the function. They cannot read the table or the summary.

insert into auth.users (id, aud, role, email) values
  ('f1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'one@example.invalid'),
  ('f1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'two@example.invalid');

do $t$
declare
  policies int;
  locked boolean;
begin
  select count(*) into policies from pg_policy where polrelid = 'public.feedback'::regclass;
  if policies <> 0 then raise exception 'feedback has a policy'; end if;
  select relrowsecurity into locked from pg_class where oid = 'public.feedback'::regclass;
  if not locked then raise exception 'rls is off'; end if;
  if has_table_privilege('anon', 'public.feedback', 'SELECT')
     or has_table_privilege('anon', 'public.feedback', 'INSERT')
     or has_table_privilege('anon', 'public.feedback', 'UPDATE')
     or has_table_privilege('anon', 'public.feedback', 'DELETE')
     or has_table_privilege('authenticated', 'public.feedback', 'SELECT')
     or has_table_privilege('authenticated', 'public.feedback', 'INSERT')
     or has_table_privilege('authenticated', 'public.feedback', 'UPDATE')
     or has_table_privilege('authenticated', 'public.feedback', 'DELETE') then
    raise exception 'a client can touch the table';
  end if;
  if has_function_privilege('anon', 'public.mm_send_feedback(text,text,text,text,text,text,text)', 'EXECUTE')
     or has_function_privilege('public', 'public.mm_send_feedback(text,text,text,text,text,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.mm_feedback_summary(timestamptz)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.mm_feedback_summary(timestamptz)', 'EXECUTE')
     or has_function_privilege('public', 'public.mm_feedback_summary(timestamptz)', 'EXECUTE') then
    raise exception 'a client can execute a feedback function they should not';
  end if;
  if not has_function_privilege('authenticated', 'public.mm_send_feedback(text,text,text,text,text,text,text)', 'EXECUTE') then
    raise exception 'a signed-in player cannot send';
  end if;
  if not has_function_privilege('service_role', 'public.mm_feedback_summary(timestamptz)', 'EXECUTE') then
    raise exception 'service_role cannot read the summary';
  end if;
end $t$;

set local role anon;
do $t$
begin
  perform public.mm_send_feedback('bug', 'hi', null, 'ios', '0.1.1', '79', 'iPhone');
  raise exception 'anon sent feedback';
exception when insufficient_privilege then null;
end $t$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $t$
begin
  perform public.mm_send_feedback('bug', 'hi', null, 'ios', '0.1.1', '79', 'iPhone');
  raise exception 'a signed-out session stored a note';
exception when others then
  if sqlerrm <> 'not_signed_in' then raise; end if;
end $t$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
do $t$
declare
  raised boolean;
begin
  if not public.mm_send_feedback('bug', '  The board froze  ', '  ada@example.com  ', 'ios', '0.1.1', '79', 'iPhone17,2 · 18.1') then
    raise exception 'a note was refused';
  end if;
  -- The player cannot read it back, and cannot call the weekly summary.
  begin
    perform 1 from public.feedback;
    raise exception 'a player read the table';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.mm_feedback_summary();
    raise exception 'a player read the summary';
  exception when insufficient_privilege then null;
  end;

  raised := false;
  begin perform public.mm_send_feedback('praise', 'Nice', null, 'ios', '0.1.1', '79', 'iPhone'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'an unknown kind'; end if;
  raised := false;
  begin perform public.mm_send_feedback('bug', '   ', null, 'ios', '0.1.1', '79', 'iPhone'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'a blank note'; end if;
  raised := false;
  begin perform public.mm_send_feedback('bug', repeat('a', 4001), null, 'ios', '0.1.1', '79', 'iPhone'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'a note over 4000 characters'; end if;
  raised := false;
  begin perform public.mm_send_feedback('bug', E'bad\x01note', null, 'ios', '0.1.1', '79', 'iPhone'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'a control character'; end if;
  raised := false;
  begin perform public.mm_send_feedback('feature', E'line\nnext', null, 'web', '0.1.1', 'web', 'macOS · Safari'); exception when others then raised := true; end;
  if raised then raise exception 'a line break should be kept'; end if;
  raised := false;
  begin perform public.mm_send_feedback('bug', 'hi', repeat('a', 121), 'ios', '0.1.1', '79', 'iPhone'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'a contact over 120 characters'; end if;
  raised := false;
  begin perform public.mm_send_feedback('bug', 'hi', E'ada\n@example.com', 'ios', '0.1.1', '79', 'iPhone'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'a line break in the contact'; end if;
  raised := false;
  begin perform public.mm_send_feedback('bug', 'hi', null, 'desktop', '0.1.1', '79', 'iPhone'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'an unknown platform'; end if;
  raised := false;
  begin perform public.mm_send_feedback('bug', 'hi', null, 'android', '', '56', 'Pixel'); exception when others then raised := sqlerrm = 'invalid_feedback'; end;
  if not raised then raise exception 'a blank version'; end if;
  if not public.mm_send_feedback('bug', 'it said ''); drop table public.feedback; --', '   ', 'android', '0.1.1', '56', 'Pixel · Android 15') then
    raise exception 'a note with quotes was refused';
  end if;
end $t$;
reset role;

do $t$
declare
  row_count int;
  stored text;
  who text;
begin
  select count(*), max(message) filter (where kind = 'bug' and platform = 'ios'), max(contact) filter (where kind = 'bug' and platform = 'ios')
    into row_count, stored, who
    from public.feedback
   where user_id = 'f1000000-0000-0000-0000-000000000001';
  if stored <> 'The board froze' or who <> 'ada@example.com' then raise exception 'stored note: % / %', stored, who; end if;
  if not exists (select 1 from public.feedback where message = E'line\nnext' and contact is null and platform = 'web') then
    raise exception 'the line break or the blank contact was not stored';
  end if;
  if not exists (select 1 from public.feedback where message = 'it said ''); drop table public.feedback; --' and contact is null) then
    raise exception 'the quoted note was rewritten';
  end if;
  -- Three stored notes so far (trimmed bug, line break, quoted). Invalid attempts stored nothing.
  if row_count <> 3 then raise exception 'row count %', row_count; end if;
  if to_regclass('public.feedback') is null then raise exception 'the table was dropped'; end if;
end $t$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
do $t$
declare
  i int;
  raised boolean := false;
begin
  -- Three notes are already in the last hour. Two more fill the five-an-hour cap. The next is refused.
  for i in 1..2 loop
    if not public.mm_send_feedback('feature', 'Idea ' || i, null, 'android', '0.1.1', '56', 'Pixel · Android 15') then
      raise exception 'idea % refused', i;
    end if;
  end loop;
  begin
    perform public.mm_send_feedback('bug', 'one more', null, 'ios', '0.1.1', '79', 'iPhone');
    raise exception 'a sixth note in an hour was stored';
  exception when others then
    raised := sqlerrm = 'too_many_feedback';
  end;
  if not raised then raise exception 'the rate limit did not say too_many_feedback'; end if;
end $t$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000002', true);
do $t$
begin
  if not public.mm_send_feedback('feature', 'From the other player', null, 'web', '0.1.1', 'web', 'macOS · Safari') then
    raise exception 'another player was rate limited';
  end if;
end $t$;
reset role;

update public.feedback set created_at = now() - interval '2 hours' where user_id = 'f1000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000001', true);
do $t$
begin
  if not public.mm_send_feedback('bug', 'After the hour', null, 'ios', '0.1.1', '80', 'iPhone17,2 · 18.2') then
    raise exception 'an old hour still counted';
  end if;
end $t$;
reset role;

set local role service_role;
do $t$
declare
  summary jsonb;
  bug_ios int;
  recent int;
begin
  begin
    perform 1 from public.feedback;
    raise exception 'service_role read the table directly';
  exception when insufficient_privilege then null;
  end;
  summary := public.mm_feedback_summary(now() - interval '7 days');
  select (item ->> 'n')::int into bug_ios
    from jsonb_array_elements(summary -> 'counts') item
   where item ->> 'kind' = 'bug' and item ->> 'platform' = 'ios' and item ->> 'app_version' = '0.1.1';
  -- The first bug, plus the one after the hour. The five-cap ideas are feature/android.
  if bug_ios is distinct from 2 then raise exception 'bug ios count % in %', bug_ios, summary -> 'counts'; end if;
  if not exists (
    select 1 from jsonb_array_elements(summary -> 'counts') item
     where item ->> 'kind' = 'feature' and item ->> 'platform' = 'android' and item ->> 'app_version' = '0.1.1' and (item ->> 'n')::int = 2
  ) then raise exception 'feature android count %', summary -> 'counts'; end if;
  if not exists (
    select 1 from jsonb_array_elements(summary -> 'counts') item
     where item ->> 'kind' = 'feature' and item ->> 'platform' = 'web' and (item ->> 'n')::int = 2
  ) then raise exception 'feature web count %', summary -> 'counts'; end if;
  select jsonb_array_length(summary -> 'recent') into recent;
  if recent <> 7 then raise exception 'recent %', recent; end if;
  if not exists (
    select 1 from jsonb_array_elements(summary -> 'recent') item
     where item ->> 'message' = 'After the hour' and item ->> 'device' = 'iPhone17,2 · 18.2' and item ->> 'build' = '80'
  ) then raise exception 'recent notes dropped the device'; end if;
  -- The default window is seven days and still sees these rows.
  if jsonb_array_length(public.mm_feedback_summary() -> 'recent') <> 7 then raise exception 'default window'; end if;
  -- A window that starts after the rows hides them.
  if jsonb_array_length(public.mm_feedback_summary(now() + interval '1 day') -> 'recent') <> 0 then
    raise exception 'a future window still returned notes';
  end if;
end $t$;
reset role;

delete from auth.users where id = 'f1000000-0000-0000-0000-000000000001';
do $t$
begin
  if exists (select 1 from public.feedback where user_id = 'f1000000-0000-0000-0000-000000000001') then
    raise exception 'notes survived the account';
  end if;
  if not exists (select 1 from public.feedback where user_id = 'f1000000-0000-0000-0000-000000000002') then
    raise exception 'the other player was deleted too';
  end if;
end $t$;
