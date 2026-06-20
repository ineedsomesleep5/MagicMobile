import type { CSSProperties } from "react";
import { fetchCardVisuals, type VisualCard } from "@/lib/scryfall-cards";

interface DeckColumn {
  title: string;
  cards: Array<{ name: string; quantity: number }>;
}

const commander = { name: "Ezuri, Claw of Progress", quantity: 1 };

const deckColumns: DeckColumn[] = [
  {
    title: "+1/+1 Targets",
    cards: [
      { name: "Slither Blade", quantity: 1 },
      { name: "Invisible Stalker", quantity: 1 },
      { name: "Cold-Eyed Selkie", quantity: 1 },
      { name: "Herald of Secret Streams", quantity: 1 },
      { name: "Champion of Lambholt", quantity: 1 }
    ]
  },
  {
    title: "Counters",
    cards: [
      { name: "Hardened Scales", quantity: 1 },
      { name: "Branching Evolution", quantity: 1 },
      { name: "Deepglow Skate", quantity: 1 },
      { name: "Evolution Sage", quantity: 1 },
      { name: "Master Biomancer", quantity: 1 }
    ]
  },
  {
    title: "Card Draw",
    cards: [
      { name: "Guardian Project", quantity: 1 },
      { name: "Beast Whisperer", quantity: 1 },
      { name: "Toothy, Imaginary Friend", quantity: 1 },
      { name: "Bident of Thassa", quantity: 1 },
      { name: "Prime Speaker Zegana", quantity: 1 }
    ]
  },
  {
    title: "Ramp",
    cards: [
      { name: "Sol Ring", quantity: 1 },
      { name: "Arcane Signet", quantity: 1 },
      { name: "Birds of Paradise", quantity: 1 },
      { name: "Cultivate", quantity: 1 },
      { name: "Command Tower", quantity: 1 }
    ]
  },
  {
    title: "Interaction",
    cards: [
      { name: "Cyclonic Rift", quantity: 1 },
      { name: "Heroic Intervention", quantity: 1 },
      { name: "Swan Song", quantity: 1 },
      { name: "Pongify", quantity: 1 },
      { name: "Beast Within", quantity: 1 }
    ]
  },
  {
    title: "Lands",
    cards: [
      { name: "Breeding Pool", quantity: 1 },
      { name: "Hinterland Harbor", quantity: 1 },
      { name: "Yavimaya Coast", quantity: 1 },
      { name: "Forest", quantity: 12 },
      { name: "Island", quantity: 10 }
    ]
  }
];

export default async function NewDeckPage() {
  const cardNames = [commander.name, ...deckColumns.flatMap((column) => column.cards.map((card) => card.name))];
  const visuals = await fetchCardVisuals(cardNames);
  const commanderVisual = visuals.get(commander.name);
  const totalCards = commander.quantity + deckColumns.flatMap((column) => column.cards).reduce((sum, card) => sum + card.quantity, 0);
  const resolvedCount = Array.from(visuals.values()).filter((card) => card.source === "scryfall").length;

  return (
    <section className="deck-builder-screen">
      <header className="deck-builder-topbar">
        <div>
          <p className="deck-builder-brand">MagicMobile Decks</p>
          <h1>Ezuri Again</h1>
          <div className="deck-builder-meta">
            <span>Commander / EDH</span>
            <span>{totalCards}/100 cards</span>
            <span>{resolvedCount}/{visuals.size} real card images</span>
          </div>
        </div>
        <div className="deck-builder-actions">
          <a href="https://archidekt.com" rel="noreferrer" target="_blank">Open Archidekt</a>
          <button type="button">Import cards</button>
          <button type="button">Save Draft</button>
        </div>
      </header>

      <section className="deck-builder-controls" aria-label="Deck controls">
        <label>
          Add card
          <input placeholder="Card search" />
        </label>
        <label>
          Archidekt URL
          <input placeholder="https://archidekt.com/decks/..." />
        </label>
        <label>
          View as
          <select defaultValue="stacks">
            <option value="stacks">Stacks</option>
            <option value="list">List</option>
          </select>
        </label>
        <label>
          Sort by
          <select defaultValue="category">
            <option value="category">Category</option>
            <option value="color">Color</option>
            <option value="mana">Mana value</option>
          </select>
        </label>
        <label>
          Deck filter
          <input placeholder="type:creature or mana:2" />
        </label>
      </section>

      <div className="deck-builder-layout">
        <aside className="deck-focus-card">
          {commanderVisual ? <DeckCard card={commanderVisual} quantity={commander.quantity} large /> : null}
          <div className="deck-focus-notes">
            <strong>Commander</strong>
            <span>Experience counters, evasive bodies, and counters payoffs.</span>
          </div>
          <textarea defaultValue={"Commander\n1 Ezuri, Claw of Progress\n\nDeck\n1 Sol Ring\n1 Cultivate\n1 Cyclonic Rift"} />
        </aside>

        <div className="deck-stack-board">
          {deckColumns.map((column) => (
            <section className="deck-stack-column" key={column.title}>
              <header>
                <h2>{column.title}</h2>
                <span>{column.cards.reduce((sum, card) => sum + card.quantity, 0)} cards</span>
              </header>
              <div className="deck-stack-list">
                {column.cards.map((entry) => {
                  const visual = visuals.get(entry.name);
                  return visual ? <DeckCard card={visual} key={entry.name} quantity={entry.quantity} /> : null;
                })}
              </div>
            </section>
          ))}
        </div>

        <aside className="deck-inspector">
          <section>
            <h2>Color Cost & Production</h2>
            <div className="mana-ring" aria-label="Simulated Simic mana distribution" />
            <dl>
              <div><dt>Avg Mana Value</dt><dd>2.74</dd></div>
              <div><dt>Creatures</dt><dd>31</dd></div>
              <div><dt>Interaction</dt><dd>12</dd></div>
            </dl>
          </section>
          <section>
            <h2>Mana Curve</h2>
            <div className="curve-bars" aria-hidden="true">
              {[2, 11, 15, 14, 8, 5, 3, 2].map((height, index) => (
                <span key={index} style={{ "--bar": height } as CSSProperties} />
              ))}
            </div>
          </section>
        </aside>
      </div>
    </section>
  );
}

function DeckCard({ card, quantity, large = false }: { card: VisualCard; quantity: number; large?: boolean }) {
  return (
    <article className={large ? "deck-card deck-card-large" : "deck-card"}>
      <div className="deck-card-frame">
        {card.imageUrl ? (
          <img alt={`${card.name} card`} src={card.imageUrl} />
        ) : (
          <div className="missing-card-art">{card.name}</div>
        )}
        {quantity > 1 ? <strong className="deck-card-count">x{quantity}</strong> : null}
      </div>
      {!large ? <span>{card.name}</span> : null}
    </article>
  );
}
