import type { ReactNode } from "react";

type Tone = "default" | "primary" | "danger" | "ghost";
type SeatStatus = "ready" | "waiting" | "active";

function cx(...classes: Array<string | false | undefined>): string {
  return classes.filter(Boolean).join(" ");
}

export interface ButtonProps {
  children: ReactNode;
  tone?: Tone;
  size?: "sm" | "md" | "lg";
  className?: string;
  type?: "button" | "submit" | "reset";
  disabled?: boolean;
}

export function Button({
  children,
  tone = "default",
  size = "md",
  className,
  type = "button",
  disabled
}: ButtonProps) {
  return (
    <button className={cx("mm-button", `mm-button-${tone}`, `mm-button-${size}`, className)} type={type} disabled={disabled}>
      {children}
    </button>
  );
}

export interface CardImageProps {
  name: string;
  colorIdentity?: string[];
  manaValue?: number;
  typeLine?: string;
  compact?: boolean;
}

export function CardImage({ name, colorIdentity = [], manaValue, typeLine, compact }: CardImageProps) {
  return (
    <div className={cx("mm-card-image", compact && "mm-card-image-compact")} aria-label={`${name} card preview`}>
      <div className="mm-card-image-top">
        <span>{name}</span>
        {manaValue !== undefined ? <b>{manaValue}</b> : null}
      </div>
      <div className="mm-card-image-art" />
      <div className="mm-card-image-type">{typeLine ?? "Legendary Creature"}</div>
      <div className="mm-card-image-colors">{colorIdentity.length ? colorIdentity.join(" ") : "Colorless"}</div>
    </div>
  );
}

export interface CardTileProps extends CardImageProps {
  count?: number;
  note?: string;
}

export function CardTile({ count, note, ...card }: CardTileProps) {
  return (
    <article className="mm-card-tile">
      <CardImage {...card} compact />
      <div>
        <h3>{card.name}</h3>
        <p>{note ?? card.typeLine ?? "Commander card"}</p>
      </div>
      {count ? <strong aria-label={`${count} copies`}>{count}x</strong> : null}
    </article>
  );
}

export interface DeckStatsPanelProps {
  stats: {
    lands: number;
    ramp: number;
    draw: number;
    removal: number;
    averageManaValue: number;
  };
}

export function DeckStatsPanel({ stats }: DeckStatsPanelProps) {
  const rows = [
    ["Lands", stats.lands],
    ["Ramp", stats.ramp],
    ["Draw", stats.draw],
    ["Removal", stats.removal],
    ["Avg MV", stats.averageManaValue.toFixed(2)]
  ];

  return (
    <section className="mm-panel" aria-label="Deck stats">
      <h2>Deck Stats</h2>
      <div className="mm-stat-grid">
        {rows.map(([label, value]) => (
          <div className="mm-stat" key={label}>
            <span>{label}</span>
            <strong>{value}</strong>
          </div>
        ))}
      </div>
    </section>
  );
}

export interface CommanderDamageGridProps {
  players: string[];
  damage: Record<string, Record<string, number>>;
}

export function CommanderDamageGrid({ players, damage }: CommanderDamageGridProps) {
  return (
    <section className="mm-panel" aria-label="Commander damage">
      <h2>Commander Damage</h2>
      <div className="mm-damage-grid">
        {players.map((target) => (
          <div className="mm-damage-row" key={target}>
            <strong>{target}</strong>
            {players
              .filter((source) => source !== target)
              .map((source) => (
                <span key={source}>
                  {source}: {damage[target]?.[source] ?? 0}
                </span>
              ))}
          </div>
        ))}
      </div>
    </section>
  );
}

export interface LifeTotalPanelProps {
  playerName: string;
  life: number;
  poison?: number;
}

export function LifeTotalPanel({ playerName, life, poison = 0 }: LifeTotalPanelProps) {
  return (
    <section className="mm-life-panel" aria-label={`${playerName} life total`}>
      <span>{playerName}</span>
      <strong>{life}</strong>
      <small>{poison} poison</small>
    </section>
  );
}

export interface GameLogProps {
  entries: Array<{ id: string; message: string; createdAt: string }>;
}

export function GameLog({ entries }: GameLogProps) {
  return (
    <section className="mm-panel" aria-label="Game log">
      <h2>Game Log</h2>
      <ol className="mm-log">
        {entries.map((entry) => (
          <li key={entry.id}>
            <time>{entry.createdAt}</time>
            <span>{entry.message}</span>
          </li>
        ))}
      </ol>
    </section>
  );
}

export interface PhaseTrackerProps {
  activePhase: string;
  phases?: string[];
}

export function PhaseTracker({
  activePhase,
  phases = ["Beginning", "Main", "Combat", "Second Main", "End"]
}: PhaseTrackerProps) {
  return (
    <nav className="mm-phase-tracker" aria-label="Turn phases">
      {phases.map((phase) => (
        <span className={phase === activePhase ? "is-active" : undefined} key={phase}>
          {phase}
        </span>
      ))}
    </nav>
  );
}

export interface StackPanelProps {
  spells: Array<{ id: string; name: string; controller: string }>;
}

export function StackPanel({ spells }: StackPanelProps) {
  return (
    <section className="mm-panel" aria-label="Stack">
      <h2>Stack</h2>
      {spells.length ? (
        <ol className="mm-stack">
          {spells.map((spell) => (
            <li key={spell.id}>
              <strong>{spell.name}</strong>
              <span>{spell.controller}</span>
            </li>
          ))}
        </ol>
      ) : (
        <p className="mm-muted">Stack is clear.</p>
      )}
    </section>
  );
}

export interface PlayerSeatProps {
  name: string;
  seatType: "digital" | "webcam" | "hybrid";
  status?: SeatStatus;
  children?: ReactNode;
}

export function PlayerSeat({ name, seatType, status = "waiting", children }: PlayerSeatProps) {
  return (
    <article className={cx("mm-seat", `mm-seat-${seatType}`)}>
      <div className="mm-seat-header">
        <strong>{name}</strong>
        <span>{status}</span>
      </div>
      {children}
    </article>
  );
}

export function WebcamSeat({ name, status }: Pick<PlayerSeatProps, "name" | "status">) {
  return (
    <PlayerSeat name={name} seatType="webcam" status={status ?? "waiting"}>
      <div className="mm-seat-video">Camera feed placeholder</div>
      <p>Paper board, webcam actions.</p>
    </PlayerSeat>
  );
}

export function DigitalSeat({ name, status }: Pick<PlayerSeatProps, "name" | "status">) {
  return (
    <PlayerSeat name={name} seatType="digital" status={status ?? "waiting"}>
      <div className="mm-seat-board">Digital battlefield</div>
      <p>Cards and zones tracked in app.</p>
    </PlayerSeat>
  );
}

export function HybridSeat({ name, status }: Pick<PlayerSeatProps, "name" | "status">) {
  return (
    <PlayerSeat name={name} seatType="hybrid" status={status ?? "waiting"}>
      <div className="mm-seat-hybrid">Camera plus manual actions</div>
      <p>Confirm recognized cards before state changes.</p>
    </PlayerSeat>
  );
}

export interface RuleZeroCardProps {
  headline: string;
  talkingPoints: string[];
}

export function RuleZeroCard({ headline, talkingPoints }: RuleZeroCardProps) {
  return (
    <section className="mm-rule-zero">
      <h2>Rule 0</h2>
      <strong>{headline}</strong>
      <ul>
        {talkingPoints.map((point) => (
          <li key={point}>{point}</li>
        ))}
      </ul>
    </section>
  );
}
