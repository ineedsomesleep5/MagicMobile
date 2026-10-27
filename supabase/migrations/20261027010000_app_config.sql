-- What the server can change without an app build (Caleb, 2026-10-26: "what can be handled on the server without having
-- to update builds"): a news banner for the main menu, card-name fixes for deck imports, and switches for newer features.
-- One row per key, read by every app at launch through mm_app_config; edited with SQL (docs/SERVER_CONTROLS.md).
--
--   notice:     {"id": "...", "text": "...", "platforms": ["ios","android","web"]?, "maxBuild": {"ios": 63, "android": 41}?}
--               or null. Shown once per id until dismissed; maxBuild aims it at older builds ("update to build 64").
--   name_fixes: {"Name a deck site sends": "The app's card name"}; an app uses one only when that card is in its catalogue.
--   switches:   {"leaveVote": true, "stackAutoTuck": true}; an app treats a missing switch as on.

create table if not exists public.app_settings (
  key text primary key check (key in ('notice', 'name_fixes', 'switches')),
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from public, anon, authenticated;

insert into public.app_settings (key, value) values
  ('notice', 'null'::jsonb),
  ('name_fixes', '{}'::jsonb),
  ('switches', '{"leaveVote": true, "stackAutoTuck": true}'::jsonb)
on conflict (key) do nothing;

-- The settings for one app: the notice only when it is meant for this platform and build.
create or replace function public.mm_app_config(p_platform text default null, p_build integer default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_notice jsonb := (select value from public.app_settings where key = 'notice');
  v_fixes jsonb := coalesce((select value from public.app_settings where key = 'name_fixes'), '{}'::jsonb);
  v_switches jsonb := coalesce((select value from public.app_settings where key = 'switches'), '{}'::jsonb);
begin
  if jsonb_typeof(v_notice) <> 'object' or coalesce(v_notice->>'id', '') = '' or coalesce(v_notice->>'text', '') = ''
     or (jsonb_typeof(v_notice->'platforms') = 'array' and not (v_notice->'platforms') ? coalesce(p_platform, ''))
     or (jsonb_typeof(v_notice->'maxBuild'->p_platform) = 'number' and coalesce(p_build, 0) > (v_notice->'maxBuild'->>p_platform)::integer) then
    v_notice := null;
  else
    v_notice := jsonb_build_object('id', left(v_notice->>'id', 80), 'text', left(v_notice->>'text', 280));
  end if;
  return jsonb_build_object('notice', v_notice,
                            'nameFixes', case when jsonb_typeof(v_fixes) = 'object' then v_fixes else '{}'::jsonb end,
                            'switches', case when jsonb_typeof(v_switches) = 'object' then v_switches else '{}'::jsonb end);
end $$;
revoke all on function public.mm_app_config(text, integer) from public;
grant execute on function public.mm_app_config(text, integer) to anon, authenticated;
