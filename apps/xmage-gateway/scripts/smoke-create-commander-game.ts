import { generateBracketThreeCommanderDeck } from "../../../packages/deck/src";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const endpoint = (process.env.XMAGE_GATEWAY_URL ?? "http://localhost:17171").replace(/\/$/, "");
const seed = process.env.XMAGE_SMOKE_SEED ?? "bridge-smoke";
const humanPlayerId = process.env.XMAGE_SMOKE_HUMAN_ID ?? "human";
const aiPlayerId = process.env.XMAGE_SMOKE_AI_ID ?? "ai-1";
const scenario = process.env.XMAGE_SMOKE_SCENARIO ?? "general";
const arcaneSignetScenario = scenario === "arcane-signet";
const alphaGameScenario = scenario === "alpha-game";
const fixtureScenario = scenario === "combat" || scenario === "commander-state" || arcaneSignetScenario;

const human = fixtureScenario
  ? arcaneSignetScenario
    ? arcaneSignetFixtureDeck()
    : commanderFixtureDeck("Isamaru, Hound of Konda", "Plains")
  : generateBracketThreeCommanderDeck({ seed: `${seed}:human`, playerId: humanPlayerId }).deck;
const ai = fixtureScenario
  ? commanderFixtureDeck("Kozilek, Butcher of Truth", "Wastes")
  : generateBracketThreeCommanderDeck({ seed: `${seed}:ai`, playerId: aiPlayerId }).deck;

const health = await request("/health");
if (health.status !== "ready") {
  throw new Error(`XMage smoke requires ready health, received: ${JSON.stringify(health)}`);
}
const created = await request("/games/commander", {
  method: "POST",
  body: {
    roomId: `smoke-${seed}`,
    humanPlayerId,
    humanDeck: human,
    aiPlayers: [{ playerId: aiPlayerId, displayName: "Noaddrag", difficulty: "normal", deck: ai }],
    startingLife: 40,
    commanderDamageEnabled: true
  }
});

let snapshot = created;
assertBridgeSnapshot(snapshot, "created game");

const completed: string[] = [];
const promptChecks: string[] = [];
let combatExercised = false;
let combatStepSeen = false;
let aiWaits = 0;
let staleActionRecoveries = 0;
let stackSeen = false;
let arcaneCastSeen = false;
let arcaneResolvedSeen = false;
let arcanePaymentSourceSeen = false;
const turnsObserved = new Set<number>();
const actionsByType: Record<string, number> = {};
const commanderTaxChanges: Array<{ playerId: string; tax: number; turn: number }> = [];
const commanderDamageChanges: Array<{ recipient: string; attacker: string; damage: number; turn: number }> = [];

recordCommanderState(snapshot);
recordCoverage(snapshot);
console.error(`[Smoke] Started ${scenario} game ${snapshot.id}. Turn: ${snapshot.turn}, Phase: ${snapshot.phase}, Step: ${snapshot.step}`);

const maxTurns = alphaGameScenario ? 13 : fixtureScenario ? 12 : 9; // Alpha-game observes 12 full turns.
const maxStepsCount = alphaGameScenario ? 900 : fixtureScenario ? 420 : 300; // Safeguard against infinite loops.
let stepCount = 0;

while (snapshot.turn < maxTurns && stepCount < maxStepsCount) {
  stepCount++;

  // 1. Check if game has ended
  const humanPlayer = snapshot.players?.find(p => p.playerId === humanPlayerId);
  const aiPlayer = snapshot.players?.find(p => p.playerId === aiPlayerId);
  if (humanPlayer && typeof humanPlayer.life === "number" && humanPlayer.life <= 0) {
    console.error(`[Smoke] Game ended: Human life is ${humanPlayer.life}`);
    break;
  }
  if (aiPlayer && typeof aiPlayer.life === "number" && aiPlayer.life <= 0) {
    console.error(`[Smoke] Game ended: AI life is ${aiPlayer.life}`);
    break;
  }

  // 2. Track commander tax and damage from authoritative XMage snapshots.
  recordCommanderState(snapshot);
  recordCoverage(snapshot);

  if (scenarioSatisfied()) {
    console.error(`[Smoke] ${scenario} scenario satisfied at turn ${snapshot.turn}, step ${snapshot.step}`);
    break;
  }

  // 3. Check if human has legal actions
  const actionable = snapshot.legalActions?.some(a => a.type !== "concede") ?? false;
  const isHumanActive = snapshot.priorityPlayerId === humanPlayerId || snapshot.waitingOnPlayerId === humanPlayerId || actionable;

  if (isHumanActive) {
    const action = chooseBestAction(snapshot);
    if (!action) {
      console.error(`[Smoke] Human has priority/actions but no best action was chosen. Legal: ${formatActions(snapshot)}`);
      // Fallback: wait a bit and refresh
      await new Promise(resolve => setTimeout(resolve, 1000));
      snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}`);
      continue;
    }

    console.error(`[Smoke] Turn ${snapshot.turn} (${snapshot.phase} - ${snapshot.step}): Executing human action: ${action.type} (label: ${action.label ?? "none"})`);
    actionsByType[action.type] = (actionsByType[action.type] ?? 0) + 1;
    
    // Check if combat is exercised
    if (action.type === "declare_attackers" || action.type === "declare_blockers") {
      combatExercised = true;
    }
    if (arcaneSignetScenario && action.type === "cast_spell" && /arcane signet/i.test(action.label ?? action.cardName ?? "")) {
      arcaneCastSeen = true;
    }
    if (arcaneSignetScenario && action.type === "make_mana" && snapshot.promptEnvelopeV2 && isManaOrPaymentPrompt(snapshot)) {
      arcanePaymentSourceSeen = true;
    }

    if (snapshot.promptEnvelopeV2) {
      const pKey = `${snapshot.promptEnvelopeV2.method ?? "unknown"}:${snapshot.promptEnvelopeV2.responseKind ?? "unknown"}`;
      if (!promptChecks.includes(pKey)) {
        promptChecks.push(pKey);
      }
    }

    const previous = snapshot;
    snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}/commands`, {
      method: "POST",
      body: commandFromAction(snapshot.id, action, snapshot)
    });
    if (snapshot.staleActionRecovered) {
      delete snapshot.staleActionRecovered;
      staleActionRecoveries++;
      console.error(`[Smoke] Refreshed after stale ${action.type}; choosing next live action.`);
      continue;
    }

    const semanticLabel = action.type === "play_land"
      ? "play land"
      : action.type === "make_mana"
        ? "make mana"
        : action.type === "cast_spell"
          ? "cast simple spell"
          : action.type === "declare_attackers" || action.type === "declare_blockers"
            ? "combat"
          : action.type === "pass_priority" || action.type === "pass_until_response" || action.type === "pass_until_next_turn"
            ? "pass priority"
            : "resolve prompt";
            
    snapshot = await waitForSemanticProgress(previous, snapshot, semanticLabel);
    assertBridgeSnapshot(snapshot, `action: ${action.type}`);
    assertBridgeProgress(previous, snapshot, `action: ${action.type}`);
    assertSemanticProgress(previous, snapshot, semanticLabel);
    recordCommanderState(snapshot);
    recordCoverage(snapshot);
    completed.push(`[Turn ${previous.turn} ${previous.phase}] ${action.type}: ${action.label ?? "none"}`);
  } else {
    // 4. Waiting for AI priority
    if (snapshot.waitingOnPlayerId === aiPlayerId || snapshot.priorityPlayerId === aiPlayerId) {
      aiWaits++;
      console.error(`[Smoke] Waiting for AI priority... turn ${snapshot.turn}, phase ${snapshot.phase}, step ${snapshot.step}`);
      snapshot = await waitForAiIfNeeded(snapshot, "wait for AI priority");
      recordCoverage(snapshot);
    } else {
      // General wait and refresh
      await new Promise(resolve => setTimeout(resolve, 1000));
      snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}`);
      recordCoverage(snapshot);
    }
  }
}

recordCommanderState(snapshot);
recordCoverage(snapshot);

if (scenario === "combat" && !combatExercised) {
  throw new Error(
    "[Smoke] combat scenario did not exercise real declare_attackers/declare_blockers actions.\n"
      + smokeDebug("combat scenario final snapshot", snapshot)
  );
}

if (scenario === "commander-state") {
  if (commanderTaxChanges.length === 0) {
    throw new Error(
      "[Smoke] commander-state scenario did not observe commander tax from XMage rules text.\n"
        + smokeDebug("commander tax final snapshot", snapshot)
    );
  }
  if (commanderDamageChanges.length === 0) {
    throw new Error(
      "[Smoke] commander-state scenario did not observe commander damage from XMage rules text.\n"
        + smokeDebug("commander damage final snapshot", snapshot)
    );
  }
}

if (scenario === "arcane-signet") {
  if (!arcaneCastSeen) {
    throw new Error(
      "[Smoke] arcane-signet scenario did not cast Arcane Signet from an XMage legal action.\n"
        + smokeDebug("arcane cast final snapshot", snapshot)
    );
  }
  if (!arcanePaymentSourceSeen) {
    throw new Error(
      "[Smoke] arcane-signet scenario did not expose source make_mana actions during payment.\n"
        + smokeDebug("arcane payment final snapshot", snapshot)
    );
  }
  if (!arcaneResolvedSeen) {
    throw new Error(
      "[Smoke] arcane-signet scenario did not observe Arcane Signet leaving hand and resolving to the battlefield.\n"
        + smokeDebug("arcane resolution final snapshot", snapshot)
    );
  }
}

if (scenario === "alpha-game") {
  const alphaFailures = [
    turnsObserved.size >= 12 ? "" : `observed ${turnsObserved.size}/12 turns`,
    actionsByType.keep_hand || actionsByType.mulligan ? "" : "opening-hand decision missing",
    actionsByType.play_land ? "" : "play_land missing",
    actionsByType.make_mana ? "" : "make_mana missing",
    actionsByType.cast_spell ? "" : "cast_spell missing",
    actionsByType.pass_priority || actionsByType.pass_until_response || actionsByType.pass_until_next_turn || actionsByType.advance_phase ? "" : "pass/advance action missing",
    aiWaits > 0 ? "" : "AI wait/progress missing",
    combatStepSeen ? "" : "combat step not observed"
  ].filter(Boolean);
  if (alphaFailures.length > 0) {
    throw new Error(
      `[Smoke] alpha-game scenario did not satisfy real-game coverage: ${alphaFailures.join(", ")}.\n`
        + smokeDebug("alpha-game final snapshot", snapshot)
    );
  }
}

if (stepCount >= maxStepsCount) {
  throw new Error(
    `[Smoke] hit maximum loop safeguards (${maxStepsCount} steps).\n`
      + smokeDebug("max step snapshot", snapshot)
  );
}

console.error(`[Smoke] Play loop finished at turn ${snapshot.turn}. Saving report...`);

// Produce final JSON summary report
const summaryReport = {
  endpoint,
  scenario,
  health,
  gameId: snapshot.id,
  source: snapshot.source ?? "gateway",
  bridgeRevision: snapshot.bridgeRevision ?? null,
  xmageCycle: snapshot.xmageCycle ?? null,
  phase: snapshot.phase,
  step: snapshot.step,
  turn: snapshot.turn,
  promptText: snapshot.promptText,
  promptChecks,
  completed,
  turnsObserved: Array.from(turnsObserved).sort((a, b) => a - b),
  actionsByType,
  staleActionRecoveries,
  aiWaits,
  stackSeen,
  combatStepSeen,
  combatExercised,
  arcaneSignet: {
    castSeen: arcaneCastSeen,
    paymentSourceSeen: arcanePaymentSourceSeen,
    resolvedSeen: arcaneResolvedSeen
  },
  commanderTaxChanges,
  commanderDamageChanges,
  players: snapshot.players?.map((player: SmokePlayer) => ({
    playerId: player.playerId,
    life: player.life,
    commanderTax: player.commanderTax ?? 0,
    commanderDamage: player.commanderDamage ?? {},
    library: player.zones?.library?.length ?? 0,
    hand: player.zones?.hand?.length ?? 0,
    battlefield: player.zones?.battlefield?.length ?? 0,
    command: player.zones?.command?.map((card) => card.card?.name) ?? []
  })),
  legalActions: snapshot.legalActions?.map((action: SmokeAction) => action.type).slice(0, 12) ?? []
};

// Write to smoke-report.json in apps/xmage-gateway
const reportPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "../smoke-report.json");
fs.writeFileSync(reportPath, JSON.stringify(summaryReport, null, 2), "utf8");
console.error(`[Smoke] Report saved to ${reportPath}`);

// Output summary JSON report to stdout
console.log(JSON.stringify(summaryReport, null, 2));

async function request(path: string, options: { method?: string; body?: unknown } = {}) {
  const response = await fetch(`${endpoint}${path}`, {
    method: options.method ?? "GET",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: options.body === undefined ? undefined : JSON.stringify(options.body)
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) {
    if (response.status === 409 && body?.error === "action_no_longer_legal" && body.snapshot) {
      console.error(`[Smoke] Recovered from stale action on ${path}: ${body.message ?? body.error}`);
      body.snapshot.staleActionRecovered = true;
      return body.snapshot;
    }
    throw new Error(`XMage smoke request failed (${response.status}) ${path}: ${text}`);
  }
  return body;
}

function commanderFixtureDeck(commander: string, basic: string) {
  return {
    name: `${commander} Fixture`,
    commander: { cardName: commander, quantity: 1, section: "commander" },
    entries: [{ cardName: basic, quantity: 99, section: "deck" }]
  };
}

function arcaneSignetFixtureDeck() {
  return {
    name: "Arcane Signet Payment Fixture",
    commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
    // Smoke-only bridge stress fixture. Product deck legality remains validated
    // through the normal Commander import/build path; this keeps the payment
    // scenario deterministic enough to catch command-flow regressions.
    entries: [
      { cardName: "Arcane Signet", quantity: 24, section: "deck" },
      { cardName: "Plains", quantity: 75, section: "deck" }
    ]
  };
}

function findAction(snapshot: SmokeSnapshot, type: string | string[], label = "") {
  const types = Array.isArray(type) ? type : [type];
  const matches = snapshot.legalActions?.filter((action) => types.includes(action.type)) ?? [];
  if (label === "choose starting player") {
    return matches.find((action) => /you start/i.test(action.label ?? "")) ?? matches[0];
  }
  if (types.includes("play_mana")) {
    return matches.find((action) => action.manaType === "G" || /\{G\}| G$|Choose G/i.test(action.label ?? "")) ?? matches[0];
  }
  return matches[0];
}

function chooseBestAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  if (!snapshot.legalActions || snapshot.legalActions.length === 0) {
    return undefined;
  }

  // 1. Active prompt responses from promptEnvelopeV2
  if (snapshot.promptEnvelopeV2) {
    const expected = snapshot.promptEnvelopeV2.responseCommand?.type ?? snapshot.promptEnvelopeV2.responseKind;
    console.error(`[Smoke] Prompt envelope active: ${snapshot.promptEnvelopeV2.method} expecting ${expected}`);

    // Order items/triggers
    const orderAction = snapshot.legalActions.find(a => a.type === "order_triggers" || a.type === "order_items");
    if (orderAction) return orderAction;

    // Search select / choose card/pile/player
    const selectAction = snapshot.legalActions.find(a => 
      a.type === "search_select" || 
      a.type === "choose_card" || 
      a.type === "choose_pile" || 
      a.type === "choose_player"
    );
    if (selectAction) return selectAction;

    // Play/choose/make mana prompts
    if (expected === "play_mana" || expected === "mana" || expected === "choose_mana") {
      const sourceManaAction = snapshot.legalActions.find(a => a.type === "make_mana");
      if (sourceManaAction) return sourceManaAction;
      const playManaActions = snapshot.legalActions.filter(a => a.type === "play_mana" || a.type === "choose_mana");
      if (playManaActions.length > 0) {
        const green = playManaActions.find(a => a.manaType === "G" || /\{G\}| G$|Choose G/i.test(a.label ?? ""));
        return green ?? playManaActions[0];
      }
    }

    // Yes/No / Pay Cost / Confirmation / Commander replacement
    if (expected === "answer_yes_no" || expected === "pay_cost" || expected === "confirmation" || expected === "commander_replacement") {
      const yesNo = snapshot.legalActions.find(a => 
        a.type === "answer_yes_no" || 
        a.type === "keep_hand" || 
        a.type === "commander_replacement" || 
        a.type === "pay_cost"
      );
      if (yesNo) return yesNo;
    }

    // Targets picker
    if (expected === "choose_target" || expected === "resolve_choice") {
      const promptTarget = choosePromptTarget(snapshot);
      if (promptTarget) return promptTarget;
      const target = snapshot.legalActions.find(a => 
        a.type === "choose_target" || 
        a.type === "resolve_choice" || 
        a.type === "choose_card" || 
        a.type === "choose_player"
      );
      if (target) {
        if (/you start/i.test(target.label ?? "")) return target;
        return target;
      }
    }

    // Choose amount / multi amount
    const amountAction = snapshot.legalActions.find(a => 
      a.type === "choose_amount" || 
      a.type === "choose_multi_amount" || 
      a.type === "play_x_mana"
    );
    if (amountAction) return amountAction;

    // Choose mode/ability
    const modeAction = snapshot.legalActions.find(a => a.type === "choose_mode" || a.type === "choose_ability");
    if (modeAction) return modeAction;

    // If there is any legal action that matches type or responseKind directly
    const directMatch = snapshot.legalActions.find(a => a.type === expected || a.responseKind === expected);
    if (directMatch) return directMatch;
  }

  // 2. Keep opening hand
  const keepHand = snapshot.legalActions.find(a => a.type === "keep_hand");
  if (keepHand) return keepHand;

  if (fixtureScenario) {
    const fixtureAction = chooseFixtureAction(snapshot);
    if (fixtureAction) return fixtureAction;
  }

  // 3. Play land
  const playLand = snapshot.legalActions.find(a => a.type === "play_land");
  if (playLand) return playLand;

  // 4. Make mana (tap untapped land/creature for mana)
  const makeMana = snapshot.legalActions.find(a => a.type === "make_mana");
  if (makeMana) return makeMana;

  // 5. Cast spells (prefer non-commander spells from hand first, then commander if we have mana)
  const castSpell = snapshot.legalActions.find(a => a.type === "cast_spell");
  if (castSpell) return castSpell;

  // 6. Declare attackers
  const attackers = snapshot.legalActions.find(a => a.type === "declare_attackers");
  if (attackers) return attackers;

  // 7. Declare blockers
  const blockers = snapshot.legalActions.find(a => a.type === "declare_blockers");
  if (blockers) return blockers;

  // 8. Pass priority / next phase. Prefer this before optional activated abilities
  // so the smoke runner does not loop on equipment or utility permanents.
  const pass = snapshot.legalActions.find(a => a.type === "pass_priority" || a.type === "pass_until_response" || a.type === "advance_phase");
  if (pass) return pass;

  // 9. Activate abilities on battlefield permanents only when no pass action exists.
  const activateAbility = snapshot.legalActions.find(a => a.type === "activate_ability");
  if (activateAbility) return activateAbility;

  // 10. Fallback
  const fallback = snapshot.legalActions.find(a => a.type !== "concede");
  if (fallback) return fallback;

  return undefined;
}

function chooseFixtureAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  if (arcaneSignetScenario) {
    const arcaneAction = chooseArcaneSignetAction(snapshot);
    if (arcaneAction) return arcaneAction;
  }

  const actions = snapshot.legalActions ?? [];
  const battlefieldNames = humanZone(snapshot, "battlefield").map((entry) => entry.card?.name ?? "");
  const hasIsamaru = battlefieldNames.includes("Isamaru, Hound of Konda");
  const hasLand = humanZone(snapshot, "battlefield").some((entry) => /plains/i.test(entry.card?.name ?? ""));

  if (!hasLand) {
    const land = actions.find((action) => action.type === "play_land" && /plains/i.test(action.cardName ?? action.label ?? ""));
    if (land) return land;
  }

  if (!hasIsamaru) {
    const castCommander = actions.find((action) =>
      action.type === "cast_spell"
      && ((action.sourceZone ?? action.commandTemplate?.sourceZone) === "command" || /isamaru/i.test(action.cardName ?? action.label ?? ""))
    );
    if (castCommander) return castCommander;

    const makeWhite = actions.find((action) =>
      action.type === "make_mana"
      && ((action.producedMana ?? action.commandTemplate?.producedMana ?? []).includes("W")
        || /plains|white|\{w\}/i.test(action.cardName ?? action.label ?? ""))
    );
    if (makeWhite) return makeWhite;

    const makeMana = actions.find((action) => action.type === "make_mana");
    if (makeMana) return makeMana;
  }

  const attacker = actions.find((action) => action.type === "declare_attackers" && /isamaru/i.test(action.label ?? action.cardName ?? ""))
    ?? actions.find((action) => action.type === "declare_attackers");
  if (attacker) return attacker;

  const blocker = actions.find((action) => action.type === "declare_blockers");
  if (blocker) return blocker;

  return undefined;
}

function chooseArcaneSignetAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  const actions = snapshot.legalActions ?? [];
  const battlefield = humanZone(snapshot, "battlefield");
  const landCount = battlefield.filter((entry) => /land/i.test(entry.card?.typeLine ?? "") || /plains/i.test(entry.card?.name ?? "")).length;
  const hasArcaneInHand = humanZone(snapshot, "hand").some((entry) => /arcane signet/i.test(entry.card?.name ?? ""));

  if (snapshot.promptEnvelopeV2 && isManaOrPaymentPrompt(snapshot)) {
    const sourceMana = actions.find((action) => action.type === "make_mana");
    if (sourceMana) return sourceMana;
    const pay = actions.find((action) => action.type === "pay_cost" && action.pay !== false);
    if (pay) return pay;
    const mana = actions.find((action) => action.type === "play_mana" || action.type === "choose_mana");
    if (mana) return mana;
  }

  if (landCount < 2) {
    const land = actions.find((action) => action.type === "play_land" && /plains/i.test(action.cardName ?? action.label ?? ""));
    if (land) return land;
  }

  if (landCount >= 2 && hasArcaneInHand) {
    const castArcane = actions.find((action) =>
      action.type === "cast_spell" && /arcane signet/i.test(action.cardName ?? action.label ?? "")
    );
    if (castArcane) return castArcane;
  }

  return actions.find((action) =>
    action.type === "pass_priority" || action.type === "pass_until_response" || action.type === "pass_until_next_turn" || action.type === "advance_phase"
  );
}

function choosePromptTarget(snapshot: SmokeSnapshot): SmokeAction | undefined {
  const actions = snapshot.legalActions?.filter(a =>
    a.type === "choose_target"
      || a.type === "resolve_choice"
      || a.type === "choose_card"
      || a.type === "search_select"
  ) ?? [];
  if (actions.length === 0) return undefined;

  const message = `${snapshot.promptText ?? ""} ${snapshot.promptEnvelopeV2?.message ?? ""}`.toLowerCase();
  if (message.includes("starting player")) {
    return actions.find((action) => /you start/i.test(action.label ?? "")) ?? actions[0];
  }
  const requestedCardName = requestedCardNameFromPrompt(message);
  if (requestedCardName) {
    const requested = actions.find((action) => actionName(action).toLowerCase() === requestedCardName)
      ?? actions.find((action) => actionName(action).toLowerCase().includes(requestedCardName));
    if (requested) return requested;
  }
  if (message.includes("basic land")) {
    return multiChoiceAction(snapshot, actions, actions.filter(isBasicLandAction))
      ?? multiChoiceAction(snapshot, actions, actions.filter((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? "")))
      ?? actions.find(isBasicLandAction)
      ?? actions.find((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? ""))
      ?? actions[0];
  }
  if (message.includes("land card")) {
    return multiChoiceAction(snapshot, actions, actions.filter((action) => /land/i.test(action.typeLine ?? "")))
      ?? multiChoiceAction(snapshot, actions, actions.filter((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? "")))
      ?? actions.find((action) => /land/i.test(action.typeLine ?? ""))
      ?? actions.find((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? ""))
      ?? actions[0];
  }
  if (message.includes("creature")) {
    return actions.find((action) => /creature/i.test(action.typeLine ?? "")) ?? actions[0];
  }
  return actions[0];
}

function multiChoiceAction(snapshot: SmokeSnapshot, actions: SmokeAction[], matches: SmokeAction[]) {
  const maxChoices = snapshot.promptEnvelopeV2?.maxChoices ?? 1;
  if (maxChoices <= 1 || matches.length < maxChoices) {
    return undefined;
  }
  const first = matches[0];
  const targetIds = matches
    .map((action) => action.cardInstanceId ?? action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.id?.replace(/^xmage-choice-/, ""))
    .filter((id): id is string => Boolean(id))
    .slice(0, maxChoices);
  if (targetIds.length < maxChoices) {
    return undefined;
  }
  return {
    ...first,
    label: `Choose ${targetIds.length} ${actionName(first).replace(/^Choose /i, "")} cards`,
    targetIds,
    cardInstanceIds: first.type === "choose_card" || first.type === "search_select" ? targetIds : first.cardInstanceIds,
    commandTemplate: {
      ...(first.commandTemplate ?? {}),
      targetIds
    }
  };
}

function requestedCardNameFromPrompt(message: string) {
  const match = message.match(/\bselect(?: an?| one)? ([a-z0-9,' -]+?) card\b/i)
    ?? message.match(/\bchoose(?: an?| one)? ([a-z0-9,' -]+?) card\b/i);
  const requested = match?.[1]?.trim().toLowerCase();
  if (!requested || ["a", "an", "one", "target", "creature", "land", "basic land", "card"].includes(requested)) {
    return undefined;
  }
  return requested;
}

function actionName(action: SmokeAction) {
  return action.cardName ?? action.label ?? "";
}

function isBasicLandAction(action: SmokeAction) {
  if (action.isBasicLand) return true;
  return /basic land/i.test(action.typeLine ?? "")
    || /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? "");
}

async function waitForAction(snapshot: SmokeSnapshot, type: string | string[], optional = false, label = "") {
  let current = snapshot;
  const deadline = Date.now() + (optional ? 10000 : 30000);
  while (true) {
    const action = findAction(current, type, label);
    if (action || Date.now() >= deadline) {
      return { snapshot: current, action };
    }
    await new Promise((resolve) => setTimeout(resolve, 750));
    current = await request(`/games/${encodeURIComponent(current.id)}`);
  }
}

async function waitForAiIfNeeded(snapshot: SmokeSnapshot, label: string) {
  if (snapshot.waitingOnPlayerId !== aiPlayerId && snapshot.priorityPlayerId !== aiPlayerId) {
    return snapshot;
  }
  console.error(`[Smoke] Waiting for AI priority... active priority player: ${snapshot.priorityPlayerId}, waiting on: ${snapshot.waitingOnPlayerId}`);
  let current = snapshot;
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    current = await request(`/games/${encodeURIComponent(current.id)}`);
    const actionable = current.legalActions?.some((action) => action.type !== "concede") ?? false;
    if (current.waitingOnPlayerId !== aiPlayerId || current.priorityPlayerId !== aiPlayerId || actionable) {
      console.error(`[Smoke] AI finished or action became available. New priority: ${current.priorityPlayerId}`);
      return current;
    }
  }
  throw new Error(
    `XMage smoke ${label} timed out waiting for AI progress.\n`
      + smokeDebug(`AI stalled during ${label}`, current)
  );
}

async function waitForSemanticProgress(previous: SmokeSnapshot, next: SmokeSnapshot, label: string) {
  let current = next;
  const deadline = Date.now() + 10000;
  while (!hasSemanticProgress(previous, current, label) && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 750));
    current = await request(`/games/${encodeURIComponent(current.id)}`);
  }
  return current;
}

function commandFromAction(gameId: string, action: SmokeAction, snapshot: SmokeSnapshot) {
  const template = action.commandTemplate ?? {};

  // Determine max choices allowed by prompt
  let maxChoices = 1;
  if (snapshot.promptEnvelopeV2) {
    maxChoices = snapshot.promptEnvelopeV2.maxChoices ?? 1;
  }

  // Helper to slice array to maxChoices if needed
  const sliceToMax = (arr: string[] | undefined) => {
    if (!arr) return [];
    if (maxChoices > 0 && arr.length > maxChoices) {
      return arr.slice(0, maxChoices);
    }
    return arr;
  };

  const rawTargetIds = action.targetIds ?? action.validTargetIds ?? template.targetIds ?? template.choiceIds ?? [];
  const targetIds = sliceToMax(rawTargetIds);

  const rawCardInstanceIds = action.cardInstanceIds ?? action.validCardInstanceIds ?? template.cardInstanceIds ?? rawTargetIds;
  const cardInstanceIds = sliceToMax(rawCardInstanceIds);

  const rawPlayerIds = action.playerIds ?? action.validPlayerIds ?? template.playerIds ?? rawTargetIds;
  const playerIds = sliceToMax(rawPlayerIds);

  const rawChoiceIds = action.choiceIds ?? template.choiceIds ?? rawTargetIds;
  const choiceIds = sliceToMax(rawChoiceIds);

  const rawModeIds = action.modeIds ?? template.modeIds ?? rawTargetIds;
  const modeIds = sliceToMax(rawModeIds);

  return {
    ...template,
    type: action.type ?? template.type,
    gameId,
    playerId: action.playerId ?? template.playerId ?? humanPlayerId,
    promptId: action.promptId ?? template.promptId,
    messageId: action.messageId ?? template.messageId,
    cardInstanceId: action.cardInstanceId ?? template.cardInstanceId,
    sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId ?? template.sourceInstanceId ?? template.cardInstanceId,
    abilityId: action.abilityId ?? template.abilityId,
    choiceIds,
    targetIds,
    cardInstanceIds,
    modeIds,
    playerIds,
    manaType: action.manaType ?? template.manaType,
    manaTypes: action.manaTypes ?? template.manaTypes,
    orderedIds: action.orderedIds ?? template.orderedIds ?? targetIds,
    confirmed: action.confirmed ?? template.confirmed ?? true,
    pay: action.pay ?? template.pay ?? action.confirmed ?? template.confirmed ?? true,
    amount: action.amount ?? template.amount,
    amounts: action.amounts ?? template.amounts,
    pile: action.pile ?? template.pile,
    useCommandZone: action.useCommandZone ?? template.useCommandZone,
    attackers: action.attackers ?? template.attackers,
    blockers: action.blockers ?? template.blockers
  };
}

function assertBridgeProgress(
  previous: SmokeSnapshot,
  next: SmokeSnapshot,
  label: string,
  options: { allowEqual?: boolean } = {}
) {
  const revisionAdvanced = advanced(previous.bridgeRevision, next.bridgeRevision, options.allowEqual);
  const cycleAdvanced = advanced(previous.xmageCycle, next.xmageCycle, options.allowEqual);
  if (!revisionAdvanced && !cycleAdvanced) {
    throw new Error(
      `XMage smoke ${label} did not advance bridgeRevision or xmageCycle: `
        + `${previous.bridgeRevision ?? "n/a"} -> ${next.bridgeRevision ?? "n/a"}, `
        + `${previous.xmageCycle ?? "n/a"} -> ${next.xmageCycle ?? "n/a"}`
    );
  }
}

function assertBridgeSnapshot(snapshot: SmokeSnapshot, label: string) {
  if (snapshot.source !== "xmage-java-bridge") {
    throw new Error(`XMage smoke ${label} did not return a Java bridge snapshot. Source: ${snapshot.source ?? "missing"}`);
  }
  if (typeof snapshot.bridgeRevision !== "number") {
    throw new Error(`XMage smoke ${label} did not include numeric bridgeRevision.`);
  }
}

function assertSemanticProgress(previous: SmokeSnapshot, next: SmokeSnapshot, label: string) {
  if (hasSemanticProgress(previous, next, label)) {
    return;
  }
  if (label === "play land") {
    throw new Error(`XMage smoke play land did not increase human battlefield count: ${humanZone(previous, "battlefield").length} -> ${humanZone(next, "battlefield").length}`);
  }
  if (label === "make mana") {
    throw new Error(
      `XMage smoke make mana did not increase human mana pool: ${manaTotal(previous)} -> ${manaTotal(next)}\n`
        + smokeDebug("before make_mana", previous)
        + "\n"
        + smokeDebug("after make_mana", next)
    );
  }
  if (label === "cast simple spell") {
    throw new Error("XMage smoke cast simple spell did not change hand, board, graveyard, stack, mana, or prompt state.");
  }
  if (label === "pass priority") {
    throw new Error(
      "XMage smoke pass priority did not change priority, phase/step, prompt state, or visible game zones.\n"
        + smokeDebug("before pass_priority", previous)
        + "\n"
        + smokeDebug("after pass_priority", next)
    );
  }
}

function hasSemanticProgress(previous: SmokeSnapshot, next: SmokeSnapshot, label: string) {
  if (label === "play land") {
    return humanZone(next, "battlefield").length > humanZone(previous, "battlefield").length;
  }
  if (label === "make mana") {
    return manaTotal(next) > manaTotal(previous)
      || humanZone(previous, "battlefield").some((beforeCard) => {
        const afterCard = humanZone(next, "battlefield").find((card) => card.instanceId === beforeCard.instanceId);
        return beforeCard.tapped !== true && afterCard?.tapped === true;
      })
      || previous.promptEnvelopeV2?.id !== next.promptEnvelopeV2?.id
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || previous.bridgeRevision !== next.bridgeRevision
      || previous.xmageCycle !== next.xmageCycle;
  }
  if (label === "cast simple spell") {
    return humanZone(previous, "hand").length !== humanZone(next, "hand").length
      || humanZone(previous, "battlefield").length !== humanZone(next, "battlefield").length
      || humanZone(previous, "graveyard").length !== humanZone(next, "graveyard").length
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || manaTotal(previous) !== manaTotal(next)
      || next.promptEnvelopeV2 !== undefined;
  }
  if (label === "combat") {
    return previous.step !== next.step
      || previous.phase !== next.phase
      || previous.turn !== next.turn
      || previous.priorityPlayerId !== next.priorityPlayerId
      || previous.waitingOnPlayerId !== next.waitingOnPlayerId
      || JSON.stringify(previous.xmage?.combat ?? null) !== JSON.stringify(next.xmage?.combat ?? null)
      || JSON.stringify(humanZone(previous, "battlefield")) !== JSON.stringify(humanZone(next, "battlefield"))
      || JSON.stringify(next.players?.map((player) => player.life)) !== JSON.stringify(previous.players?.map((player) => player.life))
      || previous.bridgeRevision !== next.bridgeRevision
      || previous.xmageCycle !== next.xmageCycle;
  }
  if (label === "pass priority") {
    return previous.priorityPlayerId !== next.priorityPlayerId
      || previous.waitingOnPlayerId !== next.waitingOnPlayerId
      || previous.step !== next.step
      || previous.phase !== next.phase
      || previous.turn !== next.turn
      || previous.promptText !== next.promptText
      || humanZone(previous, "hand").length !== humanZone(next, "hand").length
      || humanZone(previous, "battlefield").length !== humanZone(next, "battlefield").length
      || humanZone(previous, "graveyard").length !== humanZone(next, "graveyard").length
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || manaTotal(previous) !== manaTotal(next)
      || formatActions(previous) !== formatActions(next)
      || next.promptEnvelopeV2 !== undefined
      || previous.bridgeRevision !== next.bridgeRevision
      || previous.xmageCycle !== next.xmageCycle;
  }
  if (label === "resolve prompt") {
    return previous.promptEnvelopeV2?.id !== next.promptEnvelopeV2?.id
      || previous.promptEnvelopeV2?.messageId !== next.promptEnvelopeV2?.messageId
      || formatActions(previous) !== formatActions(next)
      || previous.bridgeRevision !== next.bridgeRevision
      || previous.xmageCycle !== next.xmageCycle;
  }
  return true;
}

function advanced(before: unknown, after: unknown, allowEqual = false) {
  if (typeof before !== "number" || typeof after !== "number") return;
  return allowEqual ? after >= before : after > before;
}

function hasPromptResponseAction(snapshot: SmokeSnapshot) {
  const expected = snapshot.promptEnvelopeV2?.responseCommand?.type;
  if (!expected) return Boolean(snapshot.legalActions?.length);
  return snapshot.legalActions?.some((action) =>
    action.type === expected
    || action.responseKind === expected
    || (expected === "choose_card" && action.type === "search_select")
    || (expected === "answer_yes_no" && ["keep_hand", "mulligan", "commander_replacement"].includes(action.type))
    || (expected === "resolve_choice" && ["answer_yes_no", "choose_target", "choose_card", "choose_player"].includes(action.type))
  ) ?? false;
}

function humanZone(snapshot: SmokeSnapshot, zone: string) {
  return humanPlayer(snapshot)?.zones?.[zone] ?? [];
}

function humanPlayer(snapshot: SmokeSnapshot) {
  return snapshot.players?.find((player) => player.playerId === humanPlayerId);
}

function manaTotal(snapshot: SmokeSnapshot) {
  const pool = humanPlayer(snapshot)?.manaPool ?? {};
  return Object.values(pool).reduce((total, value) => total + (typeof value === "number" ? value : 0), 0);
}

function recordCommanderState(snapshot: SmokeSnapshot) {
  for (const player of snapshot.players ?? []) {
    if (player.commanderTax !== undefined && player.commanderTax > 0) {
      if (!commanderTaxChanges.some(t => t.playerId === player.playerId && t.tax === player.commanderTax)) {
        commanderTaxChanges.push({ playerId: player.playerId, tax: player.commanderTax, turn: snapshot.turn ?? 1 });
        console.error(`[Smoke] Witnessed Commander Tax: ${player.playerId} tax is now ${player.commanderTax} on turn ${snapshot.turn}`);
      }
    }
    for (const [oppId, dmg] of Object.entries(player.commanderDamage ?? {})) {
      if (typeof dmg === "number" && dmg > 0) {
        if (!commanderDamageChanges.some(d => d.recipient === player.playerId && d.attacker === oppId && d.damage === dmg)) {
          commanderDamageChanges.push({ recipient: player.playerId, attacker: oppId, damage: dmg, turn: snapshot.turn ?? 1 });
          console.error(`[Smoke] Witnessed Commander Damage: ${oppId} dealt ${dmg} to ${player.playerId} on turn ${snapshot.turn}`);
        }
      }
    }
  }
}

function recordCoverage(snapshot: SmokeSnapshot) {
  if (typeof snapshot.turn === "number") {
    turnsObserved.add(snapshot.turn);
  }
  const phaseStep = `${snapshot.phase ?? ""} ${snapshot.step ?? ""}`.toLowerCase();
  if (phaseStep.includes("combat") || phaseStep.includes("attack") || phaseStep.includes("block")) {
    combatStepSeen = true;
  }
  if ((snapshot.xmage?.stack as unknown[] | undefined)?.length || humanZone(snapshot, "stack").length > 0) {
    stackSeen = true;
  }
  if (arcaneSignetScenario && humanZone(snapshot, "battlefield").some((entry) => /arcane signet/i.test(entry.card?.name ?? ""))) {
    arcaneResolvedSeen = true;
  }
}

function scenarioSatisfied() {
  if (scenario === "general") {
    return turnsObserved.size >= 5
      && Boolean(actionsByType.keep_hand || actionsByType.mulligan)
      && Boolean(actionsByType.play_land)
      && Boolean(actionsByType.make_mana)
      && Boolean(actionsByType.cast_spell)
      && Boolean(actionsByType.pass_priority || actionsByType.pass_until_response || actionsByType.pass_until_next_turn || actionsByType.advance_phase)
      && aiWaits > 0
      && combatStepSeen;
  }
  if (scenario === "combat") return combatExercised;
  if (scenario === "commander-state") return commanderTaxChanges.length > 0 && commanderDamageChanges.length > 0;
  if (scenario === "arcane-signet") return arcaneCastSeen && arcanePaymentSourceSeen && arcaneResolvedSeen;
  return false;
}

function isManaOrPaymentPrompt(snapshot: SmokeSnapshot) {
  const prompt = snapshot.promptEnvelopeV2;
  if (!prompt) return false;
  const expected = `${prompt.responseCommand?.type ?? ""} ${prompt.responseKind ?? ""} ${prompt.method ?? ""} ${prompt.message ?? ""}`.toLowerCase();
  return expected.includes("mana") || expected.includes("pay") || expected.includes("cost");
}

function formatActions(snapshot: SmokeSnapshot) {
  return snapshot.legalActions?.map((action) => `${action.type}:${action.label ?? action.id}`).join(", ") || "none";
}

function smokeDebug(label: string, snapshot: SmokeSnapshot) {
  return `${label}: ${JSON.stringify({
    id: snapshot.id,
    source: snapshot.source,
    bridgeRevision: snapshot.bridgeRevision,
    xmageCycle: snapshot.xmageCycle,
    pendingStatus: snapshot.pendingStatus,
    phase: snapshot.phase,
    step: snapshot.step,
    turn: snapshot.turn,
    promptText: snapshot.promptText,
    priorityPlayerId: snapshot.priorityPlayerId,
    waitingOnPlayerId: snapshot.waitingOnPlayerId,
    humanManaPool: humanPlayer(snapshot)?.manaPool ?? {},
    humanBattlefield: humanZone(snapshot, "battlefield").map((entry) => ({
      name: entry.card?.name,
      tapped: entry.tapped,
      instanceId: entry.instanceId,
      oracleText: entry.card?.oracleText
    })),
    humanCommand: humanZone(snapshot, "command").map((entry) => ({
      name: entry.card?.name,
      oracleText: entry.card?.oracleText
    })),
    aiCommand: snapshot.players?.find((player) => player.playerId === aiPlayerId)?.zones?.command?.map((entry) => ({
      name: entry.card?.name,
      oracleText: entry.card?.oracleText
    })),
    humanHand: humanZone(snapshot, "hand").map((entry) => entry.card?.name).slice(0, 10),
    promptEnvelopeV2: snapshot.promptEnvelopeV2,
    legalActions: (snapshot.legalActions ?? []).map((action) => ({
      id: action.id,
      type: action.type,
      label: action.label,
      cardInstanceId: action.cardInstanceId,
      sourceInstanceId: action.sourceInstanceId,
      abilityId: action.abilityId,
      manaType: action.manaType,
      responseKind: action.responseKind,
      commandTemplate: action.commandTemplate
    })).slice(0, 16)
  }, null, 2)}`;
}

type SmokeSnapshot = {
  id: string;
  source?: string;
  bridgeRevision?: number;
  xmageCycle?: number;
  phase?: string;
  step?: string;
  turn?: number;
  promptText?: string;
  pendingStatus?: string;
  staleActionRecovered?: boolean;
  priorityPlayerId?: string;
  waitingOnPlayerId?: string;
  promptEnvelopeV2?: { method?: string; responseKind?: string; responseCommand?: { type?: string }; maxChoices?: number; message?: string; id?: string; messageId?: number };
  xmage?: { combat?: unknown };
  players?: SmokePlayer[];
  legalActions?: SmokeAction[];
};

type SmokePlayer = {
  playerId: string;
  life?: number;
  manaPool?: Record<string, number>;
  commanderTax?: number;
  commanderDamage?: Record<string, number>;
  zones?: Record<string, Array<{ card?: { name?: string; oracleText?: string; typeLine?: string }; tapped?: boolean; instanceId?: string }>>;
};

type SmokeAction = {
  id?: string;
  type: string;
  playerId?: string;
  label?: string;
  promptId?: string;
  messageId?: number;
  cardInstanceId?: string;
  cardName?: string;
  typeLine?: string;
  isBasicLand?: boolean;
  sourceInstanceId?: string;
  sourceZone?: string;
  abilityId?: string;
  commandTemplate?: SmokeCommandTemplate;
  responseKind?: string;
  choiceIds?: string[];
  targetIds?: string[];
  validTargetIds?: string[];
  cardInstanceIds?: string[];
  validCardInstanceIds?: string[];
  modeIds?: string[];
  playerIds?: string[];
  validPlayerIds?: string[];
  manaType?: string;
  manaTypes?: string[];
  producedMana?: string[];
  orderedIds?: string[];
  confirmed?: boolean;
  pay?: boolean;
  amount?: number;
  amounts?: number[];
  pile?: number;
  useCommandZone?: boolean;
  attackers?: Array<{ attackerId: string; defenderId: string }>;
  blockers?: Array<{ blockerId: string; attackerId: string }>;
};

type SmokeCommandTemplate = {
  type?: string;
  playerId?: string;
  promptId?: string;
  messageId?: number;
  cardInstanceId?: string;
  sourceInstanceId?: string;
  sourceZone?: string;
  abilityId?: string;
  choiceIds?: string[];
  targetIds?: string[];
  cardInstanceIds?: string[];
  modeIds?: string[];
  playerIds?: string[];
  manaType?: string;
  manaTypes?: string[];
  producedMana?: string[];
  orderedIds?: string[];
  confirmed?: boolean;
  pay?: boolean;
  amount?: number;
  amounts?: number[];
  pile?: number;
  useCommandZone?: boolean;
  attackers?: Array<{ attackerId: string; defenderId: string }>;
  blockers?: Array<{ blockerId: string; attackerId: string }>;
};
