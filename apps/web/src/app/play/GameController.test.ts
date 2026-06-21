import { describe, expect, it } from "vitest";
import type { GameSnapshot, LegalAction } from "@magicmobile/shared";
import { toCommand } from "./GameController";

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

    expect(toCommand(action, snapshot, undefined, "ai-1")).toMatchObject({
      type: "make_mana",
      gameId: "game-1",
      playerId: "human",
      sourceInstanceId: "forest-instance",
      abilityId: "mana-ability"
    });
  });
});
