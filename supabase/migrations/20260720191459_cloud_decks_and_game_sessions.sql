create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 50),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.decks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  format text not null default 'commander' check (format = 'commander'),
  commander_name text,
  raw_list text not null default '',
  source_kind text not null default 'manual'
    check (source_kind in ('manual', 'paste', 'file', 'archidekt', 'moxfield')),
  source_url text,
  source_filename text,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, owner_id)
);

create index decks_owner_updated_idx on public.decks(owner_id, updated_at desc);

create table public.deck_entries (
  id uuid primary key default gen_random_uuid(),
  deck_id uuid not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  card_name text not null check (char_length(card_name) between 1 and 200),
  quantity integer not null check (quantity between 1 and 1000),
  section text not null check (section in ('commander', 'deck', 'sideboard', 'maybeboard')),
  position integer not null check (position >= 0),
  foreign key (deck_id, owner_id) references public.decks(id, owner_id) on delete cascade,
  unique (deck_id, section, position)
);

create index deck_entries_deck_position_idx
  on public.deck_entries(deck_id, section, position);

create table public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null,
  status text not null default 'starting'
    check (status in ('starting', 'active', 'complete', 'failed')),
  revision bigint not null default 1 check (revision > 0),
  snapshot jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, game_id)
);

create index game_sessions_owner_updated_idx
  on public.game_sessions(owner_id, updated_at desc);

alter table public.profiles enable row level security;
alter table public.decks enable row level security;
alter table public.deck_entries enable row level security;
alter table public.game_sessions enable row level security;

revoke all on table public.profiles from anon;
revoke all on table public.decks from anon;
revoke all on table public.deck_entries from anon;
revoke all on table public.game_sessions from anon;

create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "decks_select_own" on public.decks
  for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy "decks_insert_own" on public.decks
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy "decks_update_own" on public.decks
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy "decks_delete_own" on public.decks
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

create policy "deck_entries_select_own" on public.deck_entries
  for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy "deck_entries_insert_own" on public.deck_entries
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy "deck_entries_update_own" on public.deck_entries
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy "deck_entries_delete_own" on public.deck_entries
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

create policy "game_sessions_select_own" on public.game_sessions
  for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy "game_sessions_insert_own" on public.game_sessions
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy "game_sessions_update_own" on public.game_sessions
  for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy "game_sessions_delete_own" on public.game_sessions
  for delete to authenticated
  using ((select auth.uid()) = owner_id);

grant usage on schema public to authenticated;
grant select, insert, update on table public.profiles to authenticated;
grant select, insert, update, delete on table public.decks to authenticated;
grant select, insert, update, delete on table public.deck_entries to authenticated;
grant select, insert, update, delete on table public.game_sessions to authenticated;

create function public.update_owned_deck(
  p_deck_id uuid,
  p_expected_revision bigint,
  p_name text,
  p_commander_name text,
  p_raw_list text,
  p_source_kind text,
  p_source_url text,
  p_source_filename text,
  p_entries jsonb
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  next_revision bigint;
begin
  update public.decks
  set name = p_name,
      commander_name = p_commander_name,
      raw_list = p_raw_list,
      source_kind = p_source_kind,
      source_url = p_source_url,
      source_filename = p_source_filename,
      revision = revision + 1,
      updated_at = now()
  where id = p_deck_id
    and owner_id = (select auth.uid())
    and revision = p_expected_revision
  returning revision into next_revision;

  if next_revision is null then
    raise exception 'deck_revision_conflict' using errcode = 'P0001';
  end if;

  delete from public.deck_entries
  where deck_id = p_deck_id
    and owner_id = (select auth.uid());

  insert into public.deck_entries (deck_id, owner_id, card_name, quantity, section, position)
  select p_deck_id,
         (select auth.uid()),
         entry.value ->> 'cardName',
         (entry.value ->> 'quantity')::integer,
         entry.value ->> 'section',
         entry.position - 1
  from jsonb_array_elements(p_entries) with ordinality
    as entry(value, position);

  return next_revision;
end;
$$;

revoke all on function public.update_owned_deck(uuid, bigint, text, text, text, text, text, text, jsonb)
  from public, anon;
grant execute on function public.update_owned_deck(uuid, bigint, text, text, text, text, text, text, jsonb)
  to authenticated;
