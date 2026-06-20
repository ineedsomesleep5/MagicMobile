import { describe, expect, it } from "vitest";
import type { DeckList, EngineAdapter } from "@magicmobile/shared";
import { MockEngineAdapter, XmageEngineAdapter } from "../src";

const deck: DeckList = {
  name: "Mock Commander",
  commander: { cardName: "Alela, Artful Provocateur", quantity: 1, section: "commander" },
  entries: [
    { cardName: "Sol Ring", quantity: 1, section: "deck" },
    { cardName: "Arcane Signet", quantity: 1, section: "deck" },
    { cardName: "Command Tower", quantity: 1, section: "deck" },
    { cardName: "Island", quantity: 4, section: "deck" },
    { cardName: "Plains", quantity: 4, section: "deck" },
    { cardName: "Opt", quantity: 1, section: "deck" }
  ]
};

describe("EngineAdapter contract", () => {
  it("runs a commander game through the shared adapter contract", async () => {
    const adapter: EngineAdapter = new MockEngineAdapter({ shuffleSeed: 7 });

    const created = await adapter.createGame({ roomId: "room-1", playerIds: ["p1", "p2"] });
    expect(created.players).toHaveLength(2);
    expect(created.players[0]).toMatchObject({ playerId: "p1", life: 40, poison: 0, commanderTax: 0 });
    expect(created.players[0]?.commanderDamage).toEqual({ p1: 0, p2: 0 });

    await adapter.loadDeck({ gameId: created.id, playerId: "p1", deck });
    await adapter.loadDeck({ gameId: created.id, playerId: "p2", deck });
    await adapter.shuffle({ gameId: created.id, playerId: "p1" });
    const opened = await adapter.drawOpeningHands({ gameId: created.id, count: 7 });
    expect(opened.players[0]?.zones.hand).toHaveLength(7);
    expect(opened.players[0]?.zones.command.map((card) => card.card.name)).toEqual(["Alela, Artful Provocateur"]);
    const movableCard = opened.players[0]?.zones.library[0]?.card.name;
    if (!movableCard) {
      throw new Error("Expected a card to remain in library after opening hand");
    }

    await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "move_card", playerId: "p1", cardName: movableCard, fromZone: "library", toZone: "battlefield" }
    });
    await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "tap_permanent", playerId: "p1", cardName: movableCard }
    });
    await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "add_counter", playerId: "p1", cardName: movableCard, amount: 2 }
    });
    await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "create_token", playerId: "p1", cardName: "Faerie Token", amount: 2 }
    });
    await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "cast_spell", playerId: "p1", cardName: "Alela, Artful Provocateur", fromZone: "command" }
    });
    await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "change_life", playerId: "p2", amount: -5 }
    });
    await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "update_commander_damage", playerId: "p1", targetPlayerId: "p2", amount: 3 }
    });
    const updated = await adapter.applyHybridAction({
      gameId: created.id,
      action: { type: "add_counter", playerId: "p1", targetPlayerId: "p2", amount: 1 }
    });

    const p1 = updated.players.find((player) => player.playerId === "p1");
    const p2 = updated.players.find((player) => player.playerId === "p2");

    expect(p1?.zones.battlefield.find((card) => card.card.name === movableCard)).toMatchObject({
      tapped: true,
      counters: { generic: 2 }
    });
    expect(p1?.zones.battlefield.filter((card) => card.card.name === "Faerie Token")).toHaveLength(2);
    expect(p1?.zones.stack.map((card) => card.card.name)).toContain("Alela, Artful Provocateur");
    expect(p1?.commanderTax).toBe(2);
    expect(p2).toMatchObject({ life: 35, poison: 1 });
    expect(p2?.commanderDamage.p1).toBe(3);
    expect(updated.log.map((entry) => entry.message)).toContain("p1 casts Alela, Artful Provocateur");
  });

  it("tracks priority, phases, turns, joins, and reconnect snapshots", async () => {
    const adapter = new MockEngineAdapter();
    const created = await adapter.createGame({ roomId: "room-2", playerIds: ["p1"] });
    const joined = await adapter.joinGame({ gameId: created.id, playerId: "p2" });
    expect(joined.players.map((player) => player.playerId)).toEqual(["p1", "p2"]);

    const priority = await adapter.passPriority({ gameId: created.id, playerId: "p1" });
    expect(priority.priorityPlayerId).toBe("p2");

    const nextPhase = await adapter.advancePhase({ gameId: created.id });
    expect(nextPhase.phase).toBe("precombat-main");

    const nextTurn = await adapter.advanceTurn({ gameId: created.id });
    expect(nextTurn).toMatchObject({ turn: 2, phase: "beginning", activePlayerId: "p2", priorityPlayerId: "p2" });

    const snapshot = await adapter.getSnapshot(created.id);
    snapshot.players[0]!.life = 1;
    const reconnect = await adapter.getSnapshot(created.id);
    expect(reconnect.players[0]?.life).toBe(40);
    expect(reconnect.log.some((entry) => entry.message.includes("turn 2"))).toBe(true);
  });

  it("exposes an XMage adapter stub without importing UI code", async () => {
    const adapter: EngineAdapter = new XmageEngineAdapter({ endpoint: "http://xmage-worker.test" });

    await expect(adapter.createGame({ roomId: "room-3", playerIds: ["p1"] })).rejects.toThrow(
      "XMage adapter is a stub"
    );
  });
});
