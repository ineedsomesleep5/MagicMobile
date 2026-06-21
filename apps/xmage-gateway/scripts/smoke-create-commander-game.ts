import { generateBracketThreeCommanderDeck } from "../../../packages/deck/src";

const endpoint = (process.env.XMAGE_GATEWAY_URL ?? "http://localhost:17171").replace(/\/$/, "");
const seed = process.env.XMAGE_SMOKE_SEED ?? "bridge-smoke";
const humanPlayerId = process.env.XMAGE_SMOKE_HUMAN_ID ?? "human";
const aiPlayerId = process.env.XMAGE_SMOKE_AI_ID ?? "ai-1";

const human = generateBracketThreeCommanderDeck({ seed: `${seed}:human`, playerId: humanPlayerId }).deck;
const ai = generateBracketThreeCommanderDeck({ seed: `${seed}:ai`, playerId: aiPlayerId }).deck;

const health = await request("/health");
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
  const waited = await waitForAction(snapshot, step.type, step.optional);
  snapshot = waited.snapshot;
  let action = waited.action;
  if (!action && step.type === "play_land") {
    const advanced = await passUntilAction(snapshot, step.type);
    snapshot = advanced.snapshot;
    action = advanced.action;
    completed.push(...advanced.completed);
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
  completed.push(step.label);

  if (snapshot.promptEnvelopeV2) {
    promptChecks.push(`${snapshot.promptEnvelopeV2.method ?? "unknown"}:${snapshot.promptEnvelopeV2.responseKind ?? "unknown"}`);
    if (!snapshot.legalActions?.length) {
      throw new Error("XMage promptEnvelopeV2 was present but no legal response action was exposed.");
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

function findAction(snapshot: SmokeSnapshot, type: string | string[]) {
  const types = Array.isArray(type) ? type : [type];
  return snapshot.legalActions?.find((action) => types.includes(action.type));
}

async function waitForAction(snapshot: SmokeSnapshot, type: string | string[], optional = false) {
  let current = snapshot;
  const deadline = Date.now() + (optional ? 500 : 30000);
  while (true) {
    const action = findAction(current, type);
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

function commandFromAction(gameId: string, action: SmokeAction) {
  const targetIds = action.targetIds ?? action.validTargetIds ?? [];
  return {
    type: action.type,
    gameId,
    playerId: action.playerId ?? humanPlayerId,
    cardInstanceId: action.cardInstanceId,
    sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId,
    abilityId: action.abilityId ?? action.commandTemplate?.abilityId,
    choiceIds: targetIds,
    targetIds,
    cardInstanceIds: action.cardInstanceIds ?? targetIds,
    modeIds: action.modeIds ?? targetIds,
    playerIds: action.playerIds ?? action.validPlayerIds ?? targetIds,
    manaTypes: action.manaTypes,
    orderedIds: action.orderedIds ?? targetIds,
    confirmed: action.confirmed,
    amount: action.amount,
    amounts: action.amounts,
    pile: action.pile,
    useCommandZone: action.useCommandZone
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

function advanced(before: unknown, after: unknown, allowEqual = false) {
  if (typeof before !== "number" || typeof after !== "number") return;
  return allowEqual ? after >= before : after > before;
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
  promptEnvelopeV2?: { method?: string; responseKind?: string };
  players?: SmokePlayer[];
  legalActions?: SmokeAction[];
};

type SmokePlayer = {
  playerId: string;
  life?: number;
  zones?: Record<string, Array<{ card?: { name?: string } }>>;
};

type SmokeAction = {
  id?: string;
  type: string;
  playerId?: string;
  label?: string;
  cardInstanceId?: string;
  sourceInstanceId?: string;
  abilityId?: string;
  commandTemplate?: { abilityId?: string };
  responseKind?: string;
  targetIds?: string[];
  validTargetIds?: string[];
  cardInstanceIds?: string[];
  modeIds?: string[];
  playerIds?: string[];
  validPlayerIds?: string[];
  manaTypes?: string[];
  orderedIds?: string[];
  confirmed?: boolean;
  amount?: number;
  amounts?: number[];
  pile?: number;
  useCommandZone?: boolean;
};
