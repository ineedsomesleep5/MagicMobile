import {
  Button,
  CardTile,
  CommanderDamageGrid,
  DeckStatsPanel,
  DigitalSeat,
  GameLog,
  HybridSeat,
  LifeTotalPanel,
  PhaseTracker,
  RuleZeroCard,
  StackPanel,
  WebcamSeat
} from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";
import { cards, decks, logEntries, ruleZero } from "@/lib/mock-data";

export default function DevComponentsPage() {
  const sampleDeck = decks[0];
  const sampleCard = cards[0];

  if (!sampleDeck || !sampleCard) {
    return null;
  }

  return (
    <>
      <PageHeader title="Components" kicker="Reusable UI package" />
      <section className="component-grid">
        <div className="panel">
          <h2>Buttons</h2>
          <div className="actions">
            <Button tone="primary">Primary</Button>
            <Button>Default</Button>
            <Button tone="danger">Danger</Button>
          </div>
        </div>
        <LifeTotalPanel playerName="Ari" life={40} />
        <DeckStatsPanel stats={sampleDeck.stats} />
        <CardTile {...sampleCard} count={1} />
        <RuleZeroCard {...ruleZero} />
        <StackPanel spells={[]} />
        <GameLog entries={logEntries} />
        <CommanderDamageGrid players={["Ari", "Bo"]} damage={{ Ari: { Bo: 3 }, Bo: { Ari: 8 } }} />
        <div className="panel">
          <h2>Phase</h2>
          <PhaseTracker activePhase="Combat" />
        </div>
        <DigitalSeat name="Digital" status="ready" />
        <WebcamSeat name="Webcam" status="ready" />
        <HybridSeat name="Hybrid" status="waiting" />
      </section>
    </>
  );
}
