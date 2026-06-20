import { Button, CardTile } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";
import { cards } from "@/lib/mock-data";

export default function CardsPage() {
  return (
    <>
      <PageHeader title="Cards" kicker="Seed card browser" actions={<Button>Sync Scryfall Stub</Button>} />
      <section className="form-panel">
        <label className="field">
          Search cards
          <input placeholder="Command Tower" />
        </label>
      </section>
      <section className="component-grid">
        {cards.map((card) => (
          <CardTile key={card.name} {...card} />
        ))}
      </section>
    </>
  );
}
