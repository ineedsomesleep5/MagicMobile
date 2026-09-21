import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';

const metadata = JSON.parse(await readFile(new URL('./matchmaking-schema-metadata.json', import.meta.url), 'utf8'));
const db = new PGlite();
const quote = value => '"' + value.replaceAll('"', '""') + '"';
const full = item => `${quote(item.schema)}.${quote(item.name)}`;
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role;
    create schema auth;
    create schema realtime;
    create schema matchmaking_private;
    create table auth.users(id uuid primary key,aud text,role text,email text);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create function realtime.send(jsonb,text,text,boolean) returns void language plpgsql as $$ begin return; end $$;
    create function realtime.topic() returns text language sql stable as $$ select ''::text $$;
    grant usage on schema auth,matchmaking_private to authenticated;
    set check_function_bodies=off;
  `);
  for (const table of metadata.tables) {
    const columns = table.columns.map(c => `${quote(c.name)} ${c.type}${c.default ? ' default ' + c.default : ''}${c.required ? ' not null' : ''}`);
    await db.exec(`create table ${full(table)} (${columns.join(',')});`);
  }
  // Primary/unique keys must exist before any foreign key is restored.
  for (const foreign of [false, true]) for (const table of metadata.tables) {
    for (const constraint of table.constraints ?? []) {
      if (constraint.definition.startsWith('FOREIGN KEY') !== foreign) continue;
      await db.exec(`alter table ${full(table)} add constraint ${quote(constraint.name)} ${constraint.definition};`);
    }
  }
  for (const table of metadata.tables) for (const index of table.indexes ?? []) {
    await db.exec(index.replace('CREATE UNIQUE INDEX ', 'CREATE UNIQUE INDEX IF NOT EXISTS ').replace('CREATE INDEX ', 'CREATE INDEX IF NOT EXISTS '));
  }
  for (const fn of metadata.functions) await db.exec(fn.definition);
  for (const fn of metadata.functions) {
    const signature = `${full(fn)}(${fn.arguments})`;
    await db.exec(`revoke all on function ${signature} from public,anon,authenticated;`);
    if ((fn.acl ?? []).some(acl => acl.startsWith('authenticated=X'))) await db.exec(`grant execute on function ${signature} to authenticated;`);
  }
  for (const table of metadata.tables) {
    if (table.rls) await db.exec(`alter table ${full(table)} enable row level security;`);
    if ((table.acl ?? []).some(acl => acl.startsWith('authenticated=r/'))) await db.exec(`grant select on ${full(table)} to authenticated;`);
  }
  for (const policy of metadata.policies ?? []) {
    await db.exec(`create policy ${quote(policy.policyname)} on ${quote(policy.schemaname)}.${quote(policy.tablename)} as ${policy.permissive} for ${policy.cmd} to ${policy.roles.map(quote).join(',')} ${policy.qual ? `using (${policy.qual})` : ''} ${policy.with_check ? `with check (${policy.with_check})` : ''};`);
  }
  await db.exec('set check_function_bodies=on;');
  await db.exec(await readFile(new URL('../migrations/20260920155409_atomic_expected_match_leave.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('./expected_match_leave.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('./exact_build_identity.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('./waiting_seat_reuse.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('./public_lobby_lifecycle.sql', import.meta.url), 'utf8'));
  console.log('PASS PGlite: authenticated public status/create/join/ready/start/nonhost-leave/status lifecycle');
  console.log('PASS PGlite: departed membership retained, replacement/rejoin works, duplicate active seat rejected');
  console.log('PASS PGlite: exact adapter join/queue rejection, compatible admission/matching, queue tenure reset');
  console.log('PASS PGlite: faithful deployed matchmaking definitions + local migration + rollback leave/ACL/lock coverage tests');
  console.log('Scope: PostgreSQL single-process execution; auth.uid and Realtime send are test stubs; no live writes, no concurrent-session proof.');
} catch (error) {
  console.error('FAIL', error.message, error.detail ?? '', error.where ?? '');
  process.exitCode = 1;
} finally {
  await db.close();
}
