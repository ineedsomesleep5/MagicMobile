import type {
  CardIdentity,
  CommanderGameConfig,
  DeckList,
  EngineAdapter,
  EngineHealth,
  GameCommand,
  GameId,
  GameLogEntry,
  GameSnapshot,
  HybridAction,
  LegalAction,
  PlayerGameState,
  PlayerId,
  RoomId,
  ZoneCard,
  ZoneName
} from "@magicmobile/shared";

type MockEngineEvent =
  | { type: "game_created"; gameId: GameId; roomId: RoomId; playerIds: PlayerId[] }
  | { type: "player_joined"; playerId: PlayerId }
  | { type: "deck_loaded"; playerId: PlayerId; deck: DeckList }
  | { type: "library_shuffled"; playerId: PlayerId; seed: number }
  | { type: "opening_hands_drawn"; count: number }
  | { type: "hybrid_action"; action: HybridAction }
  | { type: "priority_passed"; playerId: PlayerId }
  | { type: "phase_advanced" }
  | { type: "turn_advanced" };

type GamePhase = GameSnapshot["phase"];

const phases: GamePhase[] = ["beginning", "precombat-main", "combat", "postcombat-main", "ending"];
const zoneNames: ZoneName[] = ["library", "hand", "battlefield", "graveyard", "exile", "command", "stack"];

export interface MockEngineAdapterOptions {
  shuffleSeed?: number;
}

export class MockEngineAdapter implements EngineAdapter {
  private nextGameNumber = 1;
  private readonly games = new Map<GameId, MockEngineEvent[]>();
  private readonly shuffleSeed: number;

  constructor(options: MockEngineAdapterOptions = {}) {
    this.shuffleSeed = options.shuffleSeed ?? 1;
  }

  async createCommanderGame(input: CommanderGameConfig): Promise<GameSnapshot> {
    const playerIds = [input.humanPlayerId, ...input.aiPlayers.map((player) => player.playerId)];
    const created = await this.createGame({ roomId: input.roomId, playerIds });
    await this.loadDeck({ gameId: created.id, playerId: input.humanPlayerId, deck: input.humanDeck });

    for (const aiPlayer of input.aiPlayers) {
      await this.loadDeck({ gameId: created.id, playerId: aiPlayer.playerId, deck: aiPlayer.deck ?? input.humanDeck });
    }

    for (const playerId of playerIds) {
      await this.shuffle({ gameId: created.id, playerId });
    }

    return this.drawOpeningHands({ gameId: created.id, count: 7 });
  }

  async createGame(input: { roomId: RoomId; playerIds: PlayerId[] }): Promise<GameSnapshot> {
    const gameId = `mock-game-${this.nextGameNumber++}`;
    this.games.set(gameId, [{ type: "game_created", gameId, roomId: input.roomId, playerIds: input.playerIds }]);
    return this.getSnapshot(gameId);
  }

  async joinGame(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "player_joined", playerId: input.playerId });
    return this.getSnapshot(input.gameId);
  }

  async loadDeck(input: { gameId: GameId; playerId: PlayerId; deck: DeckList }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "deck_loaded", playerId: input.playerId, deck: input.deck });
    return this.getSnapshot(input.gameId);
  }

  async shuffle(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "library_shuffled", playerId: input.playerId, seed: this.shuffleSeed });
    return this.getSnapshot(input.gameId);
  }

  async drawOpeningHands(input: { gameId: GameId; count: number }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "opening_hands_drawn", count: input.count });
    return this.getSnapshot(input.gameId);
  }

  async applyHybridAction(input: { gameId: GameId; action: HybridAction }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "hybrid_action", action: input.action });
    return this.getSnapshot(input.gameId);
  }

  async passPriority(input: { gameId: GameId; playerId: PlayerId }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "priority_passed", playerId: input.playerId });
    return this.getSnapshot(input.gameId);
  }

  async advancePhase(input: { gameId: GameId }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "phase_advanced" });
    return this.getSnapshot(input.gameId);
  }

  async advanceTurn(input: { gameId: GameId }): Promise<GameSnapshot> {
    this.append(input.gameId, { type: "turn_advanced" });
    return this.getSnapshot(input.gameId);
  }

  async submitGameCommand(input: GameCommand): Promise<GameSnapshot> {
    switch (input.type) {
      case "keep_hand":
        return this.applyHybridAction({ gameId: input.gameId, action: { type: "pass_priority", playerId: input.playerId } });
      case "mulligan":
        return this.drawOpeningHands({ gameId: input.gameId, count: 7 });
      case "cast_spell": {
        const action: HybridAction = { type: "cast_spell", playerId: input.playerId };
        if (input.cardName !== undefined) action.cardName = input.cardName;
        if (input.fromZone !== undefined) action.fromZone = input.fromZone;
        return this.applyHybridAction({ gameId: input.gameId, action });
      }
      case "declare_attackers":
        return this.applyHybridAction({ gameId: input.gameId, action: { type: "attack_player", playerId: input.playerId } });
      case "pass_priority":
        return this.passPriority({ gameId: input.gameId, playerId: input.playerId });
      case "advance_phase":
        return this.advancePhase({ gameId: input.gameId });
      case "concede":
        return this.applyHybridAction({ gameId: input.gameId, action: { type: "change_life", playerId: input.playerId, amount: -99 } });
      case "activate_ability":
      case "choose_target":
      case "declare_blockers":
        return this.applyHybridAction({ gameId: input.gameId, action: { type: "pass_priority", playerId: input.playerId } });
    }
  }

  async getLegalActions(input: { gameId: GameId; playerId: PlayerId }): Promise<LegalAction[]> {
    return getLegalActions(this.reduce(input.gameId), input.playerId);
  }

  async getHealth(): Promise<EngineHealth> {
    return {
      status: "ready",
      reason: "Mock engine is available for local Commander flow testing.",
      checkedAt: new Date(0).toISOString(),
      recoveryAction: "switch_to_mock"
    };
  }

  async getSnapshot(gameId: GameId): Promise<GameSnapshot> {
    return cloneSnapshot(enrichSnapshot(this.reduce(gameId)));
  }

  private append(gameId: GameId, event: MockEngineEvent): void {
    const events = this.games.get(gameId);
    if (!events) {
      throw new Error(`Game not found: ${gameId}`);
    }
    events.push(event);
  }

  private reduce(gameId: GameId): GameSnapshot {
    const events = this.games.get(gameId);
    if (!events) {
      throw new Error(`Game not found: ${gameId}`);
    }

    let snapshot: GameSnapshot | undefined;
    const log: GameLogEntry[] = [];

    for (const [eventIndex, event] of events.entries()) {
      if (event.type === "game_created") {
        const firstPlayerId = event.playerIds[0];
        snapshot = {
          id: event.gameId,
          roomId: event.roomId,
          phase: "beginning",
          turn: 1,
          players: event.playerIds.map((playerId) => createPlayer(playerId, event.playerIds)),
          log
        };
        if (firstPlayerId) {
          snapshot.activePlayerId = firstPlayerId;
          snapshot.priorityPlayerId = firstPlayerId;
        }
        pushLog(log, eventIndex, `Game ${event.gameId} created`);
        continue;
      }

      if (!snapshot) {
        throw new Error(`Game has no creation event: ${gameId}`);
      }

      applyEvent(snapshot, event);
      pushLog(log, eventIndex, describeEvent(event, snapshot));
    }

    if (!snapshot) {
      throw new Error(`Game has no events: ${gameId}`);
    }

    return snapshot;
  }
}

function enrichSnapshot(snapshot: GameSnapshot): GameSnapshot {
  const legalActions = snapshot.priorityPlayerId ? getLegalActions(snapshot, snapshot.priorityPlayerId) : [];
  return {
    ...snapshot,
    legalActions,
    engineHealth: {
      status: "ready",
      reason: "Mock engine snapshot is current.",
      checkedAt: new Date(0).toISOString(),
      recoveryAction: "switch_to_mock"
    }
  };
}

function getLegalActions(snapshot: GameSnapshot, playerId: PlayerId): LegalAction[] {
  const player = findPlayer(snapshot, playerId);
  const handCard = player.zones.hand[0];
  const actions: LegalAction[] = [
    {
      id: `${playerId}-pass-priority`,
      type: "pass_priority",
      playerId,
      label: "Pass Priority"
    },
    {
      id: `${playerId}-advance-phase`,
      type: "advance_phase",
      playerId,
      label: "Next Phase"
    },
    {
      id: `${playerId}-concede`,
      type: "concede",
      playerId,
      label: "Concede"
    }
  ];

  if (handCard) {
    actions.unshift({
      id: `${handCard.instanceId}-cast`,
      type: "cast_spell",
      playerId,
      label: `Cast ${handCard.card.name}`,
      cardInstanceId: handCard.instanceId
    });
  }

  if (snapshot.phase === "beginning" && player.zones.hand.length > 0) {
    actions.unshift(
      {
        id: `${playerId}-keep`,
        type: "keep_hand",
        playerId,
        label: "Keep Hand"
      },
      {
        id: `${playerId}-mulligan`,
        type: "mulligan",
        playerId,
        label: "Mulligan"
      }
    );
  }

  return actions;
}

function applyEvent(snapshot: GameSnapshot, event: Exclude<MockEngineEvent, { type: "game_created" }>): void {
  switch (event.type) {
    case "player_joined":
      if (snapshot.players.some((player) => player.playerId === event.playerId)) {
        return;
      }
      for (const player of snapshot.players) {
        player.commanderDamage[event.playerId] = 0;
      }
      snapshot.players.push(createPlayer(event.playerId, snapshot.players.map((player) => player.playerId).concat(event.playerId)));
      break;
    case "deck_loaded":
      loadDeck(findPlayer(snapshot, event.playerId), event.deck);
      break;
    case "library_shuffled":
      shuffleZone(findPlayer(snapshot, event.playerId).zones.library, event.seed);
      break;
    case "opening_hands_drawn":
      for (const player of snapshot.players) {
        moveTopCards(player, "library", "hand", event.count);
      }
      break;
    case "hybrid_action":
      applyHybridAction(snapshot, event.action);
      break;
    case "priority_passed":
      snapshot.priorityPlayerId = nextPlayerId(snapshot, event.playerId);
      break;
    case "phase_advanced":
      snapshot.phase = phases[(phases.indexOf(snapshot.phase) + 1) % phases.length] ?? "beginning";
      break;
    case "turn_advanced":
      snapshot.turn += 1;
      snapshot.phase = "beginning";
      snapshot.activePlayerId = nextPlayerId(snapshot, snapshot.activePlayerId ?? snapshot.players[0]!.playerId);
      snapshot.priorityPlayerId = snapshot.activePlayerId;
      break;
  }
}

function applyHybridAction(snapshot: GameSnapshot, action: HybridAction): void {
  const player = findPlayer(snapshot, action.playerId);
  const cardName = action.cardName;

  switch (action.type) {
    case "play_land":
    case "move_card":
      if (cardName && action.fromZone && action.toZone) {
        moveNamedCard(player, cardName, action.fromZone, action.toZone);
      }
      break;
    case "cast_spell":
      if (cardName) {
        moveNamedCard(player, cardName, action.fromZone ?? "hand", "stack");
        if (action.fromZone === "command") {
          player.commanderTax += 2;
        }
      }
      break;
    case "tap_permanent":
      if (cardName) {
        findCard(player, "battlefield", cardName).tapped = true;
      }
      break;
    case "untap_permanent":
      if (cardName) {
        findCard(player, "battlefield", cardName).tapped = false;
      }
      break;
    case "add_counter":
      if (cardName) {
        const card = findCard(player, "battlefield", cardName);
        card.counters = { ...card.counters, generic: (card.counters?.generic ?? 0) + (action.amount ?? 1) };
      } else {
        findPlayer(snapshot, action.targetPlayerId ?? action.playerId).poison += action.amount ?? 1;
      }
      break;
    case "create_token":
      for (let index = 0; index < (action.amount ?? 1); index += 1) {
        player.zones.battlefield.push(createZoneCard(cardName ?? "Token", "token", index + player.zones.battlefield.length));
      }
      break;
    case "change_life":
      player.life += action.amount ?? 0;
      break;
    case "update_commander_damage":
      if (action.targetPlayerId) {
        const target = findPlayer(snapshot, action.targetPlayerId);
        target.commanderDamage[action.playerId] = (target.commanderDamage[action.playerId] ?? 0) + (action.amount ?? 0);
      }
      break;
    case "attack_player":
    case "pass_priority":
      snapshot.priorityPlayerId = nextPlayerId(snapshot, action.playerId);
      break;
  }
}

function createPlayer(playerId: PlayerId, playerIds: PlayerId[]): PlayerGameState {
  return {
    playerId,
    life: 40,
    poison: 0,
    commanderTax: 0,
    zones: createZones(),
    commanderDamage: Object.fromEntries(playerIds.map((id) => [id, 0]))
  };
}

function createZones(): Record<ZoneName, ZoneCard[]> {
  return {
    library: [],
    hand: [],
    battlefield: [],
    graveyard: [],
    exile: [],
    command: [],
    stack: []
  };
}

function loadDeck(player: PlayerGameState, deck: DeckList): void {
  player.zones = createZones();
  if (deck.commander) {
    player.zones.command.push(createZoneCard(deck.commander.cardName, "commander", 0));
  }

  let instanceIndex = 0;
  for (const entry of deck.entries) {
    if (entry.section !== "deck") {
      continue;
    }
    for (let copy = 0; copy < entry.quantity; copy += 1) {
      player.zones.library.push(createZoneCard(entry.cardName, "deck", instanceIndex++));
    }
  }
}

function createZoneCard(name: string, source: string, index: number): ZoneCard {
  return {
    instanceId: `${slug(name)}-${source}-${index}`,
    card: createCardIdentity(name)
  };
}

function createCardIdentity(name: string): CardIdentity {
  return {
    id: slug(name),
    name,
    manaValue: 0,
    colorIdentity: [],
    typeLine: "Mock Card"
  };
}

function moveTopCards(player: PlayerGameState, fromZone: ZoneName, toZone: ZoneName, count: number): void {
  const moving = player.zones[fromZone].splice(0, count);
  player.zones[toZone].push(...moving);
}

function moveNamedCard(player: PlayerGameState, cardName: string, fromZone: ZoneName, toZone: ZoneName): void {
  const source = player.zones[fromZone];
  const index = source.findIndex((card) => card.card.name === cardName);
  if (index === -1) {
    return;
  }
  const [card] = source.splice(index, 1);
  if (card) {
    player.zones[toZone].push(card);
  }
}

function findCard(player: PlayerGameState, zone: ZoneName, cardName: string): ZoneCard {
  const card = player.zones[zone].find((candidate) => candidate.card.name === cardName);
  if (!card) {
    throw new Error(`Card not found in ${zone}: ${cardName}`);
  }
  return card;
}

function findPlayer(snapshot: GameSnapshot, playerId: PlayerId): PlayerGameState {
  const player = snapshot.players.find((candidate) => candidate.playerId === playerId);
  if (!player) {
    throw new Error(`Player not found: ${playerId}`);
  }
  return player;
}

function nextPlayerId(snapshot: GameSnapshot, playerId: PlayerId): PlayerId {
  const index = snapshot.players.findIndex((player) => player.playerId === playerId);
  return snapshot.players[(index + 1) % snapshot.players.length]?.playerId ?? playerId;
}

function shuffleZone(zone: ZoneCard[], seed: number): void {
  zone.sort((left, right) => seededRank(left.instanceId, seed) - seededRank(right.instanceId, seed));
}

function seededRank(value: string, seed: number): number {
  let hash = seed;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) % 1_000_003;
  }
  return hash;
}

function describeEvent(event: Exclude<MockEngineEvent, { type: "game_created" }>, snapshot: GameSnapshot): string {
  switch (event.type) {
    case "player_joined":
      return `${event.playerId} joined the game`;
    case "deck_loaded":
      return `${event.playerId} loaded ${event.deck.name}`;
    case "library_shuffled":
      return `${event.playerId} shuffled library`;
    case "opening_hands_drawn":
      return `Opening hands drawn (${event.count})`;
    case "hybrid_action":
      return describeHybridAction(event.action);
    case "priority_passed":
      return `${event.playerId} passed priority`;
    case "phase_advanced":
      return `Advanced to ${snapshot.phase}`;
    case "turn_advanced":
      return `Advanced to turn ${snapshot.turn}`;
  }
}

function describeHybridAction(action: HybridAction): string {
  switch (action.type) {
    case "cast_spell":
      return `${action.playerId} casts ${action.cardName ?? "a spell"}`;
    case "change_life":
      return `${action.playerId} changes life by ${action.amount ?? 0}`;
    case "create_token":
      return `${action.playerId} creates ${action.amount ?? 1} ${action.cardName ?? "Token"}`;
    default:
      return `${action.playerId} ${action.type}`;
  }
}

function pushLog(log: GameLogEntry[], eventIndex: number, message: string): void {
  log.push({
    id: `event-${eventIndex}`,
    message,
    createdAt: new Date(eventIndex * 1000).toISOString()
  });
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

function cloneSnapshot(snapshot: GameSnapshot): GameSnapshot {
  return JSON.parse(JSON.stringify(snapshot)) as GameSnapshot;
}
