import type { CSSProperties } from "react";
import { fetchCardVisuals, type VisualCard } from "@/lib/scryfall-cards";

const battlefield = {
  opponent: {
    name: "Noaddrag",
    life: 20,
    lands: ["Mountain", "Sacred Foundry", "Battlefield Forge", "Clifftop Retreat"],
    creatures: [
      { name: "Swiftblade Vindicator", power: 1, toughness: 1 },
      { name: "Light of the Legion", power: 5, toughness: 5 }
    ]
  },
  player: {
    name: "TabletopPolish",
    life: 4,
    lands: ["Arboreal Grazer", "Island", "Forest", "Hinterland Harbor", "Breeding Pool"],
    creatures: [
      { name: "Llanowar Elves", power: 2, toughness: 2 },
      { name: "Hydroid Krasis", power: 4, toughness: 4 },
      { name: "Ezuri, Claw of Progress", power: 3, toughness: 3 }
    ],
    hand: ["Growth Spiral", "Hinterland Harbor", "Llanowar Elves", "Arboreal Grazer", "Time Wipe", "Hydroid Krasis"]
  }
};

export default async function PlayPage() {
  const cardNames = [
    ...battlefield.opponent.lands,
    ...battlefield.opponent.creatures.map((card) => card.name),
    ...battlefield.player.lands,
    ...battlefield.player.creatures.map((card) => card.name),
    ...battlefield.player.hand
  ];
  const visuals = await fetchCardVisuals(cardNames);
  const resolvedCount = Array.from(visuals.values()).filter((card) => card.source === "scryfall").length;

  return (
    <section className="arena-screen" aria-label="Horizontal game battlefield">
      <div className="arena-top-hud">
        <PlayerBadge name={battlefield.opponent.name} life={battlefield.opponent.life} />
        <div className="arena-status">
          <strong>Combat</strong>
          <span>{resolvedCount}/{visuals.size} real card images loaded from Scryfall</span>
        </div>
      </div>

      <div className="arena-board">
        <ZoneRow cards={battlefield.opponent.lands} visuals={visuals} zone="opponent lands" compact />
        <CombatRow cards={battlefield.opponent.creatures} visuals={visuals} owner="opponent" />
        <div className="arena-center-line">
          <span>Stack clear</span>
          <strong>Priority: TabletopPolish</strong>
          <span>Turn 7</span>
        </div>
        <CombatRow cards={battlefield.player.creatures} visuals={visuals} owner="player" />
        <ZoneRow cards={battlefield.player.lands} visuals={visuals} zone="your lands" compact />
      </div>

      <div className="arena-bottom-hud">
        <PlayerBadge name={battlefield.player.name} life={battlefield.player.life} active />
        <HandFan cards={battlefield.player.hand} visuals={visuals} />
        <aside className="arena-action-rail" aria-label="Game actions">
          <button type="button">Next</button>
          <span>To Combat</span>
          <div>
            <button type="button">Cast</button>
            <button type="button">Pass</button>
          </div>
        </aside>
      </div>
    </section>
  );
}

function PlayerBadge({ name, life, active = false }: { name: string; life: number; active?: boolean }) {
  return (
    <div className={active ? "arena-player-badge is-active" : "arena-player-badge"}>
      <div className="arena-avatar" />
      <strong>{life}</strong>
      <span>{name}</span>
    </div>
  );
}

function ZoneRow({
  cards,
  visuals,
  zone,
  compact = false
}: {
  cards: string[];
  visuals: Map<string, VisualCard>;
  zone: string;
  compact?: boolean;
}) {
  return (
    <div className={compact ? "arena-zone-row arena-zone-row-compact" : "arena-zone-row"} aria-label={zone}>
      {cards.map((name, index) => (
        <BattlefieldCard card={visuals.get(name)} key={`${name}-${index}`} tapped={index % 2 === 1} />
      ))}
    </div>
  );
}

function CombatRow({
  cards,
  visuals,
  owner
}: {
  cards: Array<{ name: string; power: number; toughness: number }>;
  visuals: Map<string, VisualCard>;
  owner: "player" | "opponent";
}) {
  return (
    <div className={`arena-combat-row arena-combat-row-${owner}`}>
      {cards.map((entry) => (
        <div className="arena-creature" key={entry.name}>
          <BattlefieldCard card={visuals.get(entry.name)} />
          <strong>{entry.power}/{entry.toughness}</strong>
        </div>
      ))}
    </div>
  );
}

function BattlefieldCard({ card, tapped = false }: { card: VisualCard | undefined; tapped?: boolean }) {
  return (
    <article className={tapped ? "arena-card is-tapped" : "arena-card"}>
      {card?.imageUrl ? <img alt={`${card.name} card`} src={card.imageUrl} /> : <div>{card?.name ?? "Card"}</div>}
    </article>
  );
}

function HandFan({ cards, visuals }: { cards: string[]; visuals: Map<string, VisualCard> }) {
  return (
    <div className="arena-hand" aria-label="Your hand">
      {cards.map((name, index) => (
        <article
          className="arena-hand-card"
          key={`${name}-${index}`}
          style={{ "--index": index, "--count": cards.length } as CSSProperties}
        >
          {visuals.get(name)?.imageUrl ? (
            <img alt={`${name} card in hand`} src={visuals.get(name)?.imageUrl} />
          ) : (
            <div>{name}</div>
          )}
        </article>
      ))}
    </div>
  );
}
