export type PlayerId = string;
export type RoomId = string;
export type GameId = string;
export type DeckId = string;
export type CardId = string;

export type ColorSymbol = "W" | "U" | "B" | "R" | "G" | "C";

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
