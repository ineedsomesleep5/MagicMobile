-- Before the referee migration: a player who published Platinum IV with 2 pips (peak Platinum III, 7-3)
-- the old way, so the migration's carry-over can be checked. Kept (no rollback) for ranked_referee.sql.
insert into auth.users(id,aud,role,email) values
 ('d7000000-0000-0000-0000-000000000005','authenticated','authenticated','ref-five@example.invalid');
insert into public.profiles(id, display_name, username) values ('d7000000-0000-0000-0000-000000000005', 'RefFive', 'RefFive');
insert into public.ranked_profiles(user_id, season, rank_step, pips, peak_step, wins, losses)
values ('d7000000-0000-0000-0000-000000000005', to_char(now() at time zone 'utc', 'YYYY-MM'), 12, 2, 13, 7, 3);
