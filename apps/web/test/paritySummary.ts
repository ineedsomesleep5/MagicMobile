/** Mirrors ParitySummary in apps/android/core/src/test/.../ParityGoldenTest.kt field for field. */
import { EnginePrompt } from "../src/core/engineClient";
import { arr, EngineError, get, int, type J, type JObject, str, bool, stringValue } from "../src/core/json";
import {
  compactPromptTitle, type GameCommand, type GameSnapshot, isSpectating, type LegalAction, type PlayerGameState, pileNumber,
  promptKind, type PromptEnvelopeV2, thinkingPlayerID, visibleXmageIcons, type ZoneCard, type ChoicePromptOption,
  type XmageResponseCommand,
} from "../src/core/models";
import { OnDevicePromptAdapter } from "../src/core/promptAdapter";

const o = (value: string | number | boolean | undefined): J => (value === undefined ? null : value);
const strings = (value: string[] | undefined): J => (value === undefined ? null : value);
const ints = (value: Record<string, number> | undefined): J => (value === undefined ? null : { ...value });
const list = <T>(value: T[] | undefined, transform: (item: T) => J): J => (value === undefined ? null : value.map(transform));

export const message = (error: unknown) => (error instanceof EngineError ? error.message : "decoding failed");

export const card = (c: ZoneCard): J => ({
  instanceId: c.instanceId, name: c.card.name, typeLine: c.card.typeLine, oracleText: o(c.card.oracleText), manaCost: o(c.card.manaCost),
  isToken: o(c.card.isToken), tokenColors: strings(c.card.tokenColors), copySourceArtworkName: o(c.card.copySourceArtworkName),
  tokenArtwork: c.card.tokenArtwork ? {
    name: c.card.tokenArtwork.name, typeLine: c.card.tokenArtwork.typeLine, oracleText: c.card.tokenArtwork.oracleText,
    power: o(c.card.tokenArtwork.power), toughness: o(c.card.tokenArtwork.toughness), colors: c.card.tokenArtwork.colors,
  } : null,
  tapped: o(c.tapped), summoningSickness: o(c.summoningSickness), damage: o(c.damage), phasedIn: o(c.phasedIn),
  isAttacking: o(c.isAttacking), blocking: strings(c.blocking), attachedToInstanceId: o(c.attachedToInstanceId),
  reportedPower: o(c.reportedPower), reportedToughness: o(c.reportedToughness), counters: ints(c.counters),
  icons: (c.cardIcons ?? []).map((i) => ({ iconType: i.iconType, category: o(i.category), text: o(i.text), hint: o(i.hint) })),
  visibleIcons: visibleXmageIcons(c).map((i) => i.iconType),
  selectable: o(c.selectable), disabledReason: o(c.disabledReason),
  displayPower: o(c.reportedPower ?? (c.power === undefined ? undefined : String(c.power))),
  displayToughness: o(c.reportedToughness ?? (c.toughness === undefined ? undefined : String(c.toughness))),
});

const player = (p: PlayerGameState): J => {
  const z = p.zones;
  return {
    playerId: p.playerId, displayName: o(p.displayName), life: p.life, poison: p.poison, commanderTax: p.commanderTax,
    commanderTaxKnown: o(p.commanderTaxKnown), hasLeft: o(p.hasLeft), isHuman: o(p.isHuman), monarch: o(p.monarch),
    initiative: o(p.initiative), counters: ints(p.counters), commanderDamage: ints(p.commanderDamage),
    commanders: (p.commanders ?? []).map((c) => ({
      id: c.id, name: o(c.name), ownerPlayerId: c.ownerPlayerId, commanderTax: o(c.commanderTax),
      castsFromCommandZone: o(c.castsFromCommandZone), damageToPlayers: ints(c.damageToPlayers),
    })),
    manaPool: p.manaPool ? { ...p.manaPool } : null, handCount: o(z.handCount), libraryCount: o(z.libraryCount),
    hand: z.hand.map(card), battlefield: z.battlefield.map(card), graveyard: z.graveyard.map(card), exile: z.exile.map(card),
    command: z.command.map(card), library: z.library.map(card), stack: z.stack.map(card),
  };
};

export const action = (a: LegalAction): J => ({
  id: a.id, type: a.type, playerId: a.playerId, label: a.label, promptId: o(a.promptId), messageId: o(a.messageId),
  cardInstanceId: o(a.cardInstanceId), sourceInstanceId: o(a.sourceInstanceId), sourceZone: o(a.sourceZone), cardName: o(a.cardName),
  abilityId: o(a.abilityId), confirmed: o(a.confirmed), choiceIds: strings(a.choiceIds), compactPromptTitle: compactPromptTitle(a),
});

export const envelope = (e: PromptEnvelopeV2): J => {
  const options = (values: ChoicePromptOption[] | undefined) => list(values, (v) => ({ id: v.id, label: v.label }));
  const command = (c: XmageResponseCommand | undefined): J => c === undefined ? null
    : { type: o(c.type), promptId: o(c.promptId), messageId: o(c.messageId), confirmed: o(c.confirmed), pay: o(c.pay) };
  const chosenValue = e.options?.chosenTargets;
  const chosen: J = Array.isArray(chosenValue) ? chosenValue.map(stringValue).filter((v): v is string => v !== undefined) : null;
  return {
    id: e.id, method: e.method, messageId: e.messageId, playerId: e.playerId, responseKind: e.responseKind, message: e.message,
    required: o(e.required), minChoices: o(e.minChoices), maxChoices: o(e.maxChoices), totalMin: o(e.totalMin), totalMax: o(e.totalMax),
    targetIds: strings(e.targetIds), choices: options(e.choices), responseCommand: command(e.responseCommand), cards: list(e.cards, card),
    targets: options(e.targets), players: list(e.players, (p) => ({ id: p.id, label: p.label, playerId: p.playerId })),
    piles: list(e.piles, (p) => ({ id: p.id, label: p.label, cards: p.cards.map(card), number: o(pileNumber(p)) })),
    abilities: list(e.abilities, (a) => ({
      id: a.id, label: a.label, sourceInstanceId: o(a.sourceInstanceId), sourceName: o(a.sourceName),
      sourceUnavailableReason: o(a.sourceUnavailableReason), sourceCard: a.sourceCard ? card(a.sourceCard) : null,
    })),
    modes: options(e.modes), amounts: list(e.amounts, (a) => a),
    multiAmounts: list(e.multiAmounts, (m) => ({ id: m.id, label: m.label, min: m.min, max: m.max, defaultValue: o(m.defaultValue) })),
    manaChoices: list(e.manaChoices, (m) => ({ id: m.id, label: m.label, manaType: o(m.manaType), amount: o(m.amount) })),
    orderedItems: options(e.orderedItems),
    confirmation: e.confirmation ? {
      yesLabel: o(e.confirmation.yesLabel), noLabel: o(e.confirmation.noLabel), yesCommand: command(e.confirmation.yesCommand),
      noCommand: command(e.confirmation.noCommand),
    } : null,
    optionKeys: e.options ? Object.keys(e.options).sort() : null, chosenTargets: chosen, kind: promptKind(e),
  };
};

export const snapshot = (s: GameSnapshot): JObject => {
  const x = s.xmage;
  return {
    id: s.id, source: o(s.source), activePlayerId: o(s.activePlayerId), phase: s.phase, step: o(s.step), turn: s.turn,
    priorityPlayerId: o(s.priorityPlayerId), waitingOnPlayerId: o(s.waitingOnPlayerId), promptText: o(s.promptText),
    bridgeRevision: o(s.bridgeRevision), xmageCycle: o(s.xmageCycle), pendingStatus: o(s.pendingStatus), gameStatus: o(s.gameStatus),
    winnerPlayerIds: strings(s.winnerPlayerIds), viewerPlayerId: o(s.viewerPlayerId), isSpectating: isSpectating(s),
    thinkingPlayerID: o(thinkingPlayerID(s)), log: s.log.map((l) => ({ id: l.id, message: l.message })),
    players: s.players.map(player), legalActions: (s.legalActions ?? []).map(action),
    promptEnvelopeV2: s.promptEnvelopeV2 ? envelope(s.promptEnvelopeV2) : null,
    manaPayment: s.manaPayment ? { active: s.manaPayment.active, remainingText: o(s.manaPayment.remainingText) } : null,
    xmage: x ? {
      gameId: x.gameId, bridgeRevision: x.bridgeRevision, xmageCycle: o(x.xmageCycle),
      stack: x.stack.map((st) => ({
        id: st.id, objectType: o(st.objectType), name: st.name, rulesText: o(st.rulesText), sourceInstanceId: o(st.sourceInstanceId),
        sourceName: o(st.sourceName), sourceCard: st.sourceCard ? card(st.sourceCard) : null, targetIds: strings(st.targetIds), paid: o(st.paid),
      })),
      combat: x.combat.map((g) => ({
        defenderId: g.defenderId, defenderName: g.defenderName, defenderKind: o(g.defenderKind), blocked: g.blocked,
        attackers: g.attackers.map(card), blockers: g.blockers.map(card),
      })),
      players: x.players.map((p) => ({
        playerId: p.playerId, name: p.name, active: p.active, hasPriority: p.hasPriority, timerActive: p.timerActive,
        passedTurn: p.skipState.passedTurn, passedAllTurns: p.skipState.passedAllTurns, sideboard: p.zones.sideboard.map(card),
      })),
      playableObjects: x.playableObjects.map((po) => ({
        sourceInstanceId: po.sourceInstanceId, sourceZone: o(po.sourceZone), cardName: po.cardName, categories: po.categories,
        abilities: po.abilities.map((a) => ({ id: a.id, label: a.label, category: a.category })),
      })),
      zones: [...x.exileZones, ...x.revealed, ...x.lookedAt, ...x.companion].map((z) => ({ id: z.id, name: z.name, cards: z.cards.map(card) })),
      panels: { ...x.panels },
    } : null,
  };
};

export const commandFrom = (f: J, gameId: string, playerId: string, promptId: string, messageId: number): GameCommand => {
  const listOf = (key: string) => arr(get(f, key))?.map(str).filter((v): v is string => v !== undefined);
  return {
    type: str(get(f, "type")) ?? "", gameId, playerId, cardInstanceId: str(get(f, "cardInstanceId")),
    sourceInstanceId: str(get(f, "sourceInstanceId")), abilityId: str(get(f, "abilityId")), promptId, messageId,
    choiceIds: listOf("choiceIds"), targetIds: listOf("targetIds"), cardInstanceIds: listOf("cardInstanceIds"), modeIds: listOf("modeIds"),
    pile: int(get(f, "pile")), amount: int(get(f, "amount")),
    amounts: arr(get(f, "amounts"))?.map(int).filter((v): v is number => v !== undefined),
    orderedIds: listOf("orderedIds"), manaType: str(get(f, "manaType")), playerIds: listOf("playerIds"), confirmed: bool(get(f, "confirmed")),
  };
};

export const answer = (command: GameCommand, prompt: EnginePrompt, viewer: string): J => {
  try {
    return OnDevicePromptAdapter.answer(command, prompt, viewer);
  } catch (error) {
    return { error: message(error) };
  }
};

export const answers = (s: GameSnapshot, prompt: EnginePrompt | undefined): J[] => {
  if (prompt === undefined || prompt.submitted) return [];
  const viewer = s.viewerPlayerId ?? "human";
  const commands: GameCommand[] = (s.legalActions ?? []).map((a) => ({
    type: a.type, gameId: s.id, playerId: a.playerId, cardInstanceId: a.cardInstanceId, sourceInstanceId: a.sourceInstanceId,
    abilityId: a.abilityId, promptId: a.promptId, messageId: a.messageId, choiceIds: a.choiceIds, targetIds: a.targetIds,
    cardInstanceIds: a.cardInstanceIds, modeIds: a.modeIds, pile: a.pile, amount: a.amount, amounts: a.amounts, orderedIds: a.orderedIds,
    manaType: a.manaType, playerIds: a.playerIds, confirmed: a.confirmed, expectedBridgeRevision: s.bridgeRevision,
  }));
  const e = s.promptEnvelopeV2;
  if (e) {
    for (const target of e.targets ?? []) commands.push({ type: "choose_target", gameId: s.id, playerId: viewer, promptId: e.id, messageId: e.messageId, targetIds: [target.id] });
    for (const confirmed of e.confirmation === undefined ? [] : [true, false]) {
      commands.push({ type: "answer_yes_no", gameId: s.id, playerId: viewer, promptId: e.id, messageId: e.messageId, confirmed });
    }
    for (const choice of e.manaChoices ?? []) commands.push({ type: "play_mana", gameId: s.id, playerId: viewer, promptId: e.id, messageId: e.messageId, manaType: choice.manaType });
  }
  return commands.map((c) => ({ type: c.type, answer: answer(c, prompt, viewer) }));
};
