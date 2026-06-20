import type { EngineAdapter, GameId, GameSnapshot, PlayerId, RoomId, DeckList, HybridAction } from "@magicmobile/shared";

export interface XmageEngineAdapterOptions {
  endpoint: string;
}

export class XmageEngineAdapter implements EngineAdapter {
  constructor(private readonly options: XmageEngineAdapterOptions) {}

  async createGame(_input: { roomId: RoomId; playerIds: PlayerId[] }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async joinGame(_input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async loadDeck(_input: { gameId: GameId; playerId: PlayerId; deck: DeckList }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async shuffle(_input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async drawOpeningHands(_input: { gameId: GameId; count: number }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async applyHybridAction(_input: { gameId: GameId; action: HybridAction }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async passPriority(_input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async advancePhase(_input: { gameId: GameId }): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  async getSnapshot(_gameId: GameId): Promise<GameSnapshot> {
    return this.notImplemented();
  }

  private notImplemented(): never {
    throw new Error(`XMage adapter is a stub for ${this.options.endpoint}`);
  }
}
