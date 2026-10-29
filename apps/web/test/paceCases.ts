/** The parity cases' compact board state and event summaries (ParityGoldenTests.swift), shared by tests and generators. */
import type { BoardFXEvent, BoardFXTint, CombatKeyword, FXCard, FXState } from "../src/core/boardEvents";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

/** The cases' compact board state (ParityGoldenTests `state`); arena cases add names, tints, stack and counters. */
export function caseState(json: Json, gameID = "combat"): FXState {
  const cards = new Map<string, FXCard>();
  for (const card of json.cards ?? []) {
    cards.set(card.id, {
      id: card.id, playerID: card.player, zone: card.zone ?? "battlefield", name: card.name ?? card.id, tint: (card.tint ?? "red") as BoardFXTint,
      damage: card.damage ?? 0, counters: card.counters ?? 0, attacking: card.attacking ?? false, blocking: card.blocking ?? [],
      isLand: card.land ?? false, isToken: card.token ?? false, keywords: new Set((card.keywords ?? []) as CombatKeyword[]),
      counterKinds: card.counterKinds ?? {}, power: card.power, toughness: card.toughness, phasedOut: card.phasedOut ?? false,
    });
  }
  return {
    gameID: json.game ?? gameID, step: json.step, lives: json.lives ?? {}, cards,
    stack: (json.stack ?? []).map((item: Json) => ({
      id: item.id, name: item.name ?? item.id, controllerID: item.controller, tint: item.tint ?? "colorless", isAbility: item.ability ?? false,
      manaValue: item.manaValue ?? 0,
    })),
    defenders: json.defenders ?? {}, commandNames: new Set(json.commandNames ?? []), blockedAttackers: new Set(json.blocked ?? []),
  };
}

/** One event as the cases write it. */
export function eventSummary(event: BoardFXEvent): string {
  switch (event.type) {
    case "firstStrikeBeat": return "first-strike";
    case "combatStrike": {
      const aim = "card" in event.target ? `card:${event.target.card}` : `player:${event.target.player}`;
      return `strike ${event.attackerID} -> ${aim} ${event.firstStrike ? "first" : "regular"}`;
    }
    case "damageMarked": return `damage ${event.cardID} ${event.amount}`;
    case "leftBattlefield": return `left ${event.cardID} ${event.to ?? "nil"}`;
    case "lifeChanged": return `life ${event.playerID} ${event.delta}`;
    default: return "other";
  }
}

/** Arena cases name every event. */
export function arenaSummary(event: BoardFXEvent): string {
  switch (event.type) {
    case "spellCast": return `cast ${event.stackID} ${event.weight} by ${event.controllerID ?? "nil"}`;
    case "attackDeclared": return `attack ${event.cardID}`;
    case "blockDeclared": return `block ${event.cardID} ${event.attackerID}`;
    case "enteredBattlefield": return `entered ${event.cardID} ${event.from ?? "nil"} ${event.entrance}`;
    case "countersChanged": return `counters ${event.cardID} ${event.kind} ${event.delta}`;
    case "statsChanged": return `stats ${event.cardID} ${event.power}/${event.toughness}`;
    case "phased": return `phased ${event.cardID} ${event.out ? "out" : "in"}`;
    case "transformed": return `transformed ${event.cardID} ${event.name}`;
    case "controlChanged": return `control ${event.cardID} ${event.from} -> ${event.to}`;
    default: return eventSummary(event);
  }
}
