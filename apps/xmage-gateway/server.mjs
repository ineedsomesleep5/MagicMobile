import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
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

      const fixtureMatch = url.pathname?.match(/^\/dev\/xmage-fixtures\/([^/]+)$/);
      if (method === "POST" && fixtureMatch) {
        const fixtureName = decodeURIComponent(fixtureMatch[1]);
        if (!xmageFixturesEnabled()) {
          return sendJson(response, { error: "xmage_fixtures_disabled" }, 404);
        }
        const body = await readJson(request);
        const fixture = commanderFixtureConfig(fixtureName, body);
        if (!bridgeClient) {
          return sendJson(
            response,
            fixtureBlockedResponse(fixture, {
              error: "xmage_fixture_bridge_required",
              setupMethod: "bridge_required",
              source: "xmage-gateway",
              blockedReason: "XMage fixtures require the real Java bridge; simulator fallback is disabled."
            }),
            503
          );
        }
        if (typeof bridgeClient.createCommanderFixtureGame !== "function") {
          return sendJson(
            response,
            fixtureBlockedResponse(fixture, {
              error: "xmage_fixture_bridge_endpoint_missing",
              setupMethod: "bridge_fixture_endpoint_missing",
              source: "xmage-gateway",
              blockedReason: "The configured bridge client does not expose createCommanderFixtureGame."
            }),
            501
          );
        }

        const fixtureResponse = await bridgeClient.createCommanderFixtureGame(fixture);
        let snapshot = latestFixtureSnapshot(fixtureResponse);
        const serviceHarness = fixtureResponse?.fixtureHarness ?? snapshot?.fixtureHarness ?? fixtureResponse;
        let proof = fixtureSnapshotProof(snapshot, fixture);
        if (serviceHarness?.directStateSeeded === true && !proof.ok && snapshot?.id && typeof bridgeClient.getSnapshot === "function") {
          for (let attempt = 0; attempt < 40 && !proof.ok; attempt++) {
            await delay(500);
            const refreshed = await bridgeClient.getSnapshot(snapshot.id);
            if (isRealBridgeSnapshot(refreshed)) {
              snapshot = refreshed;
              proof = fixtureSnapshotProof(snapshot, fixture);
            }
          }
        }
        const directStateSeeded = serviceHarness?.directStateSeeded === true && proof.ok;
        const fixtureHarness = {
          ...(serviceHarness ?? {}),
          enabled: true,
          fixtureName: fixture.fixtureName,
          schemaVersion: 1,
          directStateSeeded,
          fallback: directStateSeeded ? null : "fixture_endpoint_returned_without_direct_state",
          reason: directStateSeeded ? serviceHarness?.reason : proof.reason,
          productionDisabled: true,
          expectedRoutes: fixture.schema.expectedRoutes,
          expectedRouteCoverage: fixture.schema.expectedRouteCoverage,
          seededZones: directStateSeeded ? proof.seededZones : []
        };
        if (!directStateSeeded) {
          return sendJson(
            response,
            fixtureBlockedResponse(fixture, {
              error: fixtureResponse?.error ?? "xmage_fixture_state_seeding_unavailable",
              setupMethod: serviceHarness?.setupMethod ?? "bridge_fixture_without_real_seed_proof",
              source: serviceHarness?.source ?? snapshot?.source ?? "xmage-java-bridge",
              gameId: snapshot?.id ?? fixtureResponse?.gameId ?? null,
              bridgeRevision: snapshot?.bridgeRevision ?? fixtureResponse?.bridgeRevision ?? null,
              xmageCycle: snapshot?.xmageCycle ?? fixtureResponse?.xmageCycle ?? null,
              seededZones: [],
              blockedReason: proof.reason,
              fixtureHarness,
              latestSnapshot: isRealBridgeSnapshot(snapshot) ? snapshot : undefined
            }),
            503
          );
        }

        snapshot.fixtureHarness = fixtureHarness;
        if (fixtureResponse !== snapshot) {
          snapshot.fixtureService = fixtureServiceSummary(fixtureResponse);
        }
        lastAiProgressAt = Date.now();
        state.set(snapshot.id, snapshot);
        return sendJson(response, snapshot, 201);
      }

      const updatesMatch = url.pathname?.match(/^\/api\/engine\/games\/([^/]+)\/updates$/);
      if (method === "POST" && updatesMatch) {
        const gameId = decodeURIComponent(updatesMatch[1]);
        const nextSnapshot = await readJson(request);
        storeSnapshot(state, gameId, nextSnapshot, { broadcast: true });
        return sendJson(response, { status: "ok" });
      }

      const gameMatch = url.pathname?.match(/^\/games\/([^/]+)(?:\/([^/]+))?$/);
      if (gameMatch) {
        const gameId = decodeURIComponent(gameMatch[1]);
        const action = gameMatch[2];
        const snapshot = getGame(state, gameId);

        if (method === "GET" && !action) {
          let currentSnapshot = snapshot;
          const playerId = url.query.playerId ? String(url.query.playerId) : undefined;
          if (bridgeClient && isBridgeSnapshot(snapshot)) {
            const nextSnapshot = await bridgeClient.getSnapshot(gameId, playerId);
            lastAiProgressAt = Date.now();
            currentSnapshot = storeSnapshot(state, nextSnapshot.id, nextSnapshot);
          }
          if (playerId) {
            currentSnapshot = obfuscateSnapshotForPlayer(currentSnapshot, playerId);
          }
          return sendJson(response, currentSnapshot);
        }

        if (method === "GET" && action === "debug") {
          return sendJson(response, protocolDebug(snapshot));
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
            const storedSnapshot = storeSnapshot(state, nextSnapshot.id, nextSnapshot, { broadcast: true });
            return sendJson(response, storedSnapshot);
          }
          const nextSnapshot = applyCommand(snapshot, command);
          const storedSnapshot = storeSnapshot(state, nextSnapshot.id, nextSnapshot, { broadcast: true });
          return sendJson(response, storedSnapshot);
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
      if (error instanceof BridgeRequestError) {
        return sendJson(response, error.body, error.status);
      }
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
      return requestBridge(fetchImpl, baseUrl, "/games/commander", { method: "POST", body: config, timeoutMs: 120_000 });
    },
    async createCommanderFixtureGame(fixture) {
      return requestBridge(fetchImpl, baseUrl, "/dev/xmage-fixtures/commander", {
        method: "POST",
        body: fixture,
        timeoutMs: 120_000
      });
    },
    async getSnapshot(gameId, playerId) {
      const query = playerId ? `?playerId=${encodeURIComponent(playerId)}` : "";
      return requestBridge(fetchImpl, baseUrl, `/games/${encodeURIComponent(gameId)}${query}`);
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

export function xmageFixturesEnabled(env = process.env) {
  return env.ENABLE_XMAGE_FIXTURES === "true" && Boolean(env.NODE_ENV) && env.NODE_ENV !== "production";
}

export function commanderFixtureConfig(fixtureName, body = {}) {
  const schemaInput = body.fixture ?? body;
  const scenario = schemaInput.scenarioName ?? body.scenario ?? fixtureName;
  const humanPlayerId = body.humanPlayerId ?? "human";
  const aiPlayerId = body.aiPlayerId ?? "ai-1";
  const seed = body.seed ?? "fixture";
  const aiDifficulty = body.aiDifficulty ?? "normal";
  const humanDeck = body.humanDeck ?? fixtureHumanDeck(scenario);
  const aiDeck = body.aiDeck ?? fixtureAiDeck(scenario);
  const commander = schemaInput.commander ?? humanDeck.commander?.cardName;
  const commandZone = schemaInput.commandZone ?? [commander].filter(Boolean);
  const expectedRoutes = schemaInput.expectedRoutes ?? schemaInput.expectedRouteCoverage ?? fixtureExpectedRouteCoverage(scenario);
  const schema = {
    scenarioName: scenario,
    name: scenario,
    gameId: schemaInput.gameId ?? null,
    format: "commander",
    playerIds: { human: humanPlayerId, ai: [aiPlayerId] },
    commander,
    hand: schemaInput.hand ?? schemaInput.humanHand ?? [],
    battlefield: schemaInput.battlefield ?? schemaInput.humanBattlefield ?? [],
    commandZone,
    libraryTop: schemaInput.libraryTop ?? schemaInput.humanLibraryTop ?? [],
    graveyard: schemaInput.graveyard ?? schemaInput.humanGraveyard ?? [],
    exile: schemaInput.exile ?? schemaInput.humanExile ?? [],
    aiBattlefield: schemaInput.aiBattlefield ?? [],
    phase: schemaInput.phase ?? "precombat-main",
    step: schemaInput.step ?? "precombat-main",
    activePlayerId: schemaInput.activePlayerId ?? humanPlayerId,
    priorityPlayerId: schemaInput.priorityPlayerId ?? humanPlayerId,
    expectedRoutes,
    humanCommander: commander,
    aiCommander: aiDeck.commander?.cardName,
    humanHand: schemaInput.hand ?? schemaInput.humanHand ?? [],
    humanBattlefield: schemaInput.battlefield ?? schemaInput.humanBattlefield ?? [],
    humanCommandZone: commandZone,
    humanGraveyard: schemaInput.graveyard ?? schemaInput.humanGraveyard ?? [],
    humanExile: schemaInput.exile ?? schemaInput.humanExile ?? [],
    humanLibraryTop: schemaInput.libraryTop ?? schemaInput.humanLibraryTop ?? [],
    searchableLibraryContents: humanDeck.entries?.map((entry) => entry.cardName) ?? [],
    activePlayer: schemaInput.activePlayerId ?? humanPlayerId,
    priorityPlayer: schemaInput.priorityPlayerId ?? humanPlayerId,
    expectedRouteCoverage: expectedRoutes,
    expectedFirstLegalActions: ["keep_hand", "mulligan"]
  };

  return {
    fixtureName: scenario,
    schemaVersion: 1,
    schema,
    config: {
      roomId: body.roomId ?? `fixture-${scenario}-${seed}`,
      humanPlayerId,
      humanDeck,
      aiPlayers: [{ playerId: aiPlayerId, displayName: body.aiDisplayName ?? "Noaddrag", difficulty: aiDifficulty, deck: aiDeck }],
      startingLife: body.startingLife ?? 40,
      commanderDamageEnabled: body.commanderDamageEnabled ?? true,
      fixture: schema
    }
  };
}

function fixtureBlockedResponse(fixture, overrides = {}) {
  return {
    error: overrides.error ?? "xmage_fixture_state_seeding_unavailable",
    enabled: true,
    fixtureName: fixture.fixtureName,
    schemaVersion: fixture.schemaVersion,
    productionDisabled: true,
    directStateSeeded: false,
    setupMethod: overrides.setupMethod ?? "blocked_before_bridge",
    gameId: overrides.gameId ?? null,
    source: overrides.source ?? "xmage-gateway",
    bridgeRevision: overrides.bridgeRevision ?? null,
    xmageCycle: overrides.xmageCycle ?? null,
    seededZones: overrides.seededZones ?? [],
    fixtureHarness: overrides.fixtureHarness,
    latestSnapshot: overrides.latestSnapshot,
    blockedReason: overrides.blockedReason ?? "Fixture setup could not reach a real XMage in-process seeding hook.",
    classProcessBoundary:
      overrides.classProcessBoundary
      ?? "Node gateway -> Java bridge HTTP route -> separate XMage server JVM; direct Game.cheat(...) is only available inside the server process.",
    nextImplementationStep:
      overrides.nextImplementationStep
      ?? "Add a dev/test-only fixture hook inside the XMage server process and call it from the bridge route."
  };
}

function latestFixtureSnapshot(fixtureResponse) {
  if (!fixtureResponse || typeof fixtureResponse !== "object") return null;
  if (fixtureResponse.snapshot && typeof fixtureResponse.snapshot === "object") return fixtureResponse.snapshot;
  if (fixtureResponse.latestSnapshot && typeof fixtureResponse.latestSnapshot === "object") return fixtureResponse.latestSnapshot;
  if (fixtureResponse.id || fixtureResponse.source || fixtureResponse.players) return fixtureResponse;
  return null;
}

function fixtureServiceSummary(fixtureResponse) {
  if (!fixtureResponse || typeof fixtureResponse !== "object") return null;
  const { snapshot, latestSnapshot, ...summary } = fixtureResponse;
  return summary;
}

function fixtureSnapshotProof(snapshot, fixture) {
  if (!isRealBridgeSnapshot(snapshot)) {
    return {
      ok: false,
      reason: "Fixture endpoint did not return a real Java bridge snapshot with numeric bridgeRevision.",
      seededZones: []
    };
  }

  const schema = fixture.schema ?? {};
  const humanPlayer = snapshot.players?.find((player) => player.playerId === schema.playerIds?.human);
  const aiPlayerId = schema.playerIds?.ai?.[0];
  const aiPlayer = snapshot.players?.find((player) => player.playerId === aiPlayerId);
  const mismatches = [];
  const seededZones = [];

  if (!humanPlayer) mismatches.push(`missing human player ${schema.playerIds?.human}`);
  if (aiPlayerId && !aiPlayer) mismatches.push(`missing AI player ${aiPlayerId}`);
  if (schema.phase && snapshot.phase !== schema.phase) mismatches.push(`phase ${snapshot.phase ?? "missing"} != ${schema.phase}`);
  if (schema.step && snapshot.step !== schema.step) mismatches.push(`step ${snapshot.step ?? "missing"} != ${schema.step}`);
  if (schema.activePlayerId && snapshot.activePlayerId !== schema.activePlayerId) {
    mismatches.push(`activePlayerId ${snapshot.activePlayerId ?? "missing"} != ${schema.activePlayerId}`);
  }
  if (schema.priorityPlayerId && snapshot.priorityPlayerId !== schema.priorityPlayerId) {
    mismatches.push(`priorityPlayerId ${snapshot.priorityPlayerId ?? "missing"} != ${schema.priorityPlayerId}`);
  }

  if (humanPlayer) {
    verifyZoneContains(mismatches, seededZones, humanPlayer, "hand", schema.hand);
    verifyZoneContains(mismatches, seededZones, humanPlayer, "battlefield", schema.battlefield);
    verifyZoneContains(mismatches, seededZones, humanPlayer, "command", schema.commandZone, "commandZone");
    verifyZoneContains(mismatches, seededZones, humanPlayer, "graveyard", schema.graveyard);
    verifyZoneContains(mismatches, seededZones, humanPlayer, "exile", schema.exile);
    verifyLibraryTop(mismatches, seededZones, humanPlayer, schema.libraryTop);
  }
  if (aiPlayer) {
    verifyZoneContains(mismatches, seededZones, aiPlayer, "battlefield", schema.aiBattlefield, "aiBattlefield");
  }

  return {
    ok: mismatches.length === 0,
    reason: mismatches.length === 0
      ? "Fixture endpoint returned a direct server-side seeded XMage snapshot."
      : `Fixture endpoint returned directStateSeeded=true without matching requested seed proof: ${mismatches.join("; ")}.`,
    seededZones
  };
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function verifyZoneContains(mismatches, seededZones, player, zone, expectedCards, label = zone) {
  const expected = cardNames(expectedCards);
  if (expected.length === 0) return;
  const actual = zoneCardNames(player, zone);
  const missing = expected.filter((cardName) => !actual.includes(cardName));
  if (missing.length > 0) {
    mismatches.push(`${player.playerId}.${label} missing ${missing.join(", ")}`);
    return;
  }
  seededZones.push(`${player.playerId}.${label}`);
}

function verifyLibraryTop(mismatches, seededZones, player, expectedCards) {
  const expected = cardNames(expectedCards);
  if (expected.length === 0) return;
  const actual = zoneCardNames(player, "library").slice(0, expected.length);
  const hidden = actual.length >= expected.length && actual.every((name) => /hidden/i.test(name));
  if (hidden) {
    seededZones.push(`${player.playerId}.libraryTopHidden:${expected.length}`);
    return;
  }
  const mismatched = expected.filter((cardName, index) => actual[index] !== cardName);
  if (mismatched.length > 0) {
    mismatches.push(`${player.playerId}.libraryTop expected ${expected.join(", ")} but saw ${actual.join(", ") || "empty"}`);
    return;
  }
  seededZones.push(`${player.playerId}.libraryTop`);
}

function cardNames(cards) {
  return (cards ?? [])
    .map((entry) => typeof entry === "string" ? entry : entry?.cardName ?? entry?.name ?? entry?.card?.name)
    .filter(Boolean);
}

function zoneCardNames(player, zone) {
  return (player.zones?.[zone] ?? []).map((entry) => entry.card?.name ?? entry.cardName ?? entry.name).filter(Boolean);
}

function fixtureExpectedRouteCoverage(scenario) {
  const common = ["keep_hand", "mulligan", "play_land", "cast_spell", "make_mana", "pass_priority"];
  if (scenario === "search-library" || scenario === "search-select") return [...common, "activate_ability", "search_select", "choose_card", "zone_updates"];
  if (scenario === "commander-replacement" || scenario === "commander-replacement-tax") return [...common, "choose_target", "commander_replacement", "commander_tax", "command_zone"];
  if (scenario === "activated-ability-stack") return [...common, "activate_ability", "choose_player", "stack_objects"];
  if (scenario === "triggered-ability" || scenario === "triggered-ability-stack") return [...common, "triggered_ability", "order_triggers", "stack_objects"];
  if (scenario === "combat-blockers" || scenario === "blocker-flow") return [...common, "declare_attackers", "declare_blockers"];
  if (scenario === "damage-assignment") return [...common, "declare_attackers", "declare_blockers", "damage_assignment"];
  return [
    ...common,
    "activate_ability",
    "search_select",
    "choose_card",
    "choose_target",
    "commander_replacement",
    "commander_tax",
    "commander_damage",
    "stack_objects",
    "zone_updates"
  ];
}

function fixtureHumanDeck(scenario) {
  if (scenario === "blocker-flow" || scenario === "damage-assignment") {
    return {
      name: scenario === "damage-assignment" ? "Damage Assignment Human Fixture" : "Blocker Flow Human Fixture",
      commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
      entries: [
        { cardName: "Silvercoat Lion", quantity: 1, section: "deck" },
        { cardName: "Plains", quantity: 98, section: "deck" }
      ]
    };
  }
  if (scenario === "commander-gauntlet") {
    return {
      name: "Commander Gauntlet Fixture",
      commander: { cardName: "Loran of the Third Path", quantity: 1, section: "commander" },
      entries: [
        { cardName: "Sol Ring", quantity: 1, section: "deck" },
        { cardName: "Arcane Signet", quantity: 1, section: "deck" },
        { cardName: "Evolving Wilds", quantity: 1, section: "deck" },
        { cardName: "Terramorphic Expanse", quantity: 1, section: "deck" },
        { cardName: "Fateful Absence", quantity: 1, section: "deck" },
        { cardName: "Spirited Companion", quantity: 1, section: "deck" },
        { cardName: "Plains", quantity: 93, section: "deck" }
      ]
    };
  }
  if (scenario === "mana-rock") {
    return {
      name: "Mana Rock Fixture",
      commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
      entries: [
        { cardName: "Sol Ring", quantity: 1, section: "deck" },
        { cardName: "Plains", quantity: 98, section: "deck" }
      ]
    };
  }
  if (scenario === "activated-ability-stack") {
    return {
      name: "Activated Ability Stack Fixture",
      commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
      entries: [
        { cardName: "Seal of Cleansing", quantity: 1, section: "deck" },
        { cardName: "Sol Ring", quantity: 1, section: "deck" },
        { cardName: "Plains", quantity: 97, section: "deck" }
      ]
    };
  }
  if (scenario === "prompt-mode") {
    return {
      name: "Prompt Mode Fixture",
      commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
      entries: [
        { cardName: "Lavabrink Venturer", quantity: 1, section: "deck" },
        { cardName: "Plains", quantity: 98, section: "deck" }
      ]
    };
  }
  return fixtureCommanderDeck("Isamaru, Hound of Konda", "Plains", `${scenario} Human Fixture`);
}

function fixtureAiDeck(scenario) {
  if (scenario === "blocker-flow" || scenario === "damage-assignment") {
    return {
      name: scenario === "damage-assignment" ? "Damage Assignment AI Fixture" : "Blocker Flow AI Fixture",
      commander: { cardName: "Kozilek, Butcher of Truth", quantity: 1, section: "commander" },
      entries: [
        { cardName: "Memnite", quantity: 1, section: "deck" },
        { cardName: "Wastes", quantity: 98, section: "deck" }
      ]
    };
  }
  return fixtureCommanderDeck("Kozilek, Butcher of Truth", "Wastes", "Fixture AI Deck");
}

function fixtureCommanderDeck(commander, basic, name) {
  return {
    name,
    commander: { cardName: commander, quantity: 1, section: "commander" },
    entries: [{ cardName: basic, quantity: 99, section: "deck" }]
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
  const requestId = options.body?.requestId ?? randomUUID();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 20_000);
  const requestInit = {
    method: options.method ?? "GET",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-Request-Id": requestId
    },
    signal: controller.signal
  };
  if (options.body !== undefined) {
    requestInit.body = JSON.stringify(options.body);
  }

  let response;
  try {
    response = await fetchImpl(`${baseUrl}${path}`, requestInit);
  } finally {
    clearTimeout(timeout);
  }
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { error: text || `bridge request failed (${response.status})` };
  }
  if (!response.ok) {
    throw new BridgeRequestError(response.status, body);
  }
  return body;
}

function isBridgeSnapshot(snapshot) {
  return snapshot?.source === "xmage-java-bridge" || String(snapshot?.id ?? "").startsWith("xmage-bridge-");
}

function isRealBridgeSnapshot(snapshot) {
  return snapshot?.source === "xmage-java-bridge" && typeof snapshot.bridgeRevision === "number";
}

export function applyCommand(snapshot, command) {
  lastAiProgressAt = Date.now();

  const knownCommands = new Set([
    "resolve_choice",
    "keep_hand",
    "mulligan",
    "play_land",
    "cast_spell",
    "tap_permanent",
    "make_mana",
    "untap_permanent",
    "declare_attackers",
    "pass_priority",
    "pass_until_response",
    "pass_until_next_turn",
    "advance_phase",
    "concede"
  ]);
  if (!knownCommands.has(command.type)) {
    throw new Error(`Unknown command type: ${command.type}`);
  }

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

  if (command.type === "make_mana") {
    const player = findPlayer(snapshot, command.playerId);
    const card = findCardByNameOrInstance(player, "battlefield", command.sourceInstanceId ?? command.cardInstanceId);
    card.tapped = true;
    const symbol = manaSymbolFor(card);
    player.manaPool[symbol] += 1;
    snapshot.log.push(logEntry(snapshot.log.length, `${command.playerId} tapped ${card.card.name} for {${symbol}}`));
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
      cardName: firstHandCard.card.name,
      manaCost: firstHandCard.card.manaCost,
      sourceZone: "hand",
      isPrimary: true,
      requiresPayment: (firstHandCard.card.manaValue ?? 0) > 0,
      requiresTarget: false,
      commandTemplate: {
        type: "cast_spell",
        cardInstanceId: firstHandCard.instanceId,
        sourceInstanceId: firstHandCard.instanceId,
        sourceZone: "hand",
        cardName: firstHandCard.card.name
      }
    });
    if (isLand(firstHandCard)) {
      actions.unshift({
        id: `${firstHandCard.instanceId}-play-land`,
        type: "play_land",
        playerId,
        label: `Play ${firstHandCard.card.name}`,
        shortLabel: "Play",
        cardInstanceId: firstHandCard.instanceId,
        cardName: firstHandCard.card.name,
        sourceZone: "hand",
        isPrimary: true,
        requiresTarget: false,
        commandTemplate: {
          type: "play_land",
          cardInstanceId: firstHandCard.instanceId,
          sourceInstanceId: firstHandCard.instanceId,
          sourceZone: "hand",
          cardName: firstHandCard.card.name
        }
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

  const untappedManaPermanent = player.zones.battlefield.find((card) => !card.tapped && canMakeMana(card));
  if (untappedManaPermanent) {
    actions.unshift({
      id: `${untappedManaPermanent.instanceId}-mana`,
      type: "make_mana",
      playerId,
      label: `Tap ${untappedManaPermanent.card.name} for mana`,
      shortLabel: "Mana",
      cardInstanceId: untappedManaPermanent.instanceId,
      sourceInstanceId: untappedManaPermanent.instanceId,
      cardName: untappedManaPermanent.card.name,
      sourceZone: "battlefield",
      producedMana: producedManaHint(untappedManaPermanent),
      requiresTarget: false,
      commandTemplate: {
        type: "make_mana",
        cardInstanceId: untappedManaPermanent.instanceId,
        sourceInstanceId: untappedManaPermanent.instanceId,
        sourceZone: "battlefield",
        cardName: untappedManaPermanent.card.name
      }
    });
  }

  const untappedPermanent = player.zones.battlefield.find((card) => !card.tapped && !canMakeMana(card));
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
    manaPool: emptyManaPool(),
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

function emptyManaPool() {
  return { W: 0, U: 0, B: 0, R: 0, G: 0, C: 0 };
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

function canMakeMana(card) {
  const text = `${card.card.name} ${card.card.typeLine} ${card.card.oracleText ?? ""}`;
  return isLand(card) || /\{T\}:\s*Add|Add \{[WUBRGC]\}/i.test(text);
}

function producedManaHint(card) {
  const text = `${card?.card?.name ?? ""}\n${card?.card?.oracleText ?? ""}`.toLowerCase();
  const symbols = [];
  for (const [token, symbol] of [
    ["{w}", "W"],
    ["{u}", "U"],
    ["{b}", "B"],
    ["{r}", "R"],
    ["{g}", "G"],
    ["{c}", "C"]
  ]) {
    if (text.includes(token)) symbols.push(symbol);
  }
  if (symbols.length === 0 && text.includes("mana of any color")) {
    symbols.push("W", "U", "B", "R", "G");
  }
  if (symbols.length === 0) {
    const name = card?.card?.name?.toLowerCase() ?? "";
    if (name.includes("plains")) symbols.push("W");
    if (name.includes("island")) symbols.push("U");
    if (name.includes("swamp")) symbols.push("B");
    if (name.includes("mountain")) symbols.push("R");
    if (name.includes("forest")) symbols.push("G");
  }
  return Array.from(new Set(symbols));
}

function manaSymbolFor(card) {
  const name = card.card.name.toLowerCase();
  const text = `${card.card.oracleText ?? ""} ${card.card.typeLine}`;
  const explicit = text.match(/Add \{([WUBRGC])\}/i);
  if (explicit) return explicit[1].toUpperCase();
  if (name.includes("plains")) return "W";
  if (name.includes("island")) return "U";
  if (name.includes("swamp")) return "B";
  if (name.includes("mountain")) return "R";
  if (name.includes("forest")) return "G";
  return "C";
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

export function shouldAcceptSnapshot(currentSnapshot, nextSnapshot) {
  const currentRevision = Number(currentSnapshot?.bridgeRevision ?? -1);
  const nextRevision = Number(nextSnapshot?.bridgeRevision ?? -1);
  if (currentRevision >= 0 && nextRevision >= 0) {
    if (nextRevision > currentRevision) {
      return true;
    }
    if (nextRevision < currentRevision) {
      return false;
    }
    const currentCycle = Number(currentSnapshot?.xmageCycle ?? -1);
    const nextCycle = Number(nextSnapshot?.xmageCycle ?? -1);
    if (currentCycle >= 0 && nextCycle >= 0) {
      return nextCycle >= currentCycle;
    }
    return true;
  }
  return true;
}

export function storeSnapshot(state, gameId, nextSnapshot, options = {}) {
  const currentSnapshot = state.get(gameId);
  if (!shouldAcceptSnapshot(currentSnapshot, nextSnapshot)) {
    return currentSnapshot;
  }
  const storedSnapshot = sanitizePendingSnapshot(nextSnapshot);
  state.set(gameId, storedSnapshot);
  if (options.broadcast) {
    broadcastSnapshot(gameId, storedSnapshot);
  }
  return storedSnapshot;
}

function sanitizePendingSnapshot(snapshot) {
  if (!snapshot?.pendingStatus) {
    return snapshot;
  }
  const legalActions = Array.isArray(snapshot.legalActions) ? snapshot.legalActions : [];
  return {
    ...snapshot,
    legalActions: legalActions.filter((action) => action?.type === "concede")
  };
}

export function obfuscateSnapshotForPlayer(snapshot, targetPlayerId) {
  if (!snapshot) return snapshot;

  const obfuscated = JSON.parse(JSON.stringify(snapshot));

  if (Array.isArray(obfuscated.players)) {
    for (const player of obfuscated.players) {
      if (player.playerId !== targetPlayerId) {
        if (player.zones && Array.isArray(player.zones.hand)) {
          player.zones.hand = player.zones.hand.map((card, idx) => ({
            instanceId: `hidden-hand-${player.playerId}-${idx}`,
            card: {
              id: "hidden-card",
              name: "Hidden card",
              manaValue: 0,
              colorIdentity: [],
              typeLine: "Hidden"
            }
          }));
        }
      }
      if (player.zones && Array.isArray(player.zones.library)) {
        player.zones.library = player.zones.library.map((card, idx) => ({
          instanceId: `hidden-library-${player.playerId}-${idx}`,
          card: {
            id: "hidden-card",
            name: "Hidden card",
            manaValue: 0,
            colorIdentity: [],
            typeLine: "Hidden"
          }
        }));
      }
    }
  }

  if (obfuscated.xmage && Array.isArray(obfuscated.xmage.players)) {
    for (const player of obfuscated.xmage.players) {
      if (player.playerId !== targetPlayerId) {
        if (player.zones && Array.isArray(player.zones.hand)) {
          player.zones.hand = player.zones.hand.map((card, idx) => ({
            instanceId: `hidden-hand-${player.playerId}-${idx}`,
            card: {
              id: "hidden-card",
              name: "Hidden card",
              manaValue: 0,
              colorIdentity: [],
              typeLine: "Hidden"
            }
          }));
        }
      }
      if (player.zones && Array.isArray(player.zones.library)) {
        player.zones.library = player.zones.library.map((card, idx) => ({
          instanceId: `hidden-library-${player.playerId}-${idx}`,
          card: {
            id: "hidden-card",
            name: "Hidden card",
            manaValue: 0,
            colorIdentity: [],
            typeLine: "Hidden"
          }
        }));
      }
    }
  }

  return obfuscated;
}

export function protocolDebug(snapshot) {
  const xmage = snapshot?.xmage ?? null;
  const prompt = snapshot?.promptEnvelopeV2 ?? snapshot?.promptEnvelope ?? null;
  return {
    gameId: snapshot?.id,
    source: snapshot?.source ?? "simulator",
    bridgeRevision: snapshot?.bridgeRevision ?? null,
    xmageCycle: snapshot?.xmageCycle ?? null,
    pendingStatus: snapshot?.pendingStatus ?? null,
    prompt,
    callbackCoverage: xmage?.callbackCoverage ?? (prompt?.method ? [prompt.method] : []),
    panels: xmage?.panels ?? {},
    xmage
  };
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

class BridgeRequestError extends Error {
  constructor(status, body) {
    super(body?.message ?? body?.error ?? `Bridge request failed (${status})`);
    this.status = status;
    this.body = body;
  }
}

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
