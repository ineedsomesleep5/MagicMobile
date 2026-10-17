import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

// The social, ranked, friend-challenge, public-profile, ranked-referee and ranked-record-points migrations on a minimal Supabase stand-in: auth.users, auth.uid() and the
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
  // The referee replaces mm_ranked_report/publish, so the tests above run against the functions they were written for.
  await db.exec(await readFile(new URL('./ranked_referee_before.sql', import.meta.url), 'utf8'));
  await db.exec(await migration('20261015120000_ranked_referee.sql'));
  await db.exec(await readFile(new URL('./ranked_referee.sql', import.meta.url), 'utf8'));
  await db.exec(await migration('20261015180000_ranked_record_points.sql'));
  await db.exec(await readFile(new URL('./ranked_record_points.sql', import.meta.url), 'utf8'));
  // Ladder option B (Caleb's choice, 2026-10-15) replaces mm_ranked_apply: the referee suite above ran on the old steps.
  await db.exec(await migration('20261015200000_ladder_option_b.sql'));
  await db.exec(await readFile(new URL('./ladder_option_b.sql', import.meta.url), 'utf8'));
  // Game records (Phase 5): built here with node's own SHA-256, so the SQL hash chain is checked against an independent
  // implementation of GameRecord.head (docs/cloud/game-record.md).
  await db.exec(await migration('20261016120000_ranked_ai_records.sql'));
  await db.exec('create table public.test_records(name text primary key, record jsonb not null); grant select on public.test_records to authenticated');
  for (const [name, record] of Object.entries(gameRecords())) {
    await db.query('insert into public.test_records values ($1, $2)', [name, JSON.stringify(record)]);
  }
  await db.exec(await readFile(new URL('./ranked_ai_records.sql', import.meta.url), 'utf8'));
  await db.exec(await migration('20261016180000_ranked_leaderboard.sql'));
  await db.exec(await readFile(new URL('./ranked_leaderboard.sql', import.meta.url), 'utf8'));
  await db.exec(await migration('20261017180000_friend_messages.sql'));
  await db.exec(await readFile(new URL('./friend_messages.sql', import.meta.url), 'utf8'));
  console.log('PASS PGlite: ranked queue pairing (rank, bracket, protocol, blocks), host/guest table hand-off, late cancel, reports');
  console.log('PASS PGlite: ranked cards for friends and profile cards, blocked players hidden, no direct table access, account deletion');
  console.log('PASS PGlite: friend challenges (friends only, same-tier ranked with season rollover, replace, accept/decline/expiry, ranked reports, blocks, no direct access)');
  console.log('PASS PGlite: public profiles (visibility public/friends/private, blocks, live prefix search with limits and index, recorded games with caps and rate limit, rank history and opponent names, no direct access, anon refused)');
  console.log('PASS PGlite: ranked referee (published standings carried over, one capped seed, agreeing reports count, disputes and capped pairs do not, lone reports time out, AI tickets with minimum time, daily cap and abandonment, streak and underdog bonuses, season rollover, publish keeps only cosmetics, no direct access, account deletion)');
  console.log('PASS PGlite: ranked record points (server points stored for ranked games, phone claims ignored, none before a seed, for quick/casual games or an earlier month, rollover first, imported standings, re-sends unchanged, public rank history, anon refused)');
  console.log('PASS PGlite: ladder option B (Arena steps per tier, Bronze losses free, tier floors with Mythic falling to Diamond, no streak bonus, underdog kept, card mirrored, still internal)');
  console.log('PASS PGlite: ranked AI records (seeded tickets with the tier skill, a valid record counts, tampered/reseeded/unknown-build/easier-AI/wrong-winner/conceded/short/too-fast/missing records settle unverified, losses need none, older tickets unchanged, records kept, no direct access, anon refused)');
  console.log('PASS PGlite: ranked leaderboard (server standings order, current season with games only, public/friends-only/private and blocks respected both ways, friends scope, online flags, own row kept past the limit, limit cap, bad scope, anon refused)');
  console.log('PASS PGlite: friend messages (friends only, trimmed 1-500 chars, unread and read state, conversations newest first, pages, 20/minute limit, message reports, blocks hide both ways, no direct access, helpers internal, anon refused, account deletion)');
  console.log('Scope: single-process PostgreSQL; auth.uid is a test stub; no live writes, no concurrent-session proof.');
} catch (error) {
  console.error('FAIL', error.message, error.detail ?? '', error.where ?? '', error.hint ?? '', error.position ?? '', error.routine ?? '');
  process.exitCode = 1;
} finally {
  await db.close();
}

// GameRecord.head: h0 = H(setup), hi = H(hi-1 ‖ "\n" ‖ entry), head = H(hn ‖ "\n" ‖ end).
function head(setup, entries, end) {
  const sha = data => createHash('sha256').update(data).digest();
  let h = sha(Buffer.from(setup, 'utf8'));
  for (const entry of [...entries, end]) h = sha(Buffer.concat([h, Buffer.from('\n' + entry, 'utf8')]));
  return h.toString('hex');
}

// A human (seat 0) beats a skill-1 AI (seat 1) on turn 6, on the test engine build and seed. Variants change one thing.
function gameRecords() {
  const build = 'sha256:' + 'ab'.repeat(32);
  const record = ({ seed = '-4123456789012345678', engineBuild = build, ai = { aiSkill: 1, aiSearchDepth: 2, aiMistakePercent: 15 },
                    winners = ['me'], turn = 6, extra = [] } = {}) => {
    const setup = JSON.stringify({ engine: { protocol: 1, upstream: 'dac400b', catalogueHash: 'c', engineBuild }, seed,
      players: ['u0', 'u1'], seats: [{ seatId: 'me', name: 'Me', controller: 'human', deck: { commander: 'x' } },
                                     { seatId: 'ai1', name: 'AI', controller: 'ai', deck: { commander: 'y' }, ...ai }] });
    const entries = [];
    const marks = [];
    for (let t = 1; t <= turn; t++) {
      marks.push(`${t} ${entries.length} ${(0x1000 + t).toString(16).padStart(8, '0')}`);
      entries.push(t % 2 ? '0h b0' : '1Q 0', '1A Forest/0 P', '1Q 1', '0h u' + t);
    }
    entries.push(...extra);
    const end = JSON.stringify({ state: 'ended', turn, winners, entries: entries.length, digest: '1a4f4c0a', engineErrors: 0,
      seats: [{ seatId: 'me', life: 31, lost: false, left: false }, { seatId: 'ai1', life: 0, lost: true, left: false }] });
    return { format: 'magicmobile-game-record', version: 1, setup, entries, marks, end, head: head(setup, entries, end) };
  };
  const valid = record();
  return {
    valid,
    tampered: { ...valid, entries: valid.entries.map((e, i) => (i === 3 ? '0h u9' : e)) },
    reseeded: record({ seed: '42' }),
    unknown_build: record({ engineBuild: 'sha256:' + 'cd'.repeat(32) }),
    easier_ai: record({ ai: { aiSkill: 1, aiSearchDepth: 2, aiMistakePercent: 50 } }),
    wrong_winner: record({ winners: ['ai1'] }),
    ai_conceded: record({ extra: ['1c 0'] }),
    short: record({ turn: 2 }),
    long: record({ turn: 60 }),
    broken: { ...valid, broken: 'unsupported value' },
    skill_two: record({ ai: { aiSkill: 2, aiSearchDepth: 3, aiMistakePercent: 15 } }),
  };
}
