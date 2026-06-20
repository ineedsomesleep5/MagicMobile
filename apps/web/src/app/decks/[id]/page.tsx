import { notFound } from "next/navigation";
import { Button, CardTile, DeckStatsPanel, RuleZeroCard } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";
import { RecommendationPlaceholder } from "@/features/recommendations";
import { getDeckDetail } from "@/lib/mock-data";

export default async function DeckDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const detail = await getDeckDetail(id);

  if (!detail) {
    return notFound();
  }

  const { cardTiles, deck, edhrecCommanderUrl, recommendations, ruleZero } = detail;

  return (
    <>
      <PageHeader
        title={deck.name}
        kicker={deck.commander}
        actions={
          <>
            <Button tone="primary">Join Table</Button>
            <Button>Export List</Button>
          </>
        }
      />
      <section className="two-column">
        <div className="list">
          {cardTiles.map((card) => (
            <CardTile key={card.name} {...card} />
          ))}
        </div>
        <aside className="list">
          <DeckStatsPanel stats={deck.stats} />
          <RuleZeroCard {...ruleZero} />
          <RecommendationPlaceholder recommendations={recommendations} edhrecCommanderUrl={edhrecCommanderUrl} />
        </aside>
      </section>
    </>
  );
}
