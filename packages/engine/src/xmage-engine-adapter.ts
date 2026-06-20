import type {
  CommanderGameConfig,
  DeckList,
  EngineAdapter,
  EngineHealth,
  GameCommand,
  GameId,
  GameSnapshot,
  HybridAction,
  LegalAction,
  PlayerId,
  RoomId
} from "@magicmobile/shared";

export interface XmageEngineAdapterOptions {
  endpoint: string;
  fetchImpl?: typeof fetch;
}

export class XmageEngineAdapter implements EngineAdapter {
  private readonly endpoint: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: XmageEngineAdapterOptions) {
    this.endpoint = options.endpoint.replace(/\/$/, "");
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async createCommanderGame(input: CommanderGameConfig): Promise<GameSnapshot> {
    return this.request<GameSnapshot>("/games/commander", {
      method: "POST",
      body: input
    });
  }

  async createGame(input: { roomId: RoomId; playerIds: PlayerId[] }): Promise<GameSnapshot> {
    return this.request<GameSnapshot>("/games", {
      method: "POST",
      body: input
    });
  }

  async joinGame(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    return this.submitGameCommand({ type: "pass_priority", gameId: input.gameId, playerId: input.playerId });
  }

  async loadDeck(input: { gameId: GameId; playerId: PlayerId; deck: DeckList }): Promise<GameSnapshot> {
    return this.request<GameSnapshot>(`/games/${encodeURIComponent(input.gameId)}/decks`, {
      method: "POST",
      body: input
    });
  }

  async shuffle(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    return this.request<GameSnapshot>(`/games/${encodeURIComponent(input.gameId)}/shuffle`, {
      method: "POST",
      body: input
    });
  }

  async drawOpeningHands(input: { gameId: GameId; count: number }): Promise<GameSnapshot> {
    return this.request<GameSnapshot>(`/games/${encodeURIComponent(input.gameId)}/opening-hands`, {
      method: "POST",
      body: input
    });
  }

  async applyHybridAction(input: { gameId: GameId; action: HybridAction }): Promise<GameSnapshot> {
    return this.submitGameCommand(hybridActionToCommand(input.gameId, input.action));
  }

  async passPriority(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    return this.submitGameCommand({ type: "pass_priority", gameId: input.gameId, playerId: input.playerId });
  }

  async advancePhase(input: { gameId: GameId }): Promise<GameSnapshot> {
    const snapshot = await this.getSnapshot(input.gameId);
    const playerId = snapshot.priorityPlayerId ?? snapshot.activePlayerId ?? snapshot.players[0]?.playerId ?? "player";
    return this.submitGameCommand({ type: "advance_phase", gameId: input.gameId, playerId });
  }

  async submitGameCommand(input: GameCommand): Promise<GameSnapshot> {
    return this.request<GameSnapshot>(`/games/${encodeURIComponent(input.gameId)}/commands`, {
      method: "POST",
      body: input
    });
  }

  async getLegalActions(input: { gameId: GameId; playerId: PlayerId }): Promise<LegalAction[]> {
    return this.request<LegalAction[]>(
      `/games/${encodeURIComponent(input.gameId)}/legal-actions?playerId=${encodeURIComponent(input.playerId)}`
    );
  }

  async getHealth(): Promise<EngineHealth> {
    try {
      return await this.request<EngineHealth>("/health");
    } catch (error) {
      return {
        status: "unavailable",
        reason: error instanceof Error ? error.message : `XMage gateway unavailable at ${this.endpoint}`,
        checkedAt: new Date().toISOString(),
        recoveryAction: "restart_gateway"
      };
    }
  }

  async getSnapshot(gameId: GameId): Promise<GameSnapshot> {
    return this.request<GameSnapshot>(`/games/${encodeURIComponent(gameId)}`);
  }

  private async request<T>(path: string, options: { method?: string; body?: unknown } = {}): Promise<T> {
    let response: Response;
    const requestInit: RequestInit = {
      method: options.method ?? "GET",
      headers: { Accept: "application/json", "Content-Type": "application/json" }
    };
    if (options.body !== undefined) {
      requestInit.body = JSON.stringify(options.body);
    }

    try {
      response = await this.fetchImpl(`${this.endpoint}${path}`, requestInit);
    } catch (error) {
      throw new Error(
        `XMage gateway unavailable at ${this.endpoint}: ${error instanceof Error ? error.message : "request failed"}`
      );
    }

    if (!response.ok) {
      throw new Error(`XMage gateway request failed (${response.status}) for ${path}: ${await response.text()}`);
    }

    return (await response.json()) as T;
  }
}

function hybridActionToCommand(gameId: GameId, action: HybridAction): GameCommand {
  if (action.type === "play_land") {
    return {
      type: "play_land",
      gameId,
      playerId: action.playerId,
      ...(action.cardName ? { cardName: action.cardName } : {})
    };
  }

  if (action.type === "cast_spell") {
    const command: GameCommand = {
      type: "cast_spell",
      gameId,
      playerId: action.playerId
    };
    if (action.cardName) command.cardName = action.cardName;
    if (action.fromZone) command.fromZone = action.fromZone;
    return command;
  }

  if (action.type === "attack_player") {
    return { type: "declare_attackers", gameId, playerId: action.playerId, attackers: [] };
  }

  if (action.type === "tap_permanent" && action.cardName) {
    return { type: "tap_permanent", gameId, playerId: action.playerId, cardInstanceId: action.cardName };
  }

  if (action.type === "untap_permanent" && action.cardName) {
    return { type: "untap_permanent", gameId, playerId: action.playerId, cardInstanceId: action.cardName };
  }

  if (action.type === "pass_priority") {
    return { type: "pass_priority", gameId, playerId: action.playerId };
  }

  return { type: "pass_priority", gameId, playerId: action.playerId };
}
