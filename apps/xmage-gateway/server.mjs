import { createServer } from "node:http";
import { parse as parseUrl } from "node:url";
import { WebSocketServer } from "ws";

export const aiDifficultyProfiles = {
  easy: { playerType: "Computer - default", skill: 3 },
  normal: { playerType: "Computer - mad", skill: 5 },
  hard: { playerType: "Computer - mad", skill: 8 },
  expert: { playerType: "Computer - monte carlo", fallbackPlayerType: "Computer - mad", skill: 10 }
};

const games = new Map();
let nextGameNumber = 1;
let lastAiProgressAt = Date.now();
const aiStallMs = Number.parseInt(process.env.XMAGE_AI_STALL_MS ?? "45000", 10);
const port = Number.parseInt(process.env.PORT ?? "17171", 10);

export function createGatewayHandler(state = games, options = {}) {
  const bridgeClient = options.bridgeClient ?? createBridgeClientFromEnv();

  return async function handleRequest(request, response) {
    try {
      const url = parseUrl(request.url ?? "/", true);
      const method = request.method ?? "GET";

      if (method === "GET" && url.pathname === "/health") {
        return sendJson(response, await getGatewayHealth(bridgeClient));
      }

      if (method === "GET" && url.pathname === "/ai/difficulties") {
        return sendJson(response, aiDifficultyProfiles);
      }

      if (method === "POST" && url.pathname === "/games") {
        const body = await readJson(request);
        const snapshot = createGame(state, body.roomId, body.playerIds ?? []);
        return sendJson(response, snapshot, 201);
      }

      if (method === "POST" && url.pathname === "/games/commander") {
        const body = await readJson(request);
        if (bridgeClient && body.simulatorPreset !== "arena-battlefield") {
          const snapshot = await bridgeClient.createCommanderGame(body);
          lastAiProgressAt = Date.now();
          state.set(snapshot.id, snapshot);
          return sendJson(response, snapshot, 201);
        }
        const snapshot = createCommanderGame(state, body);
        return sendJson(response, snapshot, 201);
      }

      const updatesMatch = url.pathname?.match(/^\/api\/engine\/games\/([^/]+)\/updates$/);
      if (method === "POST" && updatesMatch) {
        const gameId = decodeURIComponent(updatesMatch[1]);
        const nextSnapshot = await readJson(request);
        state.set(gameId, nextSnapshot);
        broadcastSnapshot(gameId, nextSnapshot);
        return sendJson(response, { status: "ok" });
      }

      const gameMatch = url.pathname?.match(/^\/games\/([^/]+)(?:\/([^/]+))?$/);
      if (gameMatch) {
        const gameId = decodeURIComponent(gameMatch[1]);
        const action = gameMatch[2];
        const snapshot = getGame(state, gameId);

        if (method === "GET" && !action) {
          if (bridgeClient && isBridgeSnapshot(snapshot)) {
            const nextSnapshot = await bridgeClient.getSnapshot(gameId);
            lastAiProgressAt = Date.now();
            state.set(nextSnapshot.id, nextSnapshot);
            return sendJson(response, nextSnapshot);
          }
          return sendJson(response, snapshot);
        }

        if (method === "GET" && action === "legal-actions") {
          if (bridgeClient && isBridgeSnapshot(snapshot)) {
            return sendJson(response, await bridgeClient.getLegalActions(gameId, String(url.query.playerId ?? "")));
          }
          return sendJson(response, getLegalActions(snapshot, String(url.query.playerId ?? "")));
        }

        if (method === "POST" && action === "commands") {
          const command = await readJson(request);
          if (bridgeClient && isBridgeSnapshot(snapshot)) {
            const nextSnapshot = await bridgeClient.submitCommand(gameId, command);
            lastAiProgressAt = Date.now();
            state.set(nextSnapshot.id, nextSnapshot);
            return sendJson(response, nextSnapshot);
          }
          return sendJson(response, applyCommand(snapshot, command));
        }

        if (method === "POST" && action === "decks") {
          const body = await readJson(request);
          loadDeck(findPlayer(snapshot, body.playerId), body.deck);
          snapshot.log.push(logEntry(snapshot.log.length, `${body.playerId} loaded ${body.deck.name}`));
          return sendJson(response, snapshot);
        }

        if (method === "POST" && action === "shuffle") {
          const body = await readJson(request);
          findPlayer(snapshot, body.playerId).zones.library.reverse();
          snapshot.log.push(logEntry(snapshot.log.length, `${body.playerId} shuffled library`));
          return sendJson(response, snapshot);
        }

        if (method === "POST" && action === "opening-hands") {
          const body = await readJson(request);
          drawOpeningHands(snapshot, body.count ?? 7);
          return sendJson(response, snapshot);
        }
      }

      return sendJson(response, { error: "Not found" }, 404);
    } catch (error) {
      return sendJson(
        response,
        { error: error instanceof Error ? error.message : "Gateway request failed" },
        error instanceof NotFoundError ? 404 : 500
      );
    }
  };
}

export function createHttpBridgeClient(endpoint, fetchImpl = fetch) {
  const baseUrl = endpoint.replace(/\/$/, "");
  return {
    async health() {
      return requestBridge(fetchImpl, baseUrl, "/health");
    },
    async createCommanderGame(config) {
      return requestBridge(fetchImpl, baseUrl, "/games/commander", { method: "POST", body: config });
    },
    async getSnapshot(gameId) {
      return requestBridge(fetchImpl, baseUrl, `/games/${encodeURIComponent(gameId)}`);
    },
    async getLegalActions(gameId, playerId) {
      return requestBridge(
        fetchImpl,
        baseUrl,
        `/games/${encodeURIComponent(gameId)}/legal-actions?playerId=${encodeURIComponent(playerId)}`
      );
    },
    async submitCommand(gameId, command) {
      return requestBridge(fetchImpl, baseUrl, `/games/${encodeURIComponent(gameId)}/commands`, {
        method: "POST",
        body: command
      });
    }
  };
}

export async function getGatewayHealth(bridgeClient = createBridgeClientFromEnv(), now = Date.now()) {
  if (!bridgeClient) {
    return getHealth(now);
  }

  let bridgeHealth;
  try {
    bridgeHealth = await bridgeClient.health();
  } catch (error) {
    return {
      status: "unavailable",
      reason: `XMage Java bridge unavailable: ${error instanceof Error ? error.message : "request failed"}`,
      checkedAt: new Date(now).toISOString(),
      recoveryAction: "restart_gateway"
    };
  }

  if (bridgeHealth.status !== "ready") {
    return bridgeHealth;
  }

  return {
    status: "ready",
    reason: bridgeHealth.reason ?? "XMage Java bridge is connected and ready.",
    checkedAt: bridgeHealth.checkedAt ?? new Date(now).toISOString(),
    recoveryAction: "wait"
  };
}

export function createCommanderGame(state, config) {
  const playerIds = [config.humanPlayerId, ...(config.aiPlayers ?? []).map((player) => player.playerId)];
  const snapshot = createGame(state, config.roomId, playerIds);

  loadDeck(findPlayer(snapshot, config.humanPlayerId), config.humanDeck);
  for (const aiPlayer of config.aiPlayers ?? []) {
    loadDeck(findPlayer(snapshot, aiPlayer.playerId), aiPlayer.deck ?? config.humanDeck);
    const profile = aiDifficultyProfiles[aiPlayer.difficulty ?? "normal"];
    snapshot.log.push(
      logEntry(
        snapshot.log.length,
        `${aiPlayer.displayName} joined as ${profile.playerType} skill ${profile.skill}`
      )
    );
  }

  if (config.simulatorPreset === "arena-battlefield") {
    drawOpeningHands(snapshot, 7);
    seedArenaBattlefield(snapshot, config.humanPlayerId, config.aiPlayers?.[0]?.playerId);
    snapshot.phase = "beginning";
    snapshot.step = "untap";
    snapshot.turn = 1;
    snapshot.promptText = "Your priority";
  } else {
    snapshot.phase = "setup";
    snapshot.step = "choose_starting_player";
    snapshot.promptText = "Choose starting player";
  }

  snapshot.legalActions = getLegalActions(snapshot, config.humanPlayerId);
  snapshot.engineHealth = getHealth();
  return snapshot;
}

export function createGame(state, roomId, playerIds) {
  const gameId = `xmage-local-${nextGameNumber++}`;
  const snapshot = {
    id: gameId,
    roomId,
    phase: "setup",
    step: "choose_starting_player",
    turn: 1,
    activePlayerId: playerIds[0],
    priorityPlayerId: playerIds[0],
    waitingOnPlayerId: playerIds[0],
    promptText: "Choose starting player",
    players: playerIds.map((playerId) => createPlayer(playerId, playerIds)),
    log: [logEntry(0, `Gateway game ${gameId} created`)],
    legalActions: [],
    engineHealth: getHealth()
  };

  state.set(gameId, snapshot);
  return snapshot;
}

export function getHealth(now = Date.now(), bridgeConnected = isBridgeConnected()) {
  if (!bridgeConnected) {
    return {
      status: "unavailable",
      reason: "XMage Java bridge is not connected. Start Docker Compose or set XMAGE_BRIDGE_URL before using /play.",
      checkedAt: new Date(now).toISOString(),
      recoveryAction: "restart_gateway"
    };
  }

  const stalled = now - lastAiProgressAt > aiStallMs;
  return {
    status: stalled ? "stalled" : "ready",
    reason: stalled
      ? "AI watchdog has not observed gateway progress inside the configured window."
      : "XMage gateway simulator is ready.",
    checkedAt: new Date(now).toISOString(),
    recoveryAction: stalled ? "recreate_game" : "wait"
  };
}

function isBridgeConnected() {
  return process.env.XMAGE_BRIDGE_READY === "true" || process.env.XMAGE_BRIDGE_MODE === "simulator";
}

function createBridgeClientFromEnv() {
  if (!process.env.XMAGE_BRIDGE_URL) return null;
  return createHttpBridgeClient(process.env.XMAGE_BRIDGE_URL);
}

async function requestBridge(fetchImpl, baseUrl, path, options = {}) {
  const requestInit = {
    method: options.method ?? "GET",
    headers: { Accept: "application/json", "Content-Type": "application/json" }
  };
  if (options.body !== undefined) {
    requestInit.body = JSON.stringify(options.body);
  }

  const response = await fetchImpl(`${baseUrl}${path}`, requestInit);
  if (!response.ok) {
    throw new Error(`bridge request failed (${response.status}) for ${path}: ${await response.text()}`);
  }
  return response.json();
}

function isBridgeSnapshot(snapshot) {
  return snapshot?.source === "xmage-java-bridge" || String(snapshot?.id ?? "").startsWith("xmage-bridge-");
}

export function applyCommand(snapshot, command) {
  lastAiProgressAt = Date.now();

  if (command.type === "resolve_choice") {
    const chosenPlayerId = command.choiceIds?.[0] ?? command.playerId;
    snapshot.activePlayerId = chosenPlayerId;
    snapshot.priorityPlayerId = "human";
    snapshot.waitingOnPlayerId = "human";
    drawOpeningHands(snapshot, 7);
    snapshot.step = "mulligan";
    snapshot.promptText = "Mulligan decision (Hand size: 7)";
    snapshot.log.push(logEntry(snapshot.log.length, `${chosenPlayerId} was chosen to start the game`));
  }

  if (command.type === "keep_hand") {
    snapshot.phase = "beginning";
    snapshot.step = "untap";
    snapshot.turn = 1;
    snapshot.priorityPlayerId = snapshot.activePlayerId;
    snapshot.waitingOnPlayerId = snapshot.activePlayerId;
    snapshot.promptText = snapshot.priorityPlayerId === "human" ? "Your priority" : "Waiting for AI";
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} kept hand`));
  }

  if (command.type === "mulligan") {
    const player = findPlayer(snapshot, command.playerId);
    player.zones.library.push(...player.zones.hand);
    player.zones.hand = [];
    player.zones.library.reverse();
    drawOpeningHands(snapshot, 7);
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} mulliganed and drew 7 cards`));
  }

  if (command.type === "play_land") {
    const player = findPlayer(snapshot, command.playerId);
    const card = command.cardName
      ? moveNamedCard(player, command.cardName, "hand", "battlefield")
      : moveCardByInstance(player, command.cardInstanceId, "hand", "battlefield");
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} plays ${card?.card.name ?? "a land"}`));
  }

  if (command.type === "cast_spell") {
    const player = findPlayer(snapshot, command.playerId);
    const card = command.cardName
      ? moveNamedCard(player, command.cardName, command.fromZone ?? "hand", "stack")
      : moveFirstCard(player, "hand", "stack");
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} casts ${card?.card.name ?? "a spell"}`));
  }

  if (command.type === "tap_permanent") {
    const player = findPlayer(snapshot, command.playerId);
    const card = findCardByNameOrInstance(player, "battlefield", command.cardInstanceId);
    card.tapped = true;
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} tapped ${card.card.name}`));
  }

  if (command.type === "untap_permanent") {
    const player = findPlayer(snapshot, command.playerId);
    const card = findCardByNameOrInstance(player, "battlefield", command.cardInstanceId);
    card.tapped = false;
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} untapped ${card.card.name}`));
  }

  if (command.type === "declare_attackers") {
    const player = findPlayer(snapshot, command.playerId);
    for (const attacker of command.attackers ?? []) {
      const card = findCardByNameOrInstance(player, "battlefield", attacker.attackerId);
      card.tapped = true;
      card.isAttacking = true;
    }
    snapshot.priorityPlayerId = nextPlayerId(snapshot, command.playerId);
    snapshot.waitingOnPlayerId = snapshot.priorityPlayerId;
    snapshot.step = "declare-blockers";
    snapshot.promptText = "Declare blockers";
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} declared attackers`));
  }

  if (command.type === "pass_priority" || command.type === "pass_until_response") {
    snapshot.priorityPlayerId = nextPlayerId(snapshot, command.playerId);
    snapshot.waitingOnPlayerId = snapshot.priorityPlayerId;
    snapshot.promptText = snapshot.priorityPlayerId === snapshot.activePlayerId ? "Your priority" : "Waiting for AI";
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} passed priority`));
  }

  if (command.type === "pass_until_next_turn") {
    snapshot.priorityPlayerId = snapshot.activePlayerId;
    snapshot.waitingOnPlayerId = snapshot.activePlayerId;
    snapshot.promptText = "Your priority";
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} passed until next turn`));
  }

  if (command.type === "advance_phase") {
    const phases = ["beginning", "precombat-main", "combat", "postcombat-main", "ending"];
    snapshot.phase = phases[(phases.indexOf(snapshot.phase) + 1) % phases.length] ?? "beginning";
    snapshot.step = phaseToStep(snapshot.phase);
    snapshot.promptText = promptForStep(snapshot.step, snapshot.priorityPlayerId, snapshot.activePlayerId);
    snapshot.log.push(logEntry(snapshot.log.length, `Advanced to ${snapshot.phase}`));
  }

  if (command.type === "concede") {
    findPlayer(snapshot, command.playerId).life = 0;
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} conceded`));
  }

  snapshot.legalActions = getLegalActions(snapshot, snapshot.priorityPlayerId ?? command.playerId);
  snapshot.engineHealth = getHealth();
  snapshot.waitingOnPlayerId = snapshot.priorityPlayerId;
  return snapshot;
}

function getLegalActions(snapshot, playerId) {
  const player = snapshot.players.find((candidate) => candidate.playerId === playerId);
  if (!player) return [];

  if (snapshot.phase === "setup") {
    if (snapshot.step === "choose_starting_player") {
      const aiPlayerId = snapshot.players.find((p) => p.playerId !== playerId)?.playerId ?? "ai-1";
      return [
        {
          id: `${playerId}-choose-human-starts`,
          type: "resolve_choice",
          playerId,
          label: "You start",
          shortLabel: "You start",
          targetIds: [playerId],
          isPrimary: true
        },
        {
          id: `${playerId}-choose-ai-starts`,
          type: "resolve_choice",
          playerId,
          label: "AI starts",
          shortLabel: "AI starts",
          targetIds: [aiPlayerId]
        },
        {
          id: `${playerId}-concede`,
          type: "concede",
          playerId,
          label: "Concede",
          shortLabel: "Concede"
        }
      ];
    }

    if (snapshot.step === "mulligan") {
      return [
        {
          id: `${playerId}-keep`,
          type: "keep_hand",
          playerId,
          label: "Keep Hand",
          shortLabel: "Keep",
          isPrimary: true
        },
        {
          id: `${playerId}-mulligan`,
          type: "mulligan",
          playerId,
          label: "Mulligan",
          shortLabel: "Mulligan"
        },
        {
          id: `${playerId}-concede`,
          type: "concede",
          playerId,
          label: "Concede",
          shortLabel: "Concede"
        }
      ];
    }
  }

  const firstHandCard = player.zones.hand[0];
  const actions = [
    { id: `${playerId}-pass`, type: "pass_priority", playerId, label: "Pass Priority", shortLabel: "Done", isPrimary: true },
    { id: `${playerId}-phase`, type: "advance_phase", playerId, label: "Next Phase", shortLabel: "Next" },
    { id: `${playerId}-skip-turn`, type: "pass_until_next_turn", playerId, label: "Pass until next turn", shortLabel: "Skip turn" },
    { id: `${playerId}-concede`, type: "concede", playerId, label: "Concede", shortLabel: "Concede" }
  ];

  if (firstHandCard) {
    actions.unshift({
      id: `${firstHandCard.instanceId}-cast`,
      type: "cast_spell",
      playerId,
      label: `Cast ${firstHandCard.card.name}`,
      shortLabel: "Cast",
      cardInstanceId: firstHandCard.instanceId,
      sourceZone: "hand",
      requiresTarget: false
    });
    if (isLand(firstHandCard)) {
      actions.unshift({
        id: `${firstHandCard.instanceId}-play-land`,
        type: "play_land",
        playerId,
        label: `Play ${firstHandCard.card.name}`,
        shortLabel: "Play",
        cardInstanceId: firstHandCard.instanceId,
        sourceZone: "hand",
        requiresTarget: false
      });
    }
  }

  const untappedCreature = player.zones.battlefield.find((card) => !card.tapped && isCreature(card));
  if (untappedCreature) {
    actions.unshift({
      id: `${untappedCreature.instanceId}-attack`,
      type: "declare_attackers",
      playerId,
      label: `Attack with ${untappedCreature.card.name}`,
      shortLabel: "Attack",
      cardInstanceId: untappedCreature.instanceId,
      requiresTarget: true
    });
  }

  const untappedPermanent = player.zones.battlefield.find((card) => !card.tapped);
  if (untappedPermanent) {
    actions.unshift({
      id: `${untappedPermanent.instanceId}-tap`,
      type: "tap_permanent",
      playerId,
      label: `Tap ${untappedPermanent.card.name}`,
      shortLabel: "Tap",
      cardInstanceId: untappedPermanent.instanceId,
      requiresTarget: false
    });
  }

  return actions;
}

function createPlayer(playerId, playerIds) {
  return {
    playerId,
    life: 40,
    poison: 0,
    commanderTax: 0,
    zones: {
      library: [],
      hand: [],
      battlefield: [],
      graveyard: [],
      exile: [],
      command: [],
      stack: []
    },
    commanderDamage: Object.fromEntries(playerIds.map((id) => [id, 0]))
  };
}

function loadDeck(player, deck) {
  player.zones.library = [];
  player.zones.hand = [];
  player.zones.battlefield = [];
  player.zones.graveyard = [];
  player.zones.exile = [];
  player.zones.stack = [];
  player.zones.command = deck.commander ? [createZoneCard(deck.commander.cardName, "commander", 0)] : [];

  let index = 0;
  for (const entry of deck.entries ?? []) {
    if (entry.section !== "deck") continue;
    for (let copy = 0; copy < entry.quantity; copy += 1) {
      player.zones.library.push(createZoneCard(entry.cardName, "deck", index++));
    }
  }
}

function drawOpeningHands(snapshot, count) {
  for (const player of snapshot.players) {
    player.zones.hand.push(...player.zones.library.splice(0, count));
  }
  snapshot.log.push(logEntry(snapshot.log.length, `Opening hands drawn (${count})`));
}

function createZoneCard(name, source, index) {
  const stats = cardStats[name];
  return {
    instanceId: `${slug(name)}-${source}-${index}`,
    card: {
      id: slug(name),
      name,
      manaValue: 0,
      colorIdentity: [],
      typeLine: isLandName(name) ? "Land" : stats ? "Creature" : "XMage Gateway Card"
    },
    ...(stats ? { power: stats.power, toughness: stats.toughness } : {})
  };
}

function moveNamedCard(player, name, fromZone, toZone) {
  const source = player.zones[fromZone] ?? [];
  const index = source.findIndex((card) => card.card.name === name);
  if (index === -1) return undefined;
  const [card] = source.splice(index, 1);
  if (card) player.zones[toZone].push(card);
  return card;
}

function moveCardByInstance(player, instanceId, fromZone, toZone) {
  const source = player.zones[fromZone] ?? [];
  const index = source.findIndex((card) => card.instanceId === instanceId);
  if (index === -1) return undefined;
  const [card] = source.splice(index, 1);
  if (card) player.zones[toZone].push(card);
  return card;
}

function moveFirstCard(player, fromZone, toZone) {
  const [card] = player.zones[fromZone].splice(0, 1);
  if (card) player.zones[toZone].push(card);
  return card;
}

function findCardByNameOrInstance(player, zone, value) {
  const card = player.zones[zone].find((candidate) => candidate.instanceId === value || candidate.card.name === value);
  if (!card) throw new NotFoundError(`Card not found in ${zone}: ${value}`);
  return card;
}

function isCreature(card) {
  return card.power !== undefined || card.card.typeLine.toLowerCase().includes("creature");
}

function isLand(card) {
  return card.card.typeLine.toLowerCase().includes("land") || isLandName(card.card.name);
}

function isLandName(name) {
  return /\b(forest|island|mountain|plains|swamp|foundry|harbor|forge|tower|pool|retreat)\b/i.test(name);
}

function phaseToStep(phase) {
  const stepByPhase = {
    beginning: "untap",
    "precombat-main": "precombat-main",
    combat: "declare-attackers",
    "postcombat-main": "postcombat-main",
    ending: "end"
  };
  return stepByPhase[phase] ?? "untap";
}

function promptForStep(step, priorityPlayerId, activePlayerId) {
  if (step === "declare-attackers") return "Declare attackers";
  if (step === "declare-blockers") return "Declare blockers";
  if (priorityPlayerId && priorityPlayerId !== activePlayerId) return "Waiting for AI";
  return "Your priority";
}

function seedArenaBattlefield(snapshot, humanPlayerId, aiPlayerId) {
  const human = findPlayer(snapshot, humanPlayerId);
  const opponent = aiPlayerId ? findPlayer(snapshot, aiPlayerId) : undefined;

  human.zones.battlefield = [
    createZoneCard("Arboreal Grazer", "battlefield", 0),
    createZoneCard("Island", "battlefield", 1),
    { ...createZoneCard("Forest", "battlefield", 2), tapped: true },
    createZoneCard("Hydroid Krasis", "battlefield", 3),
    createZoneCard("Ezuri, Claw of Progress", "battlefield", 4)
  ];
  human.zones.hand = [
    createZoneCard("Growth Spiral", "hand", 0),
    createZoneCard("Hinterland Harbor", "hand", 1),
    createZoneCard("Llanowar Elves", "hand", 2),
    createZoneCard("Arboreal Grazer", "hand", 3),
    createZoneCard("Time Wipe", "hand", 4),
    createZoneCard("Hydroid Krasis", "hand", 5)
  ];

  if (opponent) {
    opponent.zones.battlefield = [
      { ...createZoneCard("Mountain", "battlefield", 0), tapped: true },
      createZoneCard("Sacred Foundry", "battlefield", 1),
      { ...createZoneCard("Swiftblade Vindicator", "battlefield", 2), tapped: true, isAttacking: true },
      { ...createZoneCard("Light of the Legion", "battlefield", 3), tapped: true, isAttacking: true },
      createZoneCard("Battlefield Forge", "battlefield", 4)
    ];
  }

  snapshot.phase = "combat";
  snapshot.priorityPlayerId = humanPlayerId;
}

const cardStats = {
  "Arboreal Grazer": { power: 0, toughness: 3 },
  "Hydroid Krasis": { power: 4, toughness: 4 },
  "Ezuri, Claw of Progress": { power: 3, toughness: 3 },
  "Llanowar Elves": { power: 1, toughness: 1 },
  "Swiftblade Vindicator": { power: 1, toughness: 1 },
  "Light of the Legion": { power: 5, toughness: 5 }
};

function getGame(state, gameId) {
  const snapshot = state.get(gameId);
  if (!snapshot) throw new NotFoundError(`Game not found: ${gameId}`);
  return snapshot;
}

function findPlayer(snapshot, playerId) {
  const player = snapshot.players.find((candidate) => candidate.playerId === playerId);
  if (!player) throw new NotFoundError(`Player not found: ${playerId}`);
  return player;
}

function nextPlayerId(snapshot, playerId) {
  const index = snapshot.players.findIndex((player) => player.playerId === playerId);
  return snapshot.players[(index + 1) % snapshot.players.length]?.playerId ?? playerId;
}

function logEntry(index, message) {
  return {
    id: `gateway-event-${index}`,
    message,
    createdAt: new Date(index * 1000).toISOString()
  };
}

function slug(value) {
  return String(value).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function sendJson(response, body, status = 200) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body));
}

class NotFoundError extends Error {}

const wssClients = new Map(); // gameId -> Set of ws clients

export function registerWebSocketConnection(gameId, ws) {
  if (!wssClients.has(gameId)) {
    wssClients.set(gameId, new Set());
  }
  wssClients.get(gameId).add(ws);
  
  ws.on("close", () => {
    const clients = wssClients.get(gameId);
    if (clients) {
      clients.delete(ws);
      if (clients.size === 0) {
        wssClients.delete(gameId);
      }
    }
  });
}

export function broadcastSnapshot(gameId, snapshot) {
  const clients = wssClients.get(gameId);
  if (clients) {
    const payload = JSON.stringify(snapshot);
    for (const ws of clients) {
      if (ws.readyState === 1) { // OPEN
        ws.send(payload);
      }
    }
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const handler = createGatewayHandler();
  const server = createServer(handler);

  const wss = new WebSocketServer({ noServer: true });
  wss.on("connection", (ws, request) => {
    const url = parseUrl(request.url ?? "/", true);
    const match = url.pathname?.match(/^\/ws\/games\/([^/]+)$/);
    if (match) {
      const gameId = decodeURIComponent(match[1]);
      registerWebSocketConnection(gameId, ws);
      
      const snapshot = games.get(gameId);
      if (snapshot) {
        ws.send(JSON.stringify(snapshot));
      }
    } else {
      ws.close();
    }
  });

  server.on("upgrade", (request, socket, head) => {
    const url = parseUrl(request.url ?? "/", true);
    if (url.pathname?.startsWith("/ws/games/")) {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit("connection", ws, request);
      });
    } else {
      socket.destroy();
    }
  });

  server.listen(port, () => {
    console.log(`MagicMobile XMage gateway listening on ${port}`);
  });
}
