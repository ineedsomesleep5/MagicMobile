import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';

// The feedback migration on a minimal Supabase stand-in: auth.users, auth.uid(), and the three API roles.
// No production rows, keys or tokens. Nothing touches the live project.
const db = new PGlite();
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role;
    create schema auth;
    create table auth.users(id uuid primary key, aud text, role text, email text);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth, public to anon, authenticated, service_role;
  `);
  await db.exec(await readFile(new URL('../migrations/20261117180000_feedback.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('./feedback.sql', import.meta.url), 'utf8'));
  console.log('PASS PGlite: feedback is insert-only through mm_send_feedback (signed in, 4000 characters, 5 an hour, no client read)');
  console.log('PASS PGlite: mm_feedback_summary is service_role only and returns counts by kind, platform and version plus recent notes');
  console.log('Scope: single-process PostgreSQL; auth.uid is a test stub; no live writes.');
} catch (error) {
  console.error('FAIL', error.message, error.detail ?? '', error.where ?? '', error.hint ?? '', error.position ?? '');
  process.exitCode = 1;
} finally {
  await db.close();
}
