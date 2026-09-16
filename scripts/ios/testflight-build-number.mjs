#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const infoPlist = resolve(repoRoot, "apps/ios/MagicMobile/Info.plist");
const ledgerPath = resolve(repoRoot, "release/testflight/build-ledger.json");
const projectPath = resolve(repoRoot, "apps/ios/project.yml");
const plistBuddy = "/usr/libexec/PlistBuddy";

function usage() {
  console.error("Usage: testflight-build-number.mjs prepare [--date YYYYMMDD] | record --upload-log PATH --ipa PATH");
  process.exit(2);
}

function argValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function plist(command) {
  return execFileSync(plistBuddy, ["-c", command, infoPlist], { encoding: "utf8" }).trim();
}

// Deliberately support the reviewed XcodeGen settings.base scalar form only.
// Reject overrides/indirection instead of approximating YAML or Xcode evaluation.
function projectVersions() {
  const text = readFileSync(projectPath, "utf8");
  if (/^\s*["']?(?:<<|include|settingGroups|templates|targetTemplates|configFiles)["']?\s*:/m.test(text)) {
    throw new Error("Cannot resolve indirect project.yml version settings");
  }
  const settings = [...text.matchAll(/^settings:\s*(?:#.*)?\r?\n((?:[ \t]+[^\n]*\n|\r?\n)*)/gm)];
  if (settings.length !== 1) throw new Error("Expected one project.yml settings block");
  const bases = [...settings[0][1].matchAll(/^  base:\s*(?:#.*)?\r?\n((?: {4}[^\n]*\n|\r?\n)*)/gm)];
  if (bases.length !== 1) throw new Error("Expected one project.yml settings.base block");
  const values = {};
  for (const key of ["MARKETING_VERSION", "CURRENT_PROJECT_VERSION"]) {
    const occurrences = [...text.replace(/#[^\n]*/g, "").matchAll(new RegExp(`\\b${key}\\b`, "g"))];
    const scalar = new RegExp(`^    ${key}: *(["']?)([0-9]+(?:\\.[0-9]+)*)\\1 *(?:#.*)?\\r?$`, "gm");
    const matches = [...bases[0][1].matchAll(scalar)];
    if (occurrences.length !== 1 || matches.length !== 1) {
      throw new Error(`Expected one literal settings.base.${key} in project.yml`);
    }
    values[key] = matches[0][2];
  }
  if (!/^\d+$/.test(values.CURRENT_PROJECT_VERSION)) throw new Error("Invalid CURRENT_PROJECT_VERSION");
  return { text, ...values };
}

function versions(project) {
  function value(plistKey, setting, pattern) {
    const raw = plist(`Print :${plistKey}`);
    const resolved = raw === `$(${setting})` ? project[setting] : raw;
    if (!pattern.test(resolved)) throw new Error(`Unsupported ${plistKey}: ${raw}`);
    return resolved;
  }
  return {
    marketingVersion: value("CFBundleShortVersionString", "MARKETING_VERSION", /^\d+(?:\.\d+){0,2}$/),
    build: value("CFBundleVersion", "CURRENT_PROJECT_VERSION", /^\d+$/)
  };
}

function readLedger() {
  if (!existsSync(ledgerPath)) {
    return { schemaVersion: 1, bundleId: "com.calebfeliciano.magicmobile", uploads: [] };
  }
  return JSON.parse(readFileSync(ledgerPath, "utf8"));
}

function writeLedger(ledger) {
  writeFileSync(ledgerPath, `${JSON.stringify(ledger, null, 2)}\n`);
}

function todayStamp() {
  if (process.env.TESTFLIGHT_BUILD_DATE) return process.env.TESTFLIGHT_BUILD_DATE;
  return new Date().toISOString().slice(0, 10).replaceAll("-", "");
}

function numericBuilds(ledger, currentBuild) {
  return [currentBuild, ledger.lastPreparedBuild, ledger.lastUploadedBuild, ledger.lastInstalledBuild, ...(ledger.uploads ?? []).map((entry) => entry.build)]
    .filter((build) => /^\d{10}$/.test(String(build)))
    .map((build) => String(build));
}

function nextBuildNumber(ledger, currentBuild, datePrefix) {
  if (/^\d{10}$/.test(String(currentBuild))
      && currentBuild === ledger.lastPreparedBuild
      && currentBuild !== ledger.lastUploadedBuild
      && currentBuild !== ledger.lastInstalledBuild) {
    return currentBuild;
  }
  const builds = numericBuilds(ledger, currentBuild);
  const maxBuild = builds.sort().at(-1);
  const prefix = maxBuild && maxBuild.slice(0, 8) > datePrefix ? maxBuild.slice(0, 8) : datePrefix;
  const maxSequenceForPrefix = builds
    .filter((build) => build.startsWith(prefix))
    .map((build) => Number(build.slice(8)))
    .reduce((max, value) => Math.max(max, value), 0);
  return `${prefix}${String(maxSequenceForPrefix + 1).padStart(2, "0")}`;
}

function prepare() {
  const explicitDate = argValue("--date");
  const datePrefix = explicitDate ?? todayStamp();
  if (!/^\d{8}$/.test(datePrefix)) {
    throw new Error(`Expected YYYYMMDD build date, received ${datePrefix}`);
  }
  const project = projectVersions();
  const { marketingVersion, build: currentBuild } = versions(project);
  const ledger = readLedger();
  const nextBuild = nextBuildNumber(ledger, currentBuild, datePrefix);

  execFileSync(plistBuddy, ["-c", `Set :CFBundleVersion ${nextBuild}`, infoPlist], { stdio: "inherit" });
  writeFileSync(projectPath, project.text.replace(
    /^(    CURRENT_PROJECT_VERSION: *)(["']?)[0-9]+\2( *(?:#.*)?\r?)$/m,
    (_, prefix, quote, suffix) => `${prefix}${quote}${nextBuild}${quote}${suffix}`));
  ledger.bundleId = "com.calebfeliciano.magicmobile";
  ledger.marketingVersion = marketingVersion;
  ledger.lastPreparedBuild = nextBuild;
  ledger.lastPreparedAt = new Date().toISOString();
  writeLedger(ledger);
  console.log(`Prepared TestFlight build ${marketingVersion} (${nextBuild})`);
}

function deliveryUuidFromLog(uploadLog) {
  const text = readFileSync(uploadLog, "utf8");
  const match = text.match(/Delivery UUID:\s*([0-9a-fA-F-]+)/);
  return match?.[1] ?? null;
}

function record() {
  const uploadLog = argValue("--upload-log");
  const ipaPath = argValue("--ipa");
  if (!uploadLog || !ipaPath) usage();
  const { marketingVersion, build } = versions(projectVersions());
  const deliveryUuid = deliveryUuidFromLog(uploadLog);
  if (!deliveryUuid) {
    throw new Error(`Could not find Delivery UUID in ${uploadLog}`);
  }

  const ledger = readLedger();
  ledger.bundleId = "com.calebfeliciano.magicmobile";
  ledger.marketingVersion = marketingVersion;
  ledger.lastPreparedBuild = build;
  ledger.lastUploadedBuild = build;
  ledger.uploads = (ledger.uploads ?? []).filter((entry) => entry.build !== build);
  ledger.uploads.push({
    build,
    marketingVersion,
    uploadedAt: new Date().toISOString(),
    deliveryUuid,
    ipaPath: relative(repoRoot, resolve(ipaPath))
  });
  writeLedger(ledger);
  console.log(`Recorded TestFlight upload ${marketingVersion} (${build}) delivery ${deliveryUuid}`);
}

const command = process.argv[2];
try {
  if (command === "prepare") prepare();
  else if (command === "record") record();
  else usage();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
