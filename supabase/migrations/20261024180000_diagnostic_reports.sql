-- Freeze and crash reports a player chose to send (docs/FREEZE_LOG.md). Write-only for players: RLS on, no grants on
-- the table, one security-definer function to add a row. The developer reads them with SQL.

create table if not exists public.diagnostic_reports (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  platform text not null check (platform in ('ios', 'android', 'web')),
  app_version text not null check (char_length(app_version) <= 40),
  build text not null check (char_length(build) <= 40),
  kind text not null check (kind in ('hang', 'answer-not-accepted', 'engine-quiet', 'reported', 'crash', 'other')),
  report text not null check (char_length(report) <= 65536)
);
create index if not exists diagnostic_reports_user_created on public.diagnostic_reports (user_id, created_at desc);
alter table public.diagnostic_reports enable row level security;
revoke all on table public.diagnostic_reports from anon, authenticated;

create or replace function public.mm_send_diagnostic(p_platform text, p_app_version text, p_build text, p_kind text, p_report text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;
  if coalesce(p_platform, '') not in ('ios', 'android', 'web')
     or coalesce(p_kind, '') not in ('hang', 'answer-not-accepted', 'engine-quiet', 'reported', 'crash', 'other')
     or char_length(coalesce(p_report, '')) = 0 or char_length(p_report) > 65536
     or char_length(coalesce(p_app_version, '')) > 40 or char_length(coalesce(p_build, '')) > 40 then
    raise exception 'invalid_report' using errcode = '22023';
  end if;
  if (select count(*) from public.diagnostic_reports where user_id = v_uid and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'too_many_reports' using errcode = 'P0001';
  end if;
  insert into public.diagnostic_reports (user_id, platform, app_version, build, kind, report)
  values (v_uid, p_platform, coalesce(p_app_version, ''), coalesce(p_build, ''), p_kind, p_report);
  return true;
end $function$;

revoke all on function public.mm_send_diagnostic(text, text, text, text, text) from public, anon;
grant execute on function public.mm_send_diagnostic(text, text, text, text, text) to authenticated;
