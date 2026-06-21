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
        command: [
          {
            instanceId: "commander-1",
            card: { id: "ezuri", name: "Ezuri, Claw of Progress", manaValue: 4, colorIdentity: ["G", "U"], typeLine: "Legendary Creature" },
            power: 3,
            toughness: 3
          }
        ],
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
  log: [{ id: "log-1", message: "Game started", createdAt: new Date(0).toISOString() }],
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

  it("renders a stage tracker and pinned card inspector for selected cards", () => {
    const viewModel = buildBattlefieldViewModel(
      { ...snapshot, step: "declare-attackers", promptText: "Declare attackers" },
      {},
      "human"
    );
    const html = renderToStaticMarkup(
      <ArenaBattlefield
        actionPending={false}
        promptActions={[{ id: "pass", type: "pass_priority", playerId: "human", label: "Pass Priority" }]}
        selectedActions={[{ id: "spell-1-cast", type: "cast_spell", playerId: "human", label: "Cast Growth Spiral", cardInstanceId: "spell-1" }]}
        viewModel={viewModel}
        selectedInstanceId="spell-1"
        onRunAction={() => undefined}
        onSelectCard={() => undefined}
      />
    );

    expect(html).toContain("Untap");
    expect(html).toContain("Declare Attackers");
    expect(html).toContain("Declare attackers");
    expect(html).toContain("Card inspector");
    expect(html).toContain("Growth Spiral");
    expect(html).toContain("Log");
    expect(html).toContain("Game started");
    expect(html).toContain("Library 0");
    expect(html).toContain("Commander");
    expect(html).toContain("Ezuri, Claw of Progress");
    expect(html).toContain("Cast");
  });

  it("renders PromptEnvelopeV2 detail, stack detail, zone access, and every prompt action", () => {
    const promptedSnapshot: GameSnapshot = {
      ...snapshot,
      promptText: "Choose how Beast Whisperer resolves",
      promptEnvelopeV2: {
        id: "prompt-1",
        method: "GAME_CHOOSE_CHOICE",
        messageId: 9,
        playerId: "human",
        responseKind: "mode",
        message: "Choose a mode",
        required: true,
        minChoices: 1,
        maxChoices: 1,
        choices: [{ id: "draw", label: "Draw a card" }],
        targets: [{ id: "target-1", label: "Arboreal Grazer", cardInstanceId: "grazer-1" }],
        players: [{ id: "opponent", label: "Opponent", playerId: "opponent", life: 20 }],
        cards: [grazer],
        abilities: [{ id: "ability-1", label: "Beast Whisperer trigger", rulesText: "Whenever you cast a creature spell, draw a card." }],
        modes: [{ id: "mode-1", label: "Draw" }],
        amounts: [0, 1, 2],
        manaChoices: [{ id: "G", label: "Pay {G}", manaType: "G" }],
        piles: [{ id: "1", label: "Pile 1", cards: [grazer] }],
        orderedItems: [{ id: "trigger-1", label: "Resolve trigger first", kind: "order" }],
        confirmation: { yesLabel: "Yes", noLabel: "No" }
      },
      xmage: {
        schemaVersion: 1,
        gameId: "game-1",
        bridgeRevision: 7,
        callbackCoverage: ["GAME_CHOOSE_CHOICE"],
        stack: [
          {
            id: "stack-1",
            name: "Beast Whisperer",
            rulesText: "Whenever you cast a creature spell, draw a card.",
            sourceCard: grazer,
            paid: true
          }
        ],
        combat: [],
        players: [],
        exileZones: [{ id: "exile-1", name: "Exiled by Oblivion Ring", cards: [grazer] }],
        revealed: [{ id: "revealed-1", name: "Revealed cards", cards: [grazer] }],
        lookedAt: [{ id: "looked-1", name: "Looked at cards", cards: [grazer] }],
        companion: [],
        playableObjects: [],
        panels: {
          stack: true,
          command: true,
          graveyard: true,
          exile: true,
          revealed: true,
          lookedAt: true,
          search: false
        }
      }
    };
    const viewModel = buildBattlefieldViewModel(promptedSnapshot, {}, "human");
    const promptActions = Array.from({ length: 10 }, (_, index) => ({
      id: `choice-${index}`,
      type: "choose_amount" as const,
      playerId: "human",
      label: `Amount ${index + 1}`
    }));

    const html = renderToStaticMarkup(
      <ArenaBattlefield
        actionPending={false}
        promptActions={promptActions}
        snapshot={promptedSnapshot}
        viewModel={viewModel}
        onRunAction={() => undefined}
        onSelectCard={() => undefined}
      />
    );

    expect(html).toContain("GAME CHOOSE CHOICE");
    expect(html).toContain("Choose a mode");
    expect(html).toContain("Draw a card");
    expect(html).toContain("Opponent (20)");
    expect(html).toContain("Beast Whisperer trigger");
    expect(html).toContain("Whenever you cast a creature spell, draw a card.");
    expect(html).toContain("Pay {G}");
    expect(html).toContain("Resolve trigger first");
    expect(html).toContain("Confirmation");
    expect(html).toContain("Amount 10");
    expect(html).toContain("Paid");
    expect(html).toContain("Exiled by Oblivion Ring");
    expect(html).toContain("Revealed cards");
    expect(html).toContain("Looked at cards");
  });
});
