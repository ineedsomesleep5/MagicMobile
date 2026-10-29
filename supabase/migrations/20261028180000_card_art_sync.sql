-- Your own card pictures on every phone and browser signed in to the same profile (Caleb, 2026-10-28: "make sure it
-- syncs across accounts across platforms"; docs/CARD_ART_SYNC.md). Only the owner ever reads a picture: opponents still
-- see the card's usual art.
--
-- A picture is a JPEG in the private `custom-card-art` bucket at `<user id>/<sha-256 of its bytes>.jpg`, so a changed
-- picture is a new file and no device keeps a stale copy. `card_art` says which picture each card wears (by card key,
-- the front face's name in lower case), with a tombstone (picture null) for a removed one and a change sequence for
-- pulling.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('custom-card-art', 'custom-card-art', false, 2097152, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];

-- Each player reads and writes only their own folder.
drop policy if exists "card art: own folder read" on storage.objects;
drop policy if exists "card art: own folder insert" on storage.objects;
drop policy if exists "card art: own folder update" on storage.objects;
drop policy if exists "card art: own folder delete" on storage.objects;
create policy "card art: own folder read" on storage.objects for select to authenticated
  using (bucket_id = 'custom-card-art' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "card art: own folder insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'custom-card-art' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "card art: own folder update" on storage.objects for update to authenticated
  using (bucket_id = 'custom-card-art' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'custom-card-art' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "card art: own folder delete" on storage.objects for delete to authenticated
  using (bucket_id = 'custom-card-art' and (storage.foldername(name))[1] = (select auth.uid())::text);

create sequence if not exists public.card_art_change_seq;

create table if not exists public.card_art (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_key text not null check (card_key = lower(btrim(card_key)) and octet_length(card_key) between 1 and 300),
  picture text check (picture ~ '^[0-9a-f]{64}$'),
  change_seq bigint not null default nextval('public.card_art_change_seq'),
  updated_at timestamptz not null default now(),
  primary key (user_id, card_key)
);
create index if not exists card_art_user_change_idx on public.card_art(user_id, change_seq);
alter table public.card_art enable row level security;
revoke all on table public.card_art from anon, authenticated;

-- {arts: [{cardKey, picture (null when removed), changeSeq}], cursor, more}: every change after `cursor`, oldest first,
-- at most 200; ask again while `more`.
create or replace function public.mm_card_art_since(p_cursor bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_user();
  v_rows jsonb;
  v_last bigint;
  v_count integer;
begin
  with changed as (
    select a.* from public.card_art a
     where a.user_id = v_uid and a.change_seq > coalesce(p_cursor, 0)
     order by a.change_seq limit 200)
  select coalesce(jsonb_agg(jsonb_build_object('cardKey', c.card_key, 'picture', c.picture, 'changeSeq', c.change_seq)
                            order by c.change_seq), '[]'::jsonb), max(c.change_seq), count(*)
    into v_rows, v_last, v_count from changed c;
  return jsonb_build_object('arts', v_rows, 'cursor', coalesce(v_last, coalesce(p_cursor, 0)), 'more', v_count = 200);
end $$;

-- The card now wears `p_picture` (already uploaded to the caller's folder), or nothing when it is null.
-- Errors: invalid_card_art, picture_missing (not uploaded), too_many_pictures (500 cards with a picture).
create or replace function public.mm_card_art_set(p_card_key text, p_picture text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := public.mm_require_user();
  v_row public.card_art;
begin
  if p_card_key is null or p_card_key <> lower(btrim(p_card_key)) or octet_length(p_card_key) not between 1 and 300
     or (p_picture is not null and p_picture !~ '^[0-9a-f]{64}$') then
    raise exception 'invalid_card_art' using errcode = '22023';
  end if;
  if p_picture is not null then
    if not exists (select 1 from storage.objects o
                    where o.bucket_id = 'custom-card-art' and o.name = v_uid::text || '/' || p_picture || '.jpg') then
      raise exception 'picture_missing' using errcode = 'P0002';
    end if;
    if (select count(*) from public.card_art where user_id = v_uid and picture is not null and card_key <> p_card_key) >= 500 then
      raise exception 'too_many_pictures' using errcode = '54000';
    end if;
  end if;
  insert into public.card_art (user_id, card_key, picture) values (v_uid, p_card_key, p_picture)
  on conflict (user_id, card_key) do update
     set picture = excluded.picture, change_seq = nextval('public.card_art_change_seq'), updated_at = now()
  returning * into v_row;
  return jsonb_build_object('cardKey', v_row.card_key, 'picture', v_row.picture, 'changeSeq', v_row.change_seq);
end $$;

revoke all on function public.mm_card_art_since(bigint) from public, anon;
revoke all on function public.mm_card_art_set(text, text) from public, anon;
grant execute on function public.mm_card_art_since(bigint) to authenticated;
grant execute on function public.mm_card_art_set(text, text) to authenticated;
