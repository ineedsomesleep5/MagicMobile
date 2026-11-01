-- A newer AI deck file without an app build (Caleb, 2026-10-30: "so future ones don't need a update"; docs/SERVER_CONTROLS.md).
-- `ai_decks` names one file per card catalogue, as a catalogue's cards are all a file may use:
--   {"<catalogue hash>": {"revision": 2, "url": "https://...", "sha256": "..."}}
-- An app downloads it when the revision is newer than its own and it has not already; {} sends every app back to its own.

alter table public.app_settings drop constraint if exists app_settings_key_check;
alter table public.app_settings add constraint app_settings_key_check check (key in ('notice', 'name_fixes', 'switches', 'ai_decks'));
insert into public.app_settings (key, value) values ('ai_decks', '{}'::jsonb) on conflict (key) do nothing;

create or replace function public.mm_app_config(p_platform text default null, p_build integer default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_notice jsonb := (select value from public.app_settings where key = 'notice');
  v_fixes jsonb := coalesce((select value from public.app_settings where key = 'name_fixes'), '{}'::jsonb);
  v_switches jsonb := coalesce((select value from public.app_settings where key = 'switches'), '{}'::jsonb);
  v_decks jsonb := coalesce((select value from public.app_settings where key = 'ai_decks'), '{}'::jsonb);
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
                            'switches', case when jsonb_typeof(v_switches) = 'object' then v_switches else '{}'::jsonb end,
                            'aiDecks', case when jsonb_typeof(v_decks) = 'object' then v_decks else '{}'::jsonb end);
end $$;
revoke all on function public.mm_app_config(text, integer) from public;
grant execute on function public.mm_app_config(text, integer) to anon, authenticated;
