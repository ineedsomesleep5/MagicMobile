import { describe, expect, it } from "vitest";
import type { GameSnapshot, LegalAction } from "@magicmobile/shared";
import { gameWebSocketUrl, latestSnapshot, toCommand } from "./GameController";
import { narrowCommandTemplate, narrowPromptAction } from "./ArenaBattlefield";

const snapshot: GameSnapshot = {
  id: "game-1",
  roomId: "room-1",
  phase: "precombat-main",
  turn: 1,
  players: [],
  log: []
};

describe("GameController command mapping and state integration", () => {
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

  it("preserves explicit XMage pay-cost prompt responses", () => {
    const action: LegalAction = {
      id: "pay-action",
      type: "pay_cost",
      playerId: "human",
      label: "Pay cost",
      promptId: "prompt-pay",
      commandTemplate: {
        type: "pay_cost",
        promptId: "prompt-pay",
        pay: false,
        confirmed: false
      }
    };

    expect(toCommand(action, { ...snapshot, bridgeRevision: 13 }, undefined, "ai-1")).toMatchObject({
      type: "pay_cost",
      gameId: "game-1",
      playerId: "human",
      promptId: "prompt-pay",
      pay: false,
      confirmed: false,
      expectedBridgeRevision: 13
    });
  });

  it("builds gateway websocket URLs for direct gateway and same-origin proxy modes", () => {
    expect(gameWebSocketUrl("game 1", "http://localhost:17171")).toBe("ws://localhost:17171/ws/games/game%201");
    expect(gameWebSocketUrl("game-2", "https://magicmobile.example/base/")).toBe("wss://magicmobile.example/base/ws/games/game-2");
    expect(gameWebSocketUrl("game-3")).toBe("/ws/games/game-3");
  });

  describe("latestSnapshot updates and snap-back protection", () => {
    it("rejects stale bridge snapshots before updating the client board", () => {
      const current = { ...snapshot, bridgeRevision: 7, promptText: "newer" };
      const stale = { ...snapshot, bridgeRevision: 6, promptText: "older" };
      const fresh = { ...snapshot, bridgeRevision: 8, promptText: "fresh" };

      expect(latestSnapshot(current, stale)).toBe(current);
      expect(latestSnapshot(current, fresh)).toMatchObject({ bridgeRevision: 8, promptText: "fresh" });
    });

    it("rejects stale xmageCycle snapshots when bridgeRevision is identical", () => {
      const current = { ...snapshot, bridgeRevision: 10, xmageCycle: 20, promptText: "current" };
      const stale = { ...snapshot, bridgeRevision: 10, xmageCycle: 19, promptText: "stale" };
      const fresh = { ...snapshot, bridgeRevision: 10, xmageCycle: 21, promptText: "fresh" };

      expect(latestSnapshot(current, stale)).toBe(current);
      expect(latestSnapshot(current, fresh)).toMatchObject({ bridgeRevision: 10, xmageCycle: 21 });
    });

    it("prefers larger bridgeRevision over xmageCycle when deciding freshness", () => {
      const current = { ...snapshot, bridgeRevision: 10, xmageCycle: 20 };
      const nextWithNewerBridgeOlderCycle = { ...snapshot, bridgeRevision: 11, xmageCycle: 19 };

      // Revisions are checked first. Since next has a newer bridge revision, it wins.
      expect(latestSnapshot(current, nextWithNewerBridgeOlderCycle)).toBe(nextWithNewerBridgeOlderCycle);
    });
  });

  describe("prompt family mappings", () => {
    it("maps choose_target correctly", () => {
      const action: LegalAction = {
        id: "target-1",
        type: "choose_target",
        playerId: "human",
        label: "Choose target",
        validTargetIds: ["card-instance-1"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "choose_target",
        gameId: "game-1",
        playerId: "human",
        promptId: "target-1",
        targetIds: ["card-instance-1"]
      });
    });

    it("maps choose_card correctly", () => {
      const action: LegalAction = {
        id: "card-1",
        type: "choose_card",
        playerId: "human",
        label: "Choose card",
        validTargetIds: ["card-instance-1"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "choose_card",
        gameId: "game-1",
        playerId: "human",
        promptId: "card-1",
        cardInstanceIds: ["card-instance-1"]
      });
    });

    it("maps choose_player correctly", () => {
      const action: LegalAction = {
        id: "player-1",
        type: "choose_player",
        playerId: "human",
        label: "Choose player",
        validPlayerIds: ["ai-1"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "choose_player",
        gameId: "game-1",
        playerId: "human",
        promptId: "player-1",
        playerIds: ["ai-1"]
      });
    });

    it("maps choose_mode correctly", () => {
      const action: LegalAction = {
        id: "mode-1",
        type: "choose_mode",
        playerId: "human",
        label: "Choose mode",
        modeIds: ["mode-idx-2"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "choose_mode",
        gameId: "game-1",
        playerId: "human",
        promptId: "mode-1",
        modeIds: ["mode-idx-2"]
      });
    });

    it("maps choose_ability correctly", () => {
      const action: LegalAction = {
        id: "ability-1",
        type: "choose_ability",
        playerId: "human",
        label: "Choose ability",
        targetIds: ["ability-instance-3"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "choose_ability",
        gameId: "game-1",
        playerId: "human",
        promptId: "ability-1",
        abilityId: "ability-instance-3"
      });
    });

    it("maps choose_amount and play_x_mana correctly", () => {
      const actionAmount: LegalAction = {
        id: "amount-1",
        type: "choose_amount",
        playerId: "human",
        label: "Choose amount",
        targetIds: ["5"]
      };
      const cmdAmount = toCommand(actionAmount, snapshot, undefined, "opponent");
      expect(cmdAmount).toEqual({
        type: "choose_amount",
        gameId: "game-1",
        playerId: "human",
        promptId: "amount-1",
        amount: 5
      });

      const actionXMana: LegalAction = {
        id: "x-mana-1",
        type: "play_x_mana",
        playerId: "human",
        label: "Play X mana",
        targetIds: ["8"]
      };
      const cmdXMana = toCommand(actionXMana, snapshot, undefined, "opponent");
      expect(cmdXMana).toEqual({
        type: "play_x_mana",
        gameId: "game-1",
        playerId: "human",
        promptId: "x-mana-1",
        amount: 8
      });
    });

    it("maps choose_multi_amount correctly", () => {
      const action: LegalAction = {
        id: "multi-amount-1",
        type: "choose_multi_amount",
        playerId: "human",
        label: "Choose multi amount",
        targetIds: ["2", "4"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "choose_multi_amount",
        gameId: "game-1",
        playerId: "human",
        promptId: "multi-amount-1",
        amounts: [2, 4]
      });
    });

    it("maps choose_mana correctly", () => {
      const action: LegalAction = {
        id: "mana-choice-1",
        type: "choose_mana",
        playerId: "human",
        label: "Choose mana",
        manaTypes: ["W"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "choose_mana",
        gameId: "game-1",
        playerId: "human",
        promptId: "mana-choice-1",
        manaTypes: ["W"]
      });
    });

    it("maps answer_yes_no correctly", () => {
      const actionYes: LegalAction = {
        id: "yes-no-1",
        type: "answer_yes_no",
        playerId: "human",
        label: "Yes",
        confirmed: true
      };
      const cmdYes = toCommand(actionYes, snapshot, undefined, "opponent");
      expect(cmdYes).toEqual({
        type: "answer_yes_no",
        gameId: "game-1",
        playerId: "human",
        promptId: "yes-no-1",
        confirmed: true
      });

      const actionNo: LegalAction = {
        id: "yes-no-1",
        type: "answer_yes_no",
        playerId: "human",
        label: "No",
        confirmed: false
      };
      const cmdNo = toCommand(actionNo, snapshot, undefined, "opponent");
      expect(cmdNo).toEqual({
        type: "answer_yes_no",
        gameId: "game-1",
        playerId: "human",
        promptId: "yes-no-1",
        confirmed: false
      });
    });

    it("maps order_triggers and order_items correctly", () => {
      const actionTriggers: LegalAction = {
        id: "order-triggers-1",
        type: "order_triggers",
        playerId: "human",
        label: "Order triggers",
        targetIds: ["trigger-1", "trigger-2"]
      };
      const cmdTriggers = toCommand(actionTriggers, snapshot, undefined, "opponent");
      expect(cmdTriggers).toEqual({
        type: "order_triggers",
        gameId: "game-1",
        playerId: "human",
        promptId: "order-triggers-1",
        orderedIds: ["trigger-1", "trigger-2"]
      });

      const actionItems: LegalAction = {
        id: "order-items-1",
        type: "order_items",
        playerId: "human",
        label: "Order items",
        orderedIds: ["item-1", "item-2"]
      };
      const cmdItems = toCommand(actionItems, snapshot, undefined, "opponent");
      expect(cmdItems).toEqual({
        type: "order_items",
        gameId: "game-1",
        playerId: "human",
        promptId: "order-items-1",
        orderedIds: ["item-1", "item-2"]
      });
    });

    it("maps search_select correctly", () => {
      const action: LegalAction = {
        id: "search-select-1",
        type: "search_select",
        playerId: "human",
        label: "Search select",
        cardInstanceIds: ["card-instance-5"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "search_select",
        gameId: "game-1",
        playerId: "human",
        promptId: "search-select-1",
        cardInstanceIds: ["card-instance-5"]
      });
    });

    it("maps commander_replacement correctly", () => {
      const actionGraveyard: LegalAction = {
        id: "commander-replace-1",
        type: "commander_replacement",
        playerId: "human",
        label: "Graveyard",
        targetIds: ["graveyard"]
      };
      const cmdGraveyard = toCommand(actionGraveyard, snapshot, undefined, "opponent");
      expect(cmdGraveyard).toEqual({
        type: "commander_replacement",
        gameId: "game-1",
        playerId: "human",
        promptId: "commander-replace-1",
        useCommandZone: false
      });

      const actionCommandZone: LegalAction = {
        id: "commander-replace-1",
        type: "commander_replacement",
        playerId: "human",
        label: "Command Zone",
        targetIds: ["command_zone"]
      };
      const cmdCommandZone = toCommand(actionCommandZone, snapshot, undefined, "opponent");
      expect(cmdCommandZone).toEqual({
        type: "commander_replacement",
        gameId: "game-1",
        playerId: "human",
        promptId: "commander-replace-1",
        useCommandZone: true
      });
    });

    it("does not invent prompt responses when XMage did not expose exact values", () => {
      const missingPile: LegalAction = {
        id: "pile-missing",
        type: "choose_pile",
        playerId: "human",
        label: "Choose pile"
      };
      expect(toCommand(missingPile, snapshot, undefined, "opponent")).toBeUndefined();

      const missingAmount: LegalAction = {
        id: "amount-missing",
        type: "choose_amount",
        playerId: "human",
        label: "Choose amount"
      };
      expect(toCommand(missingAmount, snapshot, undefined, "opponent")).toBeUndefined();

      const missingConfirmation: LegalAction = {
        id: "yes-no-missing",
        type: "answer_yes_no",
        playerId: "human",
        label: "Confirm"
      };
      expect(toCommand(missingConfirmation, snapshot, undefined, "opponent")).toBeUndefined();

      const missingCommanderChoice: LegalAction = {
        id: "commander-missing",
        type: "commander_replacement",
        playerId: "human",
        label: "Commander replacement"
      };
      expect(toCommand(missingCommanderChoice, snapshot, undefined, "opponent")).toBeUndefined();
    });

    it("maps resolve_choice correctly", () => {
      const action: LegalAction = {
        id: "resolve-choice-1",
        type: "resolve_choice",
        playerId: "human",
        label: "Choice 1",
        targetIds: ["choice-instance-9"]
      };
      const cmd = toCommand(action, snapshot, undefined, "opponent");
      expect(cmd).toEqual({
        type: "resolve_choice",
        gameId: "game-1",
        playerId: "human",
        promptId: "resolve-choice-1",
        choiceIds: ["choice-instance-9"]
      });
    });
  });

  describe("narrowPromptAction and narrowCommandTemplate arrays & custom mappings", () => {
    it("splits comma-separated IDs for search_select, order_items, and order_triggers", () => {
      const baseAction: LegalAction = {
        id: "base",
        type: "search_select",
        playerId: "human",
        label: "Search Select"
      };

      const narrowed = narrowPromptAction(baseAction, "search_select", "id1,id2,id3", "Search Select");
      expect(narrowed.cardInstanceIds).toEqual(["id1", "id2", "id3"]);
      expect(narrowed.validCardInstanceIds).toEqual(["id1", "id2", "id3"]);

      const orderAction: LegalAction = {
        id: "order",
        type: "order_triggers",
        playerId: "human",
        label: "Order Triggers"
      };
      const narrowedOrder = narrowPromptAction(orderAction, "order_triggers", "trig1,trig2", "Order");
      expect(narrowedOrder.orderedIds).toEqual(["trig1", "trig2"]);

      const template = { type: "order_items" as const };
      const narrowedTemplate = narrowCommandTemplate(template, "order_items", "item1,item2");
      expect(narrowedTemplate).toEqual({
        type: "order_items",
        orderedIds: ["item1", "item2"]
      });
    });

    it("handles commander_replacement mapping with useCommandZone", () => {
      const baseAction: LegalAction = {
        id: "commander",
        type: "commander_replacement",
        playerId: "human",
        label: "Commander Zone Choice"
      };

      const narrowedCmdZone = narrowPromptAction(baseAction, "commander_replacement", "command_zone", "Command Zone");
      expect(narrowedCmdZone.useCommandZone).toBe(true);

      const narrowedGraveyard = narrowPromptAction(baseAction, "commander_replacement", "graveyard", "Graveyard");
      expect(narrowedGraveyard.useCommandZone).toBe(false);

      const template = { type: "commander_replacement" as const };
      const templateCmdZone = narrowCommandTemplate(template, "commander_replacement", "command_zone");
      expect(templateCmdZone).toEqual({
        type: "commander_replacement",
        useCommandZone: true
      });
      const templateGraveyard = narrowCommandTemplate(template, "commander_replacement", "graveyard");
      expect(templateGraveyard).toEqual({
        type: "commander_replacement",
        useCommandZone: false
      });
    });

    it("handles manaType mapping", () => {
      const template = { type: "play_mana" as const };
      const narrowed = narrowCommandTemplate(template, "play_mana", "G");
      expect(narrowed).toEqual({
        type: "play_mana",
        manaType: "G"
      });
    });
  });

  describe("snapshot version rules additional validations", () => {
    it("handles undefined bridgeRevision or xmageCycle gracefully", () => {
      const current = { ...snapshot, bridgeRevision: 10 };
      const nextNoRevision = { ...snapshot }; // undefined bridgeRevision

      expect(latestSnapshot(current, nextNoRevision)).toBe(nextNoRevision);
    });
  });
});
