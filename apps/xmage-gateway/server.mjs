import { createServer } from "node:http";
import { parse as parseUrl } from "node:url";

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

export function createGatewayHandler(state = games) {
  return async function handleRequest(request, response) {
    try {
      const url = parseUrl(request.url ?? "/", true);
      const method = request.method ?? "GET";

      if (method === "GET" && url.pathname === "/health") {
        return sendJson(response, getHealth());
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
        const snapshot = createCommanderGame(state, body);
        return sendJson(response, snapshot, 201);
      }

      const gameMatch = url.pathname?.match(/^\/games\/([^/]+)(?:\/([^/]+))?$/);
      if (gameMatch) {
        const gameId = decodeURIComponent(gameMatch[1]);
        const action = gameMatch[2];
        const snapshot = getGame(state, gameId);

        if (method === "GET" && !action) {
          return sendJson(response, snapshot);
        }

        if (method === "GET" && action === "legal-actions") {
          return sendJson(response, getLegalActions(snapshot, String(url.query.playerId ?? "")));
        }

        if (method === "POST" && action === "commands") {
          const command = await readJson(request);
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

  drawOpeningHands(snapshot, 7);
  snapshot.legalActions = getLegalActions(snapshot, config.humanPlayerId);
  snapshot.engineHealth = getHealth();
  return snapshot;
}

export function createGame(state, roomId, playerIds) {
  const gameId = `xmage-local-${nextGameNumber++}`;
  const snapshot = {
    id: gameId,
    roomId,
    phase: "beginning",
    turn: 1,
    activePlayerId: playerIds[0],
    priorityPlayerId: playerIds[0],
    players: playerIds.map((playerId) => createPlayer(playerId, playerIds)),
    log: [logEntry(0, `Gateway game ${gameId} created`)],
    legalActions: [],
    engineHealth: getHealth()
  };

  state.set(gameId, snapshot);
  return snapshot;
}

export function getHealth(now = Date.now()) {
  const stalled = now - lastAiProgressAt > aiStallMs;
  return {
    status: stalled ? "stalled" : "ready",
    reason: stalled
      ? "AI watchdog has not observed gateway progress inside the configured window."
      : "XMage gateway is ready. Java XMage bridge is not connected in this milestone.",
    checkedAt: new Date(now).toISOString(),
    recoveryAction: stalled ? "recreate_game" : "wait"
  };
}

function applyCommand(snapshot, command) {
  lastAiProgressAt = Date.now();

  if (command.type === "cast_spell") {
    const player = findPlayer(snapshot, command.playerId);
    const card = command.cardName
      ? moveNamedCard(player, command.cardName, command.fromZone ?? "hand", "stack")
      : moveFirstCard(player, "hand", "stack");
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} casts ${card?.card.name ?? "a spell"}`));
  }

  if (command.type === "pass_priority") {
    snapshot.priorityPlayerId = nextPlayerId(snapshot, command.playerId);
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} passed priority`));
  }

  if (command.type === "advance_phase") {
    const phases = ["beginning", "precombat-main", "combat", "postcombat-main", "ending"];
    snapshot.phase = phases[(phases.indexOf(snapshot.phase) + 1) % phases.length] ?? "beginning";
    snapshot.log.push(logEntry(snapshot.log.length, `Advanced to ${snapshot.phase}`));
  }

  if (command.type === "concede") {
    findPlayer(snapshot, command.playerId).life = 0;
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} conceded`));
  }

  snapshot.legalActions = getLegalActions(snapshot, snapshot.priorityPlayerId ?? command.playerId);
  snapshot.engineHealth = getHealth();
  return snapshot;
}

function getLegalActions(snapshot, playerId) {
  const player = snapshot.players.find((candidate) => candidate.playerId === playerId);
  if (!player) return [];

  const firstHandCard = player.zones.hand[0];
  const actions = [
    { id: `${playerId}-pass`, type: "pass_priority", playerId, label: "Pass Priority" },
    { id: `${playerId}-phase`, type: "advance_phase", playerId, label: "Next Phase" },
    { id: `${playerId}-concede`, type: "concede", playerId, label: "Concede" }
  ];

  if (firstHandCard) {
    actions.unshift({
      id: `${firstHandCard.instanceId}-cast`,
      type: "cast_spell",
      playerId,
      label: `Cast ${firstHandCard.card.name}`,
      cardInstanceId: firstHandCard.instanceId
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
  return {
    instanceId: `${slug(name)}-${source}-${index}`,
    card: {
      id: slug(name),
      name,
      manaValue: 0,
      colorIdentity: [],
      typeLine: "XMage Gateway Card"
    }
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

function moveFirstCard(player, fromZone, toZone) {
  const [card] = player.zones[fromZone].splice(0, 1);
  if (card) player.zones[toZone].push(card);
  return card;
}

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

if (import.meta.url === `file://${process.argv[1]}`) {
  createServer(createGatewayHandler()).listen(port, () => {
    console.log(`MagicMobile XMage gateway listening on ${port}`);
  });
}
