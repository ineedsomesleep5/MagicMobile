"use client";

import type { CSSProperties, MouseEventHandler } from "react";
import { useMemo, useState } from "react";
import { getHandFanStyle } from "./arena-layout";
import { ArenaFxLayer } from "./ArenaFxLayer";
import type { BattlefieldCardView, BattlefieldViewModel } from "./battlefield-view-model";
import type { GameSnapshot, LegalAction, PromptEnvelope, PromptEnvelopeV2, XmageNamedZone, XmageStackObject, ZoneCard } from "@magicmobile/shared";

interface ArenaBattlefieldProps {
  viewModel: BattlefieldViewModel;
  snapshot?: GameSnapshot | undefined;
  selectedInstanceId?: string | undefined;
  selectedActions?: LegalAction[];
  promptActions?: LegalAction[];
  actionPending?: boolean;
  onSelectCard: (card: BattlefieldCardView) => void;
  onRunAction?: (action: LegalAction) => void;
}

export function ArenaBattlefield({
  viewModel,
  snapshot,
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
  const promptEnvelope = snapshot?.promptEnvelopeV2 ?? snapshot?.promptEnvelope;

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
        {promptEnvelope ? (
          <PromptEnvelopePanel
            actions={promptActions}
            envelope={promptEnvelope}
            pending={actionPending}
            onRunAction={onRunAction}
          />
        ) : null}
        <StackDetailPanel fallbackStack={viewModel.stack} stackObjects={snapshot?.xmage?.stack ?? []} />
        <ZoneAccessPanel namedZones={namedZoneGroups(snapshot)} onSelectCard={onSelectCard} />
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
  const visibleActions = selectedActions.length > 0 ? selectedActions : promptActions;
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

function PromptEnvelopePanel({
  actions,
  envelope,
  pending,
  onRunAction
}: {
  actions: LegalAction[];
  envelope: PromptEnvelope | PromptEnvelopeV2;
  pending: boolean;
  onRunAction: ((action: LegalAction) => void) | undefined;
}) {
  const prompt = envelope as PromptEnvelopeV2;
  const choices = prompt.choices ?? [];

  return (
    <section className="arena-prompt-detail-panel" aria-label="XMage prompt detail">
      <h2>{formatPromptMethod(prompt.method)}</h2>
      <strong>{prompt.message}</strong>
      <small>{formatPromptRequirement(prompt)}</small>
      {choices.length > 0 ? (
        <div className="arena-prompt-choice-grid">
          {choices.map((choice) => {
            const action = actionForChoice(actions, choice.id);
            return (
              <button disabled={pending || !action || !onRunAction} key={choice.id} onClick={() => action && onRunAction?.(action)} type="button">
                {choice.label}
              </button>
            );
          })}
        </div>
      ) : null}
      <PromptItemList label="Targets" items={prompt.targets?.map((target) => target.label) ?? []} />
      <PromptItemList label="Players" items={prompt.players?.map((player) => player.life === undefined ? player.label : `${player.label} (${player.life})`) ?? []} />
      <PromptItemList label="Cards" items={prompt.cards?.map((card) => card.card.name) ?? []} />
      <PromptItemList label="Modes" items={prompt.modes?.map((mode) => mode.label) ?? []} />
      <PromptItemList label="Abilities" items={prompt.abilities?.map((ability) => ability.rulesText ? `${ability.label}: ${ability.rulesText}` : ability.label) ?? []} />
      <PromptItemList label="Amounts" items={prompt.amounts?.map(String) ?? []} />
      <PromptItemList label="Mana" items={prompt.manaChoices?.map((choice) => choice.label) ?? []} />
      <PromptItemList label="Piles" items={prompt.piles?.map((pile) => `${pile.label}: ${pile.cards.map((card) => card.card.name).join(", ")}`) ?? []} />
      <PromptItemList label="Order" items={prompt.orderedItems?.map((item) => item.label) ?? []} />
      {prompt.confirmation ? (
        <PromptItemList
          label="Confirmation"
          items={[prompt.confirmation.yesLabel ?? "Yes", prompt.confirmation.noLabel ?? "No"]}
        />
      ) : null}
    </section>
  );
}

function PromptItemList({ label, items }: { label: string; items: string[] }) {
  if (items.length === 0) return null;
  return (
    <dl className="arena-prompt-item-list">
      <dt>{label}</dt>
      {items.map((item) => (
        <dd key={`${label}-${item}`}>{item}</dd>
      ))}
    </dl>
  );
}

function StackDetailPanel({
  fallbackStack,
  stackObjects
}: {
  fallbackStack: BattlefieldCardView[];
  stackObjects: XmageStackObject[];
}) {
  if (stackObjects.length === 0 && fallbackStack.length === 0) return null;

  return (
    <section className="arena-stack-detail-panel" aria-label="Stack detail">
      <h2>Stack</h2>
      {stackObjects.length > 0 ? (
        <ol>
          {stackObjects.map((object) => (
            <li key={object.id}>
              <strong>{object.name}</strong>
              {object.sourceCard ? <span>Source: {object.sourceCard.card.name}</span> : null}
              {object.rulesText ? <p>{object.rulesText}</p> : null}
              {object.paid !== undefined ? <small>{object.paid ? "Paid" : "Unpaid"}</small> : null}
            </li>
          ))}
        </ol>
      ) : (
        <ol>
          {fallbackStack.map((card) => (
            <li key={card.instanceId}>
              <strong>{card.name}</strong>
              {card.oracleText ? <p>{card.oracleText}</p> : null}
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}

function ZoneAccessPanel({
  namedZones,
  onSelectCard
}: {
  namedZones: XmageNamedZone[];
  onSelectCard: (card: BattlefieldCardView) => void;
}) {
  if (namedZones.length === 0) return null;

  return (
    <section className="arena-zone-access-panel" aria-label="Visible XMage zones">
      <h2>Visible Zones</h2>
      {namedZones.map((zone) => (
        <div key={zone.id}>
          <strong>{zone.name}</strong>
          <div>
            {zone.cards.map((card) => (
              <button key={card.instanceId} onClick={() => onSelectCard(zoneCardToBattlefieldCard(card))} type="button">
                {card.card.name}
              </button>
            ))}
          </div>
        </div>
      ))}
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

function namedZoneGroups(snapshot: GameSnapshot | undefined): XmageNamedZone[] {
  if (!snapshot?.xmage) return [];
  return [
    ...snapshot.xmage.exileZones,
    ...snapshot.xmage.revealed,
    ...snapshot.xmage.lookedAt,
    ...snapshot.xmage.companion
  ].filter((zone) => zone.cards.length > 0);
}

function zoneCardToBattlefieldCard(card: ZoneCard): BattlefieldCardView {
  return {
    instanceId: card.instanceId,
    name: card.card.name,
    typeLine: card.card.typeLine,
    ...(card.card.oracleText ? { oracleText: card.card.oracleText } : {}),
    tapped: card.tapped ?? false,
    ...(card.power !== undefined ? { power: card.power } : {}),
    ...(card.toughness !== undefined ? { toughness: card.toughness } : {}),
    ...(card.damage !== undefined ? { damage: card.damage } : {}),
    isAttacking: card.isAttacking ?? false,
    blocking: card.blocking ?? [],
    counters: Object.entries(card.counters ?? {}).map(([label, value]) => ({ label, value })),
    quantity: 1,
    legalActionTypes: []
  };
}

function actionForChoice(actions: LegalAction[], choiceId: string): LegalAction | undefined {
  return actions.find((action) =>
    action.targetIds?.includes(choiceId)
    || action.validTargetIds?.includes(choiceId)
    || action.choiceIds?.includes(choiceId)
    || action.cardInstanceIds?.includes(choiceId)
    || action.modeIds?.includes(choiceId)
    || action.orderedIds?.includes(choiceId)
    || action.playerIds?.includes(choiceId)
    || action.validPlayerIds?.includes(choiceId)
    || action.manaType === choiceId
    || String(action.amount) === choiceId
    || action.id === choiceId
    || action.id.endsWith(choiceId)
  );
}

function formatPromptMethod(method: string): string {
  return method.replace(/^GAME_/, "GAME ").replaceAll("_", " ");
}

function formatPromptRequirement(prompt: PromptEnvelope | PromptEnvelopeV2): string {
  const promptV2 = prompt as PromptEnvelopeV2;
  const responseType = (promptV2.responseCommand?.type ?? prompt.responseKind).replaceAll("_", " ");
  const range = prompt.minChoices !== undefined || prompt.maxChoices !== undefined
    ? ` · ${prompt.minChoices ?? 0}-${prompt.maxChoices ?? "any"} choices`
    : "";
  return `${responseType}${prompt.required ? " · required" : ""}${range}`;
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
