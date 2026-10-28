-- mm_app_config (20261027010000_app_config.sql): the notice aimed by platform and build, fixes and switches as stored,
-- the table itself out of reach.
update public.app_settings set value = '{"id": "update-64", "text": "Update to build 64 for the new table rules.", "platforms": ["ios", "android"], "maxBuild": {"ios": 63, "android": 41}}'
 where key = 'notice';
update public.app_settings set value = '{"Lim-Dûl the Necromancer": "Lim-Dul the Necromancer"}' where key = 'name_fixes';

set local role anon;
do $t$
declare r jsonb;
begin
  r := public.mm_app_config('ios', 63);
  if r->'notice'->>'id' <> 'update-64' or r->'notice'->>'text' not like 'Update to build 64%' or r->'notice' ? 'maxBuild' then raise exception 'ios 63: %', r; end if;
  if r->'switches'->>'leaveVote' <> 'true' or r->'nameFixes'->>'Lim-Dûl the Necromancer' <> 'Lim-Dul the Necromancer' then raise exception 'fixes/switches: %', r; end if;
  if public.mm_app_config('ios', 64)->'notice' <> 'null'::jsonb then raise exception 'ios 64 should not see it'; end if;
  if public.mm_app_config('web', 1)->'notice' <> 'null'::jsonb then raise exception 'web is not a target'; end if;
  if public.mm_app_config('android', 41)->'notice'->>'id' <> 'update-64' then raise exception 'android 41'; end if;
  begin perform 1 from public.app_settings; raise exception 'settings readable';
  exception when insufficient_privilege then null; end;
end $t$;
reset role;

update public.app_settings set value = 'null' where key = 'notice';
do $t$ begin
  if public.mm_app_config(null, null)->'notice' <> 'null'::jsonb then raise exception 'no notice'; end if;
end $t$;
