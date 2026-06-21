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
const steps: Array<{ label: string; type: string; optional?: boolean }> = [
  { label: "choose starting player", type: "resolve_choice", optional: true },
  { label: "keep hand", type: "keep_hand" },
  { label: "play land", type: "play_land" },
  { label: "make mana", type: "make_mana" },
  { label: "cast simple spell", type: "cast_spell" },
  { label: "pass priority", type: "pass_priority" }
];
const completed: string[] = [];
const promptChecks: string[] = [];

for (const step of steps) {
  const action = findAction(snapshot, step.type);
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
    if (!snapshot.legalActions?.some((candidate: SmokeAction) => candidate.responseKind || candidate.targetIds?.length)) {
      throw new Error("XMage promptEnvelopeV2 was present but no response-shaped legal action was exposed.");
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

function findAction(snapshot: SmokeSnapshot, type: string) {
  return snapshot.legalActions?.find((action) => action.type === type);
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
    cardInstanceIds: targetIds,
    modeIds: targetIds
  };
}

function assertBridgeProgress(
  previous: SmokeSnapshot,
  next: SmokeSnapshot,
  label: string,
  options: { allowEqual?: boolean } = {}
) {
  assertAdvanced("bridgeRevision", previous.bridgeRevision, next.bridgeRevision, label, options.allowEqual);
  assertAdvanced("xmageCycle", previous.xmageCycle, next.xmageCycle, label, options.allowEqual);
}

function assertAdvanced(field: string, before: unknown, after: unknown, label: string, allowEqual = false) {
  if (typeof before !== "number" || typeof after !== "number") return;
  const advanced = allowEqual ? after >= before : after > before;
  if (!advanced) {
    throw new Error(`XMage smoke ${label} did not advance ${field}: ${before} -> ${after}`);
  }
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
};
