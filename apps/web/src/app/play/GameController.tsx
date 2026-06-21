"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import type { CommanderGameConfig, EngineHealth, GameCommand, GameSnapshot, LegalAction } from "@magicmobile/shared";
import { ArenaBattlefield } from "./ArenaBattlefield";
import { buildBattlefieldViewModel, type BattlefieldCardView, type VisualCardRecord } from "./battlefield-view-model";

interface GameControllerProps {
  config: CommanderGameConfig;
  initialHealth: EngineHealth;
  requireXmage?: boolean;
  simulatorMode: boolean;
  visuals: VisualCardRecord;
}

export function GameController({ config, initialHealth, requireXmage = false, simulatorMode, visuals }: GameControllerProps) {
  const [snapshot, setSnapshot] = useState<GameSnapshot | null>(null);
  const [selectedInstanceId, setSelectedInstanceId] = useState<string | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    if (requireXmage && initialHealth.status !== "ready") {
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
  }, [config, initialHealth.status, requireXmage]);

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

  if (requireXmage && health.status !== "ready") {
    return <XmageSetupRequired health={health} />;
  }

  const runLegalAction = (action: LegalAction) => {
    if (!snapshot || !viewModel) return;
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
        .then(async (response) => {
          if (!response.ok) throw new Error(await errorMessage(response, "Command failed"));
          return response.json() as Promise<GameSnapshot>;
        })
        .then((nextSnapshot) => setSnapshot(nextSnapshot))
        .catch((caughtError) => setError(caughtError instanceof Error ? caughtError.message : "Command failed"));
    });
  };

  const selectedActions = selectedInstanceId
    ? legalActions.filter((action) => action.cardInstanceId === selectedInstanceId || action.sourceInstanceId === selectedInstanceId)
    : [];
  const promptActions = legalActions.filter((action) => isPromptAction(action.type));

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
          snapshot={snapshot ?? undefined}
          selectedInstanceId={selectedInstanceId}
          selectedActions={selectedActions}
          promptActions={promptActions}
          actionPending={isPending}
          onSelectCard={(card) => {
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
        <PlayerBadge name="TabletopPolish" life={viewModel?.human.life ?? 40} active />
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

function XmageSetupRequired({ health }: { health: EngineHealth }) {
  return (
    <section className="arena-screen is-setup" aria-label="Horizontal game battlefield">
      <div className="xmage-setup-panel" role="status">
        <span>XMage setup required</span>
        <h1>Start the rules engine before playing Commander</h1>
        <p>{health.reason}</p>
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
  const commandTemplate = commandFromTemplate(action, snapshot);
  if (commandTemplate) return commandTemplate;

  switch (action.type) {
    case "play_land":
      return {
        type: "play_land",
        gameId: snapshot.id,
        playerId: action.playerId,
        ...(action.cardInstanceId ? { cardInstanceId: action.cardInstanceId } : {}),
        ...(selectedCard?.name ? { cardName: selectedCard.name } : {})
      };
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
    case "declare_blockers":
      return action.cardInstanceId && action.validTargetIds?.[0]
        ? {
            type: "declare_blockers",
            gameId: snapshot.id,
            playerId: action.playerId,
            blockers: [{ blockerId: action.cardInstanceId, attackerId: action.validTargetIds[0] }]
          }
        : undefined;
    case "make_mana":
      return action.cardInstanceId ?? action.sourceInstanceId
        ? {
            type: "make_mana",
            gameId: snapshot.id,
            playerId: action.playerId,
            sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId ?? "",
            ...abilityTemplate(action)
          }
        : undefined;
    case "play_mana":
      return {
        type: "play_mana",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        manaType: manaType(action.manaType ?? action.targetIds?.[0] ?? action.validTargetIds?.[0])
      };
    case "pay_cost": {
      const paymentId = stringTemplateValue(action, "paymentId");
      const sourceInstanceIds = action.targetIds ?? action.validTargetIds;
      return {
        type: "pay_cost",
        gameId: snapshot.id,
        playerId: action.playerId,
        ...(paymentId ? { paymentId } : {}),
        ...(sourceInstanceIds ? { sourceInstanceIds } : {})
      };
    }
    case "activate_ability":
      return action.cardInstanceId ?? action.sourceInstanceId
        ? {
            type: "activate_ability",
            gameId: snapshot.id,
            playerId: action.playerId,
            sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId ?? "",
            abilityId: abilityTemplate(action).abilityId ?? action.id
          }
        : undefined;
    case "choose_target":
      return {
        type: "choose_target",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        targetIds: action.validTargetIds ?? action.targetIds ?? []
      };
    case "choose_card":
      return {
        type: "choose_card",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        cardInstanceIds: action.cardInstanceIds ?? action.validTargetIds ?? action.targetIds ?? []
      };
    case "choose_player":
      return {
        type: "choose_player",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        playerIds: action.validPlayerIds ?? action.playerIds ?? action.validTargetIds ?? action.targetIds ?? []
      };
    case "choose_mode":
      return {
        type: "choose_mode",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        modeIds: action.modeIds ?? action.targetIds ?? action.validTargetIds ?? []
      };
    case "choose_ability":
      return {
        type: "choose_ability",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        abilityId: action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.abilityId ?? action.id
      };
    case "choose_pile":
      return {
        type: "choose_pile",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        pile: action.targetIds?.[0] === "2" || action.validTargetIds?.[0] === "2" ? 2 : 1
      };
    case "choose_amount":
    case "play_x_mana":
      return {
        type: action.type,
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        amount: Number(action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? 0)
      };
    case "choose_multi_amount":
      return {
        type: "choose_multi_amount",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        amounts: (action.targetIds ?? action.validTargetIds ?? []).map(Number).filter(Number.isFinite)
      };
    case "choose_mana":
      return {
        type: "choose_mana",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        manaTypes: action.manaTypes ?? [action.manaType ?? manaType(action.choiceIds?.[0] ?? action.targetIds?.[0] ?? action.validTargetIds?.[0])]
      };
    case "answer_yes_no":
      return {
        type: "answer_yes_no",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        confirmed: action.confirmed ?? action.targetIds?.[0] !== "false"
      };
    case "order_triggers":
      return {
        type: "order_triggers",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        orderedIds: action.targetIds ?? action.validTargetIds ?? []
      };
    case "order_items":
      return {
        type: "order_items",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        orderedIds: action.orderedIds ?? action.targetIds ?? action.validTargetIds ?? []
      };
    case "search_select":
      return {
        type: "search_select",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        cardInstanceIds: action.cardInstanceIds ?? action.validCardInstanceIds ?? action.targetIds ?? action.validTargetIds ?? []
      };
    case "commander_replacement":
      return {
        type: "commander_replacement",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        useCommandZone: action.targetIds?.[0] !== "graveyard" && action.validTargetIds?.[0] !== "graveyard"
      };
    case "resolve_choice":
      return {
        type: "resolve_choice",
        gameId: snapshot.id,
        playerId: action.playerId,
        promptId: promptId(snapshot, action),
        choiceIds: action.targetIds ?? action.validTargetIds ?? []
      };
    case "keep_hand":
      return { type: "keep_hand", gameId: snapshot.id, playerId: action.playerId };
    case "mulligan":
      return { type: "mulligan", gameId: snapshot.id, playerId: action.playerId };
    case "pass_priority":
      return { type: "pass_priority", gameId: snapshot.id, playerId: action.playerId };
    case "pass_until_response":
      return { type: "pass_until_response", gameId: snapshot.id, playerId: action.playerId };
    case "pass_until_next_turn":
      return { type: "pass_until_next_turn", gameId: snapshot.id, playerId: action.playerId };
    case "advance_phase":
      return { type: "advance_phase", gameId: snapshot.id, playerId: action.playerId };
    case "concede":
      return { type: "concede", gameId: snapshot.id, playerId: action.playerId };
    default:
      return undefined;
  }
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

function commandFromTemplate(action: LegalAction, snapshot: GameSnapshot): GameCommand | undefined {
  const template = action.commandTemplate;
  if (!template?.type) return undefined;
  return {
    ...template,
    type: template.type,
    gameId: snapshot.id,
    playerId: action.playerId
  } as GameCommand;
}

function manaType(value: string | undefined): "W" | "U" | "B" | "R" | "G" | "C" {
  return value === "W" || value === "U" || value === "B" || value === "R" || value === "G" || value === "C" ? value : "C";
}
