-- Ranked AI wins from the web game (Caleb, 2026-10-26: web wins never moved his rank). The web engine names itself
-- `web-<n>:sha256:<hex>` in its game records, which ranked_engine_builds' check refused, so no web build could be listed
-- and every web win settled `unverified` (engine_build). The check now takes that form too, the live web engine is
-- listed, and the wins held back for it are re-settled when their records pass.
alter table public.ranked_engine_builds drop constraint if exists ranked_engine_builds_engine_build_check;
alter table public.ranked_engine_builds add constraint ranked_engine_builds_engine_build_check
  check (engine_build ~ '^(web-[0-9]{1,3}:)?sha256:[0-9a-f]{64}$');

insert into public.ranked_engine_builds (engine_build, label)
values ('web-1:sha256:2a87f6e53255079c42b31446ead19653fd7d2da785c83cd94dfd14149aecc932',
        'Web engine (magicmobile-web.vercel.app, engine-38c828b004c5814e)')
on conflict (engine_build) do nothing;

do $$
declare
  g public.ranked_ai_games%rowtype;
begin
  for g in select * from public.ranked_ai_games
            where result = 'win' and settlement = 'unverified' and record_check = 'engine_build'
            order by created_at loop
    if public.mm_ranked_ai_record_check(g, (select r.record from public.ranked_ai_records r where r.game_id = g.id)) is null then
      update public.ranked_ai_games set settlement = 'counted', record_check = null where id = g.id;
      perform public.mm_ranked_apply(g.user_id, 'win', g.deck_bracket, 'ai', null, g.id);
    end if;
  end loop;
end $$;
