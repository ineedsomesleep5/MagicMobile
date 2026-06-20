"use client";

import type { CSSProperties, MouseEventHandler } from "react";
import { useMemo, useState } from "react";
import { getHandFanStyle } from "./arena-layout";
import { ArenaFxLayer } from "./ArenaFxLayer";
import type { BattlefieldCardView, BattlefieldViewModel } from "./battlefield-view-model";
import type { LegalAction } from "@magicmobile/shared";

interface ArenaBattlefieldProps {
  viewModel: BattlefieldViewModel;
  selectedInstanceId?: string | undefined;
  selectedActions?: LegalAction[];
  promptActions?: LegalAction[];
  actionPending?: boolean;
  onSelectCard: (card: BattlefieldCardView) => void;
  onRunAction?: (action: LegalAction) => void;
}

export function ArenaBattlefield({
  viewModel,
  selectedInstanceId,
  selectedActions = [],
  promptActions = [],
  actionPending = false,
  onSelectCard,
  onRunAction
}: ArenaBattlefieldProps) {
  const [hoveredInstanceId, setHoveredInstanceId] = useState<string | undefined>();
  const allCards = useMemo(() => getRenderableCards(viewModel), [viewModel]);
  const inspectCard = allCards.find((card) => card.instanceId === selectedInstanceId)
    ?? allCards.find((card) => card.instanceId === hoveredInstanceId);

  return (
    <div className="arena-battlefield" data-testid="arena-battlefield" aria-label="Arena-style Commander battlefield">
      <ArenaFxLayer phase={viewModel.phase} />
      <div className="arena-map-river" aria-hidden="true" />
      <div className="arena-prompt-banner">
        <strong>{viewModel.promptText}</strong>
        <span>Priority: {viewModel.priorityPlayerName}</span>
      </div>
      <aside className="arena-side-panel" aria-label="Game stage and move log">
        <StageTracker activeStep={viewModel.step} />
        <ActionPanel
          pending={actionPending}
          promptActions={promptActions}
          selectedActions={selectedActions}
          selectedCard={allCards.find((card) => card.instanceId === selectedInstanceId)}
          onRunAction={onRunAction}
        />
        <GameLog entries={viewModel.logEntries} />
        <ZonePanel
          humanCommand={viewModel.humanCommand}
          humanCounts={viewModel.humanZoneCounts}
          opponentCommand={viewModel.opponentCommand}
          opponentCounts={viewModel.opponentZoneCounts}
          onSelectCard={onSelectCard}
        />
      </aside>

      <div className="arena-zone arena-zone-opponent-lands" aria-label="Opponent lands">
        {viewModel.opponentLands.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onHover={setHoveredInstanceId} onSelect={onSelectCard} compact />
        ))}
      </div>

      <div className="arena-zone arena-zone-opponent-creatures" aria-label="Opponent creatures">
        {viewModel.opponentCreatures.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onHover={setHoveredInstanceId} onSelect={onSelectCard} />
        ))}
      </div>

      <div className="arena-combat-lane" aria-label="Combat lane">
        {[...viewModel.opponentAttackers, ...viewModel.humanAttackers].map((card) => (
          <div className="arena-attacker" key={card.instanceId}>
            <span className="arena-attack-arrow" aria-hidden="true" />
            <ArenaCardButton card={card} selected={selectedInstanceId === card.instanceId} onHover={setHoveredInstanceId} onSelect={onSelectCard} />
          </div>
        ))}
      </div>

      <div className="arena-zone arena-zone-player-creatures" aria-label="Your creatures">
        {viewModel.humanCreatures.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onHover={setHoveredInstanceId} onSelect={onSelectCard} />
        ))}
      </div>

      <div className="arena-zone arena-zone-player-lands" aria-label="Your lands">
        {viewModel.humanLands.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onHover={setHoveredInstanceId} onSelect={onSelectCard} compact />
        ))}
      </div>

      <div className="arena-stack-zone" aria-label="Stack">
        {viewModel.stack.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onHover={setHoveredInstanceId} onSelect={onSelectCard} compact />
        ))}
      </div>

      <div className="arena-hand-fan" aria-label="Your hand">
        {viewModel.humanHand.map((card, index) => (
          <ArenaCardButton
            card={card}
            handStyle={getHandFanStyle(index, viewModel.humanHand.length, selectedInstanceId === card.instanceId)}
            key={card.instanceId}
            selected={selectedInstanceId === card.instanceId}
            onHover={setHoveredInstanceId}
            onSelect={onSelectCard}
            hand
          />
        ))}
      </div>

      {inspectCard ? <CardInspector card={inspectCard} pinned={inspectCard.instanceId === selectedInstanceId} /> : null}

      <div className="arena-priority-strip">
        <span>Priority: {viewModel.priorityPlayerName}</span>
        <strong>{formatStepLabel(viewModel.step)}</strong>
        <span>Turn {viewModel.turn}</span>
      </div>
    </div>
  );
}

const stageLabels = [
  ["untap", "Untap"],
  ["upkeep", "Upkeep"],
  ["draw", "Draw"],
  ["precombat-main", "Main"],
  ["begin-combat", "Begin Combat"],
  ["declare-attackers", "Declare Attackers"],
  ["declare-blockers", "Declare Blockers"],
  ["combat-damage", "Combat Damage"],
  ["end-combat", "End Combat"],
  ["postcombat-main", "Second Main"],
  ["end", "End"],
  ["cleanup", "Cleanup"]
] as const;

function StageTracker({ activeStep }: { activeStep: BattlefieldViewModel["step"] }) {
  return (
    <section className="arena-stage-panel">
      <h2>Stages</h2>
      <ol className="arena-stage-tracker" aria-label="Game stage tracker">
        {stageLabels.map(([step, label]) => (
          <li className={step === activeStep ? "is-active" : ""} key={step}>
            {label}
          </li>
        ))}
      </ol>
    </section>
  );
}

function GameLog({ entries }: { entries: BattlefieldViewModel["logEntries"] }) {
  return (
    <section className="arena-log-panel" aria-label="Move log">
      <h2>Log</h2>
      {entries.length > 0 ? (
        <ol>
          {entries.map((entry) => (
            <li key={entry.id}>{entry.message}</li>
          ))}
        </ol>
      ) : (
        <p>Waiting for first move</p>
      )}
    </section>
  );
}

function ZonePanel({
  humanCommand,
  humanCounts,
  opponentCommand,
  opponentCounts,
  onSelectCard
}: {
  humanCommand: BattlefieldViewModel["humanCommand"];
  humanCounts: BattlefieldViewModel["humanZoneCounts"];
  opponentCommand: BattlefieldViewModel["opponentCommand"];
  opponentCounts: BattlefieldViewModel["opponentZoneCounts"];
  onSelectCard: (card: BattlefieldCardView) => void;
}) {
  return (
    <section className="arena-zone-panel" aria-label="Player zones">
      <h2>Zones</h2>
      <div className="arena-zone-count-grid">
        <ZoneCount label="You" counts={humanCounts} />
        <ZoneCount label="AI" counts={opponentCounts} />
      </div>
      <div className="arena-command-list">
        {humanCommand.map((card) => (
          <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button">
            <span>Commander</span>
            <strong>{card.name}</strong>
          </button>
        ))}
        {opponentCommand.map((card) => (
          <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button">
            <span>AI Commander</span>
            <strong>{card.name}</strong>
          </button>
        ))}
      </div>
    </section>
  );
}

function ZoneCount({ counts, label }: { counts: BattlefieldViewModel["humanZoneCounts"]; label: string }) {
  return (
    <dl>
      <dt>{label}</dt>
      <dd>Library {counts.library}</dd>
      <dd>Graveyard {counts.graveyard}</dd>
      <dd>Exile {counts.exile}</dd>
      <dd>Command {counts.command}</dd>
    </dl>
  );
}

function ActionPanel({
  pending,
  promptActions,
  selectedActions,
  selectedCard,
  onRunAction
}: {
  pending: boolean;
  promptActions: LegalAction[];
  selectedActions: LegalAction[];
  selectedCard: BattlefieldCardView | undefined;
  onRunAction: ((action: LegalAction) => void) | undefined;
}) {
  const visibleActions = selectedActions.length > 0 ? selectedActions : promptActions.slice(0, 8);
  if (visibleActions.length === 0) return null;

  return (
    <section className="arena-context-panel" aria-label="Context actions">
      <h2>{selectedCard?.name ?? "Prompt"}</h2>
      <div>
        {visibleActions.map((action) => (
          <button disabled={pending || !onRunAction} key={action.id} onClick={() => onRunAction?.(action)} type="button">
            {shortActionLabel(action)}
          </button>
        ))}
      </div>
    </section>
  );
}

function ArenaCardButton({
  card,
  selected,
  onHover,
  onSelect,
  compact = false,
  hand = false,
  handStyle
}: {
  card: BattlefieldCardView;
  selected: boolean;
  onHover: (instanceId: string | undefined) => void;
  onSelect: (card: BattlefieldCardView) => void;
  compact?: boolean;
  hand?: boolean;
  handStyle?: CSSProperties;
}) {
  const onClick: MouseEventHandler<HTMLButtonElement> = () => onSelect(card);
  const onMouseEnter: MouseEventHandler<HTMLButtonElement> = () => onHover(card.instanceId);
  const onMouseLeave: MouseEventHandler<HTMLButtonElement> = () => onHover(undefined);
  const classes = [
    "battle-card",
    compact ? "is-compact" : "",
    hand ? "is-hand" : "",
    selected ? "is-selected" : "",
    card.tapped ? "is-tapped" : "",
    card.isAttacking ? "is-attacking" : "",
    card.legalActionTypes.length > 0 ? "is-legal" : ""
  ].filter(Boolean).join(" ");

  return (
    <button
      className={classes}
      onClick={onClick}
      onMouseEnter={onMouseEnter}
      onMouseLeave={onMouseLeave}
      style={handStyle}
      type="button"
      aria-label={`${card.name} card`}
    >
      {card.imageUrl ? <img alt="" draggable={false} src={card.imageUrl} /> : <span className="battle-card-fallback">{card.name}</span>}
      {card.quantity > 1 ? <span className="battle-card-quantity">x{card.quantity}</span> : null}
      {card.power !== undefined && card.toughness !== undefined ? (
        <span className="battle-card-stat">{card.power}/{card.toughness}</span>
      ) : null}
      {card.counters.length > 0 ? (
        <span className="battle-card-counters">
          {card.counters.map((counter) => (
            <span key={counter.label}>{counter.label} {counter.value}</span>
          ))}
        </span>
      ) : null}
    </button>
  );
}

function CardInspector({ card, pinned }: { card: BattlefieldCardView; pinned: boolean }) {
  return (
    <aside className={pinned ? "arena-card-inspector is-pinned" : "arena-card-inspector"} aria-label="Card inspector">
      <span>Card inspector</span>
      {card.imageUrl ? <img alt="" src={card.imageUrl} /> : <div className="arena-card-inspector-fallback">{card.name}</div>}
      <strong>{card.name}</strong>
      <small>{card.manaCost ? `${card.manaCost} · ` : ""}{card.typeLine}</small>
      {card.oracleText ? <p>{card.oracleText}</p> : null}
    </aside>
  );
}

function getRenderableCards(viewModel: BattlefieldViewModel): BattlefieldCardView[] {
  return [
    ...viewModel.humanHand,
    ...viewModel.humanCreatures,
    ...viewModel.humanLands,
    ...viewModel.humanAttackers,
    ...viewModel.opponentCreatures,
    ...viewModel.opponentLands,
    ...viewModel.opponentAttackers,
    ...viewModel.stack,
    ...viewModel.humanCommand,
    ...viewModel.opponentCommand
  ];
}

function formatStepLabel(step: BattlefieldViewModel["step"]): string {
  return stageLabels.find(([candidate]) => candidate === step)?.[1] ?? step;
}

function shortActionLabel(action: LegalAction): string {
  switch (action.type) {
    case "advance_phase":
      return "Next";
    case "pass_priority":
      return "Pass";
    case "pass_until_response":
      return "Pass Until Response";
    case "pass_until_next_turn":
      return "Skip Turn";
    case "play_land":
      return "Play";
    case "cast_spell":
      return "Cast";
    case "tap_permanent":
      return "Tap";
    case "declare_attackers":
      return "Attack";
    case "declare_blockers":
      return "Block";
    case "make_mana":
      return "Mana";
    case "choose_target":
      return "Target";
    case "choose_card":
      return "Choose";
    case "resolve_choice":
      return "Resolve";
    default:
      return action.label;
  }
}
