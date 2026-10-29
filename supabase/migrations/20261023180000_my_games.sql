-- The player's own games from every device, newest first, so a profile's Recent games show what was played on the
-- phone and in the browser alike (each device already sends its finished games through mm_record_game). Read-only:
-- only the caller's own rows, through the same security-definer pattern as the other mm_* functions.

create or replace function public.mm_my_games(p_limit integer default 200)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := public.mm_require_profile();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'client_id', g.client_id, 'played_at', g.played_at, 'mode', g.mode, 'result', g.result,
             'deck_name', g.deck_name, 'commanders', to_jsonb(g.commanders), 'colors', to_jsonb(g.colors),
             'opponents', g.opponents, 'turns', g.turns, 'rank_points', g.rank_points)
           order by g.played_at desc, g.id desc)
      from (select * from public.player_games
             where user_id = v_uid
             order by played_at desc, id desc
             limit least(greatest(coalesce(p_limit, 200), 1), 500)) g), '[]'::jsonb);
end $function$;

revoke all on function public.mm_my_games(integer) from public, anon;
grant execute on function public.mm_my_games(integer) to authenticated;
