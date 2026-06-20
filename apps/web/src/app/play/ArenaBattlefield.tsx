"use client";

import type { CSSProperties, MouseEventHandler } from "react";
import { getHandFanStyle } from "./arena-layout";
import { ArenaFxLayer } from "./ArenaFxLayer";
import type { BattlefieldCardView, BattlefieldViewModel } from "./battlefield-view-model";

interface ArenaBattlefieldProps {
  viewModel: BattlefieldViewModel;
  selectedInstanceId?: string | undefined;
  onSelectCard: (card: BattlefieldCardView) => void;
}

export function ArenaBattlefield({ viewModel, selectedInstanceId, onSelectCard }: ArenaBattlefieldProps) {
  return (
    <div className="arena-battlefield" data-testid="arena-battlefield" aria-label="Arena-style Commander battlefield">
      <ArenaFxLayer phase={viewModel.phase} />
      <div className="arena-map-river" aria-hidden="true" />

      <div className="arena-zone arena-zone-opponent-lands" aria-label="Opponent lands">
        {viewModel.opponentLands.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onSelect={onSelectCard} compact />
        ))}
      </div>

      <div className="arena-zone arena-zone-opponent-creatures" aria-label="Opponent creatures">
        {viewModel.opponentCreatures.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onSelect={onSelectCard} />
        ))}
      </div>

      <div className="arena-combat-lane" aria-label="Combat lane">
        {[...viewModel.opponentAttackers, ...viewModel.humanAttackers].map((card) => (
          <div className="arena-attacker" key={card.instanceId}>
            <span className="arena-attack-arrow" aria-hidden="true" />
            <ArenaCardButton card={card} selected={selectedInstanceId === card.instanceId} onSelect={onSelectCard} />
          </div>
        ))}
      </div>

      <div className="arena-zone arena-zone-player-creatures" aria-label="Your creatures">
        {viewModel.humanCreatures.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onSelect={onSelectCard} />
        ))}
      </div>

      <div className="arena-zone arena-zone-player-lands" aria-label="Your lands">
        {viewModel.humanLands.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onSelect={onSelectCard} compact />
        ))}
      </div>

      <div className="arena-stack-zone" aria-label="Stack">
        {viewModel.stack.map((card) => (
          <ArenaCardButton card={card} key={card.instanceId} selected={selectedInstanceId === card.instanceId} onSelect={onSelectCard} compact />
        ))}
      </div>

      <div className="arena-hand-fan" aria-label="Your hand">
        {viewModel.humanHand.map((card, index) => (
          <ArenaCardButton
            card={card}
            handStyle={getHandFanStyle(index, viewModel.humanHand.length, selectedInstanceId === card.instanceId)}
            key={card.instanceId}
            selected={selectedInstanceId === card.instanceId}
            onSelect={onSelectCard}
            hand
          />
        ))}
      </div>

      <div className="arena-priority-strip">
        <span>Priority: {viewModel.priorityPlayerName}</span>
        <strong>{viewModel.phase}</strong>
        <span>Turn {viewModel.turn}</span>
      </div>
    </div>
  );
}

function ArenaCardButton({
  card,
  selected,
  onSelect,
  compact = false,
  hand = false,
  handStyle
}: {
  card: BattlefieldCardView;
  selected: boolean;
  onSelect: (card: BattlefieldCardView) => void;
  compact?: boolean;
  hand?: boolean;
  handStyle?: CSSProperties;
}) {
  const onClick: MouseEventHandler<HTMLButtonElement> = () => onSelect(card);
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
    <button className={classes} onClick={onClick} style={handStyle} type="button" aria-label={`${card.name} card`}>
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
