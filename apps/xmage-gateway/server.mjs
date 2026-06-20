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
  if (config.simulatorPreset === "arena-battlefield") {
    seedArenaBattlefield(snapshot, config.humanPlayerId, config.aiPlayers?.[0]?.playerId);
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

export function applyCommand(snapshot, command) {
  lastAiProgressAt = Date.now();

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
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} declared attackers`));
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

  const untappedCreature = player.zones.battlefield.find((card) => !card.tapped && isCreature(card));
  if (untappedCreature) {
    actions.unshift({
      id: `${untappedCreature.instanceId}-attack`,
      type: "declare_attackers",
      playerId,
      label: `Attack with ${untappedCreature.card.name}`,
      cardInstanceId: untappedCreature.instanceId
    });
  }

  const untappedPermanent = player.zones.battlefield.find((card) => !card.tapped);
  if (untappedPermanent) {
    actions.unshift({
      id: `${untappedPermanent.instanceId}-tap`,
      type: "tap_permanent",
      playerId,
      label: `Tap ${untappedPermanent.card.name}`,
      cardInstanceId: untappedPermanent.instanceId
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
      typeLine: stats ? "Creature" : "XMage Gateway Card"
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

if (import.meta.url === `file://${process.argv[1]}`) {
  createServer(createGatewayHandler()).listen(port, () => {
    console.log(`MagicMobile XMage gateway listening on ${port}`);
  });
}
