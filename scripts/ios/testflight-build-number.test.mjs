import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const here = dirname(fileURLToPath(import.meta.url));
const buddy = "/usr/libexec/PlistBuddy";
function fixture(t, placeholders = true) {
  const root = mkdtempSync(join(tmpdir(), "mm-build-number-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const dir of ["scripts/ios", "apps/ios/MagicMobile", "release/testflight"]) mkdirSync(join(root, dir), { recursive: true });
  const script = join(root, "scripts/ios/testflight-build-number.mjs");
  copyFileSync(join(here, "testflight-build-number.mjs"), script);
  const info = join(root, "apps/ios/MagicMobile/Info.plist");
  const project = join(root, "apps/ios/project.yml");
  const ledger = join(root, "release/testflight/build-ledger.json");
  writeFileSync(project, 'name: Fixture\nsettings:\n  base:\n    MARKETING_VERSION: "0.1.0"\n    CURRENT_PROJECT_VERSION: "2026062902" # keep\ntargets:\n  App:\n    type: application\n');
  writeFileSync(info, '<?xml version="1.0"?><plist version="1.0"><dict></dict></plist>');
  const set = (key, value, add = false) => execFileSync(buddy, ["-c", `${add ? "Add" : "Set"} :${key} ${add ? "string " : ""}${value}`, info]);
  set("CFBundleShortVersionString", placeholders ? "$(MARKETING_VERSION)" : "0.1.0", true);
  set("CFBundleVersion", placeholders ? "$(CURRENT_PROJECT_VERSION)" : "2026062902", true);
  writeFileSync(ledger, JSON.stringify({ schemaVersion: 1, uploads: [] }));
  const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
  const prepare = () => {
    const result = run("prepare", "--date", "20260912");
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(readFileSync(ledger));
  };
  return { root, info, project, ledger, set, run, prepare };
}

for (const placeholders of [true, false]) {
  test(`prepare/record/next build with ${placeholders ? "placeholders" : "literals"}`, { skip: process.platform !== "darwin" }, t => {
    const f = fixture(t, placeholders);
    assert.equal(f.prepare().lastPreparedBuild, "2026091201");
    assert.equal(f.prepare().lastPreparedBuild, "2026091201");
    assert.match(readFileSync(f.project, "utf8"), /CURRENT_PROJECT_VERSION: "2026091201" # keep/);
    const log = join(f.root, "upload.log");
    writeFileSync(log, "Delivery UUID: 01234567-89ab-cdef-0123-456789abcdef\n");
    if (placeholders) f.set("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)");
    const recorded = f.run("record", "--upload-log", log, "--ipa", join(f.root, "app.ipa"));
    assert.equal(recorded.status, 0, recorded.stderr);
    const ledger = JSON.parse(readFileSync(f.ledger));
    assert.equal(ledger.marketingVersion, "0.1.0");
    assert.equal(ledger.uploads[0].build, "2026091201");
    assert.equal(ledger.uploads[0].marketingVersion, "0.1.0");
    assert.equal(f.prepare().lastPreparedBuild, "2026091202");
    assert.match(readFileSync(f.project, "utf8"), /CURRENT_PROJECT_VERSION: "2026091202"/);
  });
}

test("reuse prepared literal repairs stale YAML and placeholder marketing ledger", { skip: process.platform !== "darwin" }, t => {
  const f = fixture(t);
  f.set("CFBundleVersion", "2026091201");
  writeFileSync(f.ledger, JSON.stringify({ schemaVersion: 1, uploads: [], lastPreparedBuild: "2026091201", marketingVersion: "$(MARKETING_VERSION)" }));
  assert.equal(f.prepare().lastPreparedBuild, "2026091201");
  assert.equal(f.prepare().marketingVersion, "0.1.0");
  assert.match(readFileSync(f.project, "utf8"), /CURRENT_PROJECT_VERSION: "2026091201"/);
});

test("existing uploaded numbers and future prefixes are not reused", { skip: process.platform !== "darwin" }, t => {
  const f = fixture(t);
  writeFileSync(f.ledger, JSON.stringify({ schemaVersion: 1, uploads: [{ build: "2026091307" }], lastUploadedBuild: "2026091307" }));
  assert.equal(f.prepare().lastPreparedBuild, "2026091308");
});

test("configured floor starts a durable sequential TestFlight counter", { skip: process.platform !== "darwin" }, t => {
  const f = fixture(t);
  writeFileSync(f.ledger, JSON.stringify({
    schemaVersion: 1,
    uploads: [{ build: "2026091702" }],
    lastUploadedBuild: "2026091702",
    nextBuildFloor: "5000000000"
  }));
  assert.equal(f.prepare().lastPreparedBuild, "5000000000");
  const log = join(f.root, "upload.log");
  writeFileSync(log, "Delivery UUID: 01234567-89ab-cdef-0123-456789abcdef\n");
  assert.equal(f.run("record", "--upload-log", log, "--ipa", join(f.root, "app.ipa")).status, 0);
  assert.equal(f.prepare().lastPreparedBuild, "5000000001");
});

test("a directly installed build is not reused or mislabeled as uploaded", { skip: process.platform !== "darwin" }, t => {
  const f = fixture(t);
  const installed = f.prepare();
  installed.lastInstalledBuild = installed.lastPreparedBuild;
  writeFileSync(f.ledger, JSON.stringify(installed));
  const next = f.prepare();
  assert.equal(next.lastPreparedBuild, "2026091202");
  assert.equal(next.lastInstalledBuild, "2026091201");
  assert.equal(next.lastUploadedBuild, undefined);
  assert.deepEqual(next.uploads, []);
});

test("unknown references and ambiguous YAML fail before writes", { skip: process.platform !== "darwin" }, t => {
  const f = fixture(t);
  const original = readFileSync(f.project, "utf8");
  for (const [key, value, yaml] of [
    ["CFBundleVersion", "$(OTHER_BUILD)", original],
    ["CFBundleVersion", "${CURRENT_PROJECT_VERSION}", original],
    ["CFBundleVersion", "$(MARKETING_VERSION)", original],
    ["CFBundleShortVersionString", "$(OTHER_VERSION)", original],
    ["CFBundleVersion", "$(CURRENT_PROJECT_VERSION)", original + '    settings: {CURRENT_PROJECT_VERSION: "9999999999"}\n'],
    ["CFBundleVersion", "$(CURRENT_PROJECT_VERSION)", original + 'include: versions.yml\n'],
    ["CFBundleVersion", "$(CURRENT_PROJECT_VERSION)", original + '"configFiles": {Release: versions.xcconfig}\n'],
    ["CFBundleVersion", "$(CURRENT_PROJECT_VERSION)", original.replace('"2026062902"', '"$(UNKNOWN)"')]
  ]) {
    f.set("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)");
    f.set("CFBundleShortVersionString", "$(MARKETING_VERSION)");
    f.set(key, value); writeFileSync(f.project, yaml);
    const before = [f.info, f.project, f.ledger].map(p => readFileSync(p, "utf8"));
    assert.notEqual(f.run("prepare", "--date", "20260912").status, 0);
    assert.deepEqual([f.info, f.project, f.ledger].map(p => readFileSync(p, "utf8")), before);
    assert.notEqual(f.run("record", "--upload-log", join(f.root, "unused"), "--ipa", "unused").status, 0);
    assert.deepEqual([f.info, f.project, f.ledger].map(p => readFileSync(p, "utf8")), before);
  }
});

test("new version starts at one, reuses preparation, records by train and increments", { skip: process.platform !== "darwin" }, t => {
  const f = fixture(t);
  writeFileSync(f.project, readFileSync(f.project, "utf8").replace('"0.1.0"', '"0.1.1"'));
  const old = { schemaVersion: 1, marketingVersion: "0.1.0", nextBuildFloor: "5000000000", lastPreparedBuild: "5000000002", lastInstalledBuild: "1", lastUploadedBuild: "5000000002", uploads: [{build:"1", marketingVersion:"0.1.0"}, {build:"5000000002",marketingVersion:"0.1.0"}] };
  writeFileSync(f.ledger, JSON.stringify(old));
  let result = f.run("prepare", "--start-at", "1"); assert.equal(result.status, 0, result.stderr);
  assert.equal(f.prepare().lastPreparedBuild, "1");
  assert.equal(f.prepare().lastInstalledMarketingVersion, "0.1.0");
  const log = join(f.root, "upload.log"); writeFileSync(log, "Delivery UUID: 01234567-89ab-cdef-0123-456789abcdef\n");
  for (let n=0;n<2;n++) { result=f.run("record","--upload-log",log,"--ipa",join(f.root,"app.ipa"));assert.equal(result.status,0,result.stderr); }
  assert.equal(JSON.parse(readFileSync(f.ledger)).uploads.length,3);
  assert.equal(f.prepare().lastPreparedBuild,"2");
  const installed=JSON.parse(readFileSync(f.ledger));installed.lastInstalledBuild="2";installed.lastInstalledMarketingVersion="0.1.1";writeFileSync(f.ledger,JSON.stringify(installed));
  assert.equal(f.prepare().lastPreparedBuild,"3");
  const before=[f.info,f.project,f.ledger].map(p=>readFileSync(p,"utf8"));
  assert.notEqual(f.run("prepare","--start-at","1").status,0);
  assert.deepEqual([f.info,f.project,f.ledger].map(p=>readFileSync(p,"utf8")),before);
});

test("new train rejects unknown history, collisions and unsupported reset arguments without writes", { skip: process.platform !== "darwin" }, t => {
  const f=fixture(t);
  writeFileSync(f.project,readFileSync(f.project,"utf8").replace('"0.1.0"','"0.1.1"'));
  for(const ledger of [
    {marketingVersion:"0.1.0",uploads:[{build:"1"}]},
    {marketingVersion:"$(MARKETING_VERSION)",uploads:[]},
    {marketingVersion:"0.1.0",uploads:[{build:"1",marketingVersion:"0.1.1"}]},
    {marketingVersion:"0.1.0",lastInstalledBuild:"1",lastInstalledMarketingVersion:"0.1.1",uploads:[]}
  ]) {
    writeFileSync(f.ledger,JSON.stringify(ledger));
    const before=[f.info,f.project,f.ledger].map(p=>readFileSync(p,"utf8"));
    assert.notEqual(f.run("prepare","--start-at","1").status,0);
    assert.deepEqual([f.info,f.project,f.ledger].map(p=>readFileSync(p,"utf8")),before);
  }
  writeFileSync(f.ledger,JSON.stringify({marketingVersion:"0.1.0",uploads:[]}));
  for(const args of [["--start-at"],["--start-at","2"],["--start-at","1","--date","20260919"]])assert.notEqual(f.run("prepare",...args).status,0);
});

test("migration derives uploaded ownership from historical rows, not abandoned preparation", { skip: process.platform !== "darwin" }, t => {
  const f=fixture(t);
  writeFileSync(f.project,readFileSync(f.project,"utf8").replace('"0.1.0"','"0.1.1"'));
  writeFileSync(f.ledger,JSON.stringify({marketingVersion:"0.1.0",lastPreparedBuild:"5000000003",lastUploadedBuild:"5000000002",lastInstalledBuild:"2026091501",uploads:[{build:"5000000002",marketingVersion:"0.3.0"}]}));
  const result=f.run("prepare","--start-at","1");assert.equal(result.status,0,result.stderr);
  const ledger=JSON.parse(readFileSync(f.ledger));
  assert.equal(ledger.lastUploadedMarketingVersion,"0.3.0");
  assert.equal(ledger.lastInstalledMarketingVersion,"0.1.0");
  assert.equal(ledger.uploads[0].marketingVersion,"0.3.0");
});
