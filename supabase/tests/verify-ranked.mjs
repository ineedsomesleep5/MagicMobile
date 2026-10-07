import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';

// The social, ranked, friend-challenge and public-profile migrations on a minimal Supabase stand-in: auth.users, auth.uid() and the
// original profiles table. No production rows, keys or tokens; nothing touches the live project.
const db = new PGlite();
const migration = name => readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8');
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create table auth.users(id uuid primary key,aud text,role text,email text);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema auth to authenticated;
    create table public.profiles (
      id uuid primary key references auth.users(id) on delete cascade,
      display_name text not null check (char_length(display_name) between 1 and 50),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now());
    alter table public.profiles enable row level security;
  `);
  await db.exec(await migration('20260928120000_social_profiles_friends.sql'));
  await db.exec(await migration('20261004120000_ranked_ladder.sql'));
  await db.exec(await migration('20261004180000_friend_challenges.sql'));
  await db.exec(await migration('20261007120000_public_profiles.sql'));
  await db.exec(await readFile(new URL('./ranked_ladder.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('./friend_challenges.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('./public_profiles.sql', import.meta.url), 'utf8'));
  console.log('PASS PGlite: ranked queue pairing (rank, bracket, protocol, blocks), host/guest table hand-off, late cancel, reports');
  console.log('PASS PGlite: ranked cards for friends and profile cards, blocked players hidden, no direct table access, account deletion');
  console.log('PASS PGlite: friend challenges (friends only, same-tier ranked with season rollover, replace, accept/decline/expiry, ranked reports, blocks, no direct access)');
  console.log('PASS PGlite: public profiles (visibility public/friends/private, blocks, live prefix search with limits and index, recorded games with caps and rate limit, rank history and opponent names, no direct access, anon refused)');
  console.log('Scope: single-process PostgreSQL; auth.uid is a test stub; no live writes, no concurrent-session proof.');
} catch (error) {
  console.error('FAIL', error.message, error.detail ?? '', error.where ?? '', error.hint ?? '', error.position ?? '', error.routine ?? '');
  process.exitCode = 1;
} finally {
  await db.close();
}
