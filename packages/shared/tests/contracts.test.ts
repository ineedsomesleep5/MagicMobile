import { describe, expect, it } from "vitest";
import type {
  CardDataProvider,
  DeckAnalyzer,
  DeckParser,
  EngineAdapter,
  GameSnapshot,
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
});
