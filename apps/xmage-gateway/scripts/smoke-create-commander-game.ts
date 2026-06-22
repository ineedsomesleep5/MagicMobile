import { generateBracketThreeCommanderDeck } from "../../../packages/deck/src";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const endpoint = (process.env.XMAGE_GATEWAY_URL ?? "http://localhost:17171").replace(/\/$/, "");
const seed = process.env.XMAGE_SMOKE_SEED ?? "bridge-smoke";
const humanPlayerId = process.env.XMAGE_SMOKE_HUMAN_ID ?? "human";
const aiPlayerId = process.env.XMAGE_SMOKE_AI_ID ?? "ai-1";

const human = generateBracketThreeCommanderDeck({ seed: `${seed}:human`, playerId: humanPlayerId }).deck;
const ai = generateBracketThreeCommanderDeck({ seed: `${seed}:ai`, playerId: aiPlayerId }).deck;

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
const commanderTaxChanges: Array<{ playerId: string; tax: number; turn: number }> = [];
const commanderDamageChanges: Array<{ recipient: string; attacker: string; damage: number; turn: number }> = [];

console.error(`[Smoke] Started game ${snapshot.id}. Turn: ${snapshot.turn}, Phase: ${snapshot.phase}, Step: ${snapshot.step}`);

const maxTurns = 9; // Play until turn 9 (which completes 8 full turns)
const maxStepsCount = 300; // Safeguard against infinite loops
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

  // 2. Track commander tax and damage
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
    
    // Check if combat is exercised
    if (action.type === "declare_attackers" || action.type === "declare_blockers") {
      combatExercised = true;
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
    
    assertBridgeSnapshot(snapshot, `action: ${action.type}`);
    assertBridgeProgress(previous, snapshot, `action: ${action.type}`);
    
    const semanticLabel = action.type === "play_land"
      ? "play land"
      : action.type === "make_mana"
        ? "make mana"
        : action.type === "cast_spell"
          ? "cast simple spell"
          : action.type === "pass_priority" || action.type === "pass_until_response" || action.type === "pass_until_next_turn"
            ? "pass priority"
            : "resolve prompt";
            
    snapshot = await waitForSemanticProgress(previous, snapshot, semanticLabel);
    assertSemanticProgress(previous, snapshot, semanticLabel);
    completed.push(`[Turn ${previous.turn} ${previous.phase}] ${action.type}: ${action.label ?? "none"}`);
  } else {
    // 4. Waiting for AI priority
    if (snapshot.waitingOnPlayerId === aiPlayerId || snapshot.priorityPlayerId === aiPlayerId) {
      console.error(`[Smoke] Waiting for AI priority... turn ${snapshot.turn}, phase ${snapshot.phase}, step ${snapshot.step}`);
      snapshot = await waitForAiIfNeeded(snapshot, "wait for AI priority");
    } else {
      // General wait and refresh
      await new Promise(resolve => setTimeout(resolve, 1000));
      snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}`);
    }
  }
}

if (stepCount >= maxStepsCount) {
  console.error(`[Smoke] Warning: hit maximum loop safeguards (${maxStepsCount} steps).`);
}

console.error(`[Smoke] Play loop finished at turn ${snapshot.turn}. Saving report...`);

// Produce final JSON summary report
const summaryReport = {
  endpoint,
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
  combatExercised,
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
    throw new Error(`XMage smoke request failed (${response.status}) ${path}: ${text}`);
  }
  return body;
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

  // 3. Play land
  const playLand = snapshot.legalActions.find(a => a.type === "play_land");
  if (playLand) return playLand;

  // 4. Make mana (tap untapped land/creature for mana)
  const makeMana = snapshot.legalActions.find(a => a.type === "make_mana");
  if (makeMana) return makeMana;

  // 5. Cast spells (prefer non-commander spells from hand first, then commander if we have mana)
  const castSpell = snapshot.legalActions.find(a => a.type === "cast_spell");
  if (castSpell) return castSpell;

  // 6. Activate abilities on battlefield permanents
  const activateAbility = snapshot.legalActions.find(a => a.type === "activate_ability");
  if (activateAbility) return activateAbility;

  // 7. Declare attackers
  const attackers = snapshot.legalActions.find(a => a.type === "declare_attackers");
  if (attackers) return attackers;

  // 8. Declare blockers
  const blockers = snapshot.legalActions.find(a => a.type === "declare_blockers");
  if (blockers) return blockers;

  // 9. Pass priority / next phase
  const pass = snapshot.legalActions.find(a => a.type === "pass_priority" || a.type === "pass_until_response" || a.type === "advance_phase");
  if (pass) return pass;

  // 10. Fallback
  const fallback = snapshot.legalActions.find(a => a.type !== "concede");
  if (fallback) return fallback;

  return undefined;
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
    useCommandZone: action.useCommandZone ?? template.useCommandZone
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
    return manaTotal(next) > manaTotal(previous);
  }
  if (label === "cast simple spell") {
    return humanZone(previous, "hand").length !== humanZone(next, "hand").length
      || humanZone(previous, "battlefield").length !== humanZone(next, "battlefield").length
      || humanZone(previous, "graveyard").length !== humanZone(next, "graveyard").length
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || manaTotal(previous) !== manaTotal(next)
      || next.promptEnvelopeV2 !== undefined;
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
      instanceId: entry.instanceId
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
  priorityPlayerId?: string;
  waitingOnPlayerId?: string;
  promptEnvelopeV2?: { method?: string; responseKind?: string; responseCommand?: { type?: string }; maxChoices?: number };
  players?: SmokePlayer[];
  legalActions?: SmokeAction[];
};

type SmokePlayer = {
  playerId: string;
  life?: number;
  manaPool?: Record<string, number>;
  commanderTax?: number;
  commanderDamage?: Record<string, number>;
  zones?: Record<string, Array<{ card?: { name?: string }; tapped?: boolean; instanceId?: string }>>;
};

type SmokeAction = {
  id?: string;
  type: string;
  playerId?: string;
  label?: string;
  promptId?: string;
  messageId?: number;
  cardInstanceId?: string;
  sourceInstanceId?: string;
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
  orderedIds?: string[];
  confirmed?: boolean;
  pay?: boolean;
  amount?: number;
  amounts?: number[];
  pile?: number;
  useCommandZone?: boolean;
};

type SmokeCommandTemplate = {
  type?: string;
  playerId?: string;
  promptId?: string;
  messageId?: number;
  cardInstanceId?: string;
  sourceInstanceId?: string;
  abilityId?: string;
  choiceIds?: string[];
  targetIds?: string[];
  cardInstanceIds?: string[];
  modeIds?: string[];
  playerIds?: string[];
  manaType?: string;
  manaTypes?: string[];
  orderedIds?: string[];
  confirmed?: boolean;
  pay?: boolean;
  amount?: number;
  amounts?: number[];
  pile?: number;
  useCommandZone?: boolean;
};
