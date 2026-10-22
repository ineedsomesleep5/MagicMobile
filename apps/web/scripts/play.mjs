#!/usr/bin/env node
/**
 * Plays solo games against the XMage AI on the real engine in headless Chrome and records what the board did: every
 * answer the session sent (smart pass, skips, the player's), each snapshot's stack and board, the board's holds, flights,
 * banners and notices, console errors, and the result. The evidence for docs/WEB_PARITY.md rows marked "game".
 *
 *   zsh scripts/dev/heavy.sh "web autoplay" -- node apps/web/scripts/play.mjs --url "http://127.0.0.1:5181/?debug" \
 *     --me token-triumph --ai grave-danger --games 1 --out /tmp/autoplay
 *
 * The page must expose the debug handle (`?debug`, or the dev server). The policy plays like a careful beginner through
 * the board's own controls where they exist (Auto Pay, Attack All, the corner plaques) and the session elsewhere.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright-core";

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
  if (value.startsWith("--")) pairs.push([value.slice(2), all[index + 1]?.startsWith("--") || all[index + 1] === undefined ? "true" : all[index + 1]]);
  return pairs;
}, []));
const url = args.url ?? "http://127.0.0.1:5181/?debug";
const games = Number(args.games ?? 1);
const out = args.out ?? "/tmp/magicmobile-autoplay";
const maxTurns = Number(args.turns ?? 40);
const deckNames = {
  "token-triumph": "Token Triumph", "first-flight": "First Flight", "grave-danger": "Grave Danger", "chaos-incarnate": "Chaos Incarnate",
  "draconic-destruction": "Draconic Destruction",
};
mkdirSync(out, { recursive: true });

/** Installed in the page: records the session's answers, the snapshots and the board's effects into window.__rec. */
const recorder = () => {
  const rec = { t0: performance.now(), sends: [], snaps: [], fx: [], errors: [] };
  window.__rec = rec;
  const now = () => Math.round(performance.now() - rec.t0);
  const install = () => {
    const mm = window.__mm;
    if (!mm?.table?.session || mm.table.session.__recorded) return;
    const s = mm.table.session;
    s.__recorded = true;
    const submit = s.submit.bind(s);
    s.submit = async (command, label, actionID, fromSkip) => {
      const snap = s.state.snapshot;
      const top = snap?.xmage?.stack?.[0];
      const hold = s.presentationHold;
      rec.sends.push({ t: now(), type: command.type, label, by: actionID.startsWith("smart-pass") ? "smart" : actionID.startsWith("auto-pass") ? "skip" : "player",
        turn: snap?.turn, step: snap?.step, top: top ? `${top.name}${top.controllerId === snap.viewerPlayerId ? " (you)" : " (ai)"}` : undefined,
        holdLeft: hold?.until !== undefined ? Math.round((hold.until - performance.now() / 1000) * 1000) : undefined });
      return submit(command, label, actionID, fromSkip);
    };
  };
  let lastKey = "";
  setInterval(() => {
    install();
    const snap = window.__mm?.table?.session?.state.snapshot;
    if (!snap) return;
    const top = snap.xmage?.stack?.[0];
    const key = `${snap.id}:${snap.bridgeRevision}`;
    if (key === lastKey) return;
    lastKey = key;
    rec.snaps.push({ t: now(), turn: snap.turn, step: snap.step, active: snap.activePlayerId === snap.viewerPlayerId ? "you" : "ai",
      top: top ? `${top.name}${top.controllerId === snap.viewerPlayerId ? " (you)" : " (ai)"}` : undefined,
      board: snap.players.map((p) => p.zones.battlefield.length).join("/"), life: snap.players.map((p) => p.life).join("/") });
    if (rec.snaps.length > 6000) rec.snaps.splice(0, 2000);
  }, 25);
  let last = "";
  const frame = () => {
    const flights = [...document.querySelectorAll(".fxflight")].map((e) => e.className.replace("acard fxflight", "").trim() || "fly");
    const hidden = document.querySelectorAll(".acard.fx-hidden").length;
    const banner = document.querySelector(".abanner")?.getAttribute("aria-label") ?? undefined;
    const notice = document.querySelector(".aprompt.notice")?.textContent ?? undefined;
    const reveal = document.querySelector(".acard[style*='z-index: 650']") ? "reveal" : undefined;
    const key = JSON.stringify([flights, hidden > 0, banner, notice, reveal]);
    if (key !== last) { rec.fx.push({ t: now(), flights, hidden, banner, notice, reveal }); last = key; }
    if (rec.fx.length > 6000) rec.fx.splice(0, 2000);
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
  window.addEventListener("error", (e) => rec.errors.push(String(e.message)));
};

/** One look at the game from the page: what the policy needs. */
const look = () => {
  const s = window.__mm?.table?.session;
  const snap = s?.state.snapshot;
  if (!snap) return { ready: false, stage: window.__mm?.table?.state.stage };
  const env = snap.promptEnvelopeV2;
  const me = snap.players.find((p) => p.playerId === snap.viewerPlayerId);
  return {
    ready: true, turn: snap.turn, step: snap.step, mine: snap.activePlayerId === snap.viewerPlayerId, over: snap.gameStatus === "completed",
    winners: snap.winnerPlayerIds ?? [], viewer: snap.viewerPlayerId, working: s.state.working || s.state.pendingActionID !== undefined,
    error: s.state.errorMessage, life: snap.players.map((p) => p.life),
    prompt: env && { id: env.id, mine: env.playerId === snap.viewerPlayerId, method: env.method, kind: env.responseKind, message: env.message,
      targets: env.targetIds ?? env.targets?.map((t) => t.id) ?? [], choices: (env.choices ?? []).map((c) => c.id), abilities: (env.abilities ?? []).map((a) => a.id),
      modes: (env.modes ?? []).map((m) => m.id), players: (env.players ?? []).map((p) => p.id), cards: (env.cards ?? []).map((c) => c.instanceId),
      confirmation: env.confirmation !== undefined, min: env.minChoices, max: env.maxChoices },
    paying: snap.manaPayment?.active === true || ["mana", "pay_cost", "cost", "x_mana"].includes((env?.responseKind ?? "").toLowerCase()),
    autoPaying: [...document.querySelectorAll(".aplaque")].some((b) => b.textContent === "Paying…"),
    stack: (snap.xmage?.stack ?? []).length,
    actions: (snap.legalActions ?? []).map((a) => ({ id: a.id, type: a.type, label: a.label, card: a.cardName, cost: a.manaCost, confirmed: a.confirmed })),
    hand: me?.zones.hand.length ?? 0, creatures: me?.zones.battlefield.filter((c) => /creature/i.test(c.card.typeLine)).length ?? 0,
  };
};

const manaValue = (cost) => (cost ?? "").match(/\{[^}]+\}/g)?.reduce((n, sym) => n + (/^\{\d+\}$/.test(sym) ? Number(sym.slice(1, -1)) : sym === "{X}" ? 0 : 1), 0) ?? 0;

/** The policy's next move for a look, or undefined to wait. */
function decide(state, memory) {
  const p = state.prompt;
  if (!state.ready || state.over || state.working || !p || !p.mine) return undefined;
  const acts = state.actions;
  if (/mulligan/i.test(p.message)) return { submit: { type: "answer_yes_no", confirmed: false }, label: "Keep" };
  if (state.paying) {
    // The board's own Auto Pay, once per payment; the sources by hand if it can't pay.
    if (!memory.autoPaid.has(p.id) && !state.autoPaying) { memory.autoPaid.add(p.id); return { click: "Auto Pay" }; }
    if (state.autoPaying) return undefined;
    const tap = acts.find((a) => a.type === "make_mana");
    if (tap) return { action: tap.id };
    const cancel = acts.find((a) => a.type === "cancel_payment");
    return cancel ? { action: cancel.id } : undefined;
  }
  if (p.kind === "priority") {
    if (state.mine && /MAIN/.test(state.step ?? "") && state.stack === 0) {
      const land = acts.find((a) => a.type === "play_land");
      if (land) return { action: land.id };
      const spells = acts.filter((a) => a.type === "cast_spell" && !memory.failed.has(a.id)).sort((a, b) => manaValue(a.cost) - manaValue(b.cost));
      if (spells.length && memory.casts < 3) { memory.casts += 1; return { action: spells[0].id, cast: true }; }
    }
    // Let smart pass act first; pass by hand only when it stopped for a response.
    if (Date.now() - (memory.promptSeen.get(p.id) ?? Date.now()) < 6000) { if (!memory.promptSeen.has(p.id)) memory.promptSeen.set(p.id, Date.now()); return undefined; }
    const pass = acts.find((a) => a.type === "pass_priority");
    return pass ? { action: pass.id, manualPass: true } : undefined;
  }
  if (p.method === "GAME_SELECT" && p.kind === "target") {
    // Combat: attackers on your turn (everything that can), no blocks on theirs.
    if (state.mine && /attack/i.test(p.message) && p.targets.length && !memory.attacked.has(p.id)) {
      memory.attacked.add(p.id);
      return { submit: { type: "choose_target", targetIds: [p.targets[0]] }, label: "Attack" };
    }
    const done = acts.find((a) => a.type === "answer_yes_no");
    return done ? { action: done.id } : undefined;
  }
  if (p.targets.length) return { submit: { type: "choose_target", targetIds: [p.targets[0]] }, label: "Choose" };
  if (p.abilities.length) return { submit: { type: "choose_ability", abilityId: p.abilities[0] }, label: "Ability" };
  if (p.modes.length) return { submit: { type: "choose_mode", modeIds: [p.modes[0]] }, label: "Mode" };
  if (p.players.length) return { submit: { type: "choose_player", playerIds: [p.players[0]] }, label: "Player" };
  if (p.choices.length) return { submit: { type: "choose_choice", choiceIds: [p.choices[0]] }, label: "Choice" };
  const no = acts.find((a) => a.type === "answer_yes_no" && a.confirmed === false);
  const first = no ?? acts[0];
  return first ? { action: first.id } : undefined;
}

async function play(page, game) {
  await page.goto(url);
  await page.addScriptTag({ content: `(${recorder.toString()})()` });
  const start = page.getByRole("button", { name: "Start the game" });
  await start.waitFor({ timeout: 180_000 });
  // Two shelves of deck tiles: yours, then the AI's.
  await page.locator(".deck-shelf").nth(0).locator(".deck-tile", { hasText: deckNames[args.me ?? "token-triumph"] }).click();
  await page.locator(".deck-shelf").nth(1).locator(".deck-tile", { hasText: deckNames[args.ai ?? "grave-danger"] }).click();
  for (let i = 0; i < 360 && !(await start.isEnabled()); i++) await page.waitForTimeout(500);
  await start.click();
  const memory = { casts: 0, failed: new Set(), attacked: new Set(), promptSeen: new Map(), turn: 0, autoPaid: new Set() };
  const started = Date.now();
  let lastTurn = 0;
  for (;;) {
    const roll = page.getByRole("button", { name: "Roll the D20" });
    if (await roll.isVisible().catch(() => false) && await roll.isEnabled().catch(() => false)) await roll.click().catch(() => {});
    const state = await page.evaluate(look);
    if (state.ready && state.over) break;
    if (state.ready && state.turn !== lastTurn) {
      lastTurn = state.turn; memory.casts = 0;
      console.log(`game ${game} turn ${state.turn} life ${state.life.join("/")} ${state.mine ? "yours" : "theirs"}`);
    }
    // A decision nothing answers for two minutes is a stall: say what it was and concede.
    const stuckKey = state.prompt ? `${state.prompt.id}:${state.prompt.message}` : "none";
    if (stuckKey !== memory.stuckKey) { memory.stuckKey = stuckKey; memory.stuckSince = Date.now(); }
    else if (state.prompt?.mine && Date.now() - memory.stuckSince > 120_000) {
      console.log(`game ${game} stalled on ${JSON.stringify(state.prompt)} actions ${JSON.stringify(state.actions)}`);
      await page.screenshot({ path: join(out, `game-${game}-stall.png`) });
      await page.evaluate(() => window.__mm.table.concede());
      await page.waitForTimeout(3000);
      break;
    }
    if (state.ready && state.turn > maxTurns) {
      await page.evaluate(() => window.__mm.table.concede());
      await page.waitForTimeout(3000);
      break;
    }
    if (Date.now() - started > 45 * 60_000) throw new Error("Game took longer than 45 minutes");
    const move = decide(state, memory);
    if (move?.click) {
      const button = page.getByRole("button", { name: move.click, exact: true });
      if (await button.isEnabled().catch(() => false)) {
        await button.click().catch(() => {});
        await page.evaluate((name) => window.__rec.sends.push({ t: Math.round(performance.now() - window.__rec.t0), type: "click", label: name }), move.click);
      }
    } else if (move) {
      const result = await page.evaluate(async ({ move }) => {
        const s = window.__mm.table.session;
        const snap = s.state.snapshot;
        const env = snap.promptEnvelopeV2;
        try {
          if (move.action) {
            const action = snap.legalActions.find((a) => a.id === move.action);
            if (!action) return "gone";
            await s.send(action);
          } else {
            await s.submit({ ...move.submit, gameId: snap.id, playerId: snap.viewerPlayerId, promptId: env.id, messageId: env.messageId }, move.label, `${env.id}:${move.label}`);
          }
          return "ok";
        } catch (error) { return `error: ${error.message ?? error}`; }
      }, { move });
      if (result !== "ok" && move.action) memory.failed.add(move.action);
    }
    await page.waitForTimeout(250);
  }
  const final = await page.evaluate(look);
  const rec = await page.evaluate(() => window.__rec);
  const won = final.winners.includes(final.viewer);
  await page.screenshot({ path: join(out, `game-${game}-end.png`) });
  writeFileSync(join(out, `game-${game}.json`), JSON.stringify({ final: { turn: final.turn, life: final.life, won }, ...rec }, null, 1));
  return { game, turn: final.turn, life: final.life, won, sends: rec.sends.length, errors: rec.errors };
}

// The installed Google Chrome (new headless mode): no Playwright browser download needed.
const browser = await chromium.launch({ headless: true, channel: "chrome" });
const results = [];
try {
  for (let game = 1; game <= games; game++) {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    const consoleErrors = [];
    page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
    page.on("pageerror", (e) => consoleErrors.push(String(e)));
    const result = await play(page, game);
    results.push({ ...result, consoleErrors });
    console.log(JSON.stringify(results.at(-1)));
    await page.close();
  }
} finally {
  await browser.close();
  writeFileSync(join(out, "summary.json"), JSON.stringify(results, null, 1));
}
