"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import type { CommanderGameConfig, EngineHealth, GameCommand, GameSnapshot, LegalAction } from "@magicmobile/shared";
import { ArenaBattlefield } from "./ArenaBattlefield";
import { buildBattlefieldViewModel, type BattlefieldCardView, type VisualCardRecord } from "./battlefield-view-model";

interface GameControllerProps {
  config: CommanderGameConfig;
  initialHealth: EngineHealth;
  simulatorMode: boolean;
  visuals: VisualCardRecord;
}

export function GameController({ config, initialHealth, simulatorMode, visuals }: GameControllerProps) {
  const [snapshot, setSnapshot] = useState<GameSnapshot | null>(null);
  const [selectedInstanceId, setSelectedInstanceId] = useState<string | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    let active = true;
    setError(undefined);
    fetch("/api/engine/commander", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(config)
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Game start failed (${response.status})`);
        return response.json() as Promise<GameSnapshot>;
      })
      .then((nextSnapshot) => {
        if (active) {
          setSnapshot(nextSnapshot);
          setSelectedInstanceId(undefined);
        }
      })
      .catch((caughtError) => {
        if (active) setError(caughtError instanceof Error ? caughtError.message : "Game start failed");
      });

    return () => {
      active = false;
    };
  }, [config]);

  const viewModel = useMemo(() => {
    if (!snapshot) return undefined;
    return buildBattlefieldViewModel(snapshot, visuals, config.humanPlayerId);
  }, [config.humanPlayerId, snapshot, visuals]);

  const selectedCard = useMemo(() => {
    if (!viewModel || !selectedInstanceId) return undefined;
    return getAllCards(viewModel).find((card) => card.instanceId === selectedInstanceId);
  }, [selectedInstanceId, viewModel]);

  const legalActions = snapshot?.legalActions ?? [];
  const health = snapshot?.engineHealth ?? initialHealth;
  const modeLabel = simulatorMode ? "Simulator preview" : "XMage rules";

  const runAction = (type: LegalAction["type"]) => {
    if (!snapshot || !viewModel) return;
    const action = pickLegalAction(type, legalActions, selectedInstanceId);
    if (!action) return;
    const actionCard = selectedCard ?? findActionCard(viewModel, action.cardInstanceId);
    const command = toCommand(action, snapshot, actionCard, viewModel.opponent.playerId);
    if (!command) return;

    startTransition(() => {
      setError(undefined);
      fetch(`/api/engine/games/${encodeURIComponent(snapshot.id)}/commands`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(command)
      })
        .then((response) => {
          if (!response.ok) throw new Error(`Command failed (${response.status})`);
          return response.json() as Promise<GameSnapshot>;
        })
        .then((nextSnapshot) => setSnapshot(nextSnapshot))
        .catch((caughtError) => setError(caughtError instanceof Error ? caughtError.message : "Command failed"));
    });
  };

  const actionEnabled = (type: LegalAction["type"]) => Boolean(pickLegalAction(type, legalActions, selectedInstanceId));

  return (
    <section className="arena-screen" aria-label="Horizontal game battlefield">
      <div className="arena-top-hud">
        <PlayerBadge name="Noaddrag" life={viewModel?.opponent.life ?? 40} />
        <div className="arena-status">
          <strong>{viewModel?.phase ?? "starting"}</strong>
          <span>{modeLabel}</span>
          <small>{health.status}: {simulatorMode ? "UI mechanics only; full rules require XMage bridge." : health.reason}</small>
        </div>
      </div>

      {viewModel ? (
        <ArenaBattlefield
          viewModel={viewModel}
          selectedInstanceId={selectedInstanceId}
          onSelectCard={(card) => setSelectedInstanceId(card.instanceId)}
        />
      ) : (
        <div className="arena-battlefield is-loading" data-testid="arena-battlefield">
          <p>{error ?? "Starting Commander table..."}</p>
        </div>
      )}

      <div className="arena-bottom-hud">
        <PlayerBadge name="TabletopPolish" life={viewModel?.human.life ?? 40} active />
        <div className="arena-selected-card">
          <span>Selected</span>
          <strong>{selectedCard?.name ?? "Choose a card"}</strong>
        </div>
        <aside className="arena-action-rail" aria-label="Game actions">
          <button disabled={!actionEnabled("advance_phase") || isPending} onClick={() => runAction("advance_phase")} type="button">
            Next
          </button>
          <span>{isPending ? "Resolving" : "Engine approved"}</span>
          <div>
            <button disabled={!actionEnabled("cast_spell") || isPending} onClick={() => runAction("cast_spell")} type="button">Cast</button>
            <button disabled={!actionEnabled("tap_permanent") || isPending} onClick={() => runAction("tap_permanent")} type="button">Tap</button>
            <button disabled={!actionEnabled("declare_attackers") || isPending} onClick={() => runAction("declare_attackers")} type="button">
              Attack
            </button>
            <button disabled={!actionEnabled("pass_priority") || isPending} onClick={() => runAction("pass_priority")} type="button">Pass</button>
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

function pickLegalAction(type: LegalAction["type"], legalActions: LegalAction[], selectedInstanceId?: string): LegalAction | undefined {
  const selectedAction = legalActions.find((action) => action.type === type && action.cardInstanceId === selectedInstanceId);
  if (selectedInstanceId && isCardSpecificAction(type)) {
    return selectedAction;
  }
  return selectedAction ?? legalActions.find((action) => action.type === type);
}

function isCardSpecificAction(type: LegalAction["type"]): boolean {
  return ["activate_ability", "cast_spell", "choose_target", "declare_attackers", "declare_blockers", "tap_permanent", "untap_permanent"].includes(type);
}

function findActionCard(viewModel: ReturnType<typeof buildBattlefieldViewModel>, cardInstanceId?: string): BattlefieldCardView | undefined {
  if (!cardInstanceId) return undefined;
  return getAllCards(viewModel).find((card) => card.instanceId === cardInstanceId);
}

function getAllCards(viewModel: ReturnType<typeof buildBattlefieldViewModel>): BattlefieldCardView[] {
  return [
    ...viewModel.humanHand,
    ...viewModel.humanCreatures,
    ...viewModel.humanLands,
    ...viewModel.humanAttackers,
    ...viewModel.opponentCreatures,
    ...viewModel.opponentLands,
    ...viewModel.opponentAttackers,
    ...viewModel.stack
  ];
}

function toCommand(
  action: LegalAction,
  snapshot: GameSnapshot,
  selectedCard: BattlefieldCardView | undefined,
  opponentPlayerId: string
): GameCommand | undefined {
  switch (action.type) {
    case "cast_spell":
      return {
        type: "cast_spell",
        gameId: snapshot.id,
        playerId: action.playerId,
        ...(action.cardInstanceId ? { cardInstanceId: action.cardInstanceId } : {}),
        ...(selectedCard?.name ? { cardName: selectedCard.name, fromZone: "hand" as const } : {})
      };
    case "tap_permanent":
      return action.cardInstanceId
        ? { type: "tap_permanent", gameId: snapshot.id, playerId: action.playerId, cardInstanceId: action.cardInstanceId }
        : undefined;
    case "declare_attackers":
      return action.cardInstanceId
        ? {
            type: "declare_attackers",
            gameId: snapshot.id,
            playerId: action.playerId,
            attackers: [{ attackerId: action.cardInstanceId, defenderId: opponentPlayerId }]
          }
        : undefined;
    case "pass_priority":
      return { type: "pass_priority", gameId: snapshot.id, playerId: action.playerId };
    case "advance_phase":
      return { type: "advance_phase", gameId: snapshot.id, playerId: action.playerId };
    case "concede":
      return { type: "concede", gameId: snapshot.id, playerId: action.playerId };
    default:
      return undefined;
  }
}
