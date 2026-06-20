import { generateBracketThreeCommanderDeck } from "../../../packages/deck/src";

const endpoint = (process.env.XMAGE_GATEWAY_URL ?? "http://localhost:17171").replace(/\/$/, "");
const seed = process.env.XMAGE_SMOKE_SEED ?? "bridge-smoke";
const human = generateBracketThreeCommanderDeck({ seed: `${seed}:human`, playerId: "human" }).deck;
const ai = generateBracketThreeCommanderDeck({ seed: `${seed}:ai`, playerId: "ai-1" }).deck;

const response = await fetch(`${endpoint}/games/commander`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Accept: "application/json" },
  body: JSON.stringify({
    roomId: `smoke-${seed}`,
    humanPlayerId: "human",
    humanDeck: human,
    aiPlayers: [{ playerId: "ai-1", displayName: "Noaddrag", difficulty: "normal", deck: ai }],
    startingLife: 40,
    commanderDamageEnabled: true
  })
});

if (!response.ok) {
  throw new Error(`XMage smoke game failed (${response.status}): ${await response.text()}`);
}

const snapshot = await response.json();
console.log(JSON.stringify({
  id: snapshot.id,
  source: snapshot.source ?? "gateway",
  phase: snapshot.phase,
  step: snapshot.step,
  turn: snapshot.turn,
  promptText: snapshot.promptText,
  health: snapshot.engineHealth,
  players: snapshot.players?.map((player) => ({
    playerId: player.playerId,
    life: player.life,
    library: player.zones?.library?.length ?? 0,
    hand: player.zones?.hand?.length ?? 0,
    command: player.zones?.command?.map((card) => card.card?.name) ?? []
  })),
  legalActions: snapshot.legalActions?.map((action) => action.type).slice(0, 8) ?? []
}, null, 2));
