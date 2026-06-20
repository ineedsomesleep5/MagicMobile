import type { DeckList, Recommendation, RecommendationProvider } from "@magicmobile/shared";

export type { Recommendation, RecommendationProvider } from "@magicmobile/shared";

export interface EdhrecProviderConfig {
  enabled: boolean;
  approvedIntegration: boolean;
}

export class MockRecommendationProvider implements RecommendationProvider {
  async recommend(input: { deck: DeckList }): Promise<Recommendation[]> {
    const commanderName = input.deck.commander?.cardName ?? "this commander";

    return [
      {
        cardName: "Command Tower",
        confidence: 0.5,
        reason: `Mock recommendation for ${commanderName} decks.`,
        source: "mock"
      },
      {
        cardName: "Swords to Plowshares",
        confidence: 0.4,
        reason: "Mock staple suggestion for early recommendation UI wiring.",
        source: "mock"
      }
    ];
  }
}

export class LocalSynergyRecommendationProvider implements RecommendationProvider {
  async recommend(_input: { deck: DeckList }): Promise<Recommendation[]> {
    return [];
  }
}

export class EdhrecProvider implements RecommendationProvider {
  constructor(private readonly config: EdhrecProviderConfig) {}

  async recommend(_input: { deck: DeckList }): Promise<Recommendation[]> {
    if (!this.config.enabled || !this.config.approvedIntegration) {
      throw new Error("EDHREC recommendations are disabled until an approved integration is configured.");
    }

    return [];
  }
}

export function createEdhrecCommanderUrl(cardName: string): string {
  const slug = cardName
    .trim()
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");

  return `https://edhrec.com/commanders/${slug}`;
}
