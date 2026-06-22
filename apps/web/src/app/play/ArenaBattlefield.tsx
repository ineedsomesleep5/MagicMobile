"use client";

import React, { useMemo, useState } from "react";
import type { CSSProperties, MouseEventHandler } from "react";
import { getHandFanStyle } from "./arena-layout";
import { ArenaFxLayer } from "./ArenaFxLayer";
import type { BattlefieldCardView, BattlefieldViewModel } from "./battlefield-view-model";
import type { GameSnapshot, LegalAction, ManaPool, PromptEnvelope, PromptEnvelopeV2, XmageCombatGroup, XmageNamedZone, XmageStackObject, ZoneCard } from "@magicmobile/shared";

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
        <CombatPairingsPanel combat={snapshot?.xmage?.combat} />
        <GameLog entries={viewModel.logEntries} />
        <ZonePanel
          humanCommand={viewModel.humanCommand}
          humanCounts={viewModel.humanZoneCounts}
          opponentCommand={viewModel.opponentCommand}
          opponentCounts={viewModel.opponentZoneCounts}
          humanGraveyard={viewModel.humanGraveyard}
          opponentGraveyard={viewModel.opponentGraveyard}
          humanExile={viewModel.humanExile}
          opponentExile={viewModel.opponentExile}
          humanManaPool={viewModel.human.manaPool}
          opponentManaPool={viewModel.opponent.manaPool}
          stackCards={viewModel.stack}
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
        <span>Turn {viewModel.turn} {viewModel.health ? `(Engine: ${viewModel.health.status})` : ""}</span>
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
    <details className="arena-stage-panel" open style={{ pointerEvents: "auto" }}>
      <summary style={{ cursor: "pointer", outline: "none", listStyle: "none" }}>
        <h2 style={{ display: "inline-block", margin: 0 }}>Stages</h2>
      </summary>
      <ol className="arena-stage-tracker" aria-label="Game stage tracker" style={{ marginTop: "0.38rem" }}>
        {stageLabels.map(([step, label]) => (
          <li className={step === activeStep ? "is-active" : ""} key={step}>
            {label}
          </li>
        ))}
      </ol>
    </details>
  );
}

function GameLog({ entries }: { entries: BattlefieldViewModel["logEntries"] }) {
  return (
    <details className="arena-log-panel" aria-label="Move log" open style={{ pointerEvents: "auto" }}>
      <summary style={{ cursor: "pointer", outline: "none", listStyle: "none" }}>
        <h2 style={{ display: "inline-block", margin: 0 }}>Log</h2>
      </summary>
      <div style={{ marginTop: "0.38rem" }}>
        {entries.length > 0 ? (
          <ol>
            {entries.map((entry) => (
              <li key={entry.id}>{entry.message}</li>
            ))}
          </ol>
        ) : (
          <p>Waiting for first move</p>
        )}
      </div>
    </details>
  );
}

function ManaPoolCompact({ pool }: { pool?: ManaPool | undefined }) {
  if (!pool) return <span style={{ fontSize: "0.7rem", color: "rgba(246,240,223,0.4)" }}>None</span>;
  const symbols = ["W", "U", "B", "R", "G", "C"] as const;
  const colors: Record<string, string> = {
    W: "#fef3c7",
    U: "#3b82f6",
    B: "#1f2937",
    R: "#ef4444",
    G: "#10b981",
    C: "#6b7280"
  };
  const textColors: Record<string, string> = {
    W: "#000",
    U: "#fff",
    B: "#fff",
    R: "#fff",
    G: "#fff",
    C: "#fff"
  };

  return (
    <span style={{ display: "inline-flex", gap: "2px" }}>
      {symbols.map((sym) => {
        const count = pool[sym] ?? 0;
        if (count === 0) return null;
        return (
          <span
            key={sym}
            style={{
              background: colors[sym],
              color: textColors[sym],
              padding: "1px 4px",
              borderRadius: "3px",
              fontSize: "0.65rem",
              fontWeight: "bold",
              border: "1px solid rgba(255,255,255,0.15)"
            }}
          >
            {sym}:{count}
          </span>
        );
      })}
      {Object.values(pool).every((val) => val === 0) && (
        <span style={{ fontSize: "0.65rem", color: "rgba(246,240,223,0.4)" }}>0</span>
      )}
    </span>
  );
}

function ZonePanel({
  humanCommand,
  humanCounts,
  opponentCommand,
  opponentCounts,
  humanGraveyard,
  opponentGraveyard,
  humanExile,
  opponentExile,
  humanManaPool,
  opponentManaPool,
  stackCards,
  onSelectCard
}: {
  humanCommand: BattlefieldViewModel["humanCommand"];
  humanCounts: BattlefieldViewModel["humanZoneCounts"];
  opponentCommand: BattlefieldViewModel["opponentCommand"];
  opponentCounts: BattlefieldViewModel["opponentZoneCounts"];
  humanGraveyard: BattlefieldViewModel["humanGraveyard"];
  opponentGraveyard: BattlefieldViewModel["opponentGraveyard"];
  humanExile: BattlefieldViewModel["humanExile"];
  opponentExile: BattlefieldViewModel["opponentExile"];
  humanManaPool?: ManaPool | undefined;
  opponentManaPool?: ManaPool | undefined;
  stackCards: BattlefieldViewModel["stack"];
  onSelectCard: (card: BattlefieldCardView) => void;
}) {
  return (
    <details className="arena-zone-panel" aria-label="Player zones" open style={{ pointerEvents: "auto" }}>
      <summary style={{ cursor: "pointer", outline: "none", listStyle: "none" }}>
        <h2 style={{ display: "inline-block", margin: 0 }}>Zones</h2>
      </summary>
      <div style={{ marginTop: "0.38rem", display: "grid", gap: "0.42rem" }}>
        <div className="arena-zone-count-grid">
          <ZoneCount label="You" counts={humanCounts} />
          <ZoneCount label="AI" counts={opponentCounts} />
        </div>

        {/* Mana Pools */}
        <details className="zone-details-group" style={{ cursor: "pointer", borderTop: "1px solid rgba(246, 240, 223, 0.12)", paddingTop: "0.45rem" }} open>
          <summary style={{ fontSize: "0.7rem", color: "#ffb45d", fontWeight: "bold", outline: "none", listStyle: "none" }}>
            <strong style={{ fontSize: "0.6rem", color: "#ffb45d", textTransform: "uppercase", display: "inline-block" }}>Mana Pools</strong>
          </summary>
          <div style={{ display: "flex", flexDirection: "column", gap: "4px", marginTop: "4px", paddingLeft: "8px" }}>
            <div>
              <span style={{ fontSize: "0.7rem", color: "rgba(246, 240, 223, 0.7)" }}>You: </span>
              <ManaPoolCompact pool={humanManaPool} />
            </div>
            <div>
              <span style={{ fontSize: "0.7rem", color: "rgba(246, 240, 223, 0.7)" }}>AI: </span>
              <ManaPoolCompact pool={opponentManaPool} />
            </div>
          </div>
        </details>

        {/* Zone Card Details */}
        <div className="arena-zone-details" style={{ display: "flex", flexDirection: "column", gap: "4px", borderTop: "1px solid rgba(246, 240, 223, 0.12)", padding: "0.45rem" }}>
          
          {/* Command Zone */}
          <details className="zone-details-group" style={{ cursor: "pointer" }}>
            <summary style={{ fontSize: "0.7rem", color: "#ffb45d", fontWeight: "bold", outline: "none" }}>
              Command Zone ({humanCommand.length + opponentCommand.length})
            </summary>
            <div className="zone-card-list" style={{ display: "flex", flexDirection: "column", gap: "2px", marginTop: "4px", paddingLeft: "8px" }}>
              {humanCommand.map((card) => (
                <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button" style={zoneCardBtnStyle}>
                  [You] {card.name}
                </button>
              ))}
              {opponentCommand.map((card) => (
                <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button" style={zoneCardBtnStyle}>
                  [AI] {card.name}
                </button>
              ))}
              {humanCommand.length === 0 && opponentCommand.length === 0 && (
                <span style={{ fontSize: "0.65rem", color: "rgba(246,240,223,0.4)" }}>Empty</span>
              )}
            </div>
          </details>

          {/* Graveyard */}
          <details className="zone-details-group" style={{ cursor: "pointer" }}>
            <summary style={{ fontSize: "0.7rem", color: "#ffb45d", fontWeight: "bold", outline: "none" }}>
              Graveyard ({humanGraveyard.length + opponentGraveyard.length})
            </summary>
            <div className="zone-card-list" style={{ display: "flex", flexDirection: "column", gap: "2px", marginTop: "4px", paddingLeft: "8px" }}>
              {humanGraveyard.map((card) => (
                <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button" style={zoneCardBtnStyle}>
                  [You] {card.name}
                </button>
              ))}
              {opponentGraveyard.map((card) => (
                <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button" style={zoneCardBtnStyle}>
                  [AI] {card.name}
                </button>
              ))}
              {humanGraveyard.length === 0 && opponentGraveyard.length === 0 && (
                <span style={{ fontSize: "0.65rem", color: "rgba(246,240,223,0.4)" }}>Empty</span>
              )}
            </div>
          </details>

          {/* Exile */}
          <details className="zone-details-group" style={{ cursor: "pointer" }}>
            <summary style={{ fontSize: "0.7rem", color: "#ffb45d", fontWeight: "bold", outline: "none" }}>
              Exile ({humanExile.length + opponentExile.length})
            </summary>
            <div className="zone-card-list" style={{ display: "flex", flexDirection: "column", gap: "2px", marginTop: "4px", paddingLeft: "8px" }}>
              {humanExile.map((card) => (
                <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button" style={zoneCardBtnStyle}>
                  [You] {card.name}
                </button>
              ))}
              {opponentExile.map((card) => (
                <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button" style={zoneCardBtnStyle}>
                  [AI] {card.name}
                </button>
              ))}
              {humanExile.length === 0 && opponentExile.length === 0 && (
                <span style={{ fontSize: "0.65rem", color: "rgba(246,240,223,0.4)" }}>Empty</span>
              )}
            </div>
          </details>

          {/* Stack */}
          <details className="zone-details-group" style={{ cursor: "pointer" }}>
            <summary style={{ fontSize: "0.7rem", color: "#ffb45d", fontWeight: "bold", outline: "none" }}>
              Stack ({stackCards.length})
            </summary>
            <div className="zone-card-list" style={{ display: "flex", flexDirection: "column", gap: "2px", marginTop: "4px", paddingLeft: "8px" }}>
              {stackCards.map((card) => (
                <button key={card.instanceId} onClick={() => onSelectCard(card)} type="button" style={zoneCardBtnStyle}>
                  {card.name}
                </button>
              ))}
              {stackCards.length === 0 && (
                <span style={{ fontSize: "0.65rem", color: "rgba(246,240,223,0.4)" }}>Empty</span>
              )}
            </div>
          </details>

        </div>
      </div>
    </details>
  );
}

const zoneCardBtnStyle: CSSProperties = {
  background: "none",
  border: "none",
  color: "rgba(246, 240, 223, 0.8)",
  textAlign: "left",
  fontSize: "0.75rem",
  padding: "2px 4px",
  cursor: "pointer",
  width: "100%",
  display: "block",
  overflow: "hidden",
  textOverflow: "ellipsis",
  whiteSpace: "nowrap"
};

function CombatPairingsPanel({ combat }: { combat?: XmageCombatGroup[] | undefined }) {
  if (!combat || combat.length === 0) return null;
  return (
    <details className="arena-combat-pairings-panel" aria-label="Combat pairings" open style={{ padding: "0.45rem", border: "1px solid rgba(246, 240, 223, 0.12)", borderRadius: "8px", background: "rgba(6, 9, 10, 0.58)", pointerEvents: "auto" }}>
      <summary style={{ cursor: "pointer", outline: "none", listStyle: "none" }}>
        <h2 style={{ display: "inline-block", margin: 0 }}>Combat Pairings</h2>
      </summary>
      <div style={{ marginTop: "0.38rem", display: "flex", flexDirection: "column", gap: "6px" }}>
        {combat.map((group, idx) => (
          <div key={idx} style={{ fontSize: "0.7rem", color: "rgba(246,240,223,0.85)" }}>
            <div style={{ fontWeight: "bold" }}>Defending: {group.defenderName}</div>
            {group.attackers.map((att) => {
              const attackersBlockers = group.blockers.map(b => b.card.name).join(", ");
              return (
                <div key={att.instanceId} style={{ paddingLeft: "6px", marginTop: "2px" }}>
                  ⚔️ <strong>{att.card.name}</strong> 
                  {group.blocked ? (
                    <span style={{ color: "#ef4444" }}> (Blocked by: {attackersBlockers || "blockers"})</span>
                  ) : (
                    <span style={{ color: "#10b981" }}> (Unblocked)</span>
                  )}
                </div>
              );
            })}
          </div>
        ))}
      </div>
    </details>
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
  if (visibleActions.length === 0 && !selectedCard) return null;

  return (
    <section className="arena-context-panel" aria-label="Context actions">
      <h2>{selectedCard?.name ?? "Prompt"}</h2>
      {visibleActions.length > 0 ? (
        <div>
          {visibleActions.map((action) => (
            <button
              className={isCastOrPlayAction(action) ? "arena-primary-action" : undefined}
              disabled={pending || !onRunAction}
              key={action.id}
              onClick={() => onRunAction?.(action)}
              type="button"
            >
              {shortActionLabel(action)}
              {actionHint(action) ? <small>{actionHint(action)}</small> : null}
            </button>
          ))}
        </div>
      ) : (
        <p className="arena-action-help">
          XMage is not exposing a cast/play action for this card right now. Answer the active prompt, wait for priority, or inspect the card.
        </p>
      )}
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

  const isCommanderReplacement = (p: PromptEnvelopeV2) => {
    const type = (p.responseCommand?.type ?? p.responseKind ?? "").toLowerCase();
    return type === "commander_replacement" || (p.message ?? "").toLowerCase().includes("command zone");
  };

  const isConfirmationPrompt = (p: PromptEnvelopeV2) => {
    return p.responseCommand?.type?.toLowerCase() === "answer_yes_no" || (p.responseKind ?? "").toLowerCase() === "confirmation";
  };

  const isManaPrompt = (p: PromptEnvelopeV2) => {
    return p.responseCommand?.type?.toLowerCase() === "play_mana" || ["mana", "play_mana"].includes((p.responseKind ?? "").toLowerCase());
  };

  const isManaOrPaymentPrompt = (p: PromptEnvelopeV2) => {
    const type = p.responseCommand?.type?.toLowerCase() ?? "";
    const kind = (p.responseKind ?? "").toLowerCase();
    const message = (p.message ?? "").toLowerCase();
    return isManaPrompt(p) || ["pay_cost", "choose_mana", "play_x_mana"].includes(type) || ["pay_cost", "cost", "mana", "x_mana"].includes(kind) || message.includes("pay") || message.includes("mana");
  };

  const isTriggerOrderPrompt = (p: PromptEnvelopeV2) => {
    return (p.responseCommand?.type?.toLowerCase() ?? p.responseKind?.toLowerCase() ?? "") === "order_triggers";
  };

  const isSearchPrompt = (p: PromptEnvelopeV2) => {
    const type = p.responseCommand?.type?.toLowerCase() ?? p.responseKind?.toLowerCase() ?? "";
    return type === "search_select" || (p.method ?? "").toLowerCase().includes("search");
  };

  return (
    <section className="arena-prompt-detail-panel" aria-label="XMage prompt detail">
      <h2>{formatPromptMethod(prompt.method)}</h2>
      <strong>{prompt.message}</strong>
      <small>{formatPromptRequirement(prompt)}</small>

      {isManaOrPaymentPrompt(prompt) ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Available Mana Sources"
          options={actions
            .filter((action) => action.type === "make_mana" && (action.sourceInstanceId || action.cardInstanceId))
            .map((action) => ({
              id: action.id,
              label: `${action.cardName ? `Tap ${action.cardName}` : action.label}${actionHint(action) ? ` · ${actionHint(action)}` : ""}`,
              type: "make_mana" as const
            }))}
          onRun={runPromptValue}
        />
      ) : null}

      {/* Commander Replacement parity */}
      {isCommanderReplacement(prompt) ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Commander Placement"
          options={[
            { id: "command_zone", label: "Command Zone", type: "commander_replacement" },
            { id: "graveyard", label: "Original Zone", type: "commander_replacement" }
          ]}
          onRun={runPromptValue}
        />
      ) : null}

      {/* Confirmation parity */}
      {!prompt.confirmation && isConfirmationPrompt(prompt) ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Confirmation"
          options={[
            { id: "true", label: "Yes", type: prompt.responseCommand?.type ?? "answer_yes_no" },
            { id: "false", label: "No", type: prompt.responseCommand?.type ?? "answer_yes_no" }
          ]}
          onRun={runPromptValue}
        />
      ) : null}

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
      
      {/* Mana choices and Mana Picker parity */}
      <PromptActionList
        disabled={pending || !onRunAction}
        label="Mana"
        options={prompt.manaChoices?.map((choice) => ({ id: choice.manaType ?? choice.id, label: choice.label, type: "play_mana" as const })) ?? []}
        onRun={runPromptValue}
      />
      {isManaPrompt(prompt) && (!prompt.manaChoices || prompt.manaChoices.length === 0) ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Mana Picker"
          options={[
            { id: "W", label: "{W}", type: "play_mana" },
            { id: "U", label: "{U}", type: "play_mana" },
            { id: "B", label: "{B}", type: "play_mana" },
            { id: "R", label: "{R}", type: "play_mana" },
            { id: "G", label: "{G}", type: "play_mana" },
            { id: "C", label: "{C}", type: "play_mana" }
          ]}
          onRun={runPromptValue}
        />
      ) : null}

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
      
      {/* Trigger Order parity */}
      {isTriggerOrderPrompt(prompt) ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Trigger Order"
          options={[
            {
              id: (prompt.cards?.map(c => c.instanceId) ?? prompt.targets?.map(t => t.id) ?? prompt.choices?.map(c => c.id) ?? []).join(","),
              label: "Submit shown order",
              type: "order_triggers"
            }
          ]}
          onRun={runPromptValue}
        />
      ) : null}

      {/* Search/Select parity */}
      {isSearchPrompt(prompt) && (!prompt.cards || prompt.cards.length === 0) && (!prompt.targets || prompt.targets.length === 0) ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Search/Select"
          options={[
            {
              id: (prompt.targetIds ?? []).join(","),
              label: "Submit exposed selection",
              type: "search_select"
            }
          ]}
          onRun={runPromptValue}
        />
      ) : null}

      {prompt.confirmation ? (
        <PromptActionList
          disabled={pending || !onRunAction}
          label="Confirmation"
          options={[
            { id: "true", label: prompt.confirmation.yesLabel ?? "Yes", type: prompt.confirmation.yesCommand?.type ?? prompt.responseCommand?.type ?? "answer_yes_no" },
            { id: "false", label: prompt.confirmation.noLabel ?? "No", type: prompt.confirmation.noCommand?.type ?? prompt.responseCommand?.type ?? "answer_yes_no" }
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
    <details className="arena-stack-detail-panel" aria-label="Stack detail" open style={{ pointerEvents: "auto" }}>
      <summary style={{ cursor: "pointer", outline: "none", listStyle: "none" }}>
        <h2 style={{ display: "inline-block", margin: 0 }}>Stack</h2>
      </summary>
      <div style={{ marginTop: "0.38rem" }}>
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
      </div>
    </details>
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
    <details className="arena-zone-access-panel" aria-label="Visible XMage zones" open style={{ pointerEvents: "auto" }}>
      <summary style={{ cursor: "pointer", outline: "none", listStyle: "none" }}>
        <h2 style={{ display: "inline-block", margin: 0 }}>Visible Zones</h2>
      </summary>
      <div style={{ marginTop: "0.38rem", display: "grid", gap: "0.38rem" }}>
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
      </div>
    </details>
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
    ...viewModel.opponentCommand,
    ...viewModel.humanGraveyard,
    ...viewModel.opponentGraveyard,
    ...viewModel.humanExile,
    ...viewModel.opponentExile
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

export function narrowPromptAction(action: LegalAction, type: LegalAction["type"], choiceId: string, label: string): LegalAction {
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
      return { ...narrowed, cardInstanceIds: [choiceId], validCardInstanceIds: [choiceId] };
    case "search_select":
      return {
        ...narrowed,
        cardInstanceIds: choiceId ? choiceId.split(",") : [],
        validCardInstanceIds: choiceId ? choiceId.split(",") : []
      };
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
    case "pay_cost":
      return { ...narrowed, confirmed: choiceId !== "false", pay: choiceId !== "false", targetIds: [choiceId] };
    case "order_items":
    case "order_triggers":
      return { ...narrowed, orderedIds: choiceId ? choiceId.split(",") : [] };
    case "resolve_choice":
      return { ...narrowed, choiceIds: [choiceId], targetIds: [choiceId] };
    case "commander_replacement":
      return { ...narrowed, targetIds: [choiceId], validTargetIds: [choiceId], useCommandZone: choiceId !== "graveyard" };
    default:
      return narrowed;
  }
}

export function narrowCommandTemplate(command: LegalAction["commandTemplate"], type: LegalAction["type"], choiceId: string): LegalAction["commandTemplate"] {
  if (!command) return command;
  const narrowed = { ...command, type };
  switch (type) {
    case "choose_target":
      return { ...narrowed, targetIds: [choiceId] };
    case "choose_card":
      return { ...narrowed, cardInstanceIds: [choiceId] };
    case "search_select":
      return { ...narrowed, cardInstanceIds: choiceId ? choiceId.split(",") : [] };
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
    case "pay_cost":
      return { ...narrowed, confirmed: choiceId !== "false", pay: choiceId !== "false" };
    case "order_items":
    case "order_triggers":
      return { ...narrowed, orderedIds: choiceId ? choiceId.split(",") : [] };
    case "resolve_choice":
      return { ...narrowed, choiceIds: [choiceId] };
    case "commander_replacement":
      return { ...narrowed, useCommandZone: choiceId !== "graveyard" };
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

function isCastOrPlayAction(action: LegalAction): boolean {
  return action.type === "cast_spell" || action.type === "play_land";
}

function actionHint(action: LegalAction): string | undefined {
  if (action.type === "cast_spell") {
    if (action.manaCost && action.requiresPayment) return `${action.manaCost} · XMage will ask for payment`;
    if (action.manaCost) return action.manaCost;
    if (action.requiresPayment) return "XMage will ask for payment";
  }
  if (action.type === "make_mana" && action.producedMana?.length) {
    return action.producedMana.map((symbol) => `{${symbol}}`).join(" ");
  }
  return action.sourceZone ?? action.zoneContext;
}
