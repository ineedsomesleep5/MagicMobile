-- Requires the already deployed MagicMobile matchmaking schema. Local review only;
-- this migration does not attempt to reconstruct its untracked historical baseline.
-- Retain departed users' membership rows while allowing their seat to be reused.
-- The live constraint has no dependent foreign keys (read-only catalog audit).
-- DROP without CASCADE deliberately fails if a future dependency appears.
alter table public.match_players drop constraint match_players_match_id_seat_key;
create unique index match_players_active_seat_key
  on public.match_players(match_id,seat) where left_at is null;

-- A shared transaction lock is appropriate for the small MVP capacity. All paths
-- that can change membership take it BEFORE reading or locking a match. This also
-- covers enqueue placing OTHER queued users; a caller-only lock would not suffice.
do $migration$
declare
  f record;
  changed text;
  definition text;
  expected integer := 0;
begin
  for f in
    select p.oid,p.proname,p.prosrc,pg_catalog.pg_get_functiondef(p.oid) as definition
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    join pg_catalog.pg_language l on l.oid=p.prolang
    where n.nspname='matchmaking_private' and l.lanname='plpgsql'
      and p.proname in ('create_lobby_impl','join_lobby_impl','enqueue_impl',
        'cleanup','state_impl','start_impl','set_ready_impl','finish_impl','cancel_impl')
  loop
    expected := expected + 1;
    if pg_catalog.strpos(f.prosrc,'pg_advisory_xact_lock(1936028278, 1)') > 0 then
      continue;
    end if;
    changed := pg_catalog.regexp_replace(f.prosrc, E'\\mbegin\\M',
      E'begin\n  perform pg_catalog.pg_advisory_xact_lock(1936028278, 1);', 'i');
    if changed=f.prosrc then raise exception 'Unrecognized implementation body: %',f.proname; end if;
    definition := pg_catalog.replace(f.definition,f.prosrc,changed);
    execute definition;
  end loop;
  if expected <> 9 then raise exception 'Expected nine deployed matchmaking implementations, found %',expected; end if;
end;
$migration$;

-- adapterVersion is carried in engine_build. Protocol/upstream/catalogue alone
-- do not guarantee two app adapters understand the same prompts and projection.
do $identity$
declare
  f record;
  changed text;
  expected integer := 0;
begin
  for f in
    select p.oid,p.proname,p.prosrc,pg_catalog.pg_get_functiondef(p.oid) as definition
    from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname='matchmaking_private' and p.proname in ('join_lobby_impl','enqueue_impl')
  loop
    expected := expected+1;
    changed := f.prosrc;
    if f.proname='join_lobby_impl' then
      -- RETURNS TABLE includes match_id; spelling the conflict columns makes
      -- PostgreSQL treat match_id as ambiguous at runtime. Use its named key.
      changed := pg_catalog.replace(changed,'on conflict (match_id, user_id)',
        'on conflict on constraint match_players_pkey');
      if pg_catalog.strpos(changed,'v_match.engine_build is distinct from p_engine_build')=0 then
        if pg_catalog.strpos(changed,'or v_match.catalogue_hash <> p_catalogue_hash then')=0 then
          raise exception 'Unrecognized join identity predicate';
        end if;
        changed := pg_catalog.replace(changed,'or v_match.catalogue_hash <> p_catalogue_hash then',
          E'or v_match.catalogue_hash <> p_catalogue_hash\n     or v_match.engine_build is distinct from p_engine_build then');
      end if;
    else
      if pg_catalog.strpos(changed,'and q.engine_build = p_engine_build')=0 then
        if pg_catalog.strpos(changed,'and q.catalogue_hash = p_catalogue_hash')=0 then
          raise exception 'Unrecognized queue candidate identity predicate';
        end if;
        changed := pg_catalog.replace(changed,'and q.catalogue_hash = p_catalogue_hash',
          E'and q.catalogue_hash = p_catalogue_hash\n      and q.engine_build = p_engine_build');
      end if;
      if pg_catalog.strpos(changed,'and matchmaking_private.quick_queue.engine_build = excluded.engine_build')=0 then
        if pg_catalog.strpos(changed,'and matchmaking_private.quick_queue.catalogue_hash = excluded.catalogue_hash')=0 then
          raise exception 'Unrecognized queue reset identity predicate';
        end if;
        changed := pg_catalog.replace(changed,'and matchmaking_private.quick_queue.catalogue_hash = excluded.catalogue_hash',
          E'and matchmaking_private.quick_queue.catalogue_hash = excluded.catalogue_hash\n       and matchmaking_private.quick_queue.engine_build = excluded.engine_build');
      end if;
    end if;
    execute pg_catalog.replace(f.definition,f.prosrc,changed);
  end loop;
  if expected<>2 then raise exception 'Expected two matchmaking identity implementations, found %',expected; end if;
end;
$identity$;

create or replace function matchmaking_private.leave_match_impl(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  v_uid uuid := auth.uid();
  v_match public.matches%rowtype;
  v_remaining integer;
  v_host uuid;
begin
  if v_uid is null then raise exception using errcode='42501',message='Authentication required'; end if;
  if p_match_id is null then raise exception using errcode='22023',message='Expected match ID is required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(1936028278, 1);
  select m.* into v_match
  from public.matches m join public.match_players mp on mp.match_id=m.id
  where mp.user_id=v_uid and mp.left_at is null and m.status in ('waiting','ready','active')
  order by m.created_at desc limit 1 for update of m;
  if not found then return jsonb_build_object('left',true); end if;
  if v_match.id <> p_match_id then
    raise exception using errcode='42501',message='This is not your current lobby';
  end if;
  delete from matchmaking_private.quick_queue where user_id=v_uid;
  if v_match.status='active' then
    -- The MVP has no player replacement: any explicit leave ends the whole game.
    update public.match_players set left_at=coalesce(left_at,now()),ready=false
      where match_id=v_match.id;
    update public.matches set status='abandoned',ended_at=now(),updated_at=now(),revision=revision+1
      where id=v_match.id;
    delete from matchmaking_private.match_transport where match_id=v_match.id;
  else
    update public.match_players set left_at=now(),ready=false
      where match_id=v_match.id and user_id=v_uid and left_at is null;
    select count(*) into v_remaining from public.match_players
      where match_id=v_match.id and left_at is null;
    if v_remaining=0 then
      update public.matches set status='cancelled',ended_at=now(),updated_at=now(),revision=revision+1
        where id=v_match.id;
    else
      v_host := v_match.host_user_id;
      if v_host=v_uid then
        select user_id into v_host from public.match_players
          where match_id=v_match.id and left_at is null
          order by host_score desc,joined_at,user_id limit 1;
      end if;
      update public.matches set status='waiting',host_user_id=v_host,updated_at=now(),revision=revision+1
        where id=v_match.id;
    end if;
  end if;
  return jsonb_build_object('left',true);
end;
$function$;

-- Public wrapper remains SECURITY INVOKER, matching the existing schema's ACL
-- arrangement. Authenticated EXECUTE on its private target is necessary for this
-- arrangement; the private target independently checks auth.uid and expected ID.
create or replace function public.matchmaking_leave_match(p_match_id uuid)
returns jsonb
language sql
security invoker
set search_path = pg_catalog
as $function$
  select matchmaking_private.leave_match_impl(p_match_id);
$function$;

revoke all on function matchmaking_private.leave_match_impl(uuid) from public,anon;
revoke all on function public.matchmaking_leave_match(uuid) from public,anon;
grant execute on function matchmaking_private.leave_match_impl(uuid) to authenticated;
grant execute on function public.matchmaking_leave_match(uuid) to authenticated;

-- Keep the deployed parameterless API compatible, but give it the same lock and
-- whole-game termination semantics. Existing clients intentionally leave their
-- current match; new clients must use the expected-ID API to prevent stale exits.
create or replace function matchmaking_private.leave_impl()
returns table(state text,queue_topic text,match_id uuid,match_topic text,join_code text,
  seat smallint,is_host boolean,player_count smallint,match_status text,
  protocol_version integer,engine_build text)
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then raise exception using errcode='42501',message='Authentication required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(1936028278, 1);
  select m.id into v_id from public.matches m
    join public.match_players mp on mp.match_id=m.id
    where mp.user_id=v_uid and mp.left_at is null and m.status in ('waiting','ready','active')
    order by m.created_at desc limit 1 for update of m;
  if v_id is not null then perform matchmaking_private.leave_match_impl(v_id);
  else delete from matchmaking_private.quick_queue where user_id=v_uid;
  end if;
  return query select * from matchmaking_private.state_impl();
end;
$function$;

comment on function public.matchmaking_leave_match(uuid) is
  'Idempotent expected-match leave. Same transaction lock as all matchmaking membership mutations. Active leave ends all seats.';
