import { generateBracketThreeCommanderDeck } from "../../../packages/deck/src";

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
const steps: Array<{ label: string; type: string | string[]; optional?: boolean }> = [
  { label: "choose starting player", type: ["resolve_choice", "choose_target"], optional: true },
  { label: "keep hand", type: "keep_hand" },
  { label: "play land", type: "play_land" },
  { label: "make mana", type: "make_mana" },
  { label: "cast simple spell", type: "cast_spell" },
  { label: "pass priority", type: "pass_priority" }
];
const completed: string[] = [];
const promptChecks: string[] = [];

for (const step of steps) {
  const waited = await waitForAction(snapshot, step.type, step.optional, step.label);
  snapshot = waited.snapshot;
  let action = waited.action;
  if (!action && step.type === "play_land") {
    const advanced = await passUntilAction(snapshot, step.type);
    snapshot = advanced.snapshot;
    action = advanced.action;
    completed.push(...advanced.completed);
  }
  if (!action && step.type === "cast_spell") {
    const prepared = await prepareUntilCastSpell(snapshot);
    snapshot = prepared.snapshot;
    action = prepared.action;
    completed.push(...prepared.completed);
  }
  if (!action && step.type === "pass_priority") {
    const resolved = await resolvePromptsUntilAction(snapshot, step.type);
    snapshot = resolved.snapshot;
    action = resolved.action;
    completed.push(...resolved.completed);
  }
  if (!action) {
    if (step.optional) continue;
    throw new Error(`XMage smoke missing ${step.label} action. Legal actions: ${formatActions(snapshot)}`);
  }

  const previous = snapshot;
  snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}/commands`, {
    method: "POST",
    body: commandFromAction(snapshot.id, action)
  });
  assertBridgeProgress(previous, snapshot, step.label);
  snapshot = await waitForSemanticProgress(previous, snapshot, step.label);
  assertSemanticProgress(previous, snapshot, step.label);
  completed.push(step.label);

  if (snapshot.promptEnvelopeV2) {
    promptChecks.push(`${snapshot.promptEnvelopeV2.method ?? "unknown"}:${snapshot.promptEnvelopeV2.responseKind ?? "unknown"}`);
    if (!hasPromptResponseAction(snapshot)) {
      throw new Error(
        "XMage promptEnvelopeV2 was present but no matching legal response action was exposed. "
          + `Expected: ${snapshot.promptEnvelopeV2.responseCommand?.type ?? snapshot.promptEnvelopeV2.responseKind ?? "unknown"}; `
          + `Actions: ${formatActions(snapshot)}; `
          + `Prompt: ${snapshot.promptEnvelopeV2.method ?? "unknown"}:${snapshot.promptEnvelopeV2.responseKind ?? "unknown"}`
      );
    }
  }
}

const refreshed = await request(`/games/${encodeURIComponent(snapshot.id)}`);
assertBridgeProgress(snapshot, refreshed, "refresh snapshot", { allowEqual: true });

console.log(JSON.stringify({
  endpoint,
  health,
  gameId: refreshed.id,
  source: refreshed.source ?? "gateway",
  bridgeRevision: refreshed.bridgeRevision ?? null,
  xmageCycle: refreshed.xmageCycle ?? null,
  phase: refreshed.phase,
  step: refreshed.step,
  turn: refreshed.turn,
  promptText: refreshed.promptText,
  promptChecks,
  completed,
  players: refreshed.players?.map((player: SmokePlayer) => ({
    playerId: player.playerId,
    life: player.life,
    library: player.zones?.library?.length ?? 0,
    hand: player.zones?.hand?.length ?? 0,
    battlefield: player.zones?.battlefield?.length ?? 0,
    command: player.zones?.command?.map((card) => card.card?.name) ?? []
  })),
  legalActions: refreshed.legalActions?.map((action: SmokeAction) => action.type).slice(0, 12) ?? []
}, null, 2));

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

async function passUntilAction(snapshot: SmokeSnapshot, type: string | string[]) {
  let current = snapshot;
  const completedPasses: string[] = [];
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const action = findAction(current, type);
    if (action) return { snapshot: current, action, completed: completedPasses };
    const pass = findAction(current, ["pass_priority", "pass_until_response"]);
    if (!pass) return { snapshot: current, action: undefined, completed: completedPasses };
    const previous = current;
    current = await request(`/games/${encodeURIComponent(current.id)}/commands`, {
      method: "POST",
      body: commandFromAction(current.id, pass)
    });
    assertBridgeProgress(previous, current, "pass toward main phase");
    completedPasses.push(`pass toward main phase ${attempt + 1}`);
    current = (await waitForAction(current, type, true)).snapshot;
  }
  return { snapshot: current, action: findAction(current, type), completed: completedPasses };
}

async function prepareUntilCastSpell(snapshot: SmokeSnapshot) {
  let current = snapshot;
  const completedPreparations: string[] = [];
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const cast = findAction(current, "cast_spell");
    if (cast) return { snapshot: current, action: cast, completed: completedPreparations };

    const prep = findAction(current, "play_land")
      ?? findAction(current, "make_mana")
      ?? findAction(current, "answer_yes_no")
      ?? findAction(current, "resolve_choice")
      ?? findAction(current, "pass_until_next_turn")
      ?? findAction(current, ["pass_priority", "pass_until_response"]);
    if (!prep) return { snapshot: current, action: undefined, completed: completedPreparations };

    const previous = current;
    current = await request(`/games/${encodeURIComponent(current.id)}/commands`, {
      method: "POST",
      body: commandFromAction(current.id, prep)
    });
    assertBridgeProgress(previous, current, `prepare cast spell ${prep.type}`);
    const semanticLabel = prep.type === "play_land"
      ? "play land"
      : prep.type === "make_mana"
        ? "make mana"
        : prep.type === "answer_yes_no" || prep.type === "resolve_choice"
          ? "resolve prompt"
          : "pass priority";
    current = await waitForSemanticProgress(previous, current, semanticLabel);
    completedPreparations.push(`prepare cast spell ${prep.type} ${attempt + 1}`);
    current = (await waitForAction(current, "cast_spell", true)).snapshot;
  }
  return { snapshot: current, action: findAction(current, "cast_spell"), completed: completedPreparations };
}

async function resolvePromptsUntilAction(snapshot: SmokeSnapshot, type: string | string[]) {
  let current = snapshot;
  const completedPrompts: string[] = [];
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const action = findAction(current, type);
    if (action) return { snapshot: current, action, completed: completedPrompts };

    const promptAction = findAction(current, "play_mana")
      ?? findAction(current, "choose_mana")
      ?? findAction(current, "answer_yes_no")
      ?? findAction(current, "resolve_choice")
      ?? findAction(current, "choose_target")
      ?? findAction(current, "choose_card");
    if (!promptAction) return { snapshot: current, action: undefined, completed: completedPrompts };

    const previous = current;
    current = await request(`/games/${encodeURIComponent(current.id)}/commands`, {
      method: "POST",
      body: commandFromAction(current.id, promptAction)
    });
    assertBridgeProgress(previous, current, `resolve prompt for ${Array.isArray(type) ? type.join("/") : type}`);
    current = await waitForSemanticProgress(previous, current, "resolve prompt");
    completedPrompts.push(`resolve prompt ${promptAction.type} ${attempt + 1}`);
    current = (await waitForAction(current, type, true)).snapshot;
  }
  return { snapshot: current, action: findAction(current, type), completed: completedPrompts };
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

function commandFromAction(gameId: string, action: SmokeAction) {
  const template = action.commandTemplate ?? {};
  const targetIds = action.targetIds ?? action.validTargetIds ?? template.targetIds ?? template.choiceIds ?? [];
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
    choiceIds: action.choiceIds ?? template.choiceIds ?? targetIds,
    targetIds,
    cardInstanceIds: action.cardInstanceIds ?? action.validCardInstanceIds ?? template.cardInstanceIds ?? targetIds,
    modeIds: action.modeIds ?? template.modeIds ?? targetIds,
    playerIds: action.playerIds ?? action.validPlayerIds ?? template.playerIds ?? targetIds,
    manaType: action.manaType ?? template.manaType,
    manaTypes: action.manaTypes ?? template.manaTypes,
    orderedIds: action.orderedIds ?? template.orderedIds ?? targetIds,
    confirmed: action.confirmed ?? template.confirmed,
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

function assertSemanticProgress(previous: SmokeSnapshot, next: SmokeSnapshot, label: string) {
  if (hasSemanticProgress(previous, next, label)) {
    return;
  }
  if (label === "play land") {
    throw new Error(`XMage smoke play land did not increase human battlefield count: ${humanZone(previous, "battlefield").length} -> ${humanZone(next, "battlefield").length}`);
  }
  if (label === "make mana") {
    throw new Error(`XMage smoke make mana did not increase human mana pool: ${manaTotal(previous)} -> ${manaTotal(next)}`);
  }
  if (label === "cast simple spell") {
    throw new Error("XMage smoke cast simple spell did not change hand, board, graveyard, stack, mana, or prompt state.");
  }
  if (label === "pass priority") {
    throw new Error("XMage smoke pass priority did not change priority, phase/step, or prompt state.");
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
      || next.promptEnvelopeV2 !== undefined;
  }
  if (label === "resolve prompt") {
    return previous.promptEnvelopeV2?.id !== next.promptEnvelopeV2?.id
      || previous.promptEnvelopeV2?.messageId !== next.promptEnvelopeV2?.messageId
      || formatActions(previous) !== formatActions(next);
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

type SmokeSnapshot = {
  id: string;
  source?: string;
  bridgeRevision?: number;
  xmageCycle?: number;
  phase?: string;
  step?: string;
  turn?: number;
  promptText?: string;
  priorityPlayerId?: string;
  waitingOnPlayerId?: string;
  promptEnvelopeV2?: { method?: string; responseKind?: string; responseCommand?: { type?: string } };
  players?: SmokePlayer[];
  legalActions?: SmokeAction[];
};

type SmokePlayer = {
  playerId: string;
  life?: number;
  manaPool?: Record<string, number>;
  zones?: Record<string, Array<{ card?: { name?: string } }>>;
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
  amount?: number;
  amounts?: number[];
  pile?: number;
  useCommandZone?: boolean;
};
