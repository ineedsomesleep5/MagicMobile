import { fetchCardVisuals, type VisualCard } from "@/lib/scryfall-cards";
import { createRuntimeEngineAdapter } from "@/lib/engine";
import { ThreeBattlefield, type BattlefieldVisualCard } from "./ThreeBattlefield";

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
  const engine = createRuntimeEngineAdapter();
  const engineHealth = await engine.getHealth();
  const cardNames = [
    ...battlefield.opponent.lands,
    ...battlefield.opponent.creatures.map((card) => card.name),
    ...battlefield.player.lands,
    ...battlefield.player.creatures.map((card) => card.name),
    ...battlefield.player.hand
  ];
  const visuals = await fetchCardVisuals(cardNames);
  const resolvedCount = Array.from(visuals.values()).filter((card) => card.source === "scryfall").length;
  const threeCards = buildBattlefieldCards(visuals);

  return (
    <section className="arena-screen" aria-label="Horizontal game battlefield">
      <div className="arena-top-hud">
        <PlayerBadge name={battlefield.opponent.name} life={battlefield.opponent.life} />
        <div className="arena-status">
          <strong>Combat</strong>
          <span>{resolvedCount}/{visuals.size} real card images loaded from Scryfall</span>
          <small>{engineHealth.status}: {engineHealth.reason}</small>
        </div>
      </div>

      <ThreeBattlefield cards={threeCards} activePlayerName={battlefield.player.name} phase="Combat" />

      <div className="arena-bottom-hud">
        <PlayerBadge name={battlefield.player.name} life={battlefield.player.life} active />
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

function buildBattlefieldCards(visuals: Map<string, VisualCard>): BattlefieldVisualCard[] {
  return [
    ...battlefield.opponent.lands.map((name, index) => toBattlefieldCard(name, visuals, "opponent-land", index % 2 === 1)),
    ...battlefield.opponent.creatures.map((card) =>
      toBattlefieldCard(card.name, visuals, "opponent-creature", false, card.power, card.toughness)
    ),
    ...battlefield.player.creatures.map((card) =>
      toBattlefieldCard(card.name, visuals, "player-creature", false, card.power, card.toughness)
    ),
    ...battlefield.player.lands.map((name, index) => toBattlefieldCard(name, visuals, "player-land", index % 2 === 1)),
    ...battlefield.player.hand.map((name) => toBattlefieldCard(name, visuals, "hand"))
  ];
}

function toBattlefieldCard(
  name: string,
  visuals: Map<string, VisualCard>,
  zone: BattlefieldVisualCard["zone"],
  tapped = false,
  power?: number,
  toughness?: number
): BattlefieldVisualCard {
  const visual = visuals.get(name);
  const card: BattlefieldVisualCard = {
    id: `${zone}-${name}`,
    name,
    zone,
    tapped
  };

  if (visual?.imageUrl) card.imageUrl = proxyCardImageUrl(visual.imageUrl);
  if (power !== undefined) card.power = power;
  if (toughness !== undefined) card.toughness = toughness;

  return card;
}

function proxyCardImageUrl(url: string): string {
  return `/api/card-image?url=${encodeURIComponent(url)}`;
}
