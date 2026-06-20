import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { GameSnapshot, ZoneCard } from "@magicmobile/shared";
import { ArenaBattlefield } from "./ArenaBattlefield";
import { buildBattlefieldViewModel } from "./battlefield-view-model";

const forest = (index: number): ZoneCard => ({
  instanceId: `forest-${index}`,
  card: { id: `forest-${index}`, name: "Forest", manaValue: 0, colorIdentity: ["G"], typeLine: "Basic Land", isBasicLand: true }
});

const grazer: ZoneCard = {
  instanceId: "grazer-1",
  tapped: true,
  card: { id: "grazer", name: "Arboreal Grazer", manaValue: 1, colorIdentity: ["G"], typeLine: "Creature" },
  power: 0,
  toughness: 3,
  counters: { "+1/+1": 2 }
};

const snapshot: GameSnapshot = {
  id: "game-1",
  roomId: "room-1",
  phase: "combat",
  turn: 4,
  activePlayerId: "human",
  priorityPlayerId: "human",
  players: [
    {
      playerId: "human",
      life: 12,
      poison: 0,
      commanderTax: 0,
      commanderDamage: { human: 0, opponent: 0 },
      zones: {
        library: [],
        hand: [
          { instanceId: "spell-1", card: { id: "growth", name: "Growth Spiral", manaValue: 2, colorIdentity: ["G", "U"], typeLine: "Instant" } }
        ],
        battlefield: [forest(1), forest(2), grazer],
        graveyard: [],
        exile: [],
        command: [],
        stack: []
      }
    },
    {
      playerId: "opponent",
      life: 20,
      poison: 0,
      commanderTax: 0,
      commanderDamage: { human: 0, opponent: 0 },
      zones: {
        library: [],
        hand: [],
        battlefield: [],
        graveyard: [],
        exile: [],
        command: [],
        stack: []
      }
    }
  ],
  log: [],
  legalActions: [
    { id: "spell-1-cast", type: "cast_spell", playerId: "human", label: "Cast Growth Spiral", cardInstanceId: "spell-1" }
  ]
};

describe("BattlefieldViewModel", () => {
  it("groups duplicate stacks while keeping legal cards individually clickable", () => {
    const viewModel = buildBattlefieldViewModel(snapshot, {}, "human");

    expect(viewModel.humanLands).toEqual([expect.objectContaining({ name: "Forest", quantity: 2 })]);
    expect(viewModel.humanHand).toEqual([
      expect.objectContaining({ name: "Growth Spiral", quantity: 1, legalActionTypes: ["cast_spell"] })
    ]);
  });

  it("renders tapped creature state, stats, counters, and legal glow classes", () => {
    const viewModel = buildBattlefieldViewModel(snapshot, {}, "human");
    const html = renderToStaticMarkup(
      <ArenaBattlefield viewModel={viewModel} selectedInstanceId="spell-1" onSelectCard={() => undefined} />
    );

    expect(html).toContain("battle-card is-hand is-selected is-legal");
    expect(html).toContain("battle-card is-tapped");
    expect(html).toContain("0/3");
    expect(html).toContain("+1/+1 2");
    expect(html).toContain("x2");
  });
});
