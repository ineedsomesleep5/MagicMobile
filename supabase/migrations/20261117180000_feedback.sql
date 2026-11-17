-- Player feedback: a bug or a feature idea, in the player's words. Write-only for the apps, on the same
-- terms as diagnostic_reports. Row level security is on and there are no policies. anon and authenticated
-- have no privileges on the table, so a client cannot select, insert, update or delete. The only write is
-- mm_send_feedback, and it is granted to authenticated alone.
--
-- Signed-out callers are refused (not_signed_in), matching mm_send_diagnostic. A rate limit needs a stable
-- user id, and every install already makes an anonymous account the first time it is online, so a player
-- does not need a username to send a note. Someone with no session yet (offline, or still signing in)
-- is told to try again; nothing is stored.
--
-- The note is the message they typed, plus an optional contact, the app version, the platform and the
-- device. Deck lists and other saved content are not columns and are not accepted.
--
-- Nothing here grants a client a read. mm_feedback_summary is for a weekly check and is granted to
-- service_role only. The SQL editor (the table owner) can also run the queries in docs/SERVER_CONTROLS.md.

create table if not exists public.feedback (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  kind text not null check (kind in ('bug', 'feature')),
  message text not null check (char_length(message) between 1 and 4000),
  contact text check (contact is null or char_length(contact) between 1 and 120),
  platform text not null check (platform in ('ios', 'android', 'web')),
  app_version text not null check (char_length(app_version) between 1 and 40),
  build text not null check (char_length(build) between 1 and 40),
  device text not null check (char_length(device) between 1 and 80)
);

create index if not exists feedback_user_created on public.feedback (user_id, created_at desc);
create index if not exists feedback_created on public.feedback (created_at desc);

alter table public.feedback enable row level security;
revoke all on table public.feedback from public, anon, authenticated;

create or replace function public.mm_send_feedback(
  p_kind text, p_message text, p_contact text, p_platform text, p_app_version text, p_build text, p_device text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_message text := regexp_replace(coalesce(p_message, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_contact text := nullif(regexp_replace(coalesce(p_contact, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g'), '');
  v_version text := regexp_replace(coalesce(p_app_version, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_build text := regexp_replace(coalesce(p_build, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_device text := regexp_replace(coalesce(p_device, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
begin
  if v_uid is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;
  if coalesce(p_kind, '') not in ('bug', 'feature')
     or coalesce(p_platform, '') not in ('ios', 'android', 'web')
     or char_length(v_message) = 0 or char_length(v_message) > 4000
     or translate(v_message, E'\n\t', '') ~ '[[:cntrl:]]'
     or (v_contact is not null and (char_length(v_contact) > 120 or v_contact ~ '[[:cntrl:]]'))
     or char_length(v_version) = 0 or char_length(v_version) > 40 or v_version ~ '[[:cntrl:]]'
     or char_length(v_build) = 0 or char_length(v_build) > 40 or v_build ~ '[[:cntrl:]]'
     or char_length(v_device) = 0 or char_length(v_device) > 80 or v_device ~ '[[:cntrl:]]' then
    raise exception 'invalid_feedback' using errcode = '22023';
  end if;
  if (select count(*) from public.feedback where user_id = v_uid and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'too_many_feedback' using errcode = 'P0001';
  end if;
  insert into public.feedback (user_id, kind, message, contact, platform, app_version, build, device)
  values (v_uid, p_kind, v_message, v_contact, p_platform, v_version, v_build, v_device);
  return true;
end
$function$;

revoke all on function public.mm_send_feedback(text, text, text, text, text, text, text) from public, anon;
grant execute on function public.mm_send_feedback(text, text, text, text, text, text, text) to authenticated;

-- Counts by kind, platform and version, plus the newest notes in the window. service_role only.
-- The default window is the last seven days. Recent notes are capped at 40.
create or replace function public.mm_feedback_summary(p_since timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_since timestamptz := coalesce(p_since, now() - interval '7 days');
  v_counts jsonb;
  v_recent jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', kind, 'platform', platform, 'app_version', app_version, 'n', n
         ) order by kind, platform, app_version), '[]'::jsonb)
    into v_counts
    from (
      select kind, platform, app_version, count(*)::integer as n
        from public.feedback
       where created_at >= v_since
       group by kind, platform, app_version
    ) counts;

  select coalesce(jsonb_agg(jsonb_build_object(
           'created_at', created_at, 'kind', kind, 'platform', platform, 'app_version', app_version,
           'build', build, 'device', device, 'contact', contact, 'message', message
         ) order by created_at desc), '[]'::jsonb)
    into v_recent
    from (
      select created_at, kind, platform, app_version, build, device, contact, message
        from public.feedback
       where created_at >= v_since
       order by created_at desc
       limit 40
    ) recent;

  return jsonb_build_object('since', v_since, 'counts', v_counts, 'recent', v_recent);
end
$function$;

revoke all on function public.mm_feedback_summary(timestamptz) from public, anon, authenticated;

do $grant$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.mm_feedback_summary(timestamptz) to service_role;
  end if;
end
$grant$;
