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
  simulatorPreset?: "arena-battlefield";
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

export interface PlayerGameState {
  playerId: PlayerId;
  life: number;
  poison: number;
  commanderTax: number;
  zones: Record<ZoneName, ZoneCard[]>;
  commanderDamage: Record<PlayerId, number>;
}

export interface GameSnapshot {
  id: GameId;
  roomId: RoomId;
  activePlayerId?: PlayerId;
  phase: "beginning" | "precombat-main" | "combat" | "postcombat-main" | "ending";
  turn: number;
  priorityPlayerId?: PlayerId;
  players: PlayerGameState[];
  log: GameLogEntry[];
  legalActions?: LegalAction[];
  choicePrompt?: ChoicePrompt;
  engineHealth?: EngineHealth;
}

export type LegalActionType =
  | "keep_hand"
  | "mulligan"
  | "cast_spell"
  | "activate_ability"
  | "choose_target"
  | "declare_attackers"
  | "declare_blockers"
  | "tap_permanent"
  | "untap_permanent"
  | "pass_priority"
  | "advance_phase"
  | "concede";

export interface LegalAction {
  id: string;
  type: LegalActionType;
  playerId: PlayerId;
  label: string;
  cardInstanceId?: string;
  targetIds?: string[];
}

export interface ChoicePrompt {
  id: string;
  playerId: PlayerId;
  message: string;
  minChoices: number;
  maxChoices: number;
  choices: Array<{
    id: string;
    label: string;
    cardInstanceId?: string;
  }>;
}

export type GameCommand =
  | { type: "keep_hand"; gameId: GameId; playerId: PlayerId }
  | { type: "mulligan"; gameId: GameId; playerId: PlayerId }
  | { type: "cast_spell"; gameId: GameId; playerId: PlayerId; cardInstanceId?: string; cardName?: string; fromZone?: ZoneName }
  | { type: "activate_ability"; gameId: GameId; playerId: PlayerId; sourceInstanceId: string; abilityId: string }
  | { type: "choose_target"; gameId: GameId; playerId: PlayerId; promptId: string; targetIds: string[] }
  | { type: "declare_attackers"; gameId: GameId; playerId: PlayerId; attackers: Array<{ attackerId: string; defenderId: string }> }
  | { type: "declare_blockers"; gameId: GameId; playerId: PlayerId; blockers: Array<{ blockerId: string; attackerId: string }> }
  | { type: "tap_permanent"; gameId: GameId; playerId: PlayerId; cardInstanceId: string }
  | { type: "untap_permanent"; gameId: GameId; playerId: PlayerId; cardInstanceId: string }
  | { type: "pass_priority"; gameId: GameId; playerId: PlayerId }
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
