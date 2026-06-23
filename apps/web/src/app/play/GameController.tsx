"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import type { CommanderGameConfig, EngineHealth, GameCommand, GameSnapshot, LegalAction, ManaPool } from "@magicmobile/shared";
import { ArenaBattlefield } from "./ArenaBattlefield";
import { buildBattlefieldViewModel, type BattlefieldCardView, type VisualCardRecord } from "./battlefield-view-model";

interface GameControllerProps {
  config: CommanderGameConfig;
  initialHealth: EngineHealth;
  requireXmage?: boolean;
  simulatorMode: boolean;
  visuals: VisualCardRecord;
  webSocketBaseUrl?: string | undefined;
}

export function GameController({ config, initialHealth, requireXmage = false, simulatorMode, visuals, webSocketBaseUrl }: GameControllerProps) {
  const [snapshot, setSnapshot] = useState<GameSnapshot | null>(null);
  const [selectedInstanceId, setSelectedInstanceId] = useState<string | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [pendingActionId, setPendingActionId] = useState<string | undefined>();
  const [pendingActionLabel, setPendingActionLabel] = useState<string | undefined>();
  const [socketStatus, setSocketStatus] = useState<"idle" | "connecting" | "live" | "unavailable">("idle");
  const snapshotRef = useRef<GameSnapshot | null>(null);
  const pendingActionIdRef = useRef<string | undefined>(undefined);

  const finalRequireXmage = requireXmage || !simulatorMode;

  const clearPendingAction = () => {
    pendingActionIdRef.current = undefined;
    setPendingActionId(undefined);
    setPendingActionLabel(undefined);
  };

  const acceptSnapshot = (nextSnapshot: GameSnapshot) => {
    const current = snapshotRef.current;
    const accepted = latestSnapshot(current, nextSnapshot);
    if (accepted === current) return;
    snapshotRef.current = accepted;
    setSnapshot(accepted);
    if (current && pendingActionIdRef.current && shouldClearPendingAfterSnapshot(current, accepted)) {
      clearPendingAction();
    }
  };

  useEffect(() => {
    if (finalRequireXmage && initialHealth.status !== "ready") {
      return;
    }

    let active = true;
    setError(undefined);
    fetch("/api/engine/commander", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(config)
    })
      .then(async (response) => {
        if (!response.ok) throw new Error(await errorMessage(response, "Game start failed"));
        return response.json() as Promise<GameSnapshot>;
      })
      .then((nextSnapshot) => {
        if (active) {
          snapshotRef.current = nextSnapshot;
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
  }, [config, initialHealth.status, finalRequireXmage]);

  useEffect(() => {
    if (!snapshot?.id || simulatorMode || typeof WebSocket === "undefined") {
      setSocketStatus("idle");
      return;
    }

    let active = true;
    const socket = new WebSocket(gameWebSocketUrl(snapshot.id, webSocketBaseUrl));
    setSocketStatus("connecting");

    socket.addEventListener("open", () => {
      if (active) setSocketStatus("live");
    });
    socket.addEventListener("message", (event) => {
      try {
        const nextSnapshot = JSON.parse(String(event.data)) as GameSnapshot;
        if (active) acceptSnapshot(nextSnapshot);
      } catch {
        if (active) setError("Received an unreadable XMage live update.");
      }
    });
    socket.addEventListener("error", () => {
      if (active) setSocketStatus("unavailable");
    });
    socket.addEventListener("close", () => {
      if (active) setSocketStatus("unavailable");
    });

    return () => {
      active = false;
      socket.close();
    };
  }, [simulatorMode, snapshot?.id, webSocketBaseUrl]);

  const legalActions = snapshot?.legalActions ?? [];
  const health = snapshot?.engineHealth ?? initialHealth;

  const viewModel = useMemo(() => {
    if (!snapshot) return undefined;
    return buildBattlefieldViewModel(snapshot, visuals, config.humanPlayerId, health);
  }, [config.humanPlayerId, snapshot, visuals, health]);

  const selectedCard = useMemo(() => {
    if (!viewModel || !selectedInstanceId) return undefined;
    return getAllCards(viewModel).find((card) => card.instanceId === selectedInstanceId);
  }, [selectedInstanceId, viewModel]);

  const modeLabel = simulatorMode ? "DEVELOPMENT ONLY - Simulator Preview" : "XMage rules";
  const actionPending = pendingActionId !== undefined;
  const statusLines = snapshot ? gameStatusLines(snapshot, health, socketStatus, simulatorMode) : [];

  const connectionFailed = (finalRequireXmage && health.status !== "ready") || (finalRequireXmage && socketStatus === "unavailable");

  if (connectionFailed) {
    return (
      <XmageSetupRequired
        health={health}
        reason={socketStatus === "unavailable" ? "WebSocket connection to XMage Gateway is unavailable." : undefined}
      />
    );
  }

  const runLegalAction = (action: LegalAction) => {
    if (!snapshot || !viewModel || actionPending) return;
    const actionCard = selectedCard ?? findActionCard(viewModel, action.cardInstanceId);
    const command = toCommand(action, snapshot, actionCard, viewModel.opponent.playerId);
    if (!command) {
      setError(`Unsupported prompt/action: ${actionLabel(action)}. XMage did not expose enough data for this route.`);
      return;
    }

    setError(undefined);
    pendingActionIdRef.current = action.id;
    setPendingActionId(action.id);
    setPendingActionLabel(actionLabel(action));
    fetch(`/api/engine/games/${encodeURIComponent(snapshot.id)}/commands`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(command)
    })
      .then(async (response) => {
        const result = await commandResponse(response);
        if (result.stale) {
          setError(result.message ?? "That action was already replaced by a newer XMage state. Refreshed to the latest snapshot.");
        }
        return result.snapshot;
      })
      .then((nextSnapshot) => acceptSnapshot(nextSnapshot))
      .catch(async (caughtError) => {
        if (isStaleCommandError(caughtError) && snapshotRef.current?.id) {
          const refreshed = await fetchLatestSnapshot(snapshotRef.current.id).catch(() => undefined);
          if (refreshed) acceptSnapshot(refreshed);
        }
        setError(caughtError instanceof Error ? caughtError.message : "Command failed");
        clearPendingAction();
      });
  };

  const selectedActions = selectedInstanceId
    ? legalActions.filter((action) => action.cardInstanceId === selectedInstanceId || action.sourceInstanceId === selectedInstanceId)
    : [];
  const promptActions = legalActions.filter((action) => isPromptAction(action.type));

  const handlePlayerClick = (playerId: string) => {
    const matchingPromptAction = promptActions.find((action) =>
      action.playerIds?.includes(playerId)
      || action.validPlayerIds?.includes(playerId)
      || action.targetIds?.includes(playerId)
      || action.validTargetIds?.includes(playerId)
    );
    if (matchingPromptAction) {
      runLegalAction(matchingPromptAction);
    }
  };

  return (
    <section className="arena-screen" aria-label="Horizontal game battlefield">
      {simulatorMode && (
        <div
          className="simulator-banner"
          style={{
            background: "#b45309",
            color: "#fff",
            textAlign: "center",
            padding: "6px",
            fontWeight: "bold",
            fontSize: "0.85rem",
            letterSpacing: "0.05em",
            borderBottom: "1px solid rgba(246, 240, 223, 0.15)",
            zIndex: 10,
            position: "relative"
          }}
        >
          ⚠️ DEVELOPMENT ONLY: SIMULATOR PREVIEW MODE (UI MECHANICS ONLY) ⚠️
        </div>
      )}
      <div className="arena-top-hud">
        <PlayerBadge
          name="Noaddrag"
          life={viewModel?.opponent.life ?? 40}
          manaPool={viewModel?.opponent.manaPool}
          onClick={() => {
            if (viewModel?.opponent.playerId) {
              handlePlayerClick(viewModel.opponent.playerId);
            }
          }}
        />
        <div className="arena-status">
          <strong>{viewModel?.phase ?? "starting"}</strong>
          <span>{modeLabel}</span>
          <small>{health.status}: {simulatorMode ? "UI mechanics only; full rules require XMage bridge." : health.reason}</small>
          {statusLines.map((line) => <small key={line}>{line}</small>)}
          {!simulatorMode ? <small>Live updates: {socketStatus}</small> : null}
          {pendingActionLabel ? <small>Action sent: {pendingActionLabel}. Waiting for XMage.</small> : null}
          {error ? <small role="alert">Command error: {error}</small> : null}
        </div>
      </div>

      {viewModel ? (
        <ArenaBattlefield
          viewModel={viewModel}
          snapshot={snapshot ?? undefined}
          selectedInstanceId={selectedInstanceId}
          selectedActions={selectedActions}
          promptActions={promptActions}
          actionPending={actionPending}
          onSelectCard={(card) => {
            const matchingPromptAction = promptActions.find((action) =>
              action.cardInstanceId === card.instanceId
              || action.sourceInstanceId === card.instanceId
              || action.targetIds?.includes(card.instanceId)
              || action.validTargetIds?.includes(card.instanceId)
              || action.choiceIds?.includes(card.instanceId)
              || action.cardInstanceIds?.includes(card.instanceId)
              || action.validCardInstanceIds?.includes(card.instanceId)
            );
            if (matchingPromptAction) {
              runLegalAction(matchingPromptAction);
              return;
            }

            const immediateAction = getImmediateCardAction(card.instanceId, legalActions);
            if (immediateAction) {
              setSelectedInstanceId(card.instanceId);
              runLegalAction(immediateAction);
              return;
            }
            setSelectedInstanceId(card.instanceId);
          }}
          onRunAction={runLegalAction}
        />
      ) : (
        <div className="arena-battlefield is-loading" data-testid="arena-battlefield">
          <p>{error ?? "Starting Commander table..."}</p>
        </div>
      )}

      <div className="arena-bottom-hud">
        <PlayerBadge
          name="TabletopPolish"
          life={viewModel?.human.life ?? 40}
          manaPool={viewModel?.human.manaPool}
          active
          onClick={() => {
            if (viewModel?.human.playerId) {
              handlePlayerClick(viewModel.human.playerId);
            }
          }}
        />
        <div className="arena-selected-card">
          <span>Selected</span>
          <strong>{selectedCard?.name ?? "Choose a card"}</strong>
        </div>
      </div>
    </section>
  );
}

async function errorMessage(response: Response, fallback: string): Promise<string> {
  const status = `${fallback} (${response.status})`;
  try {
    const body = (await response.json()) as { error?: string; message?: string };
    return body.error || body.message ? `${status}: ${body.error ?? body.message}` : status;
  } catch {
    return status;
  }
}

async function commandResponse(response: Response): Promise<{ snapshot: GameSnapshot; stale: boolean; message?: string }> {
  const body = await response.json().catch(() => undefined) as unknown;
  if (response.ok && isGameSnapshot(body)) {
    return { snapshot: body, stale: false };
  }

  const staleSnapshot = staleCommandSnapshot(response.status, body);
  if (staleSnapshot) {
    const message = typeof body === "object" && body && "message" in body && typeof body.message === "string"
      ? body.message
      : undefined;
    return { snapshot: staleSnapshot, stale: true, ...(message ? { message } : {}) };
  }

  const fallback = response.ok ? "Command returned an unreadable snapshot" : `Command failed (${response.status})`;
  const message = typeof body === "object" && body
    ? [stringProperty(body, "error"), stringProperty(body, "message")].find(Boolean)
    : undefined;
  throw new StaleCommandError(response.status === 409 && stringProperty(body, "error") === "action_no_longer_legal", message ? `${fallback}: ${message}` : fallback);
}

async function fetchLatestSnapshot(gameId: string): Promise<GameSnapshot> {
  const response = await fetch(`/api/engine/games/${encodeURIComponent(gameId)}`);
  if (!response.ok) throw new Error(await errorMessage(response, "Snapshot refresh failed"));
  return response.json() as Promise<GameSnapshot>;
}

class StaleCommandError extends Error {
  constructor(readonly isStaleCommand: boolean, message: string) {
    super(message);
  }
}

function isStaleCommandError(error: unknown): boolean {
  return error instanceof StaleCommandError && error.isStaleCommand;
}

export function staleCommandSnapshot(status: number, body: unknown): GameSnapshot | undefined {
  if (status !== 409 || !body || typeof body !== "object") return undefined;
  if (stringProperty(body, "error") !== "action_no_longer_legal") return undefined;
  const snapshot = "snapshot" in body ? body.snapshot : undefined;
  return isGameSnapshot(snapshot) ? snapshot : undefined;
}

function isGameSnapshot(value: unknown): value is GameSnapshot {
  return !!value
    && typeof value === "object"
    && stringProperty(value, "id") !== undefined
    && stringProperty(value, "roomId") !== undefined
    && typeof (value as { turn?: unknown }).turn === "number";
}

function stringProperty(value: unknown, key: string): string | undefined {
  return value && typeof value === "object" && key in value && typeof value[key as keyof typeof value] === "string"
    ? value[key as keyof typeof value] as string
    : undefined;
}

function XmageSetupRequired({ health, reason }: { health: EngineHealth; reason?: string | undefined }) {
  const displayReason = reason ?? health.reason ?? "XMage rules engine is not reachable.";
  return (
    <section className="arena-screen is-setup" aria-label="Horizontal game battlefield">
      <div className="xmage-setup-panel" role="status">
        <span>XMage setup required</span>
        <h1>Start the rules engine before playing Commander</h1>
        <p>{displayReason}</p>
        <code>docker compose up --build xmage-bridge xmage-gateway</code>
        <code>ENGINE_MODE=xmage XMAGE_GATEWAY_URL=http://localhost:17171 pnpm --filter @magicmobile/web exec next dev --hostname 0.0.0.0</code>
        <small>
          The simulator preview lives at /dev/play-simulator. Production /play does not fall back because tapping,
          priority, combat, costs, and AI decisions must come from XMage.
        </small>
      </div>
    </section>
  );
}

export function gameWebSocketUrl(gameId: string, baseUrl?: string): string {
  const path = `/ws/games/${encodeURIComponent(gameId)}`;
  if (baseUrl) {
    const url = new URL(baseUrl);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    url.pathname = `${url.pathname.replace(/\/$/, "")}${path}`;
    url.search = "";
    url.hash = "";
    return url.toString();
  }

  if (typeof window === "undefined") {
    return path;
  }
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}${path}`;
}

export function latestSnapshot(current: GameSnapshot | null, next: GameSnapshot): GameSnapshot {
  if (!current) return next;

  const currentRevision = current.bridgeRevision;
  const nextRevision = next.bridgeRevision;
  if (typeof currentRevision === "number" && typeof nextRevision === "number") {
    if (nextRevision > currentRevision) {
      return next;
    }
    if (nextRevision < currentRevision) {
      return current;
    }
  }

  const currentCycle = current.xmageCycle;
  const nextCycle = next.xmageCycle;
  if (typeof currentCycle === "number" && typeof nextCycle === "number") {
    if (nextCycle < currentCycle) {
      return current;
    }
  }

  return next;
}

export function shouldClearPendingAfterSnapshot(current: GameSnapshot, next: GameSnapshot): boolean {
  if (latestSnapshot(current, next) === current) return false;
  return next.pendingStatus !== "waiting_for_xmage";
}

function gameStatusLines(
  snapshot: GameSnapshot,
  health: EngineHealth,
  socketStatus: "idle" | "connecting" | "live" | "unavailable",
  simulatorMode: boolean
): string[] {
  const source = snapshotSource(snapshot, simulatorMode);
  const active = snapshot.activePlayerId ?? "unknown";
  const priority = snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId ?? "unknown";
  const phase = snapshot.step ? `${snapshot.phase}/${snapshot.step}` : snapshot.phase;
  const lines = [
    `Source: ${source} · Bridge: ${health.status} · rev ${snapshot.bridgeRevision ?? "n/a"} · cycle ${snapshot.xmageCycle ?? "n/a"}`,
    `Turn ${snapshot.turn} · ${phase} · active ${active} · priority ${priority}`,
    `WebSocket: ${socketStatus} · pendingStatus: ${snapshot.pendingStatus ?? "none"}`
  ];
  if (snapshot.priorityPlayerId === "human" || snapshot.waitingOnPlayerId === "human") {
    lines.push("Your priority");
  } else if (snapshot.priorityPlayerId || snapshot.waitingOnPlayerId) {
    lines.push("AI thinking");
  }
  if (snapshot.pendingStatus === "waiting_for_xmage") lines.push("Waiting for XMage");
  if (snapshot.pendingStatus === "stalled" || health.status === "stalled") lines.push("XMage stalled");
  return lines;
}

function snapshotSource(snapshot: GameSnapshot, simulatorMode: boolean): string {
  const source = (snapshot as GameSnapshot & { source?: string }).source;
  if (source) return source;
  if (simulatorMode) return "simulator";
  if (snapshot.xmage) return "xmage-java-bridge";
  return "xmage";
}

function ManaPoolView({ manaPool }: { manaPool?: ManaPool | undefined }) {
  if (!manaPool) return null;
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
    <div className="mana-pool-view" style={{ display: "flex", gap: "2px", marginTop: "2px" }}>
      {symbols.map((sym) => {
        const count = manaPool[sym] ?? 0;
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
    </div>
  );
}

function PlayerBadge({
  name,
  life,
  manaPool,
  active = false,
  onClick
}: {
  name: string;
  life: number;
  manaPool?: ManaPool | undefined;
  active?: boolean;
  onClick?: (() => void) | undefined;
}) {
  return (
    <button
      onClick={onClick}
      disabled={!onClick}
      className={active ? "arena-player-badge is-active" : "arena-player-badge"}
      style={{
        background: "none",
        border: "none",
        textAlign: "left",
        cursor: onClick ? "pointer" : "default",
        padding: 0,
        display: "block"
      }}
      type="button"
    >
      <div className="arena-avatar" />
      <strong>{life}</strong>
      <span>{name}</span>
      <ManaPoolView manaPool={manaPool} />
    </button>
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
  return [
    "activate_ability",
    "cast_spell",
    "choose_card",
    "choose_target",
    "declare_attackers",
    "declare_blockers",
    "make_mana",
    "play_land",
    "tap_permanent",
    "untap_permanent"
  ].includes(type);
}

function isPromptAction(type: LegalAction["type"]): boolean {
  return [
    "advance_phase",
    "pass_priority",
    "pass_until_response",
    "pass_until_next_turn",
    "keep_hand",
    "mulligan",
    "resolve_choice",
    "choose_target",
    "choose_card",
    "choose_player",
    "choose_mode",
    "choose_ability",
    "choose_pile",
    "choose_amount",
    "choose_multi_amount",
    "choose_mana",
    "answer_yes_no",
    "play_mana",
    "play_x_mana",
    "pay_cost",
    "order_triggers",
    "order_items",
    "search_select",
    "commander_replacement",
    "concede"
  ].includes(type);
}

function getImmediateCardAction(instanceId: string, legalActions: LegalAction[]): LegalAction | undefined {
  const actions = legalActions.filter((action) => action.cardInstanceId === instanceId || action.sourceInstanceId === instanceId);
  if (actions.length !== 1) return undefined;
  const [action] = actions;
  return action && ["make_mana", "tap_permanent"].includes(action.type) ? action : undefined;
}

function actionLabel(action: LegalAction): string {
  return action.shortLabel ?? action.label ?? action.type.replaceAll("_", " ");
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

export function toCommand(
  action: LegalAction,
  snapshot: GameSnapshot,
  selectedCard: BattlefieldCardView | undefined,
  opponentPlayerId: string
): GameCommand | undefined {
  let command: GameCommand | undefined;
  switch (action.type) {
    case "play_land":
      command = {
        type: "play_land",
        gameId: snapshot.id,
        playerId: action.playerId,
        ...(action.cardInstanceId ? { cardInstanceId: action.cardInstanceId } : {}),
        ...(action.sourceInstanceId ? { sourceInstanceId: action.sourceInstanceId } : {}),
        ...(selectedCard?.name ? { cardName: selectedCard.name } : {})
      };
      break;
    case "cast_spell":
      command = {
        type: "cast_spell",
        gameId: snapshot.id,
        playerId: action.playerId,
        ...(action.cardInstanceId ? { cardInstanceId: action.cardInstanceId } : {}),
        ...(action.sourceInstanceId ? { sourceInstanceId: action.sourceInstanceId } : {}),
        ...(selectedCard?.name ? { cardName: selectedCard.name, fromZone: "hand" as const } : {})
      };
      break;
    case "tap_permanent":
      command = action.cardInstanceId
        ? { type: "tap_permanent", gameId: snapshot.id, playerId: action.playerId, cardInstanceId: action.cardInstanceId }
        : undefined;
      break;
    case "declare_attackers":
      command = action.cardInstanceId
        ? {
            type: "declare_attackers",
            gameId: snapshot.id,
            playerId: action.playerId,
            attackers: [{ attackerId: action.cardInstanceId, defenderId: opponentPlayerId }]
          }
        : undefined;
      break;
    case "declare_blockers":
      command = action.cardInstanceId && action.validTargetIds?.[0]
        ? {
            type: "declare_blockers",
            gameId: snapshot.id,
            playerId: action.playerId,
            blockers: [{ blockerId: action.cardInstanceId, attackerId: action.validTargetIds[0] }]
          }
        : undefined;
      break;
    case "make_mana":
      command = action.cardInstanceId ?? action.sourceInstanceId
        ? {
            type: "make_mana",
            gameId: snapshot.id,
            playerId: action.playerId,
            sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId ?? "",
            ...abilityTemplate(action)
          }
        : undefined;
      break;
    case "play_mana":
      {
        const chosenManaType = explicitManaType(action);
        command = chosenManaType
          ? {
              type: "play_mana",
              gameId: snapshot.id,
              playerId: action.playerId,
              promptId: promptId(snapshot, action),
              manaType: chosenManaType
            }
          : undefined;
      }
      break;
    case "pay_cost": {
      const paymentId = stringTemplateValue(action, "paymentId");
      const sourceInstanceIds = action.targetIds ?? action.validTargetIds;
      const pay = action.pay ?? action.confirmed ?? booleanTemplateValue(action, "pay") ?? booleanTemplateValue(action, "confirmed");
      command = pay === undefined
        ? undefined
        : {
            type: "pay_cost",
            gameId: snapshot.id,
            playerId: action.playerId,
            promptId: promptId(snapshot, action),
            pay,
            ...(paymentId ? { paymentId } : {}),
            ...(sourceInstanceIds ? { sourceInstanceIds } : {})
          };
      break;
    }
    case "activate_ability":
      {
        const abilityId = action.abilityId ?? abilityTemplate(action).abilityId;
        command = (action.cardInstanceId ?? action.sourceInstanceId) && abilityId
        ? {
            type: "activate_ability",
            gameId: snapshot.id,
            playerId: action.playerId,
            sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId ?? "",
            abilityId
          }
        : undefined;
      }
      break;
    case "choose_target":
      command = {
        type: "choose_target",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        targetIds: action.validTargetIds ?? action.targetIds ?? []
      };
      break;
    case "choose_card":
      command = {
        type: "choose_card",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        cardInstanceIds: action.cardInstanceIds ?? action.validTargetIds ?? action.targetIds ?? []
      };
      break;
    case "choose_player":
      command = {
        type: "choose_player",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        playerIds: action.validPlayerIds ?? action.playerIds ?? action.validTargetIds ?? action.targetIds ?? []
      };
      break;
    case "choose_mode":
      command = {
        type: "choose_mode",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        modeIds: action.modeIds ?? action.targetIds ?? action.validTargetIds ?? []
      };
      break;
    case "choose_ability":
      {
        const abilityId = action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.abilityId ?? abilityTemplate(action).abilityId;
        command = abilityId
          ? {
              type: "choose_ability",
              gameId: snapshot.id,
              playerId: action.playerId,
              promptId: promptId(snapshot, action),
              abilityId
            }
          : undefined;
      }
      break;
    case "choose_pile":
      {
        const pile = explicitPile(action);
        command = pile
          ? {
              type: "choose_pile",
              gameId: snapshot.id,
              playerId: action.playerId,
              promptId: promptId(snapshot, action),
              pile
            }
          : undefined;
      }
      break;
    case "choose_amount":
    case "play_x_mana": {
      const amount = explicitNumber(action, "amount");
      command = amount === undefined
        ? undefined
        : {
            type: action.type,
            gameId: snapshot.id,
            playerId: action.playerId,
            promptId: promptId(snapshot, action),
            amount
          };
      break;
    }
    case "choose_multi_amount":
      {
        const amounts = explicitAmounts(action);
        command = amounts.length
          ? {
              type: "choose_multi_amount",
              gameId: snapshot.id,
              playerId: action.playerId,
              promptId: promptId(snapshot, action),
              amounts
            }
          : undefined;
      }
      break;
    case "choose_mana":
      {
        const manaTypes = explicitManaTypes(action);
        command = manaTypes.length
          ? {
              type: "choose_mana",
              gameId: snapshot.id,
              playerId: action.playerId,
              promptId: promptId(snapshot, action),
              manaTypes
            }
          : undefined;
      }
      break;
    case "answer_yes_no":
      {
        const confirmed = explicitBooleanChoice(action, "confirmed");
        command = confirmed === undefined
          ? undefined
          : {
              type: "answer_yes_no",
              gameId: snapshot.id,
              playerId: action.playerId,
              promptId: promptId(snapshot, action),
              confirmed
            };
      }
      break;
    case "order_triggers":
      command = {
        type: "order_triggers",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        orderedIds: action.targetIds ?? action.validTargetIds ?? []
      };
      break;
    case "order_items":
      command = {
        type: "order_items",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        orderedIds: action.orderedIds ?? action.targetIds ?? action.validTargetIds ?? []
      };
      break;
    case "search_select":
      command = {
        type: "search_select",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        cardInstanceIds: action.cardInstanceIds ?? action.validCardInstanceIds ?? action.targetIds ?? action.validTargetIds ?? []
      };
      break;
    case "commander_replacement":
      {
        const useCommandZone = explicitCommanderReplacementChoice(action);
        command = useCommandZone === undefined
          ? undefined
          : {
              type: "commander_replacement",
              gameId: snapshot.id,
              playerId: action.playerId,
              promptId: promptId(snapshot, action),
              useCommandZone
            };
      }
      break;
    case "resolve_choice":
      command = {
        type: "resolve_choice",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        choiceIds: action.targetIds ?? action.validTargetIds ?? []
      };
      break;
    case "keep_hand":
      command = { type: "keep_hand", gameId: snapshot.id, playerId: action.playerId };
      break;
    case "mulligan":
      command = { type: "mulligan", gameId: snapshot.id, playerId: action.playerId };
      break;
    case "pass_priority":
      command = { type: "pass_priority", gameId: snapshot.id, playerId: action.playerId };
      break;
    case "pass_until_response":
      command = { type: "pass_until_response", gameId: snapshot.id, playerId: action.playerId };
      break;
    case "pass_until_next_turn":
      command = { type: "pass_until_next_turn", gameId: snapshot.id, playerId: action.playerId };
      break;
    case "advance_phase":
      command = { type: "advance_phase", gameId: snapshot.id, playerId: action.playerId };
      break;
    case "concede":
      command = { type: "concede", gameId: snapshot.id, playerId: action.playerId };
      break;
    default:
      command = undefined;
  }

  return command ? withExpectedBridgeRevision(mergeCommandTemplate(command, action), snapshot.bridgeRevision) : undefined;
}

function abilityTemplate(action: LegalAction): { abilityId?: string } {
  const template = action.commandTemplate as { abilityId?: unknown } | undefined;
  return typeof template?.abilityId === "string" ? { abilityId: template.abilityId } : {};
}

function promptId(snapshot: GameSnapshot, action: LegalAction): string {
  return action.promptId ?? snapshot.promptEnvelopeV2?.id ?? snapshot.promptEnvelope?.id ?? snapshot.choicePrompt?.id ?? action.id;
}

function stringTemplateValue(action: LegalAction, key: string): string | undefined {
  const value = action.commandTemplate?.[key as keyof GameCommand];
  return typeof value === "string" ? value : undefined;
}

function booleanTemplateValue(action: LegalAction, key: string): boolean | undefined {
  const value = action.commandTemplate?.[key as keyof GameCommand];
  return typeof value === "boolean" ? value : undefined;
}

function numberTemplateValue(action: LegalAction, key: string): number | undefined {
  const value = action.commandTemplate?.[key as keyof GameCommand];
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function numberArrayTemplateValue(action: LegalAction, key: string): number[] | undefined {
  const value = action.commandTemplate?.[key as keyof GameCommand];
  return Array.isArray(value) && value.every((item) => typeof item === "number" && Number.isFinite(item)) ? value : undefined;
}

function stringArrayTemplateValue(action: LegalAction, key: string): string[] | undefined {
  const value = action.commandTemplate?.[key as keyof GameCommand];
  return Array.isArray(value) && value.every((item) => typeof item === "string") ? value : undefined;
}

function mergeCommandTemplate(command: GameCommand, action: LegalAction): GameCommand {
  const template = action.commandTemplate;
  if (!template) return command;
  return {
    ...command,
    ...template,
    type: template.type ?? command.type,
    gameId: command.gameId,
    playerId: action.playerId
  } as GameCommand;
}

function withExpectedBridgeRevision(command: GameCommand, bridgeRevision: number | undefined): GameCommand {
  if (bridgeRevision === undefined) return command;
  return { ...command, expectedBridgeRevision: bridgeRevision };
}

function explicitPile(action: LegalAction): 1 | 2 | undefined {
  const templatePile = numberTemplateValue(action, "pile");
  if (templatePile === 1 || templatePile === 2) return templatePile;
  const rawPile = action.pile ?? action.targetIds?.[0] ?? action.validTargetIds?.[0];
  if (rawPile === 1 || rawPile === "1") return 1;
  if (rawPile === 2 || rawPile === "2") return 2;
  return undefined;
}

function explicitNumber(action: LegalAction, templateKey: string): number | undefined {
  const templateNumber = numberTemplateValue(action, templateKey);
  if (templateNumber !== undefined) return templateNumber;
  if (typeof action.amount === "number" && Number.isFinite(action.amount)) return action.amount;
  const raw = action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.choiceIds?.[0];
  if (raw === undefined) return undefined;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function explicitAmounts(action: LegalAction): number[] {
  const templateAmounts = numberArrayTemplateValue(action, "amounts");
  if (templateAmounts) return templateAmounts;
  if (action.amounts?.every((amount) => Number.isFinite(amount))) return action.amounts;
  const rawAmounts = action.targetIds ?? action.validTargetIds ?? action.choiceIds;
  if (!rawAmounts?.length) return [];
  const amounts = rawAmounts.map(Number);
  return amounts.every(Number.isFinite) ? amounts : [];
}

function explicitManaType(action: LegalAction): "W" | "U" | "B" | "R" | "G" | "C" | undefined {
  return parseManaType(stringTemplateValue(action, "manaType") ?? action.manaType ?? action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.choiceIds?.[0]);
}

function explicitManaTypes(action: LegalAction): Array<"W" | "U" | "B" | "R" | "G" | "C"> {
  const templateTypes = stringArrayTemplateValue(action, "manaTypes")?.map(parseManaType).filter((type): type is "W" | "U" | "B" | "R" | "G" | "C" => type !== undefined);
  if (templateTypes?.length) return templateTypes;
  const actionTypes = action.manaTypes?.map(parseManaType).filter((type): type is "W" | "U" | "B" | "R" | "G" | "C" => type !== undefined);
  if (actionTypes?.length) return actionTypes;
  const singleType = explicitManaType(action);
  return singleType ? [singleType] : [];
}

function explicitBooleanChoice(action: LegalAction, templateKey: string): boolean | undefined {
  return action.confirmed
    ?? booleanTemplateValue(action, templateKey)
    ?? booleanTemplateValue(action, "confirmed")
    ?? booleanTemplateValue(action, "pay")
    ?? parseBooleanChoice(action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.choiceIds?.[0]);
}

function explicitCommanderReplacementChoice(action: LegalAction): boolean | undefined {
  const explicit = action.useCommandZone ?? booleanTemplateValue(action, "useCommandZone") ?? booleanTemplateValue(action, "confirmed");
  if (explicit !== undefined) return explicit;
  const raw = action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.choiceIds?.[0];
  if (raw === "command_zone" || raw === "command" || raw === "true") return true;
  if (raw === "graveyard" || raw === "original_zone" || raw === "false") return false;
  return undefined;
}

function parseBooleanChoice(value: string | undefined): boolean | undefined {
  if (value === "true" || value === "yes") return true;
  if (value === "false" || value === "no") return false;
  return undefined;
}

function parseManaType(value: string | undefined): "W" | "U" | "B" | "R" | "G" | "C" | undefined {
  return value === "W" || value === "U" || value === "B" || value === "R" || value === "G" || value === "C" ? value : undefined;
}
