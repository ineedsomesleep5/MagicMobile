import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

// Isolated fake-process checks: no remote calls, real JVM, or production database.
const source = dirname(fileURLToPath(import.meta.url));
const root = mkdtempSync(join(tmpdir(), 'magicmobile-launcher-test-'));
let count = 0;
function fixture() {
  const dir = join(root, String(++count)); mkdirSync(dir);
  for (const name of ['launch.sh', 'server.properties', 'runtime.properties']) copyFileSync(join(source, name), join(dir, name));
  mkdirSync(join(dir, 'bin'));
  writeFileSync(join(dir, 'bin/java'), '#!/bin/bash\nif [[ "$1" == -version ]]; then echo \'openjdk version "17.0.16"\' >&2; else printf "%s\\n" "$@" > "$CAPTURE"; printf "%s\\n" "$MAGICMOBILE_BUILD_IDENTITY" "$MAX_MATCHES" "$PWD" >> "$CAPTURE"; fi\n', { mode: 0o755 });
  writeFileSync(join(dir, 'bin/curl'), '#!/bin/bash\nwhile [[ $# -gt 0 ]]; do if [[ "$1" == -o ]]; then cp "$FIXTURE_ARCHIVE" "$2"; exit; fi; shift; done\nexit 9\n', { mode: 0o755 });
  return dir;
}
function change(dir, from, to) { const p = join(dir, 'server.properties'); writeFileSync(p, readFileSync(p, 'utf8').replace(from, to)); }
function run(dir, extra = {}) { return spawnSync('bash', [join(dir, 'launch.sh')], { encoding: 'utf8', env: { ...process.env, JAVA_HOME: dir, PATH: `${dir}/bin:${process.env.PATH}`, CAPTURE: join(dir, 'captured'), ...extra } }); }
function ready(dir) { change(dir, 'DATABASE_MIGRATION_READY=false', 'DATABASE_MIGRATION_READY=true'); }

const gate = fixture(); assert.match(run(gate).stderr, /Setup pending/); assert(!existsSync(join(gate, '.runtime')));
const secret = fixture(); change(secret, 'sb_publishable_V_i-mPM26P8fNLlKAYu2xg_4p-lPHYu', 'service_role_not_allowed'); assert.match(run(secret).stderr, /publishable key only/);
const injection = fixture(); change(injection, 'PORT=8088', 'PORT=$(touch SHOULD_NOT_EXIST)'); assert.match(run(injection).stderr, /Invalid port/); assert(!existsSync(join(injection, 'SHOULD_NOT_EXIST')));
const java = fixture(); ready(java); writeFileSync(join(java, 'bin/java'), '#!/bin/bash\necho \'openjdk version "21.0.1"\' >&2\n', { mode: 0o755 }); assert.match(run(java).stderr, /Java 17 is required/);
const checksum = fixture(); ready(checksum); mkdirSync(join(checksum, '.runtime'));
const cacheName = readFileSync(join(checksum, 'runtime.properties'), 'utf8').match(/^DIRECTORY=(runtime-[\w.-]+)$/m)[1];
writeFileSync(join(checksum, `.runtime/${cacheName}.tar.gz`), 'corrupt'); assert.match(run(checksum).stderr, /checksum failed/); assert(!existsSync(join(checksum, 'captured')));

const download = fixture(); ready(download);
const payload = join(download, 'payload'); mkdirSync(payload);
copyFileSync(join(source, '../run.sh'), join(payload, 'run.sh'));
writeFileSync(join(payload, 'runtime-classpath.txt'), 'cp/000-server:cp/001-engine.jar\n');
const archive = join(download, 'fixture.tar.gz');
assert.equal(spawnSync('tar', ['-czf', archive, '-C', payload, '.']).status, 0);
const digest = createHash('sha256').update(readFileSync(archive)).digest('hex');
writeFileSync(join(download, 'runtime.properties'), `URL=https://github.com/ineedsomesleep5/MagicMobile/releases/download/test/fixture.tar.gz\nSHA256=${digest}\nDIRECTORY=runtime-fixture\n`);
const started = run(download, { FIXTURE_ARCHIVE: archive }); assert.equal(started.status, 0, started.stderr);
const args = readFileSync(join(download, 'captured'), 'utf8');
assert.match(args, /-Xmx1024m/); assert.match(args, /cp\/000-server:cp\/001-engine.jar/); assert.match(args, /"protocolVersion":1/); assert.match(args, /\n1\n/); assert.match(args, /\.runtime\/runtime-fixture/);
const cached = run(download); assert.equal(cached.status, 0, cached.stderr); // No archive env: download stub would fail if called.
const powershell = readFileSync(join(source, 'Launch-MagicMobile.ps1'), 'utf8');
assert(powershell.includes("[string]::Join(';',$ClasspathEntries)"));
assert(!/Set-ExecutionPolicy|New-NetFirewallRule|Register-ScheduledTask/.test(powershell));
console.log('PASS: 7 isolated shell launcher regressions; Windows classpath/security source checks (not Windows execution).');
