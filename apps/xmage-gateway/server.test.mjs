import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { aiDifficultyProfiles, applyCommand, createCommanderGame, getHealth } from "./server.mjs";

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
    const snapshot = createCommanderGame(state, {
      roomId: "room-1",
      humanPlayerId: "human",
      humanDeck: deck,
      aiPlayers: [{ playerId: "ai-1", displayName: "AI Easy", difficulty: "easy", deck }],
      startingLife: 40,
      commanderDamageEnabled: true
    });

    assert.equal(snapshot.players.length, 2);
    assert.equal(snapshot.players[0].zones.command[0].card.name, "Ezuri, Claw of Progress");
    assert.equal(snapshot.players[0].zones.hand.length, 7);
    assert.equal(snapshot.legalActions.some((action) => action.type === "cast_spell"), true);
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
});
