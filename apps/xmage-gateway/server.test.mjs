import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import {
  aiDifficultyProfiles,
  applyCommand,
  commanderFixtureConfig,
  createCommanderGame,
  createGatewayHandler,
  createHttpBridgeClient,
  cleanupIdleGames,
  getGatewayHealth,
  getHealth,
  registerWebSocketConnection,
  shouldAcceptSnapshot,
  obfuscateSnapshotForPlayer,
  xmageFixturesEnabled
} from "./server.mjs";

const deck = {
  name: "Gateway Commander",
  commander: { cardName: "Ezuri, Claw of Progress", quantity: 1, section: "commander" },
  entries: Array.from({ length: 99 }, (_, index) => ({
    cardName: index === 0 ? "Sol Ring" : `Forest ${index}`,
    quantity: 1,
    section: "deck"
  }))
};

describe("xmage gateway", () => {
  it("maps MagicMobile difficulties to XMage player profiles", () => {
    assert.deepEqual(aiDifficultyProfiles.easy, { playerType: "Computer - default", skill: 3 });
    assert.deepEqual(aiDifficultyProfiles.normal, { playerType: "Computer - mad", skill: 5 });
    assert.deepEqual(aiDifficultyProfiles.hard, { playerType: "Computer - mad", skill: 8 });
    assert.equal(aiDifficultyProfiles.expert.skill, 10);
  });

  it("creates a Commander game with a human and AI seat", () => {
    const state = new Map();
    let snapshot = createCommanderGame(state, {
      roomId: "room-1",
      humanPlayerId: "human",
      humanDeck: deck,
      aiPlayers: [{ playerId: "ai-1", displayName: "AI Easy", difficulty: "easy", deck }],
      startingLife: 40,
      commanderDamageEnabled: true
    });

    assert.equal(snapshot.players.length, 2);
    assert.equal(snapshot.players[0].zones.command[0].card.name, "Ezuri, Claw of Progress");
    assert.equal(snapshot.players[0].zones.hand.length, 0);
    assert.equal(snapshot.phase, "setup");
    assert.equal(snapshot.step, "choose_starting_player");
    assert.equal(snapshot.legalActions.some((action) => action.type === "resolve_choice"), true);

    snapshot = applyCommand(snapshot, {
      type: "resolve_choice",
      gameId: snapshot.id,
      playerId: "human",
      choiceIds: ["human"]
    });

    assert.equal(snapshot.step, "mulligan");
    assert.equal(snapshot.players[0].zones.hand.length, 7);
    assert.equal(snapshot.legalActions.some((action) => action.type === "keep_hand"), true);

    snapshot = applyCommand(snapshot, {
      type: "keep_hand",
      gameId: snapshot.id,
      playerId: "human"
    });

    assert.equal(snapshot.phase, "beginning");
    assert.equal(snapshot.step, "untap");
    assert.equal(snapshot.turn, 1);
    assert.equal(snapshot.players[0].zones.hand.length, 7);
    assert.equal(snapshot.legalActions.some((action) => action.type === "play_land" || action.type === "cast_spell"), true);
    assert.equal(state.has(snapshot.id), true);
  });

  it("applies simulator tap and attack commands through snapshots", () => {
    const snapshot = createCommanderGame(new Map(), {
      roomId: "room-arena",
      humanPlayerId: "human",
      humanDeck: deck,
      aiPlayers: [{ playerId: "ai-1", displayName: "AI Normal", difficulty: "normal", deck }],
      startingLife: 40,
      commanderDamageEnabled: true,
      simulatorPreset: "arena-battlefield"
    });

    const tapAction = snapshot.legalActions.find((action) => action.type === "tap_permanent");
    assert.ok(tapAction.cardInstanceId);

    const tapped = applyCommand(snapshot, {
      type: "tap_permanent",
      gameId: snapshot.id,
      playerId: "human",
      cardInstanceId: tapAction.cardInstanceId
    });
    assert.equal(
      tapped.players[0].zones.battlefield.find((card) => card.instanceId === tapAction.cardInstanceId).tapped,
      true
    );

    const attackAction = tapped.legalActions.find((action) => action.type === "declare_attackers");
    assert.ok(attackAction.cardInstanceId);
    const attacking = applyCommand(tapped, {
      type: "declare_attackers",
      gameId: snapshot.id,
      playerId: "human",
      attackers: [{ attackerId: attackAction.cardInstanceId, defenderId: "ai-1" }]
    });
    assert.equal(
      attacking.players[0].zones.battlefield.find((card) => card.instanceId === attackAction.cardInstanceId).isAttacking,
      true
    );
  });

  it("initializes mana pools and exposes make-mana actions for untapped lands", () => {
    const state = new Map();
    let snapshot = createCommanderGame(state, {
      roomId: "room-mana",
      humanPlayerId: "human",
      humanDeck: {
        ...deck,
        entries: [{ cardName: "Forest", quantity: 1, section: "deck" }, ...deck.entries.slice(1)]
      },
      aiPlayers: [{ playerId: "ai-1", displayName: "AI Normal", difficulty: "normal", deck }],
      startingLife: 40,
      commanderDamageEnabled: true
    });

    assert.deepEqual(snapshot.players[0].manaPool, { W: 0, U: 0, B: 0, R: 0, G: 0, C: 0 });

    snapshot = applyCommand(snapshot, {
      type: "resolve_choice",
      gameId: snapshot.id,
      playerId: "human",
      choiceIds: ["human"]
    });
    snapshot = applyCommand(snapshot, {
      type: "keep_hand",
      gameId: snapshot.id,
      playerId: "human"
    });
    snapshot = applyCommand(snapshot, {
      type: "play_land",
      gameId: snapshot.id,
      playerId: "human",
      cardInstanceId: snapshot.players[0].zones.hand.find((card) => card.card.name === "Forest").instanceId
    });

    const manaAction = snapshot.legalActions.find((action) => action.type === "make_mana");
    assert.equal(manaAction.shortLabel, "Mana");
    assert.equal(manaAction.sourceZone, "battlefield");
    assert.equal(manaAction.cardName, "Forest");
    assert.deepEqual(manaAction.producedMana, ["G"]);
    assert.deepEqual(manaAction.commandTemplate, {
      type: "make_mana",
      cardInstanceId: manaAction.cardInstanceId,
      sourceInstanceId: manaAction.sourceInstanceId,
      sourceZone: "battlefield",
      cardName: "Forest"
    });

    snapshot = applyCommand(snapshot, {
      type: "make_mana",
      gameId: snapshot.id,
      playerId: "human",
      sourceInstanceId: manaAction.sourceInstanceId
    });

    assert.equal(snapshot.players[0].zones.battlefield[0].tapped, true);
    assert.deepEqual(snapshot.players[0].manaPool, { W: 0, U: 0, B: 0, R: 0, G: 1, C: 0 });
  });

  it("walks the local Commander smoke loop through priority", () => {
    const state = new Map();
    let snapshot = createCommanderGame(state, {
      roomId: "room-smoke-loop",
      humanPlayerId: "human",
      humanDeck: {
        ...deck,
        entries: [
          { cardName: "Forest", quantity: 1, section: "deck" },
          { cardName: "Growth Spiral", quantity: 1, section: "deck" },
          ...deck.entries.slice(2)
        ]
      },
      aiPlayers: [{ playerId: "ai-1", displayName: "AI Normal", difficulty: "normal", deck }],
      startingLife: 40,
      commanderDamageEnabled: true
    });

    snapshot = applyCommand(snapshot, {
      type: "resolve_choice",
      gameId: snapshot.id,
      playerId: "human",
      choiceIds: ["human"]
    });
    snapshot = applyCommand(snapshot, { type: "keep_hand", gameId: snapshot.id, playerId: "human" });

    const forest = snapshot.players[0].zones.hand.find((card) => card.card.name === "Forest");
    assert.ok(forest);
    snapshot = applyCommand(snapshot, {
      type: "play_land",
      gameId: snapshot.id,
      playerId: "human",
      cardInstanceId: forest.instanceId
    });

    const manaAction = snapshot.legalActions.find((action) => action.type === "make_mana");
    assert.ok(manaAction);
    snapshot = applyCommand(snapshot, {
      type: "make_mana",
      gameId: snapshot.id,
      playerId: "human",
      sourceInstanceId: manaAction.sourceInstanceId
    });

    const spell = snapshot.players[0].zones.hand.find((card) => card.card.name === "Growth Spiral");
    assert.ok(spell);
    snapshot = applyCommand(snapshot, {
      type: "cast_spell",
      gameId: snapshot.id,
      playerId: "human",
      cardInstanceId: spell.instanceId
    });
    assert.equal(snapshot.players[0].zones.stack.some((card) => card.card.name === "Growth Spiral"), true);

    snapshot = applyCommand(snapshot, { type: "pass_priority", gameId: snapshot.id, playerId: "human" });
    assert.equal(snapshot.priorityPlayerId, "ai-1");
    assert.equal(snapshot.waitingOnPlayerId, "ai-1");
    assert.equal(snapshot.promptText, "Waiting for AI");
    assert.equal(state.get(snapshot.id).players[0].zones.stack.some((card) => card.card.name === "Growth Spiral"), true);
  });

  it("reports stalled health when the AI watchdog window is exceeded", () => {
    const staleHealth = getHealth(Date.now() + 999_999, true);
    assert.equal(staleHealth.status, "stalled");
    assert.equal(staleHealth.recoveryAction, "recreate_game");
  });

  it("reports unavailable health when the Java bridge is not connected", () => {
    const health = getHealth(Date.now(), false);
    assert.equal(health.status, "unavailable");
    assert.equal(health.recoveryAction, "restart_gateway");
  });

  it("reports ready health from the Java bridge before a game starts", async () => {
    const health = await getGatewayHealth(
      {
        health: async () => ({
          status: "ready",
          reason: "bridge ready",
          checkedAt: new Date(0).toISOString(),
          recoveryAction: "wait"
        })
      },
      Date.now() + 999_999
    );

    assert.equal(health.status, "ready");
    assert.equal(health.reason, "bridge ready");
  });

  it("sends Commander game creation through the HTTP bridge client", async () => {
    const requests = [];
    const client = createHttpBridgeClient("http://bridge.test/", async (url, init) => {
      requests.push({ url, init });
      return new Response(JSON.stringify({ id: "xmage-game-1" }), { status: 201 });
    });

    const snapshot = await client.createCommanderGame({ roomId: "room-1", humanDisplayName: "Caleb" });

    assert.equal(snapshot.id, "xmage-game-1");
    assert.equal(requests[0].url, "http://bridge.test/games/commander");
    assert.equal(requests[0].init.method, "POST");
    assert.equal(JSON.parse(requests[0].init.body).roomId, "room-1");
    assert.equal(JSON.parse(requests[0].init.body).humanDisplayName, "Caleb");
  });

  it("forwards explicit game cleanup to the bridge and removes gateway state", async () => {
    const state = new Map();
    const activity = new Map();
    const snapshot = bridgeSmokeSnapshot(1, 1, "precombat-main", []);
    state.set(snapshot.id, snapshot);
    activity.set(snapshot.id, { lastPollAt: Date.now(), connectedClients: 0 });
    const cleaned = [];
    const handler = createGatewayHandler(state, {
      activityState: activity,
      bridgeClient: {
        cleanupGame: async (gameId, reason) => {
          cleaned.push({ gameId, reason });
          return { status: "cleaned_up" };
        }
      }
    });

    const response = await runHandler(handler, `/games/${snapshot.id}`, "DELETE", { reason: "unit-test" });
    const body = JSON.parse(response.body);

    assert.equal(response.status, 200);
    assert.equal(body.removed, true);
    assert.equal(body.bridgeCleanupAttempted, true);
    assert.equal(body.bridgeCleanupSucceeded, true);
    assert.equal(state.has(snapshot.id), false);
    assert.equal(activity.has(snapshot.id), false);
    assert.deepEqual(cleaned, [{ gameId: snapshot.id, reason: "unit-test" }]);
  });

  it("cleans idle games only after no clients or polling remain", async () => {
    const state = new Map();
    const activity = new Map();
    const snapshot = bridgeSmokeSnapshot(1, 1, "precombat-main", []);
    state.set(snapshot.id, snapshot);
    activity.set(snapshot.id, {
      lastPollAt: 1_000,
      lastCommandAt: 1_000,
      lastConnectedAt: 1_000,
      lastDisconnectedAt: 1_000,
      connectedClients: 1
    });
    const bridgeClient = { cleanupGame: async () => ({ status: "cleaned_up" }) };

    assert.deepEqual(await cleanupIdleGames(state, activity, bridgeClient, 10_000, 5_000), []);
    activity.set(snapshot.id, { ...activity.get(snapshot.id), connectedClients: 0 });
    const cleaned = await cleanupIdleGames(state, activity, bridgeClient, 10_000, 5_000);

    assert.equal(cleaned.length, 1);
    assert.equal(cleaned[0].reason, "idle-timeout");
    assert.equal(state.has(snapshot.id), false);
  });

  it("bridge source seats the human display name and treats starting-player prompts as player choices", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.ok(bridgeSource.includes("humanDisplayName"));
    assert.match(bridgeSource, /session\.joinTable\(roomId, table\.getTableId\(\), humanDisplayName/);
    assert.match(bridgeSource, /waitForStartedGame\(humanExternalId, aiExternalId, humanDisplayName, aiName/);
    assert.match(bridgeSource, /startupRecord\(gameId, existing, humanExternalId, aiExternalId, humanName, aiName\)/);
    assert.match(bridgeSource, /normalizePlayerPromptChoices\(rebound\.promptEnvelope, rebound, rebound\.latestView\)/);
    assert.match(bridgeSource, /out\.addProperty\("displayName", player\.getName\(\)\)/);
    assert.match(bridgeSource, /GAME_SELECT.*starting player.*return "player"/s);
  });

  it("starts embedded Commander games with the human as XMage starting-player chooser", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    const startSource = readFileSync(new URL("./bridge/start.sh", import.meta.url), "utf8");

    assert.match(bridgeSource, /startMatchWithHumanChooser/);
    assert.match(bridgeSource, /startGame\.invoke\(controller, humanPlayerId\)/);
    assert.doesNotMatch(bridgeSource, /startMatchWithHumanChooser[\s\S]*?setStartingPlayerId/);
    assert.match(startSource, /XMAGE_EMBEDDED_BRIDGE/);
    assert.match(startSource, /MagicMobileEmbeddedServerBridge/);
    assert.doesNotMatch(
      startSource,
      /ENABLE_XMAGE_FIXTURES[\s\S]{0,160}MagicMobileEmbeddedServerBridge/,
      "normal Commander games must not lose the starting-player chooser just because fixtures are disabled"
    );
  });

  it("dispatches hand spell casts through the source card and retries missed priority windows", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    const commandBranch = bridgeSource.match(/if \("play_land"\.equals\(type\)\)[\s\S]*?else if \("undo_mana"/)?.[0] ?? "";

    assert.match(commandBranch, /"cast_spell"\.equals\(type\)[\s\S]*?retryableUuid = playableSourceUuid\(gameId, command\)/);
    assert.match(bridgeSource, /retryPlayableUuidCommandIfNoProgress\(gameId, xmageGameId, command, type, retryableUuid, updated\)/);
    assert.match(bridgeSource, /private JsonObject retryPlayableUuidCommandIfNoProgress/);
    assert.match(bridgeSource, /private boolean playableUuidCommandStillNeedsRetry/);
    assert.match(bridgeSource, /legalActionStillAvailable\(snapshot, command, type\)/);
  });

  it("labels XMage turn-one player target as starting-player choice", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    const labelMethod = bridgeSource.match(/private String labelForChoice[\s\S]*?private boolean isStartingPlayerPrompt/)?.[0] ?? "";

    assert.match(bridgeSource, /isStartingPlayerPrompt/);
    assert.match(bridgeSource, /"GAME_TARGET"\.equals\(method\)/);
    assert.match(bridgeSource, /record\.latestView\.getTurn\(\) <= 1/);
    assert.match(labelMethod, /startingPlayerPrompt && isUuid\(choiceId\)/);
    assert.match(labelMethod, /record\.humanName \+ " starts"/);
    assert.ok(
      labelMethod.indexOf("startingPlayerPrompt && isUuid(choiceId)") < labelMethod.indexOf("JsonObject promptChoice"),
      "starting-player labels must win over raw XMage choice labels"
    );
  });

  it("exposes XMage undo only through the real PlayerAction.UNDO path", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /private boolean canUndoMana\(GameView view, Map<UUID, String> playerIds, String humanId\)/);
    assert.match(bridgeSource, /player\.getStatesSavedSize\(\) > 0/);
    assert.match(bridgeSource, /view\.getStack\(\) == null \|\| !view\.getStack\(\)\.isEmpty\(\)/);
    assert.match(bridgeSource, /action\("xmage-undo-mana", "undo_mana"/);
    assert.match(bridgeSource, /"undo_mana"\.equals\(type\)[\s\S]*?PlayerAction\.UNDO/);
  });

  it("resolves synthetic ability stack objects through XMage source cards", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /optionalMember\(card, "getSourceCard", "sourceCard"\)/);
    assert.match(bridgeSource, /sourceCardObject instanceof CardView/);
    assert.match(bridgeSource, /stackSourceName\(CardView card\)[\s\S]*?"sourceName"/);
    assert.match(bridgeSource, /sourceCardUnavailableReason/);
  });

  it("keeps combat choices XMage-authored and fails closed for speculative blockers", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /!permanent\.isCreature\(\) \|\| !permanent\.isCanAttack\(\)/);
    assert.match(bridgeSource, /!permanent\.isCreature\(\) \|\| !permanent\.isCanBlock\(\)/);
    assert.match(bridgeSource, /attackerChoices\.size\(\) > 1[\s\S]*?return actions;/);
    assert.match(bridgeSource, /addProperty\("defenderKind", defenderIsPlayer \? "player" : "permanent"\)/);
  });

  it("waits for XMage payment prompts after cast_spell instead of short-timeout rejection", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    const directMethod = bridgeSource.match(/private boolean isDirectCommand[\s\S]*?private JsonObject snapshot/)?.[0] ?? "";

    assert.doesNotMatch(directMethod, /"cast_spell"\.equals\(type\)/);
    assert.match(bridgeSource, /long waitMs = isDirectCommand\(commandType\) \? 1500 : 6000/);
  });

  it("proxies Commander fixture creation to the bridge fixture endpoint with schema payload", async () => {
    const requests = [];
    const client = createHttpBridgeClient("http://bridge.test/", async (url, init) => {
      requests.push({ url, init });
      return new Response(JSON.stringify({ directStateSeeded: false, error: "xmage_fixture_state_seeding_unavailable" }), { status: 200 });
    });

    const body = await client.createCommanderFixtureGame({
      fixtureName: "commander-gauntlet",
      schemaVersion: 1,
      schema: { scenarioName: "commander-gauntlet", expectedRoutes: ["play_land"] }
    });

    assert.equal(body.directStateSeeded, false);
    assert.equal(requests[0].url, "http://bridge.test/dev/xmage-fixtures/commander");
    assert.equal(requests[0].init.method, "POST");
    const forwarded = JSON.parse(requests[0].init.body);
    assert.equal(forwarded.fixtureName, "commander-gauntlet");
    assert.equal(forwarded.schema.scenarioName, "commander-gauntlet");
    assert.deepEqual(forwarded.schema.expectedRoutes, ["play_land"]);
  });

  it("keeps XMage fixture harness disabled unless explicitly enabled outside production", async () => {
    assert.equal(xmageFixturesEnabled({}), false);
    assert.equal(xmageFixturesEnabled({ ENABLE_XMAGE_FIXTURES: "true", NODE_ENV: "production" }), false);
    assert.equal(xmageFixturesEnabled({ ENABLE_XMAGE_FIXTURES: "true", NODE_ENV: "test" }), true);

    const previousEnabled = process.env.ENABLE_XMAGE_FIXTURES;
    const previousNodeEnv = process.env.NODE_ENV;
    delete process.env.ENABLE_XMAGE_FIXTURES;
    delete process.env.NODE_ENV;
    try {
      const handler = createGatewayHandler(new Map(), { bridgeClient: { createCommanderGame: async () => bridgeSmokeSnapshot(1, 1) } });
      const response = await runHandler(handler, "/dev/xmage-fixtures/commander", "POST", { scenario: "commander-gauntlet" });
      assert.equal(response.status, 404);
      assert.equal(JSON.parse(response.body).error, "xmage_fixtures_disabled");
    } finally {
      restoreEnv("ENABLE_XMAGE_FIXTURES", previousEnabled);
      restoreEnv("NODE_ENV", previousNodeEnv);
    }
  });

  it("keeps the fixture route production-disabled even when ENABLE_XMAGE_FIXTURES is true", async () => {
    const previousEnabled = process.env.ENABLE_XMAGE_FIXTURES;
    const previousNodeEnv = process.env.NODE_ENV;
    process.env.ENABLE_XMAGE_FIXTURES = "true";
    process.env.NODE_ENV = "production";
    try {
      let bridgeCalled = false;
      const handler = createGatewayHandler(new Map(), {
        bridgeClient: {
          createCommanderFixtureGame: async () => {
            bridgeCalled = true;
            return bridgeSmokeSnapshot(1, 1);
          }
        }
      });
      const response = await runHandler(handler, "/dev/xmage-fixtures/commander", "POST", { scenario: "core-flow" });

      assert.equal(response.status, 404);
      assert.equal(JSON.parse(response.body).error, "xmage_fixtures_disabled");
      assert.equal(bridgeCalled, false);
    } finally {
      restoreEnv("ENABLE_XMAGE_FIXTURES", previousEnabled);
      restoreEnv("NODE_ENV", previousNodeEnv);
    }
  });

  it("does not create a deterministic deck fallback when the fixture bridge endpoint is missing", async () => {
    const previousEnabled = process.env.ENABLE_XMAGE_FIXTURES;
    const previousNodeEnv = process.env.NODE_ENV;
    process.env.ENABLE_XMAGE_FIXTURES = "true";
    process.env.NODE_ENV = "test";
    try {
      const state = new Map();
      let fallbackCreated = false;
      const bridgeClient = {
        createCommanderGame: async () => {
          fallbackCreated = true;
          return bridgeSmokeSnapshot(7, 20);
        }
      };
      const handler = createGatewayHandler(state, { bridgeClient });
      const response = await runHandler(handler, "/dev/xmage-fixtures/commander", "POST", {
        scenario: "commander-gauntlet",
        seed: "fixture-test"
      });
      const body = JSON.parse(response.body);

      assert.equal(response.status, 501);
      assert.equal(body.error, "xmage_fixture_bridge_endpoint_missing");
      assert.equal(body.enabled, true);
      assert.equal(body.fixtureName, "commander-gauntlet");
      assert.equal(body.productionDisabled, true);
      assert.equal(body.directStateSeeded, false);
      assert.equal(body.setupMethod, "bridge_fixture_endpoint_missing");
      assert.equal(body.gameId, null);
      assert.equal(body.source, "xmage-gateway");
      assert.deepEqual(body.seededZones, []);
      assert.match(body.nextImplementationStep, /XMage server process/);
      assert.equal(fallbackCreated, false);
      assert.equal(state.size, 0);
    } finally {
      restoreEnv("ENABLE_XMAGE_FIXTURES", previousEnabled);
      restoreEnv("NODE_ENV", previousNodeEnv);
    }
  });

  it("propagates the bridge fixture blocked report without falling back", async () => {
    const previousEnabled = process.env.ENABLE_XMAGE_FIXTURES;
    const previousNodeEnv = process.env.NODE_ENV;
    process.env.ENABLE_XMAGE_FIXTURES = "true";
    process.env.NODE_ENV = "test";
    try {
      let fallbackCreated = false;
      const bridgeClient = createHttpBridgeClient("http://bridge.test", async (_url, init) => {
        assert.equal(init.method, "POST");
        return new Response(
          JSON.stringify({
            error: "xmage_fixture_state_seeding_unavailable",
            enabled: true,
            fixtureName: "commander-gauntlet",
            schemaVersion: 1,
            productionDisabled: true,
            directStateSeeded: false,
            setupMethod: "blocked_remote_session_client",
            gameId: null,
            source: "xmage-java-bridge",
            bridgeRevision: null,
            xmageCycle: null,
            seededZones: [],
            blockedReason: "MagicMobileBridge runs as a mage.remote.Session client in a separate JVM from mage.server.game.GameController.",
            classProcessBoundary: "MagicMobileBridge JVM -> separate XMage server JVM.",
            nextImplementationStep: "Add a dev/test-only fixture service inside the XMage server process."
          }),
          { status: 501 }
        );
      });
      bridgeClient.createCommanderGame = async () => {
        fallbackCreated = true;
        return bridgeSmokeSnapshot(7, 20);
      };
      const handler = createGatewayHandler(new Map(), { bridgeClient });
      const response = await runHandler(handler, "/dev/xmage-fixtures/commander", "POST", {
        scenario: "commander-gauntlet"
      });
      const body = JSON.parse(response.body);

      assert.equal(response.status, 501);
      assert.equal(body.error, "xmage_fixture_state_seeding_unavailable");
      assert.equal(body.source, "xmage-java-bridge");
      assert.equal(body.directStateSeeded, false);
      assert.match(body.blockedReason, /separate JVM/);
      assert.equal(fallbackCreated, false);
    } finally {
      restoreEnv("ENABLE_XMAGE_FIXTURES", previousEnabled);
      restoreEnv("NODE_ENV", previousNodeEnv);
    }
  });

  it("returns a fixture-created snapshot only when direct state seeding is proven", async () => {
    const previousEnabled = process.env.ENABLE_XMAGE_FIXTURES;
    const previousNodeEnv = process.env.NODE_ENV;
    process.env.ENABLE_XMAGE_FIXTURES = "true";
    process.env.NODE_ENV = "test";
    try {
      const state = new Map();
      let forwardedFixture;
      const handler = createGatewayHandler(state, {
        bridgeClient: {
          createCommanderFixtureGame: async (fixture) => {
            forwardedFixture = fixture;
            return {
              fixtureHarness: {
                directStateSeeded: true,
                setupMethod: "server_side_fixture_service",
                source: "xmage-java-bridge",
                reason: "seeded in XMage server process"
              },
              snapshot: fixtureProofSnapshot()
            };
          }
        }
      });
      const response = await runHandler(handler, "/dev/xmage-fixtures/commander", "POST", fixtureProofRequest());
      const body = JSON.parse(response.body);

      assert.equal(response.status, 201);
      assert.equal(body.source, "xmage-java-bridge");
      assert.equal(body.fixtureHarness.directStateSeeded, true);
      assert.equal(body.fixtureHarness.setupMethod, "server_side_fixture_service");
      assert.deepEqual(body.fixtureHarness.seededZones.sort(), [
        "ai-1.aiBattlefield",
        "human.battlefield",
        "human.commandZone",
        "human.hand",
        "human.libraryTop"
      ]);
      assert.equal(state.get(body.id).fixtureHarness.directStateSeeded, true);
      assert.equal(forwardedFixture.schema.scenarioName, "commander-gauntlet");
      assert.deepEqual(forwardedFixture.schema.hand, ["Sol Ring"]);
      assert.deepEqual(forwardedFixture.schema.expectedRoutes, ["play_land", "cast_spell"]);
    } finally {
      restoreEnv("ENABLE_XMAGE_FIXTURES", previousEnabled);
      restoreEnv("NODE_ENV", previousNodeEnv);
    }
  });

  it("does not treat a fixture response as gameplay success when seeded proof is missing", async () => {
    const previousEnabled = process.env.ENABLE_XMAGE_FIXTURES;
    const previousNodeEnv = process.env.NODE_ENV;
    process.env.ENABLE_XMAGE_FIXTURES = "true";
    process.env.NODE_ENV = "test";
    try {
      const state = new Map();
      const handler = createGatewayHandler(state, {
        bridgeClient: {
          createCommanderFixtureGame: async () => ({
            fixtureHarness: {
              directStateSeeded: true,
              setupMethod: "server_side_fixture_service",
              source: "xmage-java-bridge"
            },
            snapshot: fixtureProofSnapshot({ omitHand: true })
          })
        }
      });
      const response = await runHandler(handler, "/dev/xmage-fixtures/commander", "POST", fixtureProofRequest());
      const body = JSON.parse(response.body);

      assert.equal(response.status, 503);
      assert.equal(body.error, "xmage_fixture_state_seeding_unavailable");
      assert.equal(body.directStateSeeded, false);
      assert.equal(body.fixtureHarness.directStateSeeded, false);
      assert.match(body.blockedReason, /without matching requested seed proof/);
      assert.equal(body.latestSnapshot.source, "xmage-java-bridge");
      assert.equal(state.size, 0);
    } finally {
      restoreEnv("ENABLE_XMAGE_FIXTURES", previousEnabled);
      restoreEnv("NODE_ENV", previousNodeEnv);
    }
  });

  it("builds fixture configs with legal Commander singleton proof decks", () => {
    const fixture = commanderFixtureConfig("commander-gauntlet", { seed: "unit" });
    const entries = fixture.config.humanDeck.entries;

    assert.equal(fixture.schema.format, "commander");
    assert.equal(fixture.schema.scenarioName, "commander-gauntlet");
    assert.deepEqual(fixture.schema.playerIds, { human: "human", ai: ["ai-1"] });
    assert.deepEqual(fixture.schema.commandZone, ["Loran of the Third Path"]);
    assert.deepEqual(fixture.schema.expectedRoutes, fixture.schema.expectedRouteCoverage);
    assert.equal(fixture.config.humanDeck.commander.cardName, "Loran of the Third Path");
    assert.equal(entries.find((entry) => entry.cardName === "Sol Ring").quantity, 1);
    assert.equal(entries.find((entry) => entry.cardName === "Evolving Wilds").quantity, 1);
    assert.equal(entries.find((entry) => entry.cardName === "Plains").quantity, 93);
    assert.equal(fixture.schema.expectedRouteCoverage.includes("commander_replacement"), true);
  });

  it("builds activated-ability stack fixtures with a legal singleton proof permanent", () => {
    const fixture = commanderFixtureConfig("activated-ability-stack", { seed: "unit" });
    const entries = fixture.config.humanDeck.entries;

    assert.equal(fixture.schema.scenarioName, "activated-ability-stack");
    assert.equal(fixture.config.humanDeck.commander.cardName, "Isamaru, Hound of Konda");
    assert.equal(entries.find((entry) => entry.cardName === "Seal of Cleansing").quantity, 1);
    assert.equal(entries.find((entry) => entry.cardName === "Sol Ring").quantity, 1);
    assert.equal(entries.find((entry) => entry.cardName === "Plains").quantity, 97);
    assert.equal(fixture.schema.expectedRouteCoverage.includes("activate_ability"), true);
    assert.equal(fixture.schema.expectedRouteCoverage.includes("stack_objects"), true);
  });

  it("builds mana-rock fixtures with a legal singleton proof rock", () => {
    const fixture = commanderFixtureConfig("mana-rock", { seed: "unit" });
    const entries = fixture.config.humanDeck.entries;

    assert.equal(fixture.schema.scenarioName, "mana-rock");
    assert.equal(fixture.config.humanDeck.commander.cardName, "Isamaru, Hound of Konda");
    assert.equal(entries.find((entry) => entry.cardName === "Sol Ring").quantity, 1);
    assert.equal(entries.find((entry) => entry.cardName === "Plains").quantity, 98);
  });

  it("builds prompt-pile fixtures with a legal singleton proof spell", () => {
    const fixture = commanderFixtureConfig("prompt-pile", { seed: "unit" });
    const entries = fixture.config.humanDeck.entries;

    assert.equal(fixture.schema.scenarioName, "prompt-pile");
    assert.equal(fixture.config.humanDeck.commander.cardName, "Kenrith, the Returned King");
    assert.equal(entries.find((entry) => entry.cardName === "Fact or Fiction").quantity, 1);
    assert.equal(entries.find((entry) => entry.cardName === "Island").quantity, 98);
    assert.equal(fixture.schema.expectedRouteCoverage.includes("choose_pile"), true);
  });

  it("keeps the fixture smoke gate report-shaped and fail-fast", () => {
    const smokeSource = readFileSync(new URL("./scripts/smoke-create-commander-game.ts", import.meta.url), "utf8");

    assert.match(smokeSource, /build_output", "smoke"/);
    assert.match(smokeSource, /case "fixture-smoke"/);
    assert.match(smokeSource, /function fixtureEnvCheck/);
    assert.match(smokeSource, /failedStep: "deterministic-fixture-unavailable"/);
    assert.match(smokeSource, /directStateSeeded/);
    assert.match(smokeSource, /seededStateVerified/);
    assert.match(smokeSource, /verifySeededStateFromSnapshot/);
    assert.match(smokeSource, /recordFixtureOpeningPromptCoverage/);
    assert.match(smokeSource, /pre_seed_opening_prompt:choose_player/);
    assert.match(smokeSource, /a\.type === "keep_hand"/);
    assert.match(
      smokeSource,
      /const yesNo = snapshot\.legalActions\.find\(a =>\s+a\.type === "answer_yes_no" \|\|\s+a\.type === "commander_replacement" \|\|\s+a\.type === "pay_cost"\s+\);/
    );
  });

  it("keeps commander gauntlet smoke reports route-family based with direct seed proof", () => {
    const smokeSource = readFileSync(new URL("./scripts/smoke-create-commander-game.ts", import.meta.url), "utf8");

    assert.match(smokeSource, /routeFamiliesRequired/);
    assert.match(smokeSource, /routeFamiliesSeen/);
    assert.match(smokeSource, /directStateSeeded/);
    assert.match(smokeSource, /seededStateVerified/);
    assert.match(smokeSource, /fixtureCallRequired/);
    assert.match(smokeSource, /scenario === "prompt-variety"/);
    assert.match(smokeSource, /activated-ability-stack/);
    assert.match(smokeSource, /triggered-ability-stack/);
    assert.match(smokeSource, /activatedAbilityFixtureDeck/);
    assert.match(smokeSource, /triggeredAbilityFixtureDeck/);
    assert.match(smokeSource, /promptPileFixtureDeck/);
    assert.match(smokeSource, /Seal of Cleansing/);
    assert.match(smokeSource, /Isamaru, Hound of Konda/);
    assert.match(smokeSource, /Spirited Companion/);
    assert.match(smokeSource, /Fact or Fiction/);
    assert.match(smokeSource, /promptPileChoiceResolved/);
    assert.match(smokeSource, /function isGameOverSnapshot/);
    assert.match(smokeSource, /Game ended: XMage reported GAME_OVER/);
    for (const family of [
      "play_land",
      "cast_spell",
      "make_mana",
      "activate_ability",
      "choose_ability",
      "choose_mode",
      "choose_amount",
      "choose_multi_amount",
      "choose_pile",
      "search_select",
      "choose_card",
      "choose_target",
      "answer_yes_no",
      "pay_cost",
      "commander_replacement",
      "pass_priority",
      "order_triggers",
      "order_items",
      "stack_object_seen",
      "trigger_seen",
      "zone_update_seen",
      "commander_tax_seen"
    ]) {
      assert.ok(smokeSource.includes(family), `missing gauntlet route family ${family}`);
    }
    assert.doesNotMatch(smokeSource, /promptChecks\.length\s*>=\s*3[\s\S]*?prompt-variety/);
  });

  it("keeps the iOS stack peek visible enough for priority decisions", () => {
    const contentView = readFileSync(new URL("../ios/MagicMobile/ContentView.swift", import.meta.url), "utf8");

    assert.match(contentView, /XmageStackPeek\(/);
    assert.match(contentView, /legalActions: snapshot\.legalActions \?\? \[\]/);
    assert.match(contentView, /promptText: snapshot\.promptEnvelopeV2\?\.message \?\? snapshot\.promptText/);
    assert.ok(contentView.includes('Text("\\(objects.count)")'));
    assert.match(contentView, /RESPOND/);
    assert.match(contentView, /topDisplayCard/);
    assert.match(contentView, /CardTile\(card: card, selected:/);
  });

  it("keeps iOS mana payment source actions on battlefield cards instead of tray buttons", () => {
    const contentView = readFileSync(new URL("../ios/MagicMobile/ContentView.swift", import.meta.url), "utf8");
    const trayStart = contentView.indexOf("struct ManaPaymentTray");
    const trayEnd = contentView.indexOf("struct BattlefieldRow");
    const traySource = contentView.slice(trayStart, trayEnd);
    const battlefieldSource = contentView.slice(trayEnd);

    assert.ok(trayStart > 0, "missing ManaPaymentTray");
    assert.ok(trayEnd > trayStart, "missing BattlefieldRow after ManaPaymentTray");
    assert.match(traySource, /Text\("Pay cost"\)/);
    assert.doesNotMatch(traySource, /ForEach\(sourceManaActions/);
    assert.doesNotMatch(traySource, /sourceCardName\(for: action\)/);
    assert.doesNotMatch(traySource, /Text\(spellName\)/);
    assert.match(battlefieldSource, /tapRunnableActionTypes/);
    assert.match(battlefieldSource, /"make_mana"/);
    assert.match(battlefieldSource, /"undo_mana"/);
    assert.match(battlefieldSource, /runAction\(action\)/);
  });

  it("rejects stale bridge snapshots by revision", () => {
    assert.equal(shouldAcceptSnapshot({ bridgeRevision: 3 }, { bridgeRevision: 2 }), false);
    assert.equal(shouldAcceptSnapshot({ bridgeRevision: 3 }, { bridgeRevision: 3 }), true);
    assert.equal(shouldAcceptSnapshot({ bridgeRevision: 3 }, { bridgeRevision: 4 }), true);
  });

  it("broadcasts command-response snapshots to websocket listeners", async () => {
    const state = new Map();
    const snapshot = { id: "bridge-game-1", source: "xmage-java-bridge", bridgeRevision: 1 };
    state.set(snapshot.id, snapshot);
    let sentPayload = "";
    const socket = {
      readyState: 1,
      send(payload) {
        sentPayload = payload;
      },
      on() {}
    };
    registerWebSocketConnection(snapshot.id, socket);
    const handler = createGatewayHandler(state, {
      bridgeClient: {
        submitCommand: async () => ({ ...snapshot, bridgeRevision: 2, promptText: "Your priority" })
      }
    });
    const response = await runHandler(
      handler,
      `/games/${snapshot.id}/commands`,
      "POST",
      { type: "keep_hand", gameId: snapshot.id, playerId: "human" }
    );

    assert.equal(response.status, 200);
    assert.equal(JSON.parse(sentPayload).bridgeRevision, 2);
  });

  it("forwards prompt command metadata unchanged to the Java bridge", async () => {
    const state = new Map();
    const snapshot = {
      id: "bridge-game-prompt",
      source: "xmage-java-bridge",
      bridgeRevision: 4,
      legalActions: []
    };
    state.set(snapshot.id, snapshot);
    let forwardedCommand;
    const handler = createGatewayHandler(state, {
      bridgeClient: {
        submitCommand: async (_gameId, command) => {
          forwardedCommand = command;
          return {
            ...snapshot,
            bridgeRevision: 5,
            pendingStatus: "waiting_for_xmage",
            legalActions: [
              { id: "stale-pass", type: "pass_priority", playerId: "human", label: "Done" },
              { id: "stale-cast", type: "cast_spell", playerId: "human", label: "Cast spell" },
              { id: "safe-concede", type: "concede", playerId: "human", label: "Concede" }
            ]
          };
        }
      }
    });

    const command = {
      type: "choose_target",
      gameId: snapshot.id,
      playerId: "human",
      promptId: "xmage-prompt-7",
      messageId: 7,
      expectedBridgeRevision: 4,
      targetIds: ["target-1"],
      commandTemplate: {
        type: "choose_target",
        promptId: "xmage-prompt-7",
        messageId: 7,
        targetIds: ["target-1"]
      }
    };
    const response = await runHandler(handler, `/games/${snapshot.id}/commands`, "POST", command);

    assert.equal(response.status, 200);
    assert.deepEqual(forwardedCommand, command);
    assert.equal(state.get(snapshot.id).bridgeRevision, 5);
    const body = JSON.parse(response.body);
    assert.equal(body.pendingStatus, "waiting_for_xmage");
    assert.deepEqual(body.legalActions.map((action) => action.type), ["concede"]);
    assert.deepEqual(state.get(snapshot.id).legalActions.map((action) => action.type), ["concede"]);
  });

  it("forwards a bridge smoke loop and stores revised XMage snapshots", async () => {
    const state = new Map();
    const commands = [];
    let bridgeSnapshot = bridgeSmokeSnapshot(1, 10, "mulligan", [
      { id: "xmage-keep", type: "keep_hand", playerId: "human", label: "Keep", shortLabel: "Keep" }
    ]);
    const bridgeClient = {
      createCommanderGame: async () => bridgeSnapshot,
      getSnapshot: async () => bridgeSnapshot,
      submitCommand: async (_gameId, command) => {
        commands.push(command);
        const nextRevision = bridgeSnapshot.bridgeRevision + 1;
        const nextCycle = bridgeSnapshot.xmageCycle + 1;
        if (command.type === "cast_spell") {
          bridgeSnapshot = {
            ...bridgeSmokeSnapshot(nextRevision, nextCycle, "choose_target", [
              {
                id: "xmage-choice-ai-1",
                type: "choose_target",
                playerId: "human",
                label: "Choose AI Normal",
                shortLabel: "Choose",
                targetIds: ["ai-1"],
                validTargetIds: ["ai-1"],
                responseKind: "choose_target"
              },
              { id: "xmage-pass", type: "pass_priority", playerId: "human", label: "Done", shortLabel: "Done" }
            ]),
            promptEnvelopeV2: {
              id: "xmage-prompt-1",
              method: "GAME_TARGET",
              messageId: 1,
              playerId: "human",
              responseKind: "target",
              message: "Choose target",
              required: true,
              minChoices: 1,
              maxChoices: 1,
              responseCommand: { type: "choose_target", promptId: "xmage-prompt-1" }
            }
          };
          return bridgeSnapshot;
        }
        bridgeSnapshot = bridgeSmokeSnapshot(nextRevision, nextCycle, "priority", [
          { id: "xmage-land", type: "play_land", playerId: "human", label: "Play Forest", cardInstanceId: "forest-1" },
          {
            id: "xmage-mana",
            type: "make_mana",
            playerId: "human",
            label: "Tap Forest",
            cardInstanceId: "forest-1",
            sourceInstanceId: "forest-1",
            abilityId: "mana-1"
          },
          {
            id: "xmage-spell",
            type: "cast_spell",
            playerId: "human",
            label: "Cast Llanowar Elves",
            cardInstanceId: "elves-1"
          },
          { id: "xmage-pass", type: "pass_priority", playerId: "human", label: "Done", shortLabel: "Done" }
        ]);
        return bridgeSnapshot;
      }
    };
    const handler = createGatewayHandler(state, { bridgeClient });

    const created = await runHandler(handler, "/games/commander", "POST", { roomId: "bridge-smoke" });
    assert.equal(created.status, 201);
    const initialSnapshot = JSON.parse(created.body);
    assert.equal(initialSnapshot.bridgeRevision, 1);
    assert.equal(initialSnapshot.xmageCycle, 10);

    let choicePromptSnapshot;
    for (const type of ["keep_hand", "play_land", "make_mana", "cast_spell", "pass_priority"]) {
      const current = state.get(initialSnapshot.id);
      const action = current.legalActions.find((candidate) => candidate.type === type);
      assert.ok(action, `missing ${type} action`);
      const response = await runHandler(handler, `/games/${initialSnapshot.id}/commands`, "POST", {
        type,
        gameId: initialSnapshot.id,
        playerId: action.playerId,
        cardInstanceId: action.cardInstanceId,
        sourceInstanceId: action.sourceInstanceId,
        abilityId: action.abilityId
      });
      assert.equal(response.status, 200);
      if (type === "cast_spell") {
        choicePromptSnapshot = JSON.parse(response.body);
      }
    }

    assert.deepEqual(commands.map((command) => command.type), [
      "keep_hand",
      "play_land",
      "make_mana",
      "cast_spell",
      "pass_priority"
    ]);
    assert.equal(choicePromptSnapshot.promptEnvelopeV2.method, "GAME_TARGET");
    assert.deepEqual(choicePromptSnapshot.xmage.callbackCoverage, ["GAME_TARGET"]);
    assert.equal(state.get(initialSnapshot.id).bridgeRevision, 6);
    assert.equal(state.get(initialSnapshot.id).xmageCycle, 15);

    const snapshotResponse = await runHandler(handler, `/games/${initialSnapshot.id}`);
    assert.equal(snapshotResponse.status, 200);
    assert.equal(JSON.parse(snapshotResponse.body).bridgeRevision, 6);

    const debugResponse = await runHandler(handler, `/games/${initialSnapshot.id}/debug`);
    const debug = JSON.parse(debugResponse.body);
    assert.equal(debug.bridgeRevision, 6);
    assert.equal(debug.xmageCycle, 15);
  });

  it("exposes bridge protocol debug state with rich XMage payload coverage", async () => {
    const state = new Map();
    const snapshot = {
      id: "bridge-game-debug",
      source: "xmage-java-bridge",
      bridgeRevision: 7,
      promptEnvelopeV2: {
        id: "xmage-prompt-44",
        method: "GAME_TARGET",
        messageId: 44,
        playerId: "human",
        responseKind: "target",
        message: "Choose target",
        required: true,
        minChoices: 1,
        maxChoices: 1,
        responseCommand: { type: "choose_target", promptId: "xmage-prompt-44" }
      },
      xmage: {
        schemaVersion: 1,
        gameId: "bridge-game-debug",
        callbackCoverage: ["GAME_TARGET"],
        stack: [{
          id: "stack-1",
          name: "Lightning Bolt",
          sourceInstanceId: "stack-1",
          sourceName: "Lightning Bolt",
          sourceZone: "stack",
          controllerId: "human",
          targetIds: ["ai-1"],
          rulesText: "Lightning Bolt deals 3 damage to any target.",
          paid: true
        }],
        players: [
          {
            playerId: "human",
            command: [{ id: "cmd-1", name: "Ezuri, Claw of Progress", zone: "command" }],
            zones: { graveyard: [], exile: [], sideboard: [] },
            manaPool: { W: 0, U: 0, B: 0, R: 0, G: 0, C: 0 }
          }
        ],
        panels: {
          stack: true,
          command: true,
          graveyard: true,
          exile: true,
          revealed: true,
          lookedAt: true,
          search: true
        }
      }
    };
    state.set(snapshot.id, snapshot);
    const handler = createGatewayHandler(state, { bridgeClient: null });

    const response = await runHandler(handler, `/games/${snapshot.id}/debug`);

    assert.equal(response.status, 200);
    const body = JSON.parse(response.body);
    assert.equal(body.gameId, snapshot.id);
    assert.equal(body.bridgeRevision, 7);
    assert.deepEqual(body.callbackCoverage, ["GAME_TARGET"]);
    assert.equal(body.prompt.method, "GAME_TARGET");
    assert.equal(body.xmage.stack[0].rulesText, "Lightning Bolt deals 3 damage to any target.");
    assert.equal(body.xmage.stack[0].sourceInstanceId, "stack-1");
    assert.equal(body.xmage.stack[0].sourceName, "Lightning Bolt");
    assert.equal(body.xmage.stack[0].sourceZone, "stack");
    assert.equal(body.xmage.stack[0].controllerId, "human");
    assert.deepEqual(body.xmage.stack[0].targetIds, ["ai-1"]);
    assert.equal(body.xmage.stack[0].paid, true);
    assert.equal(body.xmage.panels.command, true);
  });

  it("keeps Java bridge prompt commands prompt-aware instead of first-choice fallbacks", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /currentPromptForCommand/);
    assert.match(bridgeSource, /ClientCallbackMethod\.START_GAME[\s\S]*?session\.joinGame\(message\.getGameId\(\)\)/);
    assert.match(bridgeSource, /validatePromptSelections/);
    assert.match(bridgeSource, /requiredBooleanResponse/);
    assert.match(bridgeSource, /prompt\.add\("manaChoices"/);
    assert.match(bridgeSource, /manaChoicesForPrompt\(callback\.getObjectId\(\), message\)/);
    assert.match(bridgeSource, /availableManaSymbols\(UUID gameId, GameView view\)/);
    assert.match(bridgeSource, /symbols\.addAll\(available\)/);
    assert.match(bridgeSource, /available\.contains\(symbol\)/);
    const sendPromptUuids = bridgeSource.match(/private void sendPromptUuids[\s\S]*?\n    private void sendPromptStringsOrUuids/)?.[0] ?? "";
    assert.doesNotMatch(sendPromptUuids, /session\.sendPlayerBoolean\(xmageGameId, true\)/);
    assert.match(bridgeSource, /prompt\.add\("confirmation"/);
    assert.match(bridgeSource, /prompt\.add\("orderedItems"/);
    assert.match(bridgeSource, /prompt\.add\("players"/);
    assert.match(bridgeSource, /players\.size\(\) > 0 && targets\.size\(\) == 0/);
    assert.match(bridgeSource, /prompt\.addProperty\("responseKind", "player"\)/);
    assert.match(bridgeSource, /responseCommand\.addProperty\("type", "choose_player"\)/);
    assert.match(bridgeSource, /"choose_player"\.equals\(type\)[\s\S]*?selectionIds\(command, "playerIds", "choiceId", "choiceIds", "choiceId"\)/);
    assert.doesNotMatch(bridgeSource, /"choose_player"\.equals\(type\)[\s\S]*?selectionIds\(command, "playerIds", "playerId", "choiceIds", "choiceId"\)/);
    assert.match(bridgeSource, /expectedBridgeRevision/);
    assert.match(bridgeSource, /pendingLegalActions/);
    assert.match(bridgeSource, /pendingStatus == null \? legalActions\(record, view, playerIds\) : pendingLegalActions\(record\)/);
    assert.match(bridgeSource, /if \(isGameOverPrompt\(record\)\)[\s\S]*?xmage-concede[\s\S]*?return actions;/);
    assert.match(bridgeSource, /isOptionalPrompt\(prompt\) && !hasExplicitBooleanResponse\(command, "value"\)/);
    assert.match(bridgeSource, /boolean response = requiredBooleanResponse\(gameId, command, "value"\);/);
    assert.match(bridgeSource, /isManaPaymentPrompt\(record\)/);
    assert.match(bridgeSource, /"pay_cost"\.equals\(responseKind\)/);
    assert.match(bridgeSource, /"pay_cost"\.equals\(responseType\)/);
    assert.match(bridgeSource, /"choose_mana"\.equals\(responseType\)/);
    assert.match(bridgeSource, /addPlayableObjectActions\(actions, humanId, view, true\)/);
    assert.match(bridgeSource, /String type = manaOnly \? "make_mana" : actionType\(card, handIds\.contains\(objectId\), inCommand\)/);
    assert.match(bridgeSource, /boolean playableFromHiddenZone = handIds\.contains\(objectId\) \|\| inCommand;/);
    assert.match(bridgeSource, /String abilityType = manaOnly \|\| \(!playableFromHiddenZone && isManaAbility\(card, abilityLabel\)\)\s*\?\s*"make_mana"\s*:\s*actionType\(card, handIds\.contains\(objectId\), inCommand, false\)/);
    assert.match(bridgeSource, /private String actionType\(CardView card, boolean inHand, boolean inCommand, boolean landManaDefault\)/);
    assert.match(bridgeSource, /if \(landManaDefault && card\.isLand\(\)\) \{\s*return "make_mana";\s*\}/);
    assert.doesNotMatch(bridgeSource, /private boolean hasManaPlayable[\s\S]*?card\.isLand\(\) \|\| producedManaHint/);
    assert.match(bridgeSource, /Set<UUID> commandIds = commandIds\(view\);/);
    assert.match(bridgeSource, /String sourceZone = handIds\.contains\(objectId\) \? "hand" : inCommand \? "command" : "battlefield";/);
    assert.match(bridgeSource, /yesCommand\.addProperty\("pay", true\)/);
    assert.match(bridgeSource, /noCommand\.addProperty\("pay", false\)/);
    assert.match(bridgeSource, /Action was based on stale XMage snapshot revision/);
    assert.match(bridgeSource, /int startCycle = record == null \? -1 : record\.latestCycle;/);
    assert.match(bridgeSource, /record\.bridgeRevision\.get\(\) > startRevision \|\| record\.latestCycle > startCycle/);
    assert.match(bridgeSource, /"cast_spell"\.equals\(type\)\) \{[\s\S]*?retryableUuid = playableSourceUuid\(gameId, command\);[\s\S]*?session\.sendPlayerUUID\(xmageGameId, retryableUuid\);/);
    assert.match(bridgeSource, /"make_mana"\.equals\(type\)\) \{[\s\S]*?session\.sendPlayerUUID\(xmageGameId, playableSourceUuid\(gameId, command\)\);/);
    assert.match(bridgeSource, /"activate_ability"\.equals\(type\)\) \{[\s\S]*?playableCommandUuid\(gameId, command\);[\s\S]*?session\.sendPlayerUUID\(xmageGameId, playableSourceUuid\(gameId, command\)\);/);
    const sendCombatSelection = bridgeSource.match(/private void sendCombatSelection[\s\S]*?\n    private JsonObject waitForUpdatedSnapshot/)?.[0] ?? "";
    assert.match(sendCombatSelection, /session\.sendPlayerUUID\(xmageGameId, UUID\.fromString\(value\)\);/);
    assert.doesNotMatch(sendCombatSelection, /session\.sendPlayerBoolean\(xmageGameId, true\)/);
    assert.match(sendCombatSelection, /session\.sendPlayerBoolean\(xmageGameId, false\);/);
    assert.match(bridgeSource, /stackObjects\(view\.getStack\(\), view, playerIds\)/);
    assert.match(bridgeSource, /resolveStackSourceCard\(card, view\)/);
    assert.match(bridgeSource, /item\.addProperty\("objectId", card\.getId\(\)\.toString\(\)\)/);
    assert.match(bridgeSource, /item\.addProperty\("objectType", stackObjectType\(card\)\)/);
    assert.match(bridgeSource, /item\.addProperty\("sourceCardUnavailableReason"/);
    assert.match(bridgeSource, /optionalUuidProperty\(card, "getControllerId", "getController", "getOwnerId", "getOwner"\)/);
    assert.match(bridgeSource, /item\.addProperty\("controllerId", playerIds\.getOrDefault\(controllerId, controllerId\.toString\(\)\)\)/);
    assert.match(bridgeSource, /optionalTargetIds\(card, playerIds\)/);
    assert.doesNotMatch(bridgeSource, /sendFirstUuid/);
    assert.doesNotMatch(bridgeSource, /sendFirstStringOrUuid/);
    assert.equal(bridgeSource.includes('session.sendPlayerBoolean(xmageGameId, booleanResponse(command, "useCommandZone", true));'), false);
    assert.equal(bridgeSource.includes('session.sendPlayerBoolean(xmageGameId, booleanResponse(command, "pay", true));'), false);
    assert.equal(bridgeSource.includes('session.sendPlayerBoolean(xmageGameId, booleanResponse(command, "confirmed", true));'), false);
  });

  it("records startup opening prompts for starting-player diagnosis", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /startupOpeningPrompts/);
    assert.match(bridgeSource, /recordStartupOpeningPrompt/);
    assert.match(bridgeSource, /snapshot\.add\("startupOpeningPrompts"/);
  });

  it("normalizes startup player choices to display names before iOS sees them", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /normalizePlayerPromptChoices\(prompt, record, message\.getGameView\(\)\)/);
    assert.match(bridgeSource, /labelForChoice\(record, playerIds, choiceId\)/);
    assert.match(bridgeSource, /record\.humanName \+ " starts"/);
    assert.match(bridgeSource, /record\.aiName \+ " starts"/);
    assert.doesNotMatch(bridgeSource, /choice\.addProperty\("label", choiceId\)/);
  });

  it("handles starting-player opening choices before keep or mulligan actions", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    const method = bridgeSource.match(/private JsonObject fixtureOpeningAction[\s\S]*?\n    private JsonObject findOpeningChoice/)?.[0] ?? "";

    assert.ok(
      method.indexOf("JsonObject startingPlayer = findOpeningChoice(actions)") < method.indexOf('JsonObject keep = findAction(actions, "keep_hand", "")'),
      "starting-player prompt must be checked before keep_hand"
    );
  });

  it("keeps XMage fixtures inside the server JVM with snapshot proof gates", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    const embeddedSource = readFileSync(new URL("./bridge/MagicMobileEmbeddedServerBridge.java", import.meta.url), "utf8");
    const startSource = readFileSync(new URL("./bridge/start.sh", import.meta.url), "utf8");

    assert.match(startSource, /MagicMobileEmbeddedServerBridge/);
    assert.match(bridgeSource, /if \(!fixturesEnabled\(\)\) \{[\s\S]*?xmage_fixtures_disabled[\s\S]*?writeJson\(exchange, 404, body\)/);
    assert.match(bridgeSource, /"true"\.equalsIgnoreCase\(env\("ENABLE_XMAGE_FIXTURES", "false"\)\)/);
    assert.match(bridgeSource, /!"production"\.equalsIgnoreCase\(nodeEnv\)/);
    assert.match(embeddedSource, /mage\.server\.Main\.main\(args\)/);
    assert.match(embeddedSource, /setFixtureManagerProvider/);
    assert.match(bridgeSource, /seedFixtureInServerProcess\(seedRequest, provider\.get\(\)\)/);
    assert.match(bridgeSource, /seedFixtureInServerProcess\(JsonObject request, ManagerFactory managerFactory\)/);
    assert.match(bridgeSource, /managerFactory\.gameManager\(\)\.getGameController\(\)\.get\(gameId\)/);
    assert.match(bridgeSource, /game\.cheat\(humanPlayerId/);
    assert.match(bridgeSource, /if \("keep_hand"\.equals\(type\) \|\| "mulligan"\.equals\(type\)\) \{\s*return;\s*\}/);
    assert.match(bridgeSource, /snapshotContainsProof/);
    assert.match(bridgeSource, /waitForFixtureProofSnapshot\(gameId, startRevision, startCycle, proofCardNames\)/);
    assert.match(bridgeSource, /directStateSeeded = snapshotAdvanced && proofFound/);
    assert.doesNotMatch(bridgeSource, /directStateSeeded", true\);[\s\S]{0,240}return report/);
  });

  it("keeps Java bridge fail-closed for prompt routes instead of route defaults", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /int pile = requiredPile\(command, gameId\);/);
    assert.match(bridgeSource, /int amount = requiredAmountFromCommand\(command, "amount", gameId\);/);
    assert.match(bridgeSource, /manaTypeFromRequiredSymbol\(gameId, manaChoice\)/);
    assert.match(bridgeSource, /sendEmptyPromptSelection\(gameId, xmageGameId, prompt\);[\s\S]*?validatePromptSelections\(gameId, prompt, singletonSelection\(abilityId\)\);/);
    assert.match(bridgeSource, /Duplicate selection for active XMage prompt/);
    assert.match(bridgeSource, /Selection is disabled for active XMage prompt/);
    assert.match(bridgeSource, /Amount is not valid for active XMage prompt/);
    assert.match(bridgeSource, /Missing explicit boolean response/);
    assert.match(bridgeSource, /requiresPromptIdentity\(type\) && !activePromptId\.isEmpty\(\) && requestedPromptId\.isEmpty\(\)/);
    assert.match(bridgeSource, /requiresPromptIdentity\(type\) && activeMessageId >= 0 && requestedMessageId < 0/);
    assert.match(bridgeSource, /XMage prompt is no longer active: /);
    assert.match(bridgeSource, /XMage prompt message is no longer active: /);
    assert.match(bridgeSource, /Action was based on stale XMage snapshot revision/);

    assert.doesNotMatch(bridgeSource, /integer\(command, "pile", 1\)/);
    assert.doesNotMatch(bridgeSource, /amountFromCommand\(command, "amount", 0\)/);
    assert.doesNotMatch(bridgeSource, /manaChoice\.isEmpty\(\) \? "C" : manaChoice/);
    assert.doesNotMatch(bridgeSource, /abilityId\.isEmpty\(\) \? null : UUID\.fromString\(abilityId\)/);
    assert.doesNotMatch(bridgeSource, /booleanResponse\(command, "value", true\)/);
  });

  it("cleans XMage HTML and hint markup before exposing card text", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.equal(bridgeSource.includes("&lt;"), true);
    assert.equal(bridgeSource.includes("<br\\\\s*/?>"), true);
    assert.equal(bridgeSource.includes("<hintstart>.*?(<hintend>|$)"), true);
    assert.equal(bridgeSource.includes("ICON_[A-Z_]+"), true);
  });

  it("rejects older bridgeRevisions or equal revisions with older xmageCycles", () => {
    const current = { bridgeRevision: 10, xmageCycle: 5 };
    assert.equal(shouldAcceptSnapshot(current, { bridgeRevision: 9, xmageCycle: 5 }), false);
    assert.equal(shouldAcceptSnapshot(current, { bridgeRevision: 10, xmageCycle: 4 }), false);
    assert.equal(shouldAcceptSnapshot(current, { bridgeRevision: 11, xmageCycle: 5 }), true);
    assert.equal(shouldAcceptSnapshot(current, { bridgeRevision: 10, xmageCycle: 6 }), true);
    assert.equal(shouldAcceptSnapshot(current, { bridgeRevision: 10, xmageCycle: 5 }), true);
  });

  it("ensures Java bridge rejects unknown command types", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    assert.match(bridgeSource, /throw new IllegalArgumentException\("Unknown command type: " \+ type\);/);
  });

  it("ensures applyCommand throws for unknown command types", () => {
    const snapshot = { players: [] };
    assert.throws(() => {
      applyCommand(snapshot, { type: "invalid_command_type" });
    }, /Unknown command type: invalid_command_type/);
  });

  it("obfuscates snapshots based on player context", () => {
    const snapshot = {
      players: [
        {
          playerId: "human",
          zones: {
            hand: [{ instanceId: "card-1", card: { name: "Growth Spiral" } }],
            library: [{ instanceId: "card-2", card: { name: "Forest" } }]
          }
        },
        {
          playerId: "ai-1",
          zones: {
            hand: [{ instanceId: "card-3", card: { name: "Sol Ring" } }],
            library: [{ instanceId: "card-4", card: { name: "Swamp" } }]
          }
        }
      ],
      xmage: {
        players: [
          {
            playerId: "human",
            zones: {
              hand: [{ instanceId: "card-1", card: { name: "Growth Spiral" } }],
              library: [{ instanceId: "card-2", card: { name: "Forest" } }]
            }
          },
          {
            playerId: "ai-1",
            zones: {
              hand: [{ instanceId: "card-3", card: { name: "Sol Ring" } }],
              library: [{ instanceId: "card-4", card: { name: "Swamp" } }]
            }
          }
        ]
      }
    };

    const obfuscatedForHuman = obfuscateSnapshotForPlayer(snapshot, "human");
    assert.equal(obfuscatedForHuman.players[0].zones.hand[0].card.name, "Growth Spiral");
    assert.equal(obfuscatedForHuman.players[0].zones.library[0].card.name, "Hidden card");
    assert.equal(obfuscatedForHuman.players[1].zones.hand[0].card.name, "Hidden card");
    assert.equal(obfuscatedForHuman.players[1].zones.library[0].card.name, "Hidden card");

    assert.equal(obfuscatedForHuman.xmage.players[0].zones.hand[0].card.name, "Growth Spiral");
    assert.equal(obfuscatedForHuman.xmage.players[0].zones.library[0].card.name, "Hidden card");
    assert.equal(obfuscatedForHuman.xmage.players[1].zones.hand[0].card.name, "Hidden card");
    assert.equal(obfuscatedForHuman.xmage.players[1].zones.library[0].card.name, "Hidden card");
  });

  it("obfuscates snapshots in GET /games/:id route if playerId query param is present", async () => {
    const state = new Map();
    const game = {
      id: "game-1",
      players: [
        {
          playerId: "human",
          zones: {
            hand: [{ instanceId: "card-1", card: { name: "Growth Spiral" } }],
            library: []
          }
        },
        {
          playerId: "ai-1",
          zones: {
            hand: [{ instanceId: "card-3", card: { name: "Sol Ring" } }],
            library: []
          }
        }
      ]
    };
    state.set(game.id, game);
    const handler = createGatewayHandler(state);

    const response = await runHandler(handler, `/games/${game.id}?playerId=human`, "GET");
    assert.equal(response.status, 200);
    const body = JSON.parse(response.body);
    assert.equal(body.players[0].zones.hand[0].card.name, "Growth Spiral");
    assert.equal(body.players[1].zones.hand[0].card.name, "Hidden card");
  });

  it("keeps Java bridge code hardened with command/prompt validations and parsing patterns", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    // Command/prompt validations
    assert.ok(bridgeSource.includes("if (command == null) {"));
    assert.ok(bridgeSource.includes("isPromptRespondingCommand"));
    assert.ok(bridgeSource.includes("validatePromptSelections(gameId, prompt, singletonSelection(String.valueOf(pile)));"));
    assert.ok(bridgeSource.includes("validatePromptSelections(gameId, prompt, singletonSelection(String.valueOf(response)));"));

    // Commander Tax text variants regex
    assert.ok(bridgeSource.includes("commander tax"));
    assert.ok(bridgeSource.includes("commander tax:?\\\\s*\\\\{?(\\\\d+)\\\\}?"));
    assert.ok(bridgeSource.includes("(?:commander\\\\s+casts|casts\\\\s+from\\\\s+(?:the\\\\s+)?command\\\\s+zone|played\\\\s+from\\\\s+(?:the\\\\s+)?command\\\\s+zone|casts|number\\\\s+of\\\\s+(?:times\\\\s+)?cast(?:s)?)\\\\s*[:\\\\s]\\\\s*(\\\\d+)"));
    assert.ok(bridgeSource.includes("(?:cast|played)\\\\s+(\\\\d+)\\\\s+time"));
    assert.ok(bridgeSource.includes("(\\\\d+)\\\\s+time(?:s)?\\\\s+played\\\\s+from\\\\s+(?:the\\\\s+)?command\\\\s+zone"));

    // Commander Damage text variants regex
    assert.ok(bridgeSource.includes("(?:did|dealt|deals|has\\\\s+dealt)\\\\s+(\\\\d+)\\\\s+(?:combat|commander)\\\\s+damage\\\\s+to\\\\s+(?:player\\\\s+)?([^.]+)"));
    assert.ok(bridgeSource.includes("(\\\\d+)\\\\s+(?:combat|commander)\\\\s+damage\\\\s+to\\\\s+(?:player\\\\s+)?([^.]+)"));
    assert.ok(bridgeSource.includes("(?:combat\\\\s+)?damage\\\\s+dealt\\\\s+(?:by\\\\s+commander\\\\s+)?to\\\\s+([^:]+):\\\\s*(\\\\d+)"));
    assert.ok(bridgeSource.includes("commander\\\\s+combat\\\\s+damage\\\\s+to\\\\s+([^:]+):\\\\s*(\\\\d+)"));

    // Combat actions preserve typed pair payloads for mobile/web clients.
    assert.ok(bridgeSource.includes("combatActions(record, view, playerIds)"));
    assert.ok(bridgeSource.includes("\"declare_attackers\""));
    assert.ok(bridgeSource.includes("\"declare_blockers\""));
    assert.ok(bridgeSource.includes("pair.addProperty(\"attackerId\", permanent.getId().toString());"));
    assert.ok(bridgeSource.includes("pair.addProperty(\"defenderId\", defenderId);"));
    assert.ok(bridgeSource.includes("pair.addProperty(\"blockerId\", permanent.getId().toString());"));
    assert.ok(bridgeSource.includes("pair.addProperty(\"attackerId\", attackerId);"));
  });

  it("keeps the Java bridge remoting session alive and reports disconnects explicitly", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");
    const smokeSource = readFileSync(new URL("./scripts/smoke-create-commander-game.ts", import.meta.url), "utf8");

    assert.match(bridgeSource, /keepAliveExecutor\.scheduleAtFixedRate\(this::pingIfConnected/);
    assert.match(bridgeSource, /current\.ping\(\)/);
    assert.ok(bridgeSource.includes("lastError = \"XMage bridge disconnected\";"));
    assert.ok(smokeSource.includes("failedStep: \"bridge-disconnected\""));
    assert.ok(smokeSource.includes("if (label === \"cast simple spell\") return 30000;"));
    assert.ok(smokeSource.includes("allowEqual: snapshot.pendingStatus === \"waiting_for_xmage\""));
    assert.ok(smokeSource.includes("if (scenario === \"blocker-flow\") return blockerAssignmentExercised;"));
    assert.ok(smokeSource.includes("blocker-flow scenario did not exercise a real declare_blockers action."));
  });
});

function fixtureProofRequest() {
  return {
    scenario: "commander-gauntlet",
    scenarioName: "commander-gauntlet",
    hand: ["Sol Ring"],
    battlefield: ["Plains"],
    commandZone: ["Isamaru, Hound of Konda"],
    libraryTop: ["Plains"],
    graveyard: [],
    exile: [],
    aiBattlefield: ["Wastes"],
    phase: "precombat-main",
    step: "precombat-main",
    activePlayerId: "human",
    priorityPlayerId: "human",
    expectedRoutes: ["play_land", "cast_spell"]
  };
}

function fixtureProofSnapshot(options = {}) {
  const snapshot = bridgeSmokeSnapshot(12, 30, "precombat-main", []);
  snapshot.id = "xmage-fixture-proof-1";
  snapshot.phase = "precombat-main";
  snapshot.step = "precombat-main";
  snapshot.activePlayerId = "human";
  snapshot.priorityPlayerId = "human";
  snapshot.waitingOnPlayerId = "human";
  snapshot.players[0].zones = {
    hand: options.omitHand ? [] : testCards(["Sol Ring"]),
    battlefield: testCards(["Plains"]),
    library: testCards(["Plains", "Plains"]),
    graveyard: [],
    exile: [],
    stack: [],
    command: testCards(["Isamaru, Hound of Konda"])
  };
  snapshot.players[1].zones = {
    hand: [],
    battlefield: testCards(["Wastes"]),
    library: [],
    graveyard: [],
    exile: [],
    stack: [],
    command: testCards(["Kozilek, Butcher of Truth"])
  };
  return snapshot;
}

function testCards(names) {
  return names.map((name, index) => ({
    instanceId: `${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${index}`,
    card: { name }
  }));
}

function bridgeSmokeSnapshot(bridgeRevision, xmageCycle, step, legalActions) {
  return {
    id: "xmage-bridge-smoke-1",
    source: "xmage-java-bridge",
    roomId: "bridge-smoke",
    phase: step === "mulligan" ? "setup" : "precombat-main",
    step,
    turn: 1,
    activePlayerId: "human",
    priorityPlayerId: "human",
    waitingOnPlayerId: "human",
    promptText: step === "choose_target" ? "Choose target" : "Your priority",
    bridgeRevision,
    xmageCycle,
    players: [
      {
        playerId: "human",
        life: 40,
        manaPool: { W: 0, U: 0, B: 0, R: 0, G: step === "mulligan" ? 0 : 1, C: 0 },
        zones: {
          hand: [],
          battlefield: [{ instanceId: "forest-1", card: { name: "Forest", typeLine: "Land" } }],
          stack: [],
          command: [{ instanceId: "commander-1", card: { name: "Ezuri, Claw of Progress" } }]
        }
      },
      {
        playerId: "ai-1",
        life: 40,
        manaPool: { W: 0, U: 0, B: 0, R: 0, G: 0, C: 0 },
        zones: { hand: [], battlefield: [], stack: [], command: [] }
      }
    ],
    legalActions,
    xmage: {
      schemaVersion: 1,
      gameId: "xmage-bridge-smoke-1",
      callbackCoverage: step === "choose_target" ? ["GAME_TARGET"] : [],
      panels: { stack: false, command: true, graveyard: false, exile: false, revealed: false, lookedAt: false, search: false }
    }
  };
}

function runHandler(handler, path, method = "GET", body = undefined) {
  return new Promise((resolve) => {
    const chunks = [];
    const request = {
      url: path,
      method,
      async *[Symbol.asyncIterator]() {
        if (body !== undefined) {
          yield Buffer.from(JSON.stringify(body));
        }
      }
    };
    const response = {
      status: 200,
      headers: {},
      writeHead(status, headers) {
        this.status = status;
        this.headers = headers;
      },
      end(chunk) {
        if (chunk) chunks.push(Buffer.from(chunk));
        resolve({
          status: this.status,
          headers: this.headers,
          body: Buffer.concat(chunks).toString("utf8")
        });
      }
    };
    void handler(request, response);
  });
}

function restoreEnv(name, value) {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
