import {
  LocalSynergyRecommendationProvider,
  MockRecommendationProvider,
  createEdhrecCommanderUrl
} from "@magicmobile/recommendations";
import type { DeckList, RecommendationProvider } from "@magicmobile/shared";

type RecommendationProviderName = "mock" | "local-synergy";

interface RecommendationRequestBody {
  deck?: DeckList;
  provider?: RecommendationProviderName;
}

export async function POST(request: Request): Promise<Response> {
  const body = (await request.json()) as RecommendationRequestBody;

  if (!isDeckList(body.deck)) {
    return Response.json({ error: "A deck is required to generate recommendations." }, { status: 400 });
  }

  const provider = createProvider(body.provider ?? "mock");
  const recommendations = await provider.recommend({ deck: body.deck });
  const edhrecCommanderUrl = body.deck.commander
    ? createEdhrecCommanderUrl(body.deck.commander.cardName)
    : undefined;

  return Response.json({ recommendations, edhrecCommanderUrl });
}

function createProvider(providerName: RecommendationProviderName): RecommendationProvider {
  if (providerName === "local-synergy") {
    return new LocalSynergyRecommendationProvider();
  }

  return new MockRecommendationProvider();
}

function isDeckList(deck: RecommendationRequestBody["deck"]): deck is DeckList {
  return Boolean(deck && typeof deck.name === "string" && Array.isArray(deck.entries));
}
