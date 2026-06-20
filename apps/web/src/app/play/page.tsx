import type { DeckList } from "@magicmobile/shared";
import { generateBracketThreeCommanderDeck } from "@magicmobile/deck";
import { fetchCardVisuals } from "@/lib/scryfall-cards";
import { createRuntimeEngineAdapter } from "@/lib/engine";
import { GameController } from "./GameController";

export const dynamic = "force-dynamic";

export default async function PlayPage() {
  const seed = `play-${Date.now()}`;
  const humanGenerated = generateBracketThreeCommanderDeck({ seed, playerId: "human" });
  const aiGenerated = generateBracketThreeCommanderDeck({ seed, playerId: "ai-1" });
  const config = {
    roomId: `commander-${seed}`,
    humanPlayerId: "human",
    humanDeck: humanGenerated.deck,
    aiPlayers: [
      {
        playerId: "ai-1",
        displayName: "Noaddrag",
        difficulty: "normal" as const,
        deck: aiGenerated.deck
      }
    ],
    startingLife: 40 as const,
    commanderDamageEnabled: true as const
  };
  const [visuals, engineHealth] = await Promise.all([
    fetchCardVisuals(deckCardNames([humanGenerated.deck, aiGenerated.deck])),
    createRuntimeEngineAdapter({ mode: "xmage" }).getHealth()
  ]);

  return (
    <GameController
      config={config}
      initialHealth={engineHealth}
      requireXmage
      simulatorMode={false}
      visuals={Object.fromEntries(visuals)}
    />
  );
}

function deckCardNames(decks: DeckList[]): string[] {
  return Array.from(new Set(decks.flatMap((deck) => deck.entries.map((entry) => entry.cardName))));
}
