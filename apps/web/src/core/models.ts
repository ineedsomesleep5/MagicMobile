/**
 * The board's game model: a port of apps/android/core/.../game/Models.kt (Swift Models.swift).
 * Field names match the Swift Codable keys. Decoders follow kotlinx.serialization with
 * `explicitNulls = false` and `coerceInputValues = true`: a missing or null optional is undefined.
 */
import { arr, bool, EngineError, get, int, isObject, isUuid, type J, type JObject, obj, str, stringValue } from "./json";

const opt = <T>(value: J | undefined, read: (value: J) => T | undefined): T | undefined =>
  value === undefined || value === null ? undefined : read(value);
const need = <T>(value: T | undefined, what: string): T => {
  if (value === undefined) throw EngineError.invalid(`Missing ${what}`);
  return value;
};
const strings = (value: J | undefined): string[] | undefined =>
  opt(value, (v) => {
    const list = arr(v);
    if (!list || !list.every((item) => typeof item === "string")) throw EngineError.invalid("Expected strings");
    return list as string[];
  });
const ints = (value: J | undefined): number[] | undefined =>
  opt(value, (v) => {
    const list = arr(v);
    if (!list || !list.every((item) => int(item) !== undefined)) throw EngineError.invalid("Expected integers");
    return list as number[];
  });
const intMap = (value: J | undefined): Record<string, number> | undefined =>
  opt(value, (v) => {
    const fields = obj(v);
    if (!fields) throw EngineError.invalid("Expected an integer map");
    const result: Record<string, number> = {};
    for (const [key, item] of Object.entries(fields)) result[key] = need(int(item), key);
    return result;
  });
const list = <T>(value: J | undefined, read: (value: J) => T): T[] | undefined =>
  opt(value, (v) => {
    const items = arr(v);
    if (!items) throw EngineError.invalid("Expected a list");
    return items.map(read);
  });
const requiredList = <T>(value: J | undefined, read: (value: J) => T, what: string): T[] => need(list(value, read), what);
const oStr = (value: J | undefined) => opt(value, (v) => need(str(v), "string"));
const oInt = (value: J | undefined) => opt(value, (v) => need(int(v), "integer"));
const oBool = (value: J | undefined) => opt(value, (v) => need(bool(v), "boolean"));
const rStr = (value: J | undefined, what: string) => need(oStr(value), what);
const rInt = (value: J | undefined, what: string) => need(oInt(value), what);
const rBool = (value: J | undefined, what: string) => need(oBool(value), what);

export interface GameLogEntry { id: string; message: string; createdAt?: string }

export interface TokenArtworkIdentity { name: string; typeLine: string; oracleText: string; power?: string; toughness?: string; colors: string[] }

export interface CardIdentity {
  name: string; typeLine: string; oracleText?: string; manaCost?: string; isToken?: boolean; tokenColors?: string[];
  copySourceArtworkName?: string; tokenArtwork?: TokenArtworkIdentity;
}

export interface XmageCardIcon { iconType: string; resourceName?: string; category?: string; text?: string; hint?: string }

export interface ZoneCard {
  instanceId: string; card: CardIdentity; tapped?: boolean; summoningSickness?: boolean; cardIcons?: XmageCardIcon[];
  counters?: Record<string, number>; power?: number; toughness?: number; isCreaturePermanent?: boolean; damage?: number;
  isAttacking?: boolean; blocking?: string[]; attachedToInstanceId?: string; selectable?: boolean; disabledReason?: string;
  reportedPower?: string; reportedToughness?: string; phasedIn?: boolean;
}

export interface ManaPool { W: number; U: number; B: number; R: number; G: number; C: number }

export interface PlayerZones {
  library: ZoneCard[]; hand: ZoneCard[]; battlefield: ZoneCard[]; graveyard: ZoneCard[]; exile: ZoneCard[]; command: ZoneCard[];
  stack: ZoneCard[]; handCount?: number; libraryCount?: number;
}

export interface CommanderPublicState {
  id: string; name?: string; ownerPlayerId: string; castsFromCommandZone?: number; commanderTax?: number;
  damageToPlayers?: Record<string, number>;
}

export interface PlayerGameState {
  playerId: string; displayName?: string; life: number; poison: number; commanderTax: number; manaPool?: ManaPool;
  zones: PlayerZones; commanderDamage?: Record<string, number>; commanderTaxKnown?: boolean; commanders?: CommanderPublicState[];
  counters?: Record<string, number>; monarch?: boolean; initiative?: boolean; hasLeft?: boolean; isHuman?: boolean; designations?: string[];
}

export interface AttackDeclaration { attackerId: string; defenderId?: string }
export interface BlockDeclaration { blockerId: string; attackerId?: string }
export interface XmagePromptMultiAmount { id: string; label: string; min: number; max: number; defaultValue?: number }

export interface LegalAction {
  id: string; type: string; playerId: string; label: string; promptId?: string; cardInstanceId?: string; cardName?: string;
  manaCost?: string; sourceZone?: string; sourceInstanceId?: string; abilityId?: string; targetIds?: string[];
  playerIds?: string[]; choiceIds?: string[]; cardInstanceIds?: string[]; modeIds?: string[]; orderedIds?: string[];
  amount?: number; amounts?: number[]; manaType?: string; manaTypes?: string[]; pile?: number; confirmed?: boolean; pay?: boolean;
  useCommandZone?: boolean; messageId?: number; shortLabel?: string; attackers?: AttackDeclaration[]; blockers?: BlockDeclaration[];
}

export interface ChoicePromptOption { id: string; label: string; cardInstanceId?: string }
export interface XmageResponseCommand { type?: string; promptId?: string; messageId?: number; confirmed?: boolean; pay?: boolean }
export interface XmagePromptPile { id: string; label: string; cards: ZoneCard[] }
export interface XmagePromptAbility {
  id: string; label: string; rulesText?: string; sourceInstanceId?: string; sourceCard?: ZoneCard; sourceName?: string;
  sourceUnavailableReason?: string;
}
export interface XmagePromptPlayer { id: string; label: string; playerId: string; life?: number; selectable?: boolean }
export interface XmagePromptManaChoice { id: string; label: string; manaType?: string; amount?: number }
export interface XmagePromptConfirmation {
  yesLabel?: string; noLabel?: string; defaultValue?: boolean; yesCommand?: XmageResponseCommand; noCommand?: XmageResponseCommand;
}

export interface PromptEnvelopeV2 {
  id: string; method: string; messageId: number; playerId: string; responseKind: string; message: string; required?: boolean;
  minChoices?: number; maxChoices?: number; totalMin?: number; totalMax?: number; targetIds?: string[]; choices?: ChoicePromptOption[];
  responseCommand?: XmageResponseCommand; cards?: ZoneCard[]; targets?: ChoicePromptOption[]; players?: XmagePromptPlayer[];
  piles?: XmagePromptPile[]; abilities?: XmagePromptAbility[]; modes?: ChoicePromptOption[]; amounts?: number[];
  multiAmounts?: XmagePromptMultiAmount[]; manaChoices?: XmagePromptManaChoice[]; orderedItems?: ChoicePromptOption[];
  confirmation?: XmagePromptConfirmation; options?: JObject;
}

export interface ManaPayment { active: boolean; spellName?: string; manaCostText?: string; remainingText?: string }

export interface XmageStackObject {
  id: string; objectId?: string; objectType?: string; name: string; rulesText?: string; sourceInstanceId?: string;
  sourceName?: string; sourceZone?: string; sourceCard?: ZoneCard; controllerId?: string; targetIds?: string[]; paid?: boolean;
}
export interface XmageCombatGroup {
  defenderId: string; defenderName: string; defenderKind?: string; blocked: boolean; attackers: ZoneCard[]; blockers: ZoneCard[];
}
export interface XmageNamedZone { id: string; name: string; cards: ZoneCard[] }
export interface XmagePlayableAbility { id: string; label: string; category: string }
export interface XmagePlayableObject {
  sourceInstanceId: string; sourceZone?: string; cardName: string; categories: string[]; abilities: XmagePlayableAbility[];
}
export interface XmageSkipState {
  passedTurn: boolean; passedUntilEndOfTurn: boolean; passedUntilNextMain: boolean; passedUntilStackResolved: boolean;
  passedAllTurns: boolean; passedUntilEndStepBeforeMyTurn: boolean;
}
export interface XmageMobilePlayer {
  playerId: string; xmagePlayerId?: string; name: string; active: boolean; hasPriority: boolean; timerActive: boolean;
  skipState: XmageSkipState; manaPool: ManaPool; command: ZoneCard[];
  zones: { battlefield: ZoneCard[]; graveyard: ZoneCard[]; exile: ZoneCard[]; sideboard: ZoneCard[] };
}
export interface XmagePanels { stack: boolean; command: boolean; graveyard: boolean; exile: boolean; revealed: boolean; lookedAt: boolean; search: boolean }
export interface XmageMobileSnapshot {
  schemaVersion: number; gameId: string; bridgeRevision: number; xmageCycle?: number; callbackCoverage: string[];
  stack: XmageStackObject[]; combat: XmageCombatGroup[]; players: XmageMobilePlayer[]; exileZones: XmageNamedZone[];
  revealed: XmageNamedZone[]; lookedAt: XmageNamedZone[]; companion: XmageNamedZone[]; playableObjects: XmagePlayableObject[];
  panels: XmagePanels;
}

export type GameStatus = "in_progress" | "completed";

export interface GameSnapshot {
  id: string; source?: string; activePlayerId?: string; phase: string; step?: string; turn: number; priorityPlayerId?: string;
  waitingOnPlayerId?: string; promptText?: string; players: PlayerGameState[]; log: GameLogEntry[]; legalActions?: LegalAction[];
  promptEnvelopeV2?: PromptEnvelopeV2; xmage?: XmageMobileSnapshot; bridgeRevision?: number; xmageCycle?: number;
  pendingStatus?: string; manaPayment?: ManaPayment; gameStatus?: GameStatus; winnerPlayerIds?: string[]; viewerPlayerId?: string;
  dayNight?: string; stormCount?: number;
}

/** A command the board asks the session to send (Swift `GameCommand`). */
export interface GameCommand {
  type: string; gameId: string; playerId: string; cardInstanceId?: string; sourceInstanceId?: string; abilityId?: string;
  promptId?: string; messageId?: number; choiceIds?: string[]; targetIds?: string[]; cardInstanceIds?: string[]; modeIds?: string[];
  pile?: number; amount?: number; amounts?: number[]; orderedIds?: string[]; manaType?: string; playerIds?: string[];
  confirmed?: boolean; expectedBridgeRevision?: number;
}

// ---- decoders ----

const decodeTokenArtwork = (value: J): TokenArtworkIdentity => ({
  name: rStr(get(value, "name"), "name"), typeLine: rStr(get(value, "typeLine"), "typeLine"),
  oracleText: rStr(get(value, "oracleText"), "oracleText"), power: oStr(get(value, "power")), toughness: oStr(get(value, "toughness")),
  colors: need(strings(get(value, "colors")), "colors"),
});

export const decodeCardIcon = (value: J): XmageCardIcon => ({
  iconType: rStr(get(value, "iconType"), "iconType"), resourceName: oStr(get(value, "resourceName")), category: oStr(get(value, "category")),
  text: oStr(get(value, "text")), hint: oStr(get(value, "hint")),
});

export const decodeZoneCard = (value: J): ZoneCard => {
  const card = get(value, "card");
  if (!isObject(card)) throw EngineError.invalid("Missing card");
  return {
    instanceId: rStr(get(value, "instanceId"), "instanceId"),
    card: {
      name: rStr(get(card, "name"), "name"), typeLine: rStr(get(card, "typeLine"), "typeLine"), oracleText: oStr(get(card, "oracleText")),
      manaCost: oStr(get(card, "manaCost")), isToken: oBool(get(card, "isToken")), tokenColors: strings(get(card, "tokenColors")),
      copySourceArtworkName: oStr(get(card, "copySourceArtworkName")), tokenArtwork: opt(get(card, "tokenArtwork"), decodeTokenArtwork),
    },
    tapped: oBool(get(value, "tapped")), summoningSickness: oBool(get(value, "summoningSickness")),
    cardIcons: list(get(value, "cardIcons"), decodeCardIcon), counters: intMap(get(value, "counters")),
    power: oInt(get(value, "power")), toughness: oInt(get(value, "toughness")), isCreaturePermanent: oBool(get(value, "isCreaturePermanent")),
    damage: oInt(get(value, "damage")), isAttacking: oBool(get(value, "isAttacking")), blocking: strings(get(value, "blocking")),
    attachedToInstanceId: oStr(get(value, "attachedToInstanceId")), selectable: oBool(get(value, "selectable")),
    disabledReason: oStr(get(value, "disabledReason")), reportedPower: oStr(get(value, "reportedPower")),
    reportedToughness: oStr(get(value, "reportedToughness")), phasedIn: oBool(get(value, "phasedIn")),
  };
};

const decodeManaPool = (value: J): ManaPool => ({
  W: rInt(get(value, "W"), "W"), U: rInt(get(value, "U"), "U"), B: rInt(get(value, "B"), "B"),
  R: rInt(get(value, "R"), "R"), G: rInt(get(value, "G"), "G"), C: rInt(get(value, "C"), "C"),
});

const cards = (value: J | undefined, what: string) => requiredList(value, decodeZoneCard, what);

export const decodePlayer = (value: J): PlayerGameState => {
  const zones = get(value, "zones");
  return {
    playerId: rStr(get(value, "playerId"), "playerId"), displayName: oStr(get(value, "displayName")), life: rInt(get(value, "life"), "life"),
    poison: rInt(get(value, "poison"), "poison"), commanderTax: rInt(get(value, "commanderTax"), "commanderTax"),
    manaPool: opt(get(value, "manaPool"), decodeManaPool),
    zones: {
      library: cards(get(zones, "library"), "library"), hand: cards(get(zones, "hand"), "hand"),
      battlefield: cards(get(zones, "battlefield"), "battlefield"), graveyard: cards(get(zones, "graveyard"), "graveyard"),
      exile: cards(get(zones, "exile"), "exile"), command: cards(get(zones, "command"), "command"), stack: cards(get(zones, "stack"), "stack"),
      handCount: oInt(get(zones, "handCount")), libraryCount: oInt(get(zones, "libraryCount")),
    },
    commanderDamage: intMap(get(value, "commanderDamage")), commanderTaxKnown: oBool(get(value, "commanderTaxKnown")),
    commanders: list(get(value, "commanders"), (c) => ({
      id: rStr(get(c, "id"), "id"), name: oStr(get(c, "name")), ownerPlayerId: rStr(get(c, "ownerPlayerId"), "ownerPlayerId"),
      castsFromCommandZone: oInt(get(c, "castsFromCommandZone")), commanderTax: oInt(get(c, "commanderTax")),
      damageToPlayers: intMap(get(c, "damageToPlayers")),
    })),
    counters: intMap(get(value, "counters")), monarch: oBool(get(value, "monarch")), initiative: oBool(get(value, "initiative")),
    hasLeft: oBool(get(value, "hasLeft")), isHuman: oBool(get(value, "isHuman")), designations: strings(get(value, "designations")),
  };
};

const decodeOption = (value: J): ChoicePromptOption => ({
  id: rStr(get(value, "id"), "id"), label: rStr(get(value, "label"), "label"), cardInstanceId: oStr(get(value, "cardInstanceId")),
});
const decodeResponseCommand = (value: J): XmageResponseCommand => ({
  type: oStr(get(value, "type")), promptId: oStr(get(value, "promptId")), messageId: oInt(get(value, "messageId")),
  confirmed: oBool(get(value, "confirmed")), pay: oBool(get(value, "pay")),
});
const decodeMultiAmount = (value: J): XmagePromptMultiAmount => ({
  id: rStr(get(value, "id"), "id"), label: rStr(get(value, "label"), "label"), min: rInt(get(value, "min"), "min"),
  max: rInt(get(value, "max"), "max"), defaultValue: oInt(get(value, "defaultValue")),
});

/** Swift `FlexibleInt`: an integer or a numeric string. */
const flexibleInt = (value: J): number => {
  if (typeof value === "string") {
    if (!/^[+-]?\d+$/.test(value)) throw EngineError.invalid("Expected an integer or numeric string.");
    return Number.parseInt(value, 10);
  }
  return need(int(value), "integer");
};

export const decodeLegalAction = (value: J): LegalAction => ({
  id: rStr(get(value, "id"), "id"), type: rStr(get(value, "type"), "type"), playerId: rStr(get(value, "playerId"), "playerId"),
  label: rStr(get(value, "label"), "label"), promptId: oStr(get(value, "promptId")), cardInstanceId: oStr(get(value, "cardInstanceId")),
  cardName: oStr(get(value, "cardName")), manaCost: oStr(get(value, "manaCost")), sourceZone: oStr(get(value, "sourceZone")),
  sourceInstanceId: oStr(get(value, "sourceInstanceId")), abilityId: oStr(get(value, "abilityId")), targetIds: strings(get(value, "targetIds")),
  playerIds: strings(get(value, "playerIds")), choiceIds: strings(get(value, "choiceIds")),
  cardInstanceIds: strings(get(value, "cardInstanceIds")), modeIds: strings(get(value, "modeIds")), orderedIds: strings(get(value, "orderedIds")),
  amount: oInt(get(value, "amount")), amounts: ints(get(value, "amounts")), manaType: oStr(get(value, "manaType")),
  manaTypes: strings(get(value, "manaTypes")), pile: opt(get(value, "pile"), flexibleInt), confirmed: oBool(get(value, "confirmed")),
  pay: oBool(get(value, "pay")), useCommandZone: oBool(get(value, "useCommandZone")), messageId: oInt(get(value, "messageId")),
  shortLabel: oStr(get(value, "shortLabel")),
});

export const decodeEnvelope = (value: J): PromptEnvelopeV2 => ({
  id: rStr(get(value, "id"), "id"), method: rStr(get(value, "method"), "method"), messageId: rInt(get(value, "messageId"), "messageId"),
  playerId: rStr(get(value, "playerId"), "playerId"), responseKind: rStr(get(value, "responseKind"), "responseKind"),
  message: rStr(get(value, "message"), "message"), required: oBool(get(value, "required")), minChoices: oInt(get(value, "minChoices")),
  maxChoices: oInt(get(value, "maxChoices")), totalMin: oInt(get(value, "totalMin")), totalMax: oInt(get(value, "totalMax")),
  targetIds: strings(get(value, "targetIds")), choices: list(get(value, "choices"), decodeOption),
  responseCommand: opt(get(value, "responseCommand"), decodeResponseCommand), cards: list(get(value, "cards"), decodeZoneCard),
  targets: list(get(value, "targets"), decodeOption),
  players: list(get(value, "players"), (p) => ({
    id: rStr(get(p, "id"), "id"), label: rStr(get(p, "label"), "label"), playerId: rStr(get(p, "playerId"), "playerId"),
    life: oInt(get(p, "life")), selectable: oBool(get(p, "selectable")),
  })),
  piles: list(get(value, "piles"), (p) => ({ id: rStr(get(p, "id"), "id"), label: rStr(get(p, "label"), "label"), cards: cards(get(p, "cards"), "cards") })),
  abilities: list(get(value, "abilities"), (a) => ({
    id: rStr(get(a, "id"), "id"), label: rStr(get(a, "label"), "label"), rulesText: oStr(get(a, "rulesText")),
    sourceInstanceId: oStr(get(a, "sourceInstanceId")), sourceCard: opt(get(a, "sourceCard"), decodeZoneCard),
    sourceName: oStr(get(a, "sourceName")), sourceUnavailableReason: oStr(get(a, "sourceUnavailableReason")),
  })),
  modes: list(get(value, "modes"), decodeOption), amounts: ints(get(value, "amounts")),
  multiAmounts: list(get(value, "multiAmounts"), decodeMultiAmount),
  manaChoices: list(get(value, "manaChoices"), (m) => ({
    id: rStr(get(m, "id"), "id"), label: rStr(get(m, "label"), "label"), manaType: oStr(get(m, "manaType")), amount: oInt(get(m, "amount")),
  })),
  orderedItems: list(get(value, "orderedItems"), decodeOption),
  confirmation: opt(get(value, "confirmation"), (c) => ({
    yesLabel: oStr(get(c, "yesLabel")), noLabel: oStr(get(c, "noLabel")), defaultValue: oBool(get(c, "defaultValue")),
    yesCommand: opt(get(c, "yesCommand"), decodeResponseCommand), noCommand: opt(get(c, "noCommand"), decodeResponseCommand),
  })),
  options: opt(get(value, "options"), (o) => need(obj(o), "options")),
});

const decodeNamedZone = (value: J): XmageNamedZone => ({
  id: rStr(get(value, "id"), "id"), name: rStr(get(value, "name"), "name"), cards: cards(get(value, "cards"), "cards"),
});

export const decodeXmage = (value: J): XmageMobileSnapshot => {
  const panels = get(value, "panels");
  return {
    schemaVersion: rInt(get(value, "schemaVersion"), "schemaVersion"), gameId: rStr(get(value, "gameId"), "gameId"),
    bridgeRevision: rInt(get(value, "bridgeRevision"), "bridgeRevision"), xmageCycle: oInt(get(value, "xmageCycle")),
    callbackCoverage: need(strings(get(value, "callbackCoverage")), "callbackCoverage"),
    stack: requiredList(get(value, "stack"), (s) => ({
      id: rStr(get(s, "id"), "id"), objectId: oStr(get(s, "objectId")), objectType: oStr(get(s, "objectType")), name: rStr(get(s, "name"), "name"),
      rulesText: oStr(get(s, "rulesText")), sourceInstanceId: oStr(get(s, "sourceInstanceId")), sourceName: oStr(get(s, "sourceName")),
      sourceZone: oStr(get(s, "sourceZone")), sourceCard: opt(get(s, "sourceCard"), decodeZoneCard), controllerId: oStr(get(s, "controllerId")),
      targetIds: strings(get(s, "targetIds")), paid: oBool(get(s, "paid")),
    }), "stack"),
    combat: requiredList(get(value, "combat"), (g) => ({
      defenderId: rStr(get(g, "defenderId"), "defenderId"), defenderName: rStr(get(g, "defenderName"), "defenderName"),
      defenderKind: oStr(get(g, "defenderKind")), blocked: rBool(get(g, "blocked"), "blocked"),
      attackers: cards(get(g, "attackers"), "attackers"), blockers: cards(get(g, "blockers"), "blockers"),
    }), "combat"),
    players: requiredList(get(value, "players"), (p) => {
      const skip = get(p, "skipState");
      const zones = get(p, "zones");
      return {
        playerId: rStr(get(p, "playerId"), "playerId"), xmagePlayerId: oStr(get(p, "xmagePlayerId")), name: rStr(get(p, "name"), "name"),
        active: rBool(get(p, "active"), "active"), hasPriority: rBool(get(p, "hasPriority"), "hasPriority"),
        timerActive: rBool(get(p, "timerActive"), "timerActive"),
        skipState: {
          passedTurn: rBool(get(skip, "passedTurn"), "passedTurn"), passedUntilEndOfTurn: rBool(get(skip, "passedUntilEndOfTurn"), "skip"),
          passedUntilNextMain: rBool(get(skip, "passedUntilNextMain"), "skip"), passedUntilStackResolved: rBool(get(skip, "passedUntilStackResolved"), "skip"),
          passedAllTurns: rBool(get(skip, "passedAllTurns"), "skip"), passedUntilEndStepBeforeMyTurn: rBool(get(skip, "passedUntilEndStepBeforeMyTurn"), "skip"),
        },
        manaPool: decodeManaPool(need(get(p, "manaPool"), "manaPool")), command: cards(get(p, "command"), "command"),
        zones: {
          battlefield: cards(get(zones, "battlefield"), "battlefield"), graveyard: cards(get(zones, "graveyard"), "graveyard"),
          exile: cards(get(zones, "exile"), "exile"), sideboard: cards(get(zones, "sideboard"), "sideboard"),
        },
      };
    }, "players"),
    exileZones: requiredList(get(value, "exileZones"), decodeNamedZone, "exileZones"),
    revealed: requiredList(get(value, "revealed"), decodeNamedZone, "revealed"),
    lookedAt: requiredList(get(value, "lookedAt"), decodeNamedZone, "lookedAt"),
    companion: requiredList(get(value, "companion"), decodeNamedZone, "companion"),
    playableObjects: requiredList(get(value, "playableObjects"), (o) => ({
      sourceInstanceId: rStr(get(o, "sourceInstanceId"), "sourceInstanceId"), sourceZone: oStr(get(o, "sourceZone")),
      cardName: rStr(get(o, "cardName"), "cardName"), categories: need(strings(get(o, "categories")), "categories"),
      abilities: requiredList(get(o, "abilities"), (a) => ({
        id: rStr(get(a, "id"), "id"), label: rStr(get(a, "label"), "label"), category: rStr(get(a, "category"), "category"),
      }), "abilities"),
    }), "playableObjects"),
    panels: {
      stack: rBool(get(panels, "stack"), "panels"), command: rBool(get(panels, "command"), "panels"), graveyard: rBool(get(panels, "graveyard"), "panels"),
      exile: rBool(get(panels, "exile"), "panels"), revealed: rBool(get(panels, "revealed"), "panels"), lookedAt: rBool(get(panels, "lookedAt"), "panels"),
      search: rBool(get(panels, "search"), "panels"),
    },
  };
};

// ---- computed properties ----

export const isCompleted = (s: GameSnapshot) => s.gameStatus === "completed";
export const viewerID = (s: GameSnapshot) => s.viewerPlayerId ?? "human";
export const isOut = (p: PlayerGameState) => p.hasLeft === true;
export const human = (s: GameSnapshot) => s.players.find((p) => p.playerId === viewerID(s));
/** The viewer conceded or was eliminated and the others play on: watch, never act. */
export const isSpectating = (s: GameSnapshot) => (human(s) ? isOut(human(s)!) : false) && !isCompleted(s);
/** An AI opponent holds priority and the game waits on its decision. */
export const thinkingPlayerID = (s: GameSnapshot): string | undefined => {
  if (isCompleted(s)) return undefined;
  const id = s.priorityPlayerId;
  if (id === undefined || id === viewerID(s) || s.promptEnvelopeV2 !== undefined) return undefined;
  const player = s.players.find((p) => p.playerId === id);
  if (!player) return undefined;
  return player.isHuman === false && !isOut(player) ? id : undefined;
};
export const playerLabel = (s: GameSnapshot, playerID: string | undefined): string => {
  if (playerID === undefined) return "Waiting";
  if (playerID === viewerID(s)) return "You";
  return s.players.find((p) => p.playerId === playerID)?.displayName ?? playerID;
};

export const isCreatureCard = (c: ZoneCard) => c.isCreaturePermanent ?? /creature/i.test(c.card.typeLine);
export const displayPower = (c: ZoneCard) => c.reportedPower ?? (c.power === undefined ? undefined : String(c.power));
export const displayToughness = (c: ZoneCard) => c.reportedToughness ?? (c.toughness === undefined ? undefined : String(c.toughness));

export const XmageIcons = {
  nativeCategory(iconType: string): string | undefined {
    switch (iconType.toUpperCase()) {
      case "PLAYABLE_COUNT": return "PLAYABLE_COUNT";
      case "COMMANDER": case "RINGBEARER": case "OTHER_HAS_TARGETS": return "COMMANDER";
      case "SYSTEM_COMBINED": case "SYSTEM_DEBUG": return "SYSTEM";
      case "ABILITY_MENACE": return "ABILITY";
      default: return XmageIcons.assetName(iconType) === undefined ? undefined : "ABILITY";
    }
  },
  assetName(iconType: string): string | undefined {
    const names: Record<string, string> = {
      PLAYABLE_COUNT: "playable-count", ABILITY_FLYING: "flying", ABILITY_DEFENDER: "defender", ABILITY_DEATHTOUCH: "deathtouch",
      ABILITY_LIFELINK: "lifelink", ABILITY_DOUBLE_STRIKE: "double-strike", ABILITY_FIRST_STRIKE: "first-strike", ABILITY_CREW: "crew",
      ABILITY_TRAMPLE: "trample", ABILITY_HEXPROOF: "hexproof", ABILITY_INFECT: "infect", ABILITY_INDESTRUCTIBLE: "indestructible",
      ABILITY_VIGILANCE: "vigilance", ABILITY_CLASS_LEVEL: "class-level", ABILITY_REACH: "reach", OTHER_FACEDOWN: "facedown",
      OTHER_COST_X: "cost-x", OTHER_HAS_RESTRICTIONS: "restrictions", OTHER_HAS_TARGETS: "targets", RINGBEARER: "ringbearer",
      COMMANDER: "commander", SYSTEM_COMBINED: "combined",
    };
    const name = names[iconType.toUpperCase()];
    return name === undefined ? undefined : `xmage-icon-${name}`;
  },
  textBadge: (icon: XmageCardIcon) => (icon.iconType === "ABILITY_MENACE" ? "Menace" : undefined),
  keywordIcons(rules: string | undefined): XmageCardIcon[] {
    if (rules === undefined) return [];
    const keywordTypes: Record<string, string> = {
      flying: "ABILITY_FLYING", defender: "ABILITY_DEFENDER", deathtouch: "ABILITY_DEATHTOUCH", lifelink: "ABILITY_LIFELINK",
      "double strike": "ABILITY_DOUBLE_STRIKE", "first strike": "ABILITY_FIRST_STRIKE", trample: "ABILITY_TRAMPLE",
      hexproof: "ABILITY_HEXPROOF", infect: "ABILITY_INFECT", indestructible: "ABILITY_INDESTRUCTIBLE", vigilance: "ABILITY_VIGILANCE",
      reach: "ABILITY_REACH",
    };
    const found: string[] = [];
    for (const rawLine of rules.split(/[\n\r]/)) {
      const line = rawLine.replace(/\([^)]*\)/g, "").replace(/^[\s.]+|[\s.]+$/g, "");
      if (line.length === 0) continue;
      const parts = line.split(",").map((part) => part.trim().toLowerCase());
      const types = parts.map((part) => keywordTypes[part]).filter((t): t is string => t !== undefined);
      if (types.length !== parts.length) continue;
      for (const type of types) if (!found.includes(type)) found.push(type);
    }
    return found.map((iconType) => ({ iconType, category: "ABILITY" }));
  },
  keywordName(iconType: string): string | undefined {
    if (!iconType.startsWith("ABILITY_") || XmageIcons.assetName(iconType) === undefined) return undefined;
    const words = iconType.slice("ABILITY_".length).replace(/_/g, " ").toLowerCase();
    return words.charAt(0).toUpperCase() + words.slice(1);
  },
};

/** Engine icons in the ability and commander categories, plus keyword icons from bare keyword rules lines. */
export const visibleXmageIcons = (c: ZoneCard): XmageCardIcon[] => {
  const engine = (c.cardIcons ?? []).filter((icon) => {
    const category = icon.category?.toUpperCase();
    return (category === "ABILITY" || category === "COMMANDER") &&
      (XmageIcons.assetName(icon.iconType) !== undefined || XmageIcons.textBadge(icon) !== undefined);
  });
  const present = new Set(engine.map((icon) => icon.iconType.toUpperCase()));
  return [...engine, ...XmageIcons.keywordIcons(c.card.oracleText).filter((icon) => !present.has(icon.iconType))];
};

export const compactPromptTitle = (a: LegalAction): string => {
  switch (a.type) {
    case "pass_priority": return "Pass Priority";
    case "resolve_stack": case "pass_until_stack_resolved": return "Resolve Stack";
    case "end_turn": return "End Turn";
    case "pass_until_end_of_turn": return "Yield Until End Step";
    case "yield_until_next_turn": case "pass_until_next_turn": return "Yield Until Next Turn";
  }
  const label = a.label.trim();
  const short = a.shortLabel?.trim();
  const generic = new Set(["ability", "activated ability", "triggered ability"]);
  if ((a.type === "choose_ability" || a.type === "activate_ability") && short !== undefined && generic.has(short.toLowerCase()) &&
    label.length > 0 && !generic.has(label.toLowerCase())) return label;
  if (short) return short;
  return label.length > 0 ? label : a.type;
};

export type MobilePromptKind = "payment" | "target" | "confirmation" | "cardChoice" | "playerChoice" | "abilityChoice" | "order" |
  "amount" | "multiAmount" | "pile" | "search" | "combat" | "unsupported";

const nonEmpty = (value: unknown[] | undefined) => value !== undefined && value.length > 0;

/** MobilePromptPresentation.kind: what sort of question an envelope asks. */
export const promptKind = (p: PromptEnvelopeV2): MobilePromptKind => {
  const type = p.responseCommand?.type?.toLowerCase() ?? "";
  const kind = p.responseKind.toLowerCase();
  const method = p.method.toUpperCase();
  if (["play_mana", "choose_mana", "pay_cost", "play_x_mana"].includes(type) || ["mana", "pay_cost", "cost", "x_mana"].includes(kind) ||
    method === "GAME_PLAY_MANA" || method === "GAME_PLAY_XMANA") return "payment";
  if (type === "choose_target" || kind === "target" || method.includes("TARGET") || nonEmpty(p.targets) || nonEmpty(p.targetIds)) return "target";
  if (type === "answer_yes_no" || kind === "confirmation" || p.confirmation !== undefined) return "confirmation";
  if (type === "choose_player" || kind === "player" || nonEmpty(p.players)) return "playerChoice";
  if (type === "choose_ability" || kind === "ability" || nonEmpty(p.abilities)) return "abilityChoice";
  if (type === "order_triggers" || type === "order_items" || kind === "order" || nonEmpty(p.orderedItems)) return "order";
  if (type === "choose_multi_amount" || kind === "multi_amount" || nonEmpty(p.multiAmounts)) return "multiAmount";
  if (type === "choose_amount" || kind === "amount" || nonEmpty(p.amounts)) return "amount";
  if (type === "choose_pile" || kind === "pile" || nonEmpty(p.piles)) return "pile";
  if (type === "search_select" || kind === "search") return "search";
  if (type === "choose_card" || kind === "card" || nonEmpty(p.cards) || nonEmpty(p.choices) || nonEmpty(p.modes)) return "cardChoice";
  return "unsupported";
};

/** XmagePromptPile.explicitPileNumber */
export const pileNumber = (pile: XmagePromptPile): number | undefined => {
  if (pile.id === "1" || pile.id === "2") return Number(pile.id);
  const id = pile.id.toLowerCase();
  if (["pile-1", "pile_1", "pile 1"].includes(id)) return 1;
  if (["pile-2", "pile_2", "pile 2"].includes(id)) return 2;
  const label = pile.label.trim().toLowerCase();
  if (["pile 1", "pile-1", "pile_1"].includes(label)) return 1;
  if (["pile 2", "pile-2", "pile_2"].includes(label)) return 2;
  return undefined;
};

/** Foundation's `String.capitalized`: each whitespace-delimited word gets an initial capital. */
export const capitalizedWords = (value: string): string => {
  let out = "";
  let start = true;
  for (const ch of value) {
    if (/\s/.test(ch)) { out += ch; start = true; continue; }
    out += start ? ch.toUpperCase() : ch.toLowerCase();
    start = false;
  }
  return out;
};

export { isUuid, stringValue };
