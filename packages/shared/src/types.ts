export type PlayerId = string;
export type RoomId = string;
export type GameId = string;
export type DeckId = string;
export type CardId = string;

export type ColorSymbol = "W" | "U" | "B" | "R" | "G" | "C";
export type AiDifficulty = "easy" | "normal" | "hard" | "expert";

export type SeatType = "digital" | "webcam" | "hybrid" | "spectator";

export type ZoneName =
  | "library"
  | "hand"
  | "battlefield"
  | "graveyard"
  | "exile"
  | "command"
  | "stack";

export interface CardIdentity {
  id: CardId;
  name: string;
  manaValue: number;
  colorIdentity: ColorSymbol[];
  typeLine: string;
  oracleText?: string;
  isBasicLand?: boolean;
}

export interface DeckEntry {
  cardName: string;
  quantity: number;
  section: "commander" | "deck" | "sideboard" | "maybeboard";
}

export interface DeckList {
  id?: DeckId;
  name: string;
  commander?: DeckEntry;
  entries: DeckEntry[];
}

export interface DeckStats {
  lands: number;
  ramp: number;
  draw: number;
  removal: number;
  boardWipes: number;
  tutors: number;
  averageManaValue: number;
  manaCurve: Record<string, number>;
  colorDistribution: Record<ColorSymbol, number>;
  colorPipDensity: Record<ColorSymbol, number>;
}

export interface BracketScore {
  bracket: 1 | 2 | 3 | 4 | 5;
  score: number;
  explanations: string[];
}

export interface RuleZeroSummary {
  headline: string;
  talkingPoints: string[];
}

export interface AiPlayerConfig {
  playerId: PlayerId;
  displayName: string;
  difficulty: AiDifficulty;
  deck?: DeckList;
}

export interface CommanderGameConfig {
  roomId: RoomId;
  humanPlayerId: PlayerId;
  humanDeck: DeckList;
  aiPlayers: AiPlayerConfig[];
  startingLife: 40;
  commanderDamageEnabled: true;
  mulligan?: CommanderMulliganConfig;
  startingPlayer?: "random" | "human" | "ai";
  simulatorPreset?: "arena-battlefield";
}

export interface CommanderMulliganConfig {
  rule: "commander-free-first" | "london";
  freeMulligans: number;
}

export interface RoomSeat {
  playerId: PlayerId;
  displayName: string;
  seatType: SeatType;
  ready: boolean;
}

export interface RoomState {
  id: RoomId;
  name: string;
  seats: RoomSeat[];
  gameId?: GameId;
  status: "lobby" | "starting" | "active" | "complete";
}

export interface GameLogEntry {
  id: string;
  message: string;
  createdAt: string;
}

export interface ZoneCard {
  instanceId: string;
  card: CardIdentity;
  tapped?: boolean;
  counters?: Record<string, number>;
  power?: number;
  toughness?: number;
  damage?: number;
  isAttacking?: boolean;
  blocking?: string[];
  attachedToInstanceId?: string;
}

export interface ManaPool {
  W: number;
  U: number;
  B: number;
  R: number;
  G: number;
  C: number;
}

export interface PlayerGameState {
  playerId: PlayerId;
  life: number;
  poison: number;
  commanderTax: number;
  manaPool?: ManaPool;
  zones: Record<ZoneName, ZoneCard[]>;
  commanderDamage: Record<PlayerId, number>;
}

export interface GameSnapshot {
  id: GameId;
  roomId: RoomId;
  bridgeRevision?: number;
  xmageCycle?: number;
  pendingStatus?: "accepted" | "waiting_for_xmage" | "stalled";
  activePlayerId?: PlayerId;
  phase: "beginning" | "precombat-main" | "combat" | "postcombat-main" | "ending";
  step?: GameStep;
  turn: number;
  priorityPlayerId?: PlayerId;
  waitingOnPlayerId?: PlayerId;
  promptText?: string;
  players: PlayerGameState[];
  log: GameLogEntry[];
  legalActions?: LegalAction[];
  choicePrompt?: ChoicePrompt;
  promptEnvelope?: PromptEnvelope;
  promptEnvelopeV2?: PromptEnvelopeV2;
  xmage?: XmageMobileSnapshot;
  engineHealth?: EngineHealth;
}

export type CommanderStartupStatus = "starting" | "ready" | "failed";

export interface CommanderStartupResponse {
  startupId: string;
  status: CommanderStartupStatus;
  snapshot?: GameSnapshot;
  message?: string;
  error?: string;
}

export type GameStep =
  | "untap"
  | "upkeep"
  | "draw"
  | "precombat-main"
  | "begin-combat"
  | "declare-attackers"
  | "declare-blockers"
  | "combat-damage"
  | "end-combat"
  | "postcombat-main"
  | "end"
  | "cleanup";

export type LegalActionType =
  | "keep_hand"
  | "mulligan"
  | "play_land"
  | "cast_spell"
  | "activate_ability"
  | "choose_target"
  | "make_mana"
  | "play_mana"
  | "pay_cost"
  | "choose_mode"
  | "choose_ability"
  | "choose_card"
  | "choose_player"
  | "choose_pile"
  | "choose_amount"
  | "choose_multi_amount"
  | "choose_mana"
  | "answer_yes_no"
  | "play_x_mana"
  | "order_triggers"
  | "order_items"
  | "search_select"
  | "commander_replacement"
  | "declare_attackers"
  | "declare_blockers"
  | "resolve_choice"
  | "tap_permanent"
  | "untap_permanent"
  | "pass_priority"
  | "pass_until_response"
  | "pass_until_next_turn"
  | "advance_phase"
  | "concede";

export interface LegalAction {
  id: string;
  type: LegalActionType;
  playerId: PlayerId;
  label: string;
  promptId?: string;
  cardInstanceId?: string;
  sourceZone?: ZoneName;
  sourceInstanceId?: string;
  abilityId?: string;
  targetIds?: string[];
  validTargetIds?: string[];
  playerIds?: PlayerId[];
  validPlayerIds?: PlayerId[];
  cardInstanceIds?: string[];
  validCardInstanceIds?: string[];
  choiceIds?: string[];
  modeIds?: string[];
  orderedIds?: string[];
  amount?: number;
  amounts?: number[];
  manaType?: ColorSymbol;
  manaTypes?: ColorSymbol[];
  pile?: 1 | 2 | string;
  confirmed?: boolean;
  isPrimary?: boolean;
  requiresTarget?: boolean;
  required?: boolean;
  optional?: boolean;
  responseKind?: string;
  messageId?: number;
  minChoices?: number;
  maxChoices?: number;
  zoneContext?: ZoneName | "prompt" | "stack" | "search";
  shortLabel?: string;
  commandTemplate?: GameCommandTemplate;
}

export type PromptChoiceKind =
  | "card"
  | "target"
  | "player"
  | "mode"
  | "ability"
  | "amount"
  | "mana"
  | "pile"
  | "order"
  | "confirmation"
  | "option";

export interface PromptChoiceOption {
  id: string;
  label: string;
  kind?: PromptChoiceKind;
  cardInstanceId?: string;
  playerId?: PlayerId;
  sourceInstanceId?: string;
  abilityId?: string;
  targetId?: string;
  zone?: ZoneName | "prompt" | "stack" | "search";
  amount?: number;
  manaType?: ColorSymbol;
  value?: string | number | boolean;
  selected?: boolean;
  disabled?: boolean;
  responseCommand?: GameCommandTemplate;
}

export interface ChoicePrompt {
  id: string;
  playerId: PlayerId;
  message: string;
  minChoices: number;
  maxChoices: number;
  choices: PromptChoiceOption[];
}

export interface PromptEnvelope {
  id: string;
  method: string;
  messageId: number;
  playerId: PlayerId;
  responseKind: string;
  message: string;
  required?: boolean;
  minChoices?: number;
  maxChoices?: number;
  targetIds?: string[];
  choices?: PromptChoiceOption[];
}

export interface PromptPlayerOption {
  id: PlayerId;
  label: string;
  playerId: PlayerId;
  life?: number;
  selectable?: boolean;
  responseCommand?: GameCommandTemplate;
}

export interface PromptTargetOption extends PromptChoiceOption {
  kind?: "target";
}

export interface PromptAbilityOption extends PromptChoiceOption {
  kind?: "ability";
  rulesText?: string;
}

export interface PromptModeOption extends PromptChoiceOption {
  kind?: "mode";
}

export interface PromptManaChoice {
  id: string;
  label: string;
  manaType?: ColorSymbol;
  amount?: number;
  manaPool?: Partial<ManaPool>;
  responseCommand?: GameCommandTemplate;
}

export interface PromptPile {
  id: 1 | 2 | string;
  label: string;
  cards: ZoneCard[];
  responseCommand?: GameCommandTemplate;
}

export interface PromptOrderedItem extends PromptChoiceOption {
  kind?: "order";
  defaultIndex?: number;
}

export interface PromptConfirmation {
  yesLabel?: string;
  noLabel?: string;
  defaultValue?: boolean;
  yesCommand?: GameCommandTemplate;
  noCommand?: GameCommandTemplate;
}

export interface PromptEnvelopeV2 extends PromptEnvelope {
  responseCommand?: GameCommandTemplate;
  cards?: ZoneCard[];
  targets?: PromptTargetOption[];
  players?: PromptPlayerOption[];
  piles?: PromptPile[];
  abilities?: PromptAbilityOption[];
  modes?: PromptModeOption[];
  amounts?: number[];
  manaChoices?: PromptManaChoice[];
  orderedItems?: PromptOrderedItem[];
  confirmation?: PromptConfirmation;
  options?: Record<string, string | number | boolean>;
}

export interface XmageMobileSnapshot {
  schemaVersion: 1;
  gameId: GameId;
  bridgeRevision: number;
  xmageCycle?: number;
  callbackCoverage: string[];
  stack: XmageStackObject[];
  combat: XmageCombatGroup[];
  players: XmageMobilePlayer[];
  exileZones: XmageNamedZone[];
  revealed: XmageNamedZone[];
  lookedAt: XmageNamedZone[];
  companion: XmageNamedZone[];
  playableObjects: XmagePlayableObject[];
  panels: {
    stack: boolean;
    command: boolean;
    graveyard: boolean;
    exile: boolean;
    revealed: boolean;
    lookedAt: boolean;
    search: boolean;
  };
}

export interface XmageMobilePlayer {
  playerId: PlayerId;
  xmagePlayerId?: string;
  name: string;
  active: boolean;
  hasPriority: boolean;
  timerActive: boolean;
  skipState: {
    passedTurn: boolean;
    passedUntilEndOfTurn: boolean;
    passedUntilNextMain: boolean;
    passedUntilStackResolved: boolean;
    passedAllTurns: boolean;
    passedUntilEndStepBeforeMyTurn: boolean;
  };
  manaPool: ManaPool;
  command: ZoneCard[];
  zones: {
    battlefield: ZoneCard[];
    graveyard: ZoneCard[];
    exile: ZoneCard[];
    sideboard: ZoneCard[];
  };
}

export interface XmageStackObject {
  id: string;
  name: string;
  rulesText?: string;
  sourceCard?: ZoneCard;
  paid?: boolean;
}

export interface XmageCombatGroup {
  defenderId: string;
  defenderName: string;
  blocked: boolean;
  attackers: ZoneCard[];
  blockers: ZoneCard[];
}

export interface XmageNamedZone {
  id: string;
  name: string;
  cards: ZoneCard[];
}

export interface XmagePlayableObject {
  sourceInstanceId: string;
  sourceZone?: ZoneName | "command" | "stack";
  cardName: string;
  categories: Array<"mana" | "play" | "cast" | "ability">;
  abilities: Array<{ id: string; label: string; category: "mana" | "play" | "cast" | "ability" }>;
}

export interface GameCommandTemplate {
  type?: GameCommand["type"];
  gameId?: GameId;
  playerId?: PlayerId;
  promptId?: string;
  messageId?: number;
  cardInstanceId?: string;
  cardInstanceIds?: string[];
  sourceInstanceId?: string;
  sourceInstanceIds?: string[];
  sourceZone?: ZoneName;
  fromZone?: ZoneName;
  abilityId?: string;
  targetIds?: string[];
  playerIds?: PlayerId[];
  modeIds?: string[];
  choiceIds?: string[];
  paymentId?: string;
  manaType?: ColorSymbol;
  manaTypes?: ColorSymbol[];
  amount?: number;
  amounts?: number[];
  pile?: 1 | 2 | string;
  orderedIds?: string[];
  confirmed?: boolean;
  useCommandZone?: boolean;
  attackers?: Array<{ attackerId: string; defenderId: string }>;
  blockers?: Array<{ blockerId: string; attackerId: string }>;
  cardName?: string;
}

export type GameCommand =
  | { type: "keep_hand"; gameId: GameId; playerId: PlayerId }
  | { type: "mulligan"; gameId: GameId; playerId: PlayerId }
  | { type: "play_land"; gameId: GameId; playerId: PlayerId; cardInstanceId?: string; sourceInstanceId?: string; abilityId?: string; cardName?: string }
  | { type: "cast_spell"; gameId: GameId; playerId: PlayerId; cardInstanceId?: string; sourceInstanceId?: string; abilityId?: string; cardName?: string; fromZone?: ZoneName }
  | { type: "activate_ability"; gameId: GameId; playerId: PlayerId; sourceInstanceId: string; abilityId: string }
  | { type: "choose_target"; gameId: GameId; playerId: PlayerId; promptId: string; targetIds: string[] }
  | { type: "make_mana"; gameId: GameId; playerId: PlayerId; sourceInstanceId: string; abilityId?: string }
  | { type: "play_mana"; gameId: GameId; playerId: PlayerId; promptId: string; manaType: "W" | "U" | "B" | "R" | "G" | "C" }
  | { type: "pay_cost"; gameId: GameId; playerId: PlayerId; paymentId?: string; sourceInstanceIds?: string[] }
  | { type: "choose_mode"; gameId: GameId; playerId: PlayerId; promptId: string; modeIds: string[] }
  | { type: "choose_ability"; gameId: GameId; playerId: PlayerId; promptId: string; abilityId: string }
  | { type: "choose_card"; gameId: GameId; playerId: PlayerId; promptId: string; cardInstanceIds: string[] }
  | { type: "choose_player"; gameId: GameId; playerId: PlayerId; promptId: string; playerIds: PlayerId[] }
  | { type: "choose_pile"; gameId: GameId; playerId: PlayerId; promptId: string; pile: 1 | 2 }
  | { type: "choose_amount"; gameId: GameId; playerId: PlayerId; promptId: string; amount: number }
  | { type: "choose_multi_amount"; gameId: GameId; playerId: PlayerId; promptId: string; amounts: number[] }
  | { type: "choose_mana"; gameId: GameId; playerId: PlayerId; promptId: string; manaTypes: ColorSymbol[] }
  | { type: "answer_yes_no"; gameId: GameId; playerId: PlayerId; promptId: string; confirmed: boolean }
  | { type: "play_x_mana"; gameId: GameId; playerId: PlayerId; promptId: string; amount: number }
  | { type: "order_triggers"; gameId: GameId; playerId: PlayerId; promptId: string; orderedIds: string[] }
  | { type: "order_items"; gameId: GameId; playerId: PlayerId; promptId: string; orderedIds: string[] }
  | { type: "search_select"; gameId: GameId; playerId: PlayerId; promptId: string; cardInstanceIds: string[] }
  | { type: "commander_replacement"; gameId: GameId; playerId: PlayerId; promptId: string; useCommandZone: boolean }
  | { type: "declare_attackers"; gameId: GameId; playerId: PlayerId; attackers: Array<{ attackerId: string; defenderId: string }> }
  | { type: "declare_blockers"; gameId: GameId; playerId: PlayerId; blockers: Array<{ blockerId: string; attackerId: string }> }
  | { type: "resolve_choice"; gameId: GameId; playerId: PlayerId; promptId: string; choiceIds: string[] }
  | { type: "tap_permanent"; gameId: GameId; playerId: PlayerId; cardInstanceId: string }
  | { type: "untap_permanent"; gameId: GameId; playerId: PlayerId; cardInstanceId: string }
  | { type: "pass_priority"; gameId: GameId; playerId: PlayerId }
  | { type: "pass_until_response"; gameId: GameId; playerId: PlayerId }
  | { type: "pass_until_next_turn"; gameId: GameId; playerId: PlayerId }
  | { type: "advance_phase"; gameId: GameId; playerId: PlayerId }
  | { type: "concede"; gameId: GameId; playerId: PlayerId };

export interface EngineHealth {
  status: "ready" | "starting" | "unavailable" | "stalled";
  reason: string;
  checkedAt: string;
  recoveryAction?: "wait" | "restart_gateway" | "recreate_game" | "switch_to_mock";
}

export interface CardCacheMetadata {
  provider: "scryfall";
  status: "empty" | "syncing" | "ready" | "stale" | "error";
  bulkVersion?: string;
  cardCount: number;
  imageCount: number;
  missingImageCount: number;
  symbolCount?: number;
  updatedAt?: string;
}

export type HybridActionType =
  | "play_land"
  | "cast_spell"
  | "move_card"
  | "tap_permanent"
  | "untap_permanent"
  | "attack_player"
  | "add_counter"
  | "create_token"
  | "change_life"
  | "update_commander_damage"
  | "pass_priority";

export interface HybridAction {
  type: HybridActionType;
  playerId: PlayerId;
  cardName?: string;
  targetPlayerId?: PlayerId;
  amount?: number;
  fromZone?: ZoneName;
  toZone?: ZoneName;
}
