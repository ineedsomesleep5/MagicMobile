/**
 * Joins a relay table as a web guest in headless Chrome, readies up, then plays on autopilot (rolls, keeps, moves the
 * turn on) and reports what the guest sees: the room, then the board. For checking a table another browser or a phone hosts. The profile server is blocked so no player is made.
 *
 *   node apps/web/scripts/guest-join.mjs --url http://127.0.0.1:5173/ --code ABC234 --out /tmp/guest [--seconds 120]
 */
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright-core";

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, arg, i, all) => (arg.startsWith("--") ? [...pairs, [arg.slice(2), all[i + 1]]] : pairs), []));
const base = args.url ?? "http://127.0.0.1:5173/";
const out = args.out ?? "/tmp/guest";
const seconds = Number(args.seconds ?? 120);
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ headless: true, channel: "chrome" });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
await page.route(/supabase\.co/, (route) => route.abort());
const log = (line) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${line}`);
page.on("console", (m) => { if (m.type() === "error") log(`console: ${m.text().slice(0, 200)}`); });
await page.goto(new URL(`join/${args.code}`, base).toString());
await page.locator('[data-id="setup.join"]').click({ timeout: 60_000 });
log("joined");
const started = Date.now();
let readied = false, shots = 0, last = "";
while (Date.now() - started < seconds * 1000) {
  await page.waitForTimeout(2000);
  const room = page.locator('[data-id="relay.guest.room"]');
  const text = (await room.count()) > 0 ? (await room.innerText()).replace(/\s+/g, " ").slice(0, 200) : `board: ${(await page.locator("body").innerText()).replace(/\s+/g, " ").slice(0, 160)}`;
  if (text !== last) { log(text); last = text; }
  if (!readied && (await page.getByRole("button", { name: "Ready up" }).count()) > 0) {
    await page.getByRole("button", { name: "Ready up" }).click(); readied = true; log("ready");
  }
  // Autopilot on the board: roll, keep, and move the turn on (the board's own plaques), so the host's engine answers us.
  if ((await room.count()) === 0) {
    for (const name of ["Roll D20", "Keep", "Resolve", "Next", "Pass", "End Turn"]) {
      const button = page.getByRole("button", { name: new RegExp(`^${name}\\b`) });
      if ((await button.count()) > 0 && (await button.first().isEnabled())) { await button.first().click().catch(() => undefined); log(`clicked ${name}`); break; }
    }
  }
  if ((await room.count()) === 0 && shots < 3) { await page.screenshot({ path: join(out, `guest-${shots++}.png`), timeout: 60_000 }).catch(() => undefined); }
}
await page.screenshot({ path: join(out, "guest-final.png"), timeout: 60_000 }).catch(() => undefined);
await browser.close();
