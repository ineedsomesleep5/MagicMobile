import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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
  shouldAcceptSnapshot,
  obfuscateSnapshotForPlayer
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

  it("keeps Java bridge prompt commands prompt-aware instead of first-choice fallbacks", () => {
    const bridgeSource = readFileSync(new URL("./bridge/MagicMobileBridge.java", import.meta.url), "utf8");

    assert.match(bridgeSource, /currentPromptForCommand/);
    assert.match(bridgeSource, /validatePromptSelections/);
    assert.match(bridgeSource, /requiredBooleanResponse/);
    assert.match(bridgeSource, /prompt\.add\("manaChoices"/);
    assert.match(bridgeSource, /prompt\.add\("confirmation"/);
    assert.match(bridgeSource, /prompt\.add\("orderedItems"/);
    assert.match(bridgeSource, /prompt\.add\("players"/);
    assert.match(bridgeSource, /expectedBridgeRevision/);
    assert.match(bridgeSource, /pendingLegalActions/);
    assert.match(bridgeSource, /pendingStatus == null \? legalActions\(record, view, playerIds\) : pendingLegalActions\(record\)/);
    assert.match(bridgeSource, /isManaPaymentPrompt\(record\)/);
    assert.match(bridgeSource, /addPlayableObjectActions\(actions, humanId, view, true\)/);
    assert.match(bridgeSource, /String type = manaOnly \? "make_mana" : actionType\(card, handIds\.contains\(objectId\), inCommand\)/);
    assert.match(bridgeSource, /Set<UUID> commandIds = commandIds\(view\);/);
    assert.match(bridgeSource, /String sourceZone = handIds\.contains\(objectId\) \? "hand" : inCommand \? "command" : "battlefield";/);
    assert.match(bridgeSource, /yesCommand\.addProperty\("pay", true\)/);
    assert.match(bridgeSource, /noCommand\.addProperty\("pay", false\)/);
    assert.match(bridgeSource, /Action was based on stale XMage snapshot revision/);
    assert.match(bridgeSource, /int startCycle = record == null \? -1 : record\.latestCycle;/);
    assert.match(bridgeSource, /record\.bridgeRevision\.get\(\) > startRevision \|\| record\.latestCycle > startCycle/);
    assert.match(bridgeSource, /"make_mana"\.equals\(type\)\) \{\s*UUID sourceUuid = playableSourceUuid\(gameId, command\);\s*playableCommandUuid\(gameId, command\);\s*session\.sendPlayerUUID\(xmageGameId, sourceUuid\);/);
    assert.doesNotMatch(bridgeSource, /sendFirstUuid/);
    assert.doesNotMatch(bridgeSource, /sendFirstStringOrUuid/);
    assert.equal(bridgeSource.includes('session.sendPlayerBoolean(xmageGameId, booleanResponse(command, "useCommandZone", true));'), false);
    assert.equal(bridgeSource.includes('session.sendPlayerBoolean(xmageGameId, booleanResponse(command, "pay", true));'), false);
    assert.equal(bridgeSource.includes('session.sendPlayerBoolean(xmageGameId, booleanResponse(command, "confirmed", true));'), false);
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
});

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
