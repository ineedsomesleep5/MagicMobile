import Link from "next/link";
import { Button, DigitalSeat, HybridSeat, RuleZeroCard, WebcamSeat } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";
import { ruleZero } from "@/lib/mock-data";

export default function HomePage() {
  return (
    <>
      <PageHeader
        title="Commander night starts here."
        kicker="Home"
        actions={
          <>
            <Link href="/play">
              <Button tone="primary" size="lg">Start Table</Button>
            </Link>
            <Link href="/decks/new">
              <Button size="lg">Add Deck</Button>
            </Link>
          </>
        }
      />
      <section className="hero-grid">
        <div className="battlefield-preview">
          <div className="seat-grid">
            <DigitalSeat name="Digital Seat" status="ready" />
            <WebcamSeat name="Webcam Seat" status="ready" />
            <HybridSeat name="Hybrid Seat" status="waiting" />
          </div>
        </div>
        <div className="list">
          <RuleZeroCard {...ruleZero} />
          <article className="feature">
            <h2>Big table actions</h2>
            <p className="muted">Life, commander damage, turn phase, stack, and room seats are visible without digging through menus.</p>
          </article>
          <article className="feature">
            <h2>Mock milestone mode</h2>
            <p className="muted">This scaffold uses static data until room, engine, and card-data services are connected.</p>
          </article>
        </div>
      </section>
    </>
  );
}
