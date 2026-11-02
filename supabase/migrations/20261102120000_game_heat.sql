-- Heat reports (Caleb, 2026-11-02: a tracker, so nobody has to record a phone). Each phone sends one game's numbers once it
-- ends, so builds, tables and phones compare by themselves. Nobody but the database reads them: no player sees another's, and
-- deleting a profile deletes its rows. docs/SERVER_CONTROLS.md "Heat reports".

create table if not exists public.game_heat (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- The phone's own id for the report: sending one twice stores it once.
  client_id uuid not null,
  played_at timestamptz not null,
  platform text not null check (platform in ('ios', 'android')),
  build integer not null check (build between 1 and 100000),
  device text not null check (char_length(device) <= 40),
  os text check (char_length(os) <= 40),
  mode text not null check (char_length(mode) <= 40),
  ai_skill integer check (ai_skill between 0 and 20),
  board text check (char_length(board) <= 40),
  table_name text check (char_length(table_name) <= 40),
  motion text check (char_length(motion) <= 40),
  effects text check (char_length(effects) <= 40),
  -- Numbers and two flags, under the names mm_game_heat keeps. A new number needs one more name there, not a new column.
  stats jsonb not null check (jsonb_typeof(stats) = 'object'),
  created_at timestamptz not null default now(),
  unique (user_id, client_id)
);

create index if not exists game_heat_user_recent on public.game_heat (user_id, created_at desc);

alter table public.game_heat enable row level security;
revoke all on public.game_heat from public, anon, authenticated;

create or replace function public.mm_game_heat(
  p_client_id uuid, p_played_at timestamptz, p_platform text, p_build integer, p_device text, p_os text, p_mode text,
  p_stats jsonb, p_ai_skill integer default null, p_board text default null, p_table text default null,
  p_motion text default null, p_effects text default null) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_profile();
  v_name constant text := '^[a-z0-9-]{1,40}$';
  v_stats jsonb;
  v_id bigint;
begin
  if p_client_id is null or p_played_at is null
     or p_played_at > now() + interval '1 day' or p_played_at < now() - interval '1 year'
     or coalesce(p_platform, '') not in ('ios', 'android') or coalesce(p_build, 0) not between 1 and 100000
     or coalesce(btrim(p_device), '') = '' or char_length(p_device) > 40 or p_device ~ '[[:cntrl:]]'
     or char_length(p_os) > 40 or p_os ~ '[[:cntrl:]]'
     or coalesce(p_mode, '') !~ v_name or p_ai_skill not between 0 and 20
     or p_board !~ v_name or p_table !~ v_name or p_motion !~ v_name or p_effects !~ v_name
     or jsonb_typeof(p_stats) is distinct from 'object' then
    raise exception 'invalid_report' using errcode = '22023';
  end if;

  if (select count(*) from public.game_heat where user_id = v_uid and created_at > now() - interval '1 hour') >= 100 then
    raise exception 'too_many_reports' using errcode = 'P0001';
  end if;

  -- Rebuilt from the names we know: nothing else a phone sends is kept.
  select coalesce(jsonb_object_agg(s.name, p_stats -> s.name), '{}'::jsonb) into v_stats
    from (select unnest(array['minutes', 'turns', 'hottest', 'startThermal', 'hotMinutes', 'warmMinutes', 'secondsToWarm',
                              'secondsToHot', 'cpu', 'cpuBoard', 'cpuUpdates', 'cpuAI', 'slowFrames', 'batteryUsed', 'peakMB',
                              'lowestHeadroomMB', 'memoryWarnings', 'tempStart', 'tempPeak']) as name, 'number' as kind
          union all
          select unnest(array['charging', 'lowPower', 'interrupted']), 'boolean') s
   where jsonb_typeof(p_stats -> s.name) = s.kind;

  insert into public.game_heat (user_id, client_id, played_at, platform, build, device, os, mode, ai_skill, board, table_name,
                                motion, effects, stats)
  values (v_uid, p_client_id, p_played_at, p_platform, p_build, btrim(p_device), nullif(btrim(p_os), ''), p_mode, p_ai_skill,
          p_board, p_table, p_motion, p_effects, v_stats)
  on conflict (user_id, client_id) do nothing
  returning id into v_id;

  if v_id is not null then
    delete from public.game_heat
     where user_id = v_uid
       and id in (select g.id from public.game_heat g where g.user_id = v_uid order by g.played_at desc, g.id desc offset 500);
  end if;
  return v_id is not null;
end $$;

revoke all on function public.mm_game_heat(uuid, timestamptz, text, integer, text, text, text, jsonb, integer, text, text, text, text)
  from public, anon;
grant execute on function public.mm_game_heat(uuid, timestamptz, text, integer, text, text, text, jsonb, integer, text, text, text, text)
  to authenticated;

-- The first read: real games of three minutes or more, not on a charger and not already hot at the start, by build, table and
-- how much the world moved. CPU is percent of one core. Only the SQL editor and the connector can read it.
create or replace view public.game_heat_summary with (security_invoker = true) as
select platform, build, table_name, motion, count(*)::integer as games,
       round(avg((stats ->> 'minutes')::numeric), 1) as minutes,
       round(100.0 * count(*) filter (where (stats ->> 'hottest')::numeric >= 2) / count(*)) as serious_pct,
       round(avg((stats ->> 'hotMinutes')::numeric), 1) as hot_minutes,
       round(avg((stats ->> 'secondsToWarm')::numeric)) as seconds_to_warm,
       round(avg((stats ->> 'cpu')::numeric)) as cpu,
       round(avg((stats ->> 'cpuBoard')::numeric)) as cpu_board,
       round(avg((stats ->> 'cpuUpdates')::numeric)) as cpu_updates,
       round(avg((stats ->> 'cpuAI')::numeric)) as cpu_ai,
       round(avg((stats ->> 'slowFrames')::numeric), 1) as slow_frames,
       round(avg((stats ->> 'batteryUsed')::numeric), 1) as battery_used
  from public.game_heat
 where (stats ->> 'minutes')::numeric >= 3
   and not coalesce((stats ->> 'charging')::boolean, false)
   and coalesce((stats ->> 'startThermal')::numeric, 0) < 2
 group by platform, build, table_name, motion;

revoke all on public.game_heat_summary from public, anon, authenticated;
