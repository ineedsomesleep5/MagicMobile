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
const shots = new Set(String(args.shots ?? "").split(",").filter(Boolean).map(Number));
const deckNames = {
  "token-triumph": "Token Triumph", "first-flight": "First Flight", "grave-danger": "Grave Danger", "chaos-incarnate": "Chaos Incarnate",
  "draconic-destruction": "Draconic Destruction",
};
mkdirSync(out, { recursive: true });

/** Installed in the page: records the session's answers, the snapshots and the board's effects into window.__rec. */
const recorder = () => {
  const rec = { t0: performance.now(), sends: [], snaps: [], fx: [], errors: [], painted: {}, shots: [] };
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
    // Each board effect the painter drew, by kind, counted once (its event object marks it), and the first time a kind
    // is on screen, asked for a screenshot (the driver takes it between moves).
    const fx = window.__mm?.fx?.current;
    const clock = performance.now() / 1000;
    for (const active of fx?.active ?? []) {
      const at = clock - active.start - active.scheduled.delay;
      if (at < 0 || at > active.scheduled.duration || active.scheduled.event.__seen) continue;
      active.scheduled.event.__seen = true;
      const kind = active.scheduled.event.type;
      rec.painted[kind] = (rec.painted[kind] ?? 0) + 1;
      if (rec.painted[kind] === 1 && !["spellCast", "enteredBattlefield"].includes(kind)) rec.shots.push(kind);
    }
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
    error: s.state.errorMessage, life: [me?.life, ...snap.players.filter((p) => p !== me).map((p) => p.life)],
    prompt: env && { id: env.id, mine: env.playerId === snap.viewerPlayerId, method: env.method, kind: env.responseKind, message: env.message,
      targets: env.targetIds ?? env.targets?.map((t) => t.id) ?? [], choices: (env.choices ?? []).map((c) => c.id), abilities: (env.abilities ?? []).map((a) => a.id),
      modes: (env.modes ?? []).map((m) => m.id), players: (env.players ?? []).map((p) => p.id), cards: (env.cards ?? []).map((c) => c.instanceId),
      confirmation: env.confirmation !== undefined, min: env.minChoices, max: env.maxChoices },
    paying: snap.manaPayment?.active === true || ["mana", "pay_cost", "cost", "x_mana"].includes((env?.responseKind ?? "").toLowerCase()),
    autoPaying: [...document.querySelectorAll(".aplaque")].some((b) => b.textContent === "Paying…"),
    stack: (snap.xmage?.stack ?? []).length,
    theirTop: (() => { const top = snap.xmage?.stack?.[0]; return top && top.controllerId !== snap.viewerPlayerId ? top.id : undefined; })(),
    actions: (snap.legalActions ?? []).map((a) => ({ id: a.id, type: a.type, label: a.label, card: a.cardName, cardId: a.cardInstanceId, cost: a.manaCost, confirmed: a.confirmed })),
    buttons: [...document.querySelectorAll(".acontrols .aplaque, .bfoot .aplaque, .aplaque")].filter((b) => !b.disabled).map((b) => b.textContent),
    hand: me?.zones.hand.length ?? 0, handIds: me?.zones.hand.map((c) => c.instanceId) ?? [],
    browser: document.querySelector(".bstage, .bframe") !== null, creatures: me?.zones.battlefield.filter((c) => /creature/i.test(c.card.typeLine)).length ?? 0,
    allCreatures: snap.players.flatMap((p) => p.zones.battlefield).filter((c) => /creature/i.test(c.card.typeLine)).length,
  };
};

const manaValue = (cost) => (cost ?? "").match(/\{[^}]+\}/g)?.reduce((n, sym) => n + (/^\{\d+\}$/.test(sym) ? Number(sym.slice(1, -1)) : sym === "{X}" ? 0 : 1), 0) ?? 0;

const SWEEPERS = ["Sweltering Suns", "Chain Reaction", "Cleansing Nova", "Time Wipe", "Citywide Bust", "Magmaquake", "Blasphemous Act", "Deadly Tempest",
  "Necromantic Selection"];

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
      // A sweeper first once three or more creatures are out (each game should show a board wipe), else the cheapest.
      const sweeper = (a) => SWEEPERS.some((name) => (a.label ?? "").includes(name)) && state.allCreatures >= 3 ? -100 : 0;
      const spells = acts.filter((a) => a.type === "cast_spell" && !memory.failed.has(a.id))
        .sort((a, b) => sweeper(a) - sweeper(b) || manaValue(a.cost) - manaValue(b.cost));
      if (spells.length && memory.casts < 3) {
        memory.casts += 1;
        // Cast the way a player does: carry the card from the hand onto the table (one with a single cast action).
        const card = spells[0];
        const sameCard = acts.filter((a) => a.cardId === card.cardId && (a.type === "cast_spell" || a.type === "play_land"));
        return sameCard.length === 1 && card.cardId && state.handIds.includes(card.cardId) ? { drag: card.cardId, action: card.id } : { action: card.id };
      }
    }
    // Let smart pass act first; pass by hand only when it stopped for a response.
    if (Date.now() - (memory.promptSeen.get(p.id) ?? Date.now()) < 6000) { if (!memory.promptSeen.has(p.id)) memory.promptSeen.set(p.id, Date.now()); return undefined; }
    const pass = acts.find((a) => a.type === "pass_priority");
    return pass ? { action: pass.id, manualPass: true } : undefined;
  }
  if (state.buttons.includes("All Attack") && !memory.allAttack.has(p.id)) { memory.allAttack.add(p.id); return { click: "All Attack" }; }
  if (state.buttons.includes("Auto Order")) return { click: "Auto Order" };
  const finish = state.buttons.find((b) => /^(\d+ Attackers?|No Attacks|\d+ Blockers?|No Blocks)$/.test(b));
  if (finish && !state.buttons.includes("Attacking…") && (state.mine ? /Attacker/.test(finish) || memory.allAttack.size > 0 : true)) {
    if (!memory.finished.has(p.id)) { memory.finished.add(p.id); return { click: finish }; }
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
  // A question on the table (yes/no, the commander's zone): its main answer, the ember plaque, as a player clicks it.
  if (p.confirmation && state.browser) return { clickIn: ".bstage .answers .aplaque.ember" };
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
  const memory = { casts: 0, failed: new Set(), attacked: new Set(), promptSeen: new Map(), turn: 0, autoPaid: new Set(), allAttack: new Set(), finished: new Set(),
    drags: 0 };
  const started = Date.now();
  let lastTurn = 0;
  for (;;) {
    const roll = page.getByRole("button", { name: "Roll the D20" });
    if (await roll.isVisible().catch(() => false) && await roll.isEnabled().catch(() => false)) await roll.click().catch(() => {});
    const state = await page.evaluate(look);
    if (state.ready && state.over) break;
    if (state.ready && state.turn !== lastTurn) {
      lastTurn = state.turn; memory.casts = 0;
      console.log(`game ${game} turn ${state.turn} life you ${state.life.join(" / them ")} ${state.mine ? "yours" : "theirs"}`);
      // --shots 6,12: the open game log at the start of those turns, for a look at the log against a real game.
      if (shots.has(state.turn)) {
        const button = page.getByRole("button", { name: "Game log", exact: true });
        await button.click().catch(() => {});
        await page.waitForTimeout(700);
        await page.screenshot({ path: join(out, `game-${game}-log-turn-${state.turn}.png`) });
        await button.click().catch(() => {});
        // The opponent's player card, then the stack browser when there is a stack.
        const medallion = page.locator(".amed").first();
        if (await medallion.count() > 0) {
          await medallion.click({ timeout: 2000 }).catch(() => {});
          await page.waitForTimeout(400);
          await page.screenshot({ path: join(out, `game-${game}-card-turn-${state.turn}.png`) });
          await page.keyboard.press("Escape");
        }
      }
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
    // Once a game, read the AI's spell on the stack for 3 s (right-click) while its reveal still holds smart pass: the pass
    // must wait for the inspector to close (BoardPresentationHold.reading).
    if (state.theirTop && state.theirTop !== memory.topSeen) { memory.topSeen = state.theirTop; memory.topSeenAt = Date.now(); }
    if (!memory.readTest && state.ready && state.theirTop && Date.now() - memory.topSeenAt < 800 && state.prompt?.mine && state.prompt.kind === "priority") {
      const card = page.locator(`.acard[data-id="${state.theirTop}"]`);
      if (await card.count() > 0) {
        memory.readTest = true;
        await card.click({ button: "right", timeout: 2000 }).catch(() => {});
        const opened = await page.evaluate(() => { const t = Math.round(performance.now() - window.__rec.t0); window.__rec.sends.push({ t, type: "inspect-open" }); return t; });
        await page.waitForTimeout(3000);
        const passedWhileReading = await page.evaluate((from) => window.__rec.sends.some((x) => x.t > from && x.by === "smart"), opened);
        await page.keyboard.press("Escape");
        await page.evaluate(() => window.__rec.sends.push({ t: Math.round(performance.now() - window.__rec.t0), type: "inspect-close" }));
        memory.readResult = passedWhileReading ? "smart pass went while the card was being read" : "smart pass waited 3 s for the inspector";
      }
    }
    // The first time each kind of effect plays, a picture of it (evidence for docs/WEB_PARITY.md section 7).
    const wanted = await page.evaluate(() => window.__rec.shots.splice(0));
    for (const kind of wanted) await page.screenshot({ path: join(out, `game-${game}-fx-${kind}.png`) });
    const move = decide(state, memory);
    if (move?.clickIn) {
      const plaque = page.locator(move.clickIn).first();
      if (await plaque.count() > 0) {
        const label = await plaque.textContent();
        await plaque.click({ timeout: 3000 }).catch(() => {});
        await page.evaluate((name) => window.__rec.sends.push({ t: Math.round(performance.now() - window.__rec.t0), type: "click", label: name }), label);
      }
    } else if (move?.drag) {
      // Carry the hand card onto the table with the mouse, as a player does (ArenaLayout.drops decides).
      const card = page.locator(`.acard[data-id="${move.drag}"]`);
      const box = await card.count() > 0 ? await card.boundingBox({ timeout: 2000 }).catch(() => null) : null;
      if (box) {
        // The hand fans up under the pointer: hover, let the fan settle, then press the card where it now stands.
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 3, { steps: 4 });
        await page.waitForTimeout(450);
        const raised = await card.boundingBox({ timeout: 2000 }).catch(() => null) ?? box;
        if (!memory.popShot) { memory.popShot = true; await page.screenshot({ path: join(out, `game-${game}-pop.png`) }); }
        await page.mouse.move(raised.x + raised.width / 2, raised.y + raised.height / 3, { steps: 2 });
        await page.waitForTimeout(120);
        const settled = await card.boundingBox({ timeout: 2000 }).catch(() => null) ?? raised;
        await page.mouse.move(settled.x + settled.width / 2, settled.y + settled.height / 3);
        await page.mouse.down();
        await page.mouse.move(640, 330, { steps: 12 });
        await page.mouse.up();
        memory.drags += 1;
        await page.evaluate(() => window.__rec.sends.push({ t: Math.round(performance.now() - window.__rec.t0), type: "drag" }));
      } else if (move.action) {
        await page.evaluate(async (id) => { const s = window.__mm.table.session; const a = s.state.snapshot.legalActions.find((x) => x.id === id); if (a) await s.send(a); }, move.action);
      }
    } else if (move?.click) {
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
  const count = (type) => rec.sends.filter((e) => e.type === type).length;
  const clicks = (label) => rec.sends.filter((e) => e.type === "click" && e.label === label).length;
  return { game, turn: final.turn, life: final.life, won, sends: rec.sends.length, drags: count("drag"), autoPay: clicks("Auto Pay"), allAttack: clicks("All Attack"),
    smartPasses: rec.sends.filter((e) => e.by === "smart").length, readHold: memory.readResult ?? "not tested", notices: rec.fx.filter((f) => f.notice).map((f) => f.notice), painted: rec.painted, errors: rec.errors };
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
    // Which resources were missing (card art, sounds), once each.
    const notFound = new Set();
    page.on("response", (r) => { if (r.status() >= 400) notFound.add(`${r.status()} ${r.url().split("?")[0]}${r.url().includes("exact=") ? "?" + r.url().split("?")[1].split("&")[0] : ""}`); });
    const result = await play(page, game);
    results.push({ ...result, consoleErrors: consoleErrors.filter((e) => !e.startsWith("Failed to load resource")), notFound: [...notFound] });
    console.log(JSON.stringify(results.at(-1)));
    await page.close();
  }
} finally {
  await browser.close();
  writeFileSync(join(out, "summary.json"), JSON.stringify(results, null, 1));
}
