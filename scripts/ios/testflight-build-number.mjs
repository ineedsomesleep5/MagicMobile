#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const infoPlist = resolve(repoRoot, "apps/ios/MagicMobile/Info.plist");
const ledgerPath = resolve(repoRoot, "release/testflight/build-ledger.json");
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
  return [currentBuild, ledger.lastPreparedBuild, ledger.lastUploadedBuild, ...(ledger.uploads ?? []).map((entry) => entry.build)]
    .filter((build) => /^\d{10}$/.test(String(build)))
    .map((build) => String(build));
}

function nextBuildNumber(ledger, currentBuild, datePrefix) {
  if (/^\d{10}$/.test(String(currentBuild))
      && currentBuild === ledger.lastPreparedBuild
      && currentBuild !== ledger.lastUploadedBuild) {
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
  const marketingVersion = plist("Print :CFBundleShortVersionString");
  const currentBuild = plist("Print :CFBundleVersion");
  const ledger = readLedger();
  const nextBuild = nextBuildNumber(ledger, currentBuild, datePrefix);

  execFileSync(plistBuddy, ["-c", `Set :CFBundleVersion ${nextBuild}`, infoPlist], { stdio: "inherit" });
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
  const marketingVersion = plist("Print :CFBundleShortVersionString");
  const build = plist("Print :CFBundleVersion");
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
