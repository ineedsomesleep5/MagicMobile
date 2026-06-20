import type {
  BracketScore,
  CardIdentity,
  DeckEntry,
  DeckList,
  DeckStats,
  GameId,
  GameSnapshot,
  HybridAction,
  PlayerId,
  RoomId,
  RoomState,
  RuleZeroSummary
} from "./types";

export interface EngineAdapter {
  createGame(input: { roomId: RoomId; playerIds: PlayerId[] }): Promise<GameSnapshot>;
  joinGame(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot>;
  loadDeck(input: { gameId: GameId; playerId: PlayerId; deck: DeckList }): Promise<GameSnapshot>;
  shuffle(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot>;
  drawOpeningHands(input: { gameId: GameId; count: number }): Promise<GameSnapshot>;
  applyHybridAction(input: { gameId: GameId; action: HybridAction }): Promise<GameSnapshot>;
  passPriority(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot>;
  advancePhase(input: { gameId: GameId }): Promise<GameSnapshot>;
  getSnapshot(gameId: GameId): Promise<GameSnapshot>;
}

export interface VideoSession {
  roomId: RoomId;
  provider: "mock" | "livekit";
  joinUrl?: string;
  token?: string;
}

export interface VideoProvider {
  createSession(input: { roomId: RoomId }): Promise<VideoSession>;
  getJoinToken(input: { roomId: RoomId; playerId: PlayerId }): Promise<VideoSession>;
}

export interface Recommendation {
  cardName: string;
  reason: string;
  confidence: number;
  source: "mock" | "local-synergy" | "edhrec-link";
}

export interface RecommendationProvider {
  recommend(input: { deck: DeckList; cardPool?: CardIdentity[] }): Promise<Recommendation[]>;
}

export interface DeckParser {
  parse(input: string): DeckList;
}

export interface DeckAnalyzer {
  validateCommander(input: { deck: DeckList; cards: CardIdentity[] }): Promise<string[]>;
  getStats(input: { deck: DeckList; cards: CardIdentity[] }): DeckStats;
  getBracketScore(input: { deck: DeckList; cards: CardIdentity[] }): BracketScore;
  getRuleZeroSummary(input: { deck: DeckList; cards: CardIdentity[] }): RuleZeroSummary;
}

export interface CardDataProvider {
  searchCards(query: string): Promise<CardIdentity[]>;
  getCardByName(name: string): Promise<CardIdentity | undefined>;
  getSeedCards(): Promise<CardIdentity[]>;
}

export interface RoomService {
  createRoom(input: { name: string; hostPlayerId: PlayerId }): Promise<RoomState>;
  joinRoom(input: { roomId: RoomId; playerId: PlayerId; displayName: string }): Promise<RoomState>;
  setReady(input: { roomId: RoomId; playerId: PlayerId; ready: boolean }): Promise<RoomState>;
  startRoom(input: { roomId: RoomId }): Promise<RoomState>;
  getRoom(roomId: RoomId): Promise<RoomState | undefined>;
}

export interface RecognitionService {
  clickToIdentifyCard(input: { imageId: string; x: number; y: number }): Promise<string[]>;
  suggestCardMatch(input: { text: string }): Promise<string[]>;
  confirmCardMatch(input: { cardName: string }): Promise<{ confirmed: true }>;
  suggestZoneChange(input: { cardName: string }): Promise<string[]>;
}
