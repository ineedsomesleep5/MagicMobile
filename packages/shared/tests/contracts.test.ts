import { describe, expect, it } from "vitest";
import type {
  CardDataProvider,
  DeckAnalyzer,
  DeckParser,
  EngineAdapter,
  GameCommand,
  GameSnapshot,
  LegalAction,
  PromptEnvelopeV2,
  RecommendationProvider,
  VideoProvider
} from "@magicmobile/shared";

describe("shared contracts", () => {
  it("allows providers to be implemented without UI or XMage imports", async () => {
    const snapshot: GameSnapshot = {
      id: "game-1",
      roomId: "room-1",
      phase: "beginning",
      turn: 1,
      players: [],
      log: []
    };

    const cardProvider: CardDataProvider = {
      async searchCards() {
        return [];
      },
      async getCardByName() {
        return undefined;
      },
      async getSeedCards() {
        return [];
      },
      async getCacheMetadata() {
        return {
          provider: "scryfall",
          status: "empty",
          cardCount: 0,
          imageCount: 0,
          missingImageCount: 0,
          updatedAt: new Date(0).toISOString()
        };
      }
    };

    const deckParser: DeckParser = {
      parse(input) {
        return { name: "Imported deck", entries: input ? [] : [] };
      }
    };

    const deckAnalyzer: DeckAnalyzer = {
      async validateCommander() {
        return [];
      },
      getStats() {
        return {
          lands: 0,
          ramp: 0,
          draw: 0,
          removal: 0,
          boardWipes: 0,
          tutors: 0,
          averageManaValue: 0,
          manaCurve: {},
          colorDistribution: { W: 0, U: 0, B: 0, R: 0, G: 0, C: 0 },
          colorPipDensity: { W: 0, U: 0, B: 0, R: 0, G: 0, C: 0 }
        };
      },
      getBracketScore() {
        return { bracket: 1, score: 0, explanations: [] };
      },
      getRuleZeroSummary() {
        return { headline: "Casual deck", talkingPoints: [] };
      }
    };

    const recommendations: RecommendationProvider = {
      async recommend() {
        return [];
      }
    };

    const video: VideoProvider = {
      async createSession({ roomId }) {
        return { roomId, provider: "mock" };
      },
      async getJoinToken({ roomId }) {
        return { roomId, provider: "mock", token: "mock-token" };
      }
    };

    const engine: EngineAdapter = {
      async createCommanderGame() {
        return snapshot;
      },
      async createGame() {
        return snapshot;
      },
      async joinGame() {
        return snapshot;
      },
      async loadDeck() {
        return snapshot;
      },
      async shuffle() {
        return snapshot;
      },
      async drawOpeningHands() {
        return snapshot;
      },
      async applyHybridAction() {
        return snapshot;
      },
      async submitGameCommand() {
        return snapshot;
      },
      async getLegalActions() {
        return [];
      },
      async getHealth() {
        return {
          status: "ready",
          reason: "test engine",
          checkedAt: new Date(0).toISOString()
        };
      },
      async passPriority() {
        return snapshot;
      },
      async advancePhase() {
        return snapshot;
      },
      async getSnapshot() {
        return snapshot;
      }
    };

    expect(cardProvider).toBeDefined();
    expect(deckParser.parse("")).toEqual({ name: "Imported deck", entries: [] });
    expect(deckAnalyzer.getBracketScore({ deck: { name: "Deck", entries: [] }, cards: [] }).bracket).toBe(1);
    expect(recommendations).toBeDefined();
    expect(video).toBeDefined();
    await expect(engine.createGame({ roomId: "room-1", playerIds: [] })).resolves.toEqual(snapshot);
  });

  it("expresses XMage prompt envelopes without changing snapshot requirements", () => {
    const prompt: PromptEnvelopeV2 = {
      id: "prompt-1",
      method: "choose",
      messageId: 42,
      playerId: "player-1",
      responseKind: "target",
      message: "Choose up to two targets.",
      required: false,
      minChoices: 0,
      maxChoices: 2,
      responseCommand: {
        type: "choose_player",
        promptId: "prompt-1",
        playerIds: []
      },
      choices: [
        { id: "yes", label: "Yes", kind: "confirmation", value: true },
        { id: "no", label: "No", kind: "confirmation", value: false }
      ],
      cards: [
        {
          instanceId: "card-1",
          card: {
            id: "card-id-1",
            name: "Example Card",
            manaValue: 1,
            colorIdentity: ["G"],
            typeLine: "Creature"
          }
        }
      ],
      targets: [{ id: "target-1", label: "Target creature", kind: "target", cardInstanceId: "card-1" }],
      players: [{ id: "player-2", label: "Opponent", playerId: "player-2", selectable: true }],
      modes: [{ id: "mode-1", label: "Destroy artifact", kind: "mode" }],
      abilities: [{ id: "ability-1", label: "Activated ability", kind: "ability", rulesText: "{T}: Add {G}." }],
      amounts: [0, 1, 2],
      manaChoices: [{ id: "mana-g", label: "Green", manaType: "G", amount: 1 }],
      piles: [{ id: 1, label: "Pile 1", cards: [] }],
      orderedItems: [{ id: "trigger-1", label: "Resolve first", kind: "order", defaultIndex: 0 }],
      confirmation: {
        yesLabel: "Yes",
        noLabel: "No",
        yesCommand: { type: "pay_cost", promptId: "prompt-1", confirmed: true, pay: true },
        noCommand: { type: "pay_cost", promptId: "prompt-1", confirmed: false, pay: false }
      }
    };

    const legalAction: LegalAction = {
      id: "action-1",
      type: "choose_mana",
      playerId: "player-1",
      label: "Choose mana",
      promptId: "prompt-1",
      cardName: "Forest",
      manaCost: "{G}",
      manaType: "G",
      requiresPayment: true,
      producedMana: ["G"],
      minChoices: 1,
      maxChoices: 1,
      required: true,
      commandTemplate: { type: "choose_mana", promptId: "prompt-1", manaTypes: ["G"] }
    };

    const command: GameCommand = {
      type: "answer_yes_no",
      gameId: "game-1",
      playerId: "player-1",
      promptId: "prompt-1",
      confirmed: true
    };

    const payCommand: GameCommand = {
      type: "pay_cost",
      gameId: "game-1",
      playerId: "player-1",
      promptId: "prompt-pay",
      pay: false,
      confirmed: false
    };

    const makeManaCommand: GameCommand = {
      type: "make_mana",
      gameId: "game-1",
      playerId: "player-1",
      sourceInstanceId: "source-card-1"
    };

    const activateAbilityCommand: GameCommand = {
      type: "activate_ability",
      gameId: "game-1",
      playerId: "player-1",
      sourceInstanceId: "source-card-1",
      abilityId: "ability-1"
    };

    expect(prompt.players?.[0]?.playerId).toBe("player-2");
    expect(legalAction.commandTemplate?.type).toBe("choose_mana");
    expect(legalAction.cardName).toBe("Forest");
    expect(legalAction.producedMana).toEqual(["G"]);
    expect(legalAction.requiresPayment).toBe(true);
    expect(prompt.confirmation?.yesCommand?.pay).toBe(true);
    expect(prompt.confirmation?.noCommand?.pay).toBe(false);
    expect(command.confirmed).toBe(true);
    expect(payCommand.pay).toBe(false);
    expect(makeManaCommand.sourceInstanceId).toBe("source-card-1");
    expect(activateAbilityCommand.abilityId).toBe("ability-1");
  });
});
