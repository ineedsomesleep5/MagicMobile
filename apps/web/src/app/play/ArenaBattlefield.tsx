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
  const runPromptValue = (type: LegalAction["type"], id: string, label: string) => {
    const action = actionForPromptValue(actions, prompt, type, id, label) ?? actionFromPromptValue(prompt, type, id, label);
    if (action) onRunAction?.(action);
  };

  return (
    <section className="arena-prompt-detail-panel" aria-label="XMage prompt detail">
      <h2>{formatPromptMethod(prompt.method)}</h2>
      <strong>{prompt.message}</strong>
      <small>{formatPromptRequirement(prompt)}</small>
      {choices.length > 0 ? (
        <div className="arena-prompt-choice-grid">
          {choices.map((choice) => {
            const type = prompt.responseCommand?.type ?? "resolve_choice";
            const action = actionForPromptValue(actions, prompt, type, choice.id, choice.label) ?? actionFromPromptValue(prompt, type, choice.id, choice.label);
            return (
              <button disabled={pending || !action || !onRunAction} key={choice.id} onClick={() => action && onRunAction?.(action)} type="button">
                {choice.label}
              </button>
            );
          })}
        </div>
      ) : null}
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Targets"
        options={prompt.targets?.map((target) => ({ id: target.id, label: target.label, type: "choose_target" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Players"
        options={prompt.players?.map((player) => ({ id: player.playerId, label: player.life === undefined ? player.label : `${player.label} (${player.life})`, type: "choose_player" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Cards"
        options={prompt.cards?.map((card) => ({ id: card.instanceId, label: card.card.name, type: prompt.responseCommand?.type === "search_select" ? "search_select" as const : "choose_card" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Modes"
        options={prompt.modes?.map((mode) => ({ id: mode.id, label: mode.label, type: "choose_mode" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Abilities"
        options={prompt.abilities?.map((ability) => ({ id: ability.id, label: ability.rulesText ? `${ability.label}: ${ability.rulesText}` : ability.label, type: "choose_ability" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Amounts"
        options={prompt.amounts?.map((amount) => ({ id: String(amount), label: String(amount), type: prompt.responseCommand?.type === "play_x_mana" ? "play_x_mana" as const : "choose_amount" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Mana"
        options={prompt.manaChoices?.map((choice) => ({ id: choice.manaType ?? choice.id, label: choice.label, type: "play_mana" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Piles"
        options={prompt.piles?.map((pile) => ({ id: String(pile.id), label: `${pile.label}: ${pile.cards.map((card) => card.card.name).join(", ")}`, type: "choose_pile" as const })) ?? []}
        onRun={runPromptValue}
      />
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Order"
        options={prompt.orderedItems?.map((item) => ({ id: item.id, label: item.label, type: "order_items" as const })) ?? []}
        onRun={runPromptValue}
      />
      {prompt.confirmation ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Confirmation"
          options={[
            { id: "true", label: prompt.confirmation.yesLabel ?? "Yes", type: "answer_yes_no" as const },
            { id: "false", label: prompt.confirmation.noLabel ?? "No", type: "answer_yes_no" as const }
          ]}
          onRun={runPromptValue}
        />
      ) : null}
    </section>
  );
}

function PromptActionList({
  disabled,
  label,
  onRun,
  options
}: {
  disabled: boolean;
  label: string;
  onRun: (type: LegalAction["type"], id: string, label: string) => void;
  options: Array<{ id: string; label: string; type: LegalAction["type"] }>;
}) {
  if (options.length === 0) return null;
  return (
    <dl className="arena-prompt-item-list">
      <dt>{label}</dt>
      {options.map((item) => (
        <dd key={`${label}-${item.id}`}>
          <button disabled={disabled} onClick={() => onRun(item.type, item.id, item.label)} type="button">
            {item.label}
          </button>
        </dd>
      ))}
    </dl>
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

function actionForPromptValue(actions: LegalAction[], prompt: PromptEnvelopeV2, type: LegalAction["type"], choiceId: string, label: string): LegalAction | undefined {
  const promptId = prompt.responseCommand?.promptId ?? prompt.id;
  const samePrompt = (action: LegalAction) =>
    (action.promptId === undefined || action.promptId === promptId)
    && (action.messageId === undefined || prompt.messageId === undefined || action.messageId === prompt.messageId);
  const action = actions.find((candidate) =>
    samePrompt(candidate) && candidate.type === type && (
      candidate.targetIds?.includes(choiceId)
      || candidate.validTargetIds?.includes(choiceId)
      || candidate.choiceIds?.includes(choiceId)
      || candidate.cardInstanceIds?.includes(choiceId)
      || candidate.validCardInstanceIds?.includes(choiceId)
      || candidate.modeIds?.includes(choiceId)
      || candidate.orderedIds?.includes(choiceId)
      || candidate.playerIds?.includes(choiceId)
      || candidate.validPlayerIds?.includes(choiceId)
      || candidate.manaType === choiceId
      || String(candidate.amount) === choiceId
      || candidate.id === choiceId
      || candidate.id.endsWith(choiceId)
    )
  ) ?? actions.find((action) =>
    samePrompt(action) && action.type === type && (
      action.targetIds?.includes(choiceId)
      || action.validTargetIds?.includes(choiceId)
      || action.choiceIds?.includes(choiceId)
      || action.cardInstanceIds?.includes(choiceId)
      || action.validCardInstanceIds?.includes(choiceId)
      || action.modeIds?.includes(choiceId)
      || action.orderedIds?.includes(choiceId)
      || action.playerIds?.includes(choiceId)
      || action.validPlayerIds?.includes(choiceId)
      || action.manaType === choiceId
      || String(action.amount) === choiceId
      || action.id === choiceId
      || action.id.endsWith(choiceId)
    )
  );
  return action ? narrowPromptAction(action, type, choiceId, label) : undefined;
}

function actionFromPromptValue(prompt: PromptEnvelopeV2, type: LegalAction["type"], choiceId: string, label: string): LegalAction | undefined {
  const commandTemplate = narrowCommandTemplate(prompt.responseCommand, type, choiceId);
  return narrowPromptAction({
    id: `${prompt.id}-${choiceId}`,
    type,
    playerId: prompt.playerId,
    label,
    promptId: prompt.responseCommand?.promptId ?? prompt.id,
    messageId: prompt.messageId,
    zoneContext: "prompt",
    ...(prompt.minChoices === undefined ? {} : { minChoices: prompt.minChoices }),
    ...(prompt.maxChoices === undefined ? {} : { maxChoices: prompt.maxChoices }),
    ...(prompt.required === undefined ? {} : { required: prompt.required }),
    ...(commandTemplate === undefined ? {} : { commandTemplate })
  }, type, choiceId, label);
}

function narrowPromptAction(action: LegalAction, type: LegalAction["type"], choiceId: string, label: string): LegalAction {
  const narrowedTemplate = narrowCommandTemplate(action.commandTemplate, type, choiceId);
  const narrowed: LegalAction = {
    ...action,
    id: `${action.id}-${choiceId}`,
    type,
    label,
    ...(narrowedTemplate === undefined ? {} : { commandTemplate: narrowedTemplate })
  };
  switch (type) {
    case "choose_target":
      return { ...narrowed, targetIds: [choiceId], validTargetIds: [choiceId] };
    case "choose_card":
    case "search_select":
      return { ...narrowed, cardInstanceIds: [choiceId], validCardInstanceIds: [choiceId] };
    case "choose_player":
      return { ...narrowed, playerIds: [choiceId], validPlayerIds: [choiceId] };
    case "choose_mode":
      return { ...narrowed, modeIds: [choiceId] };
    case "choose_ability":
      return { ...narrowed, abilityId: choiceId };
    case "choose_pile":
      return { ...narrowed, targetIds: [choiceId] };
    case "choose_amount":
    case "play_x_mana":
      return { ...narrowed, amount: Number(choiceId), targetIds: [choiceId] };
    case "play_mana":
      return { ...narrowed, manaType: promptManaType(choiceId) };
    case "choose_mana":
      return { ...narrowed, manaTypes: [promptManaType(choiceId)] };
    case "answer_yes_no":
      return { ...narrowed, confirmed: choiceId !== "false", targetIds: [choiceId] };
    case "order_items":
    case "order_triggers":
      return { ...narrowed, orderedIds: [choiceId] };
    case "resolve_choice":
      return { ...narrowed, choiceIds: [choiceId], targetIds: [choiceId] };
    default:
      return narrowed;
  }
}

function narrowCommandTemplate(command: LegalAction["commandTemplate"], type: LegalAction["type"], choiceId: string): LegalAction["commandTemplate"] {
  if (!command) return command;
  const narrowed = { ...command, type };
  switch (type) {
    case "choose_target":
      return { ...narrowed, targetIds: [choiceId] };
    case "choose_card":
    case "search_select":
      return { ...narrowed, cardInstanceIds: [choiceId] };
    case "choose_player":
      return { ...narrowed, playerIds: [choiceId] };
    case "choose_mode":
      return { ...narrowed, modeIds: [choiceId] };
    case "choose_ability":
      return { ...narrowed, abilityId: choiceId };
    case "choose_amount":
    case "play_x_mana":
      return { ...narrowed, amount: Number(choiceId) };
    case "play_mana":
      return { ...narrowed, manaType: promptManaType(choiceId) };
    case "choose_mana":
      return { ...narrowed, manaTypes: [promptManaType(choiceId)] };
    case "answer_yes_no":
      return { ...narrowed, confirmed: choiceId !== "false" };
    case "order_items":
    case "order_triggers":
      return { ...narrowed, orderedIds: [choiceId] };
    case "resolve_choice":
      return { ...narrowed, choiceIds: [choiceId] };
    default:
      return narrowed;
  }
}

function promptManaType(value: string): "W" | "U" | "B" | "R" | "G" | "C" {
  return value === "W" || value === "U" || value === "B" || value === "R" || value === "G" || value === "C" ? value : "C";
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
