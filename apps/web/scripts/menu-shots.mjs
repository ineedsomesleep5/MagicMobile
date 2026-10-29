#!/usr/bin/env node
/**
 * Screenshots of the Arena menus in headless desktop Chrome, for checking pages against iOS:
 *   node apps/web/scripts/menu-shots.mjs --url http://127.0.0.1:5173/ --out /tmp/shots [--size 1280x800]
 * Each shot is a list of clicks (by data-id) from a fresh page, then a picture.
 */
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright-core";

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, arg, i, all) => (arg.startsWith("--") ? [...pairs, [arg.slice(2), all[i + 1]?.startsWith("--") ? true : all[i + 1]]] : pairs), []));
const url = args.url ?? "http://127.0.0.1:5173/";
const out = args.out ?? "/tmp/menu-shots";
const [width, height] = (args.size ?? "1280x800").split("x").map(Number);
mkdirSync(out, { recursive: true });

const SHOTS = {
  home: [],
  play: ["menu.play"],
  ranked: ["menu.play", "play.ranked"],
  custom: ["menu.play", "play.custom", "play.start"],
  recent: ["menu.play", "play.tab.recent"],
  friends: ["menu.play", "play.tab.friends"],
  decks: ["menu.tab.decks"],
  hall: ["menu.tab.ranked"],
  profile: ["menu.tab.profile"],
  social: ["menu.messages"],
  leaderboard: ["menu.tab.ranked", "ranked.hall.leaderboard"],
  options: ["menu.settings"],
  gameplay: ["menu.settings", "settings.open.gameplay"],
  board: ["menu.settings", "settings.open.board"],
  learn: ["menu.tab.learn"],
  updates: ["menu.updates"],
  opponent: ["menu.play", "quick.deck"],
};
const only = args.only ? String(args.only).split(",") : Object.keys(SHOTS);
const browser = await chromium.launch({ headless: true, channel: "chrome" });
try {
  const page = await browser.newPage({ viewport: { width, height } });
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  for (const name of only) {
    await page.goto(url);
    await page.locator("[data-id='menu.play']").waitFor({ timeout: 30_000 });
    for (const id of SHOTS[name]) {
      await page.locator(`[data-id='${id}']`).first().click();
      await page.waitForTimeout(450);
    }
    await page.waitForTimeout(name === "social" || name === "leaderboard" || name === "profile" ? 4000 : 700);
    await page.screenshot({ path: join(out, `${name}.png`), timeout: 120_000 });
  }
  console.log(JSON.stringify({ shots: only, errors }));
} finally {
  await browser.close();
}
