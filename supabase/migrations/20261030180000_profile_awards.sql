-- Awards (Caleb, 2026-10-30: "add badges and stuff without an update ... I got Mythic in ranked, I'm the first"): medals
-- on a player's profile that live on the server. An award is a row, its art a URL, so a new one needs no app build. A
-- `rule` hands it out by itself when a player's ranked standing moves; without one it is given by hand (mm_award_give).
-- An award with a `title` also sets the player's title, which every app already shows. docs/SERVER_CONTROLS.md.

create table public.awards (
  id text primary key check (id ~ '^[a-z0-9-]{2,40}$'),
  name text not null check (char_length(name) between 1 and 40),
  description text not null check (char_length(description) between 1 and 160),
  image_url text check (image_url is null or image_url like 'https://%'),
  tint text not null default '#FFCC5C' check (tint ~ '^#[0-9A-Fa-f]{6}$'),
  -- 1 plain, 2 a soft glow, 3 a strong glow and a gold ring.
  rarity smallint not null default 1 check (rarity between 1 and 3),
  title text check (char_length(title) between 1 and 40),
  -- {"kind": "peak_step", "step": 20}, {"kind": "season_wins", "count": 100} or {"kind": "win_streak", "count": 10};
  -- "first": n stops it after n players. Null: given by hand.
  rule jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.player_awards (
  user_id uuid not null references public.profiles (id) on delete cascade,
  award_id text not null references public.awards (id) on update cascade on delete cascade,
  note text check (char_length(note) <= 80),
  awarded_at timestamptz not null default now(),
  -- When the player's app showed it; until then it opens with a ceremony.
  seen_at timestamptz,
  primary key (user_id, award_id)
);

alter table public.awards enable row level security;
alter table public.player_awards enable row level security;
revoke all on public.awards, public.player_awards from public, anon, authenticated;

-- An award as the apps read it.
create or replace function public.mm_award_row(a public.awards, p public.player_awards) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', a.id, 'name', a.name, 'description', a.description, 'imageUrl', a.image_url, 'tint', a.tint,
                            'rarity', a.rarity, 'note', p.note, 'awardedAt', p.awarded_at) $$;

-- Gives an award once. Re-saving the ranked card lets its trigger take the award's title.
create or replace function public.mm_award_insert(p_user uuid, p_award text, p_note text default null, p_at timestamptz default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_added integer;
begin
  insert into public.player_awards (user_id, award_id, note, awarded_at)
  values (p_user, p_award, left(p_note, 80), coalesce(p_at, now())) on conflict do nothing;
  get diagnostics v_added = row_count;
  if v_added > 0 then update public.ranked_profiles set title = title where user_id = p_user; end if;
  return v_added > 0;
end $$;

-- Gives the awards whose rule the player now meets. p_only limits it to one award; p_at backdates it.
create or replace function public.mm_awards_check(p_user uuid, p_only text default null, p_at timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.ranked_standings%rowtype;
  a public.awards%rowtype;
  v_peak integer;
  v_first integer;
  v_met boolean;
begin
  select * into s from public.ranked_standings where user_id = p_user;
  if not found then return; end if;
  select greatest(s.peak_points, coalesce(max(h.peak_points), 0)) into v_peak
    from public.ranked_season_history h where h.user_id = p_user;
  for a in select w.* from public.awards w
            where w.active and w.rule is not null and (p_only is null or w.id = p_only)
              and not exists (select 1 from public.player_awards p where p.user_id = p_user and p.award_id = w.id)
  loop
    v_met := case a.rule ->> 'kind'
      when 'peak_step' then public.mm_rank_points_step(v_peak) >= (a.rule ->> 'step')::integer
      when 'season_wins' then s.wins >= (a.rule ->> 'count')::integer
      when 'win_streak' then s.win_streak >= (a.rule ->> 'count')::integer
      else false end;
    if not v_met then continue; end if;
    v_first := (a.rule ->> 'first')::integer;
    if v_first is not null then
      -- Two players finishing together can't both be first.
      perform pg_advisory_xact_lock(hashtext('award:' || a.id));
      if (select count(*) from public.player_awards p where p.award_id = a.id) >= v_first then continue; end if;
    end if;
    perform public.mm_award_insert(p_user, a.id, null, p_at);
  end loop;
end $$;

-- Hands out a new rule's award to whoever already earned it, in the order they did.
create or replace function public.mm_awards_backfill(p_award text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_rule jsonb;
  v_points integer;
  v_row record;
  v_before integer;
begin
  select rule into v_rule from public.awards where id = p_award;
  if v_rule is null then raise exception 'award has no rule'; end if;
  select count(*) into v_before from public.player_awards where award_id = p_award;
  v_points := case when v_rule ->> 'kind' = 'peak_step' then (v_rule ->> 'step')::integer * 4 end;
  for v_row in
    select s.user_id, f.reached_at
      from public.ranked_standings s
      left join lateral (select min(r.created_at) as reached_at from public.ranked_results r
                          where r.user_id = s.user_id and r.points_after >= v_points) f on true
     order by f.reached_at nulls last, s.updated_at
  loop
    perform public.mm_awards_check(v_row.user_id, p_award, v_row.reached_at);
  end loop;
  return (select count(*) from public.player_awards where award_id = p_award) - v_before;
end $$;

-- A ranked result must land whatever an award does.
create or replace function public.mm_awards_on_standing() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    perform public.mm_awards_check(new.user_id);
  exception when others then
    raise warning 'award check failed: %', sqlerrm;
  end;
  return null;
end $$;

create trigger ranked_standings_awards after update on public.ranked_standings for each row
  when (new.peak_points > old.peak_points or new.wins > old.wins or new.win_streak > old.win_streak)
  execute function public.mm_awards_on_standing();

-- An award's title outranks the one the app sends, so leaderboards, friends and old apps show it too.
create or replace function public.mm_awards_title() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_title text;
begin
  select a.title into v_title
    from public.player_awards p join public.awards a on a.id = p.award_id
   where p.user_id = new.user_id and a.active and a.title is not null
   order by a.rarity desc, p.awarded_at limit 1;
  if v_title is not null then new.title := v_title; end if;
  return new;
end $$;

create trigger ranked_profiles_award_title before insert or update on public.ranked_profiles for each row
  execute function public.mm_awards_title();

-- The caller's awards, best first; `seen` is false until mm_awards_seen.
create or replace function public.mm_my_awards() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.mm_award_row(a, p) || jsonb_build_object('seen', p.seen_at is not null)
                            order by a.rarity desc, p.awarded_at), '[]'::jsonb)
    from public.player_awards p join public.awards a on a.id = p.award_id
   where p.user_id = public.mm_require_profile() and a.active $$;

create or replace function public.mm_awards_seen(p_ids text[]) returns void
language sql security definer set search_path = '' as $$
  update public.player_awards set seen_at = now()
   where user_id = public.mm_require_profile() and award_id = any (p_ids) and seen_at is null $$;

-- By hand, from the SQL editor.
create or replace function public.mm_award_give(p_username text, p_award text, p_note text default null) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid;
begin
  select id into v_user from public.profiles where lower(username) = lower(p_username);
  if v_user is null then raise exception 'no player named %', p_username; end if;
  return public.mm_award_insert(v_user, p_award, p_note);
end $$;

-- A public profile lists them.
do $$
declare
  v_def text := pg_get_functiondef('public.mm_public_profile(text)'::regprocedure);
  v_old text := '''title'', r.title, ''favoriteCommander'', r.favorite_commander,';
begin
  if position(v_old in v_def) = 0 then raise exception 'mm_public_profile changed; update this migration'; end if;
  execute replace(v_def, v_old,
    '''awards'', (select coalesce(jsonb_agg(public.mm_award_row(a, w) order by a.rarity desc, w.awarded_at), ''[]''::jsonb)
                   from public.player_awards w join public.awards a on a.id = w.award_id
                  where w.user_id = v_target and a.active),
      ' || v_old);
end $$;

revoke all on function public.mm_award_row(public.awards, public.player_awards) from public, anon, authenticated;
revoke all on function public.mm_award_insert(uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.mm_awards_check(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.mm_awards_backfill(text) from public, anon, authenticated;
revoke all on function public.mm_awards_on_standing() from public, anon, authenticated;
revoke all on function public.mm_awards_title() from public, anon, authenticated;
revoke all on function public.mm_award_give(text, text, text) from public, anon, authenticated;
revoke all on function public.mm_my_awards() from public, anon;
revoke all on function public.mm_awards_seen(text[]) from public, anon;
grant execute on function public.mm_my_awards() to authenticated;
grant execute on function public.mm_awards_seen(text[]) to authenticated;

insert into public.awards (id, name, description, tint, rarity, title, rule) values
  ('first-mythic', 'First to Mythic', 'The first player ever to reach Mythic.', '#FF7338', 3, 'First to Mythic', '{"kind": "peak_step", "step": 20, "first": 1}'),
  ('first-diamond', 'First to Diamond', 'The first player ever to reach Diamond.', '#80BFFF', 3, 'First to Diamond', '{"kind": "peak_step", "step": 16, "first": 1}'),
  ('season-1-champion', 'Season 1 Champion', 'Finished first in Season 1, October 2026.', '#FFCC5C', 3, 'Season 1 Champion', null),
  ('mythic', 'Mythic', 'Reached Mythic, the top of the ladder.', '#FF7338', 2, null, '{"kind": "peak_step", "step": 20}'),
  ('centurion', 'Centurion', 'Won 100 ranked games in one season.', '#FFCC5C', 2, null, '{"kind": "season_wins", "count": 100}'),
  ('unstoppable', 'Unstoppable', 'Won 10 ranked games in a row.', '#C2D4E0', 1, null, '{"kind": "win_streak", "count": 10}');

select public.mm_awards_backfill(id) from public.awards where rule is not null;
