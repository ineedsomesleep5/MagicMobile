-- Deck sync: your decks on every phone and browser signed in to the same profile (docs/DECK_SYNC.md).
--
-- A deck travels as one document in the phones' decks.json shape (DeckLibraryRecord: name, format, commander, entries
-- with cardName / quantity / section and an optional chosen printing, source), so nothing is lost between iOS, Android
-- and the web. The July 2026 `decks` table was never used by any client (no rows); it gains the document, a tombstone
-- for deletions and a change sequence the clients pull from. `deck_entries` stays unused.
--
-- Every write names the revision it was based on; a stale write is refused as `conflict` with the server's copy, and the
-- client keeps both (its edits become a copy), so no edit is ever lost. Deletions are tombstones that keep the id, so a
-- deck deleted on one device leaves the others.
--
-- Same rules as the other social tables: RLS on, no direct grants, everything through mm_* functions (security definer,
-- fixed search_path).

create sequence if not exists public.deck_change_seq;

alter table public.decks
  add column if not exists body jsonb not null default '{}'::jsonb,
  add column if not exists deleted_at timestamptz,
  add column if not exists change_seq bigint not null default nextval('public.deck_change_seq');

-- The phones allow 512 UTF-8 bytes for a name; the old 100-character check was never used.
alter table public.decks drop constraint if exists decks_name_check;
alter table public.decks add constraint decks_name_check check (octet_length(name) between 1 and 512);

create index if not exists decks_owner_change_idx on public.decks(owner_id, change_seq);

-- Direct table access stays closed: the functions below are the only way in.
revoke all on table public.decks from authenticated;
revoke all on table public.deck_entries from authenticated;

-- A deck as the clients read it.
create or replace function public.mm_deck_view(p_row public.decks) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_row.id, 'name', p_row.name, 'revision', p_row.revision, 'changeSeq', p_row.change_seq,
    'updatedAt', to_char(p_row.updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'deleted', p_row.deleted_at is not null,
    'deck', case when p_row.deleted_at is null then p_row.body else null end)
$$;

-- The document's rules, the phones' OnDeviceDeckEditing.validateDraft: a name, a commander row or none, rows with a
-- nonempty name and section (each at most 2,000 bytes) and 1-2,000 copies, at most 2,000 cards, at most 1 MiB in all.
create or replace function public.mm_deck_check(p_name text, p_deck jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare
  v_rows jsonb;
  v_row jsonb;
  v_total integer := 0;
begin
  if p_name is null or octet_length(p_name) not between 1 and 512 or btrim(p_name) = ''
     or p_deck is null or jsonb_typeof(p_deck) <> 'object' or octet_length(p_deck::text) > 1048576
     or jsonb_typeof(coalesce(p_deck->'entries', 'null')) <> 'array'
     or (p_deck ? 'commander' and jsonb_typeof(p_deck->'commander') not in ('object', 'null')) then
    raise exception 'invalid_deck' using errcode = '22023';
  end if;
  v_rows := p_deck->'entries';
  if jsonb_typeof(p_deck->'commander') = 'object' then v_rows := jsonb_build_array(p_deck->'commander') || v_rows; end if;
  for v_row in select value from jsonb_array_elements(v_rows) loop
    if jsonb_typeof(v_row) <> 'object' or jsonb_typeof(v_row->'cardName') <> 'string' or jsonb_typeof(v_row->'section') <> 'string'
       or jsonb_typeof(v_row->'quantity') <> 'number'
       or btrim(v_row->>'cardName') = '' or octet_length(v_row->>'cardName') > 2000
       or btrim(v_row->>'section') = '' or octet_length(v_row->>'section') > 2000
       or (v_row->>'quantity') !~ '^[0-9]+$' or (v_row->>'quantity')::integer not between 1 and 2000 then
      raise exception 'invalid_deck' using errcode = '22023';
    end if;
    v_total := v_total + (v_row->>'quantity')::integer;
    if v_total > 2000 then raise exception 'invalid_deck' using errcode = '22023'; end if;
  end loop;
end $$;

-- Every change since a cursor (0 for everything), oldest first, at most 200 at a time; `more` says to ask again with
-- the returned cursor.
create or replace function public.mm_decks_since(p_cursor bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_user();
  v_rows jsonb;
  v_last bigint;
  v_count integer;
begin
  with changed as (
    select d.* from public.decks d
     where d.owner_id = v_uid and d.change_seq > coalesce(p_cursor, 0)
     order by d.change_seq limit 200)
  select coalesce(jsonb_agg(public.mm_deck_view(c) order by c.change_seq), '[]'::jsonb), max(c.change_seq), count(*)
    into v_rows, v_last, v_count from changed c;
  return jsonb_build_object('decks', v_rows, 'cursor', coalesce(v_last, coalesce(p_cursor, 0)), 'more', v_count = 200);
end $$;

-- Saves a deck: a new id when `p_base` is null, else an update of the revision it was based on. A stale base, or a
-- deck deleted meanwhile, answers `conflict` with the server's copy instead.
create or replace function public.mm_deck_save(p_id uuid, p_name text, p_deck jsonb, p_base bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_user();
  v_row public.decks;
  v_source text := lower(coalesce(p_deck #>> '{source,kind}', 'manual'));
begin
  if p_id is null then raise exception 'invalid_deck' using errcode = '22023'; end if;
  perform public.mm_deck_check(p_name, p_deck);
  if v_source not in ('manual', 'paste', 'file', 'archidekt', 'moxfield') then v_source := 'manual'; end if;
  select * into v_row from public.decks where id = p_id for update;
  if found and v_row.owner_id <> v_uid then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not found then
    if p_base is not null then raise exception 'not_found' using errcode = 'P0002'; end if;
    if (select count(*) from public.decks where owner_id = v_uid and deleted_at is null) >= 1000 then
      raise exception 'too_many_decks' using errcode = '54000';
    end if;
    insert into public.decks (id, owner_id, name, commander_name, body, source_kind, source_url)
    values (p_id, v_uid, p_name, left(p_deck #>> '{commander,cardName}', 200), p_deck, v_source, left(p_deck #>> '{source,url}', 2000))
    returning * into v_row;
    return jsonb_build_object('status', 'saved', 'deck', public.mm_deck_view(v_row));
  end if;
  if v_row.deleted_at is not null or p_base is null or v_row.revision <> p_base then
    return jsonb_build_object('status', 'conflict', 'deck', public.mm_deck_view(v_row));
  end if;
  update public.decks set name = p_name, commander_name = left(p_deck #>> '{commander,cardName}', 200), body = p_deck,
         source_kind = v_source, source_url = left(p_deck #>> '{source,url}', 2000), revision = revision + 1,
         updated_at = now(), change_seq = nextval('public.deck_change_seq')
   where id = p_id returning * into v_row;
  return jsonb_build_object('status', 'saved', 'deck', public.mm_deck_view(v_row));
end $$;

-- Deletes a deck everywhere: a tombstone that keeps the id. A stale base answers `conflict` with the server's copy
-- (someone changed it meanwhile: it stays). Deleting what is already gone is fine.
create or replace function public.mm_deck_delete(p_id uuid, p_base bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_user();
  v_row public.decks;
begin
  select * into v_row from public.decks where id = p_id and owner_id = v_uid for update;
  if not found then return jsonb_build_object('status', 'deleted'); end if;
  if v_row.deleted_at is not null then return jsonb_build_object('status', 'deleted', 'deck', public.mm_deck_view(v_row)); end if;
  if p_base is null or v_row.revision <> p_base then
    return jsonb_build_object('status', 'conflict', 'deck', public.mm_deck_view(v_row));
  end if;
  update public.decks set deleted_at = now(), body = '{}'::jsonb, revision = revision + 1, updated_at = now(),
         change_seq = nextval('public.deck_change_seq')
   where id = p_id returning * into v_row;
  return jsonb_build_object('status', 'deleted', 'deck', public.mm_deck_view(v_row));
end $$;

do $$
declare f text;
begin
  foreach f in array array['mm_decks_since(bigint)', 'mm_deck_save(uuid, text, jsonb, bigint)', 'mm_deck_delete(uuid, bigint)',
                           'mm_deck_view(public.decks)', 'mm_deck_check(text, jsonb)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
  end loop;
  -- Internal helpers.
  revoke all on function public.mm_deck_view(public.decks) from authenticated;
  revoke all on function public.mm_deck_check(text, jsonb) from authenticated;
  foreach f in array array['mm_decks_since(bigint)', 'mm_deck_save(uuid, text, jsonb, bigint)', 'mm_deck_delete(uuid, bigint)']
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
