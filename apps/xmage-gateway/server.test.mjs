import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  aiDifficultyProfiles,
  applyCommand,
  createCommanderGame,
  createGatewayHandler,
  createHttpBridgeClient,
  getGatewayHealth,
  getHealth,
  registerWebSocketConnection,
  shouldAcceptSnapshot
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

    snapshot = applyCommand(snapshot, {
      type: "make_mana",
      gameId: snapshot.id,
      playerId: "human",
      sourceInstanceId: manaAction.sourceInstanceId
    });

    assert.equal(snapshot.players[0].zones.battlefield[0].tapped, true);
    assert.deepEqual(snapshot.players[0].manaPool, { W: 0, U: 0, B: 0, R: 0, G: 1, C: 0 });
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

    const snapshot = await client.createCommanderGame({ roomId: "room-1" });

    assert.equal(snapshot.id, "xmage-game-1");
    assert.equal(requests[0].url, "http://bridge.test/games/commander");
    assert.equal(requests[0].init.method, "POST");
    assert.equal(JSON.parse(requests[0].init.body).roomId, "room-1");
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
        stack: [{ id: "stack-1", name: "Lightning Bolt", rulesText: "Lightning Bolt deals 3 damage to any target." }],
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
    assert.equal(body.xmage.panels.command, true);
  });
});

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
