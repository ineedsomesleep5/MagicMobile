import { describe, expect, it } from "vitest";
import type { GameSnapshot, LegalAction } from "@magicmobile/shared";
import { gameWebSocketUrl, latestSnapshot, toCommand } from "./GameController";

const snapshot: GameSnapshot = {
  id: "game-1",
  roomId: "room-1",
  phase: "precombat-main",
  turn: 1,
  players: [],
  log: []
};

describe("GameController command mapping", () => {
  it("preserves the source UUID when an XMage action includes command template metadata", () => {
    const action: LegalAction = {
      id: "mana-action",
      type: "make_mana",
      playerId: "human",
      label: "Add {G}",
      cardInstanceId: "forest-instance",
      sourceInstanceId: "forest-instance",
      commandTemplate: {
        abilityId: "mana-ability"
      }
    };

    expect(toCommand(action, { ...snapshot, bridgeRevision: 12 }, undefined, "ai-1")).toMatchObject({
      type: "make_mana",
      gameId: "game-1",
      playerId: "human",
      sourceInstanceId: "forest-instance",
      abilityId: "mana-ability",
      expectedBridgeRevision: 12
    });
  });

  it("builds gateway websocket URLs for direct gateway and same-origin proxy modes", () => {
    expect(gameWebSocketUrl("game 1", "http://localhost:17171")).toBe("ws://localhost:17171/ws/games/game%201");
    expect(gameWebSocketUrl("game-2", "https://magicmobile.example/base/")).toBe("wss://magicmobile.example/base/ws/games/game-2");
    expect(gameWebSocketUrl("game-3")).toBe("/ws/games/game-3");
  });

  it("rejects stale bridge snapshots before updating the client board", () => {
    const current = { ...snapshot, bridgeRevision: 7, promptText: "newer" };
    const stale = { ...snapshot, bridgeRevision: 6, promptText: "older" };
    const fresh = { ...snapshot, bridgeRevision: 8, promptText: "fresh" };

    expect(latestSnapshot(current, stale)).toBe(current);
    expect(latestSnapshot(current, fresh)).toMatchObject({ bridgeRevision: 8, promptText: "fresh" });
  });
});
