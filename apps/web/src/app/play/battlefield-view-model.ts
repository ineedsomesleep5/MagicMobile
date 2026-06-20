import type { GameSnapshot, GameStep, LegalAction, PlayerGameState, ZoneCard } from "@magicmobile/shared";
import type { VisualCard } from "@/lib/scryfall-cards";

export type VisualCardRecord = Record<string, VisualCard>;

export interface BattlefieldCardView {
  instanceId: string;
  name: string;
  imageUrl?: string;
  typeLine: string;
  manaCost?: string;
  oracleText?: string;
  tapped: boolean;
  power?: number;
  toughness?: number;
  damage?: number;
  isAttacking: boolean;
  blocking: string[];
  counters: Array<{ label: string; value: number }>;
  quantity: number;
  legalActionTypes: string[];
}

export interface BattlefieldViewModel {
  human: PlayerGameState;
  opponent: PlayerGameState;
  activePlayerName: string;
  priorityPlayerName: string;
  waitingOnPlayerName: string;
  phase: string;
  step: GameStep;
  promptText: string;
  turn: number;
  legalActions: LegalAction[];
  logEntries: Array<{ id: string; message: string }>;
  humanHand: BattlefieldCardView[];
  humanLands: BattlefieldCardView[];
  humanCreatures: BattlefieldCardView[];
  humanAttackers: BattlefieldCardView[];
  opponentLands: BattlefieldCardView[];
  opponentCreatures: BattlefieldCardView[];
  opponentAttackers: BattlefieldCardView[];
  stack: BattlefieldCardView[];
  humanCommand: BattlefieldCardView[];
  opponentCommand: BattlefieldCardView[];
  humanZoneCounts: PlayerZoneCounts;
  opponentZoneCounts: PlayerZoneCounts;
}

export interface PlayerZoneCounts {
  library: number;
  graveyard: number;
  exile: number;
  command: number;
}

export function buildBattlefieldViewModel(
  snapshot: GameSnapshot,
  visuals: VisualCardRecord,
  humanPlayerId: string
): BattlefieldViewModel {
  const human = snapshot.players.find((player) => player.playerId === humanPlayerId) ?? snapshot.players[0];
  if (!human) {
    throw new Error("Cannot render a battlefield without players");
  }
  const opponent = snapshot.players.find((player) => player.playerId !== human.playerId) ?? human;
  const legalActions = snapshot.legalActions ?? [];

  const toViews = (cards: ZoneCard[]) => groupCardViews(cards.map((card) => toCardView(card, visuals, legalActions)));
  const humanBattlefield = toViews(human.zones.battlefield);
  const opponentBattlefield = toViews(opponent.zones.battlefield);

  return {
    human,
    opponent,
    activePlayerName: snapshot.activePlayerId ?? "unknown",
    priorityPlayerName: snapshot.priorityPlayerId ?? "unknown",
    waitingOnPlayerName: snapshot.waitingOnPlayerId ?? snapshot.priorityPlayerId ?? "unknown",
    phase: snapshot.phase,
    step: snapshot.step ?? phaseToStep(snapshot.phase),
    promptText: snapshot.promptText ?? defaultPromptText(snapshot),
    turn: snapshot.turn,
    legalActions,
    logEntries: snapshot.log.slice(-8).map((entry) => ({ id: entry.id, message: entry.message })),
    humanHand: toViews(human.zones.hand),
    humanLands: humanBattlefield.filter((card) => isLandName(card.name)),
    humanCreatures: humanBattlefield.filter((card) => isCreatureView(card) && !card.isAttacking),
    humanAttackers: humanBattlefield.filter((card) => card.isAttacking),
    opponentLands: opponentBattlefield.filter((card) => isLandName(card.name)),
    opponentCreatures: opponentBattlefield.filter((card) => isCreatureView(card) && !card.isAttacking),
    opponentAttackers: opponentBattlefield.filter((card) => card.isAttacking),
    stack: toViews(human.zones.stack.concat(opponent.zones.stack)),
    humanCommand: toViews(human.zones.command),
    opponentCommand: toViews(opponent.zones.command),
    humanZoneCounts: getZoneCounts(human),
    opponentZoneCounts: getZoneCounts(opponent)
  };
}

function toCardView(card: ZoneCard, visuals: VisualCardRecord, legalActions: LegalAction[]): BattlefieldCardView {
  const visual = visuals[card.card.name];
  const actions = legalActions
    .filter((action) => action.cardInstanceId === card.instanceId || action.sourceInstanceId === card.instanceId)
    .map((action) => action.type);
  const oracleText = visual?.oracleText ?? card.card.oracleText;

  return {
    instanceId: card.instanceId,
    name: card.card.name,
    ...(visual?.imageUrl ? { imageUrl: visual.imageUrl } : {}),
    typeLine: visual?.typeLine ?? card.card.typeLine,
    ...(visual?.manaCost ? { manaCost: visual.manaCost } : {}),
    ...(oracleText ? { oracleText } : {}),
    tapped: card.tapped ?? false,
    ...(card.power !== undefined ? { power: card.power } : {}),
    ...(card.toughness !== undefined ? { toughness: card.toughness } : {}),
    ...(card.damage !== undefined ? { damage: card.damage } : {}),
    isAttacking: card.isAttacking ?? false,
    blocking: card.blocking ?? [],
    counters: Object.entries(card.counters ?? {}).map(([label, value]) => ({ label, value })),
    quantity: 1,
    legalActionTypes: actions
  };
}

function groupCardViews(cards: BattlefieldCardView[]): BattlefieldCardView[] {
  const groups = new Map<string, BattlefieldCardView>();
  for (const card of cards) {
    const baseKey = `${card.name}:${card.tapped}:${card.isAttacking}:${card.power ?? ""}/${card.toughness ?? ""}`;
    const key = card.legalActionTypes.length === 0 ? baseKey : `${baseKey}:${card.instanceId}`;
    const existing = groups.get(key);
    if (existing) {
      existing.quantity += 1;
    } else {
      groups.set(key, { ...card });
    }
  }
  return Array.from(groups.values());
}

function isCreatureView(card: BattlefieldCardView): boolean {
  return card.power !== undefined || card.toughness !== undefined;
}

function isLandName(name: string): boolean {
  return /\b(forest|island|mountain|plains|swamp|foundry|harbor|forge|tower|pool|retreat)\b/i.test(name);
}

function getZoneCounts(player: PlayerGameState): PlayerZoneCounts {
  return {
    library: player.zones.library.length,
    graveyard: player.zones.graveyard.length,
    exile: player.zones.exile.length,
    command: player.zones.command.length
  };
}

function phaseToStep(phase: GameSnapshot["phase"]): GameStep {
  switch (phase) {
    case "beginning":
      return "untap";
    case "precombat-main":
      return "precombat-main";
    case "combat":
      return "declare-attackers";
    case "postcombat-main":
      return "postcombat-main";
    case "ending":
      return "end";
  }
}

function defaultPromptText(snapshot: GameSnapshot): string {
  if (snapshot.choicePrompt?.message) return snapshot.choicePrompt.message;
  if (snapshot.waitingOnPlayerId && snapshot.waitingOnPlayerId !== snapshot.priorityPlayerId) {
    return `Waiting on ${snapshot.waitingOnPlayerId}`;
  }
  if (snapshot.priorityPlayerId) return "Your priority";
  return "Waiting for engine";
}
