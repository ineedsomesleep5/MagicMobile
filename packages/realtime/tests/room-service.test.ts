import { describe, expect, it, vi } from "vitest";
import { InMemoryRealtimeGateway, InMemoryRoomService, MockRecognitionService, validateHybridAction } from "../src";
import type { HybridActionType } from "@magicmobile/shared";

describe("InMemoryRoomService", () => {
  it("creates, joins, readies, and starts rooms with explicit seat types", async () => {
    const gateway = new InMemoryRealtimeGateway();
    const service = new InMemoryRoomService({ gateway, idPrefix: "test" });
    const roomEvents = vi.fn();

    const room = await service.createRoom({
      hostPlayerId: "player-host",
      name: "Friday Commander",
      seatType: "hybrid"
    });
    gateway.subscribe(room.id, roomEvents);

    await service.joinRoom({
      displayName: "Webcam Player",
      playerId: "player-two",
      roomId: room.id,
      seatType: "webcam"
    });
    await service.joinRoom({
      displayName: "Spectator",
      playerId: "player-three",
      roomId: room.id,
      seatType: "spectator"
    });

    await service.setReady({ playerId: "player-host", ready: true, roomId: room.id });
    await service.setReady({ playerId: "player-two", ready: true, roomId: room.id });
    const started = await service.startRoom({ roomId: room.id });

    expect(started).toMatchObject({
      gameId: "test-game-1",
      id: "test-room-1",
      status: "active"
    });
    expect(started.seats).toEqual([
      { displayName: "Host", playerId: "player-host", ready: true, seatType: "hybrid" },
      { displayName: "Webcam Player", playerId: "player-two", ready: true, seatType: "webcam" },
      { displayName: "Spectator", playerId: "player-three", ready: false, seatType: "spectator" }
    ]);
    expect(roomEvents).toHaveBeenCalledWith(
      expect.objectContaining({
        roomId: room.id,
        type: "room.updated"
      })
    );
  });

  it("broadcasts game, presence, and chat placeholder events through the realtime gateway", () => {
    const gateway = new InMemoryRealtimeGateway();
    const listener = vi.fn();
    const unsubscribe = gateway.subscribe("room-1", listener);

    gateway.broadcastGameEvent("room-1", {
      action: {
        cardName: "Sol Ring",
        playerId: "player-one",
        type: "cast_spell"
      }
    });
    gateway.updatePresence("room-1", { playerId: "player-one", status: "online" });
    gateway.sendChatMessage("room-1", { message: "glhf", playerId: "player-one" });
    unsubscribe();
    gateway.sendChatMessage("room-1", { message: "after unsubscribe", playerId: "player-one" });

    expect(listener).toHaveBeenCalledTimes(3);
    expect(listener).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        payload: expect.objectContaining({
          action: expect.objectContaining({ type: "cast_spell" })
        }),
        type: "game.event"
      })
    );
    expect(gateway.getPresence("room-1")).toEqual([{ playerId: "player-one", status: "online" }]);
  });
});

describe("hybrid action protocol", () => {
  it("accepts the required paper action vocabulary", () => {
    const types: HybridActionType[] = [
      "play_land",
      "cast_spell",
      "move_card",
      "tap_permanent",
      "untap_permanent",
      "attack_player",
      "add_counter",
      "create_token",
      "change_life",
      "update_commander_damage",
      "pass_priority"
    ];

    expect(types.map((type) => validateHybridAction({ playerId: "player-one", type }).valid)).toEqual(
      types.map(() => true)
    );
  });

  it("rejects malformed paper actions without throwing", () => {
    expect(validateHybridAction({ playerId: "", type: "cast_spell" })).toEqual({
      errors: ["playerId is required"],
      valid: false
    });
  });
});

describe("MockRecognitionService", () => {
  it("returns deterministic placeholders for card and zone recognition", async () => {
    const service = new MockRecognitionService();

    await expect(service.clickToIdentifyCard({ imageId: "frame-1", x: 10, y: 20 })).resolves.toEqual([]);
    await expect(service.suggestCardMatch({ text: "sol" })).resolves.toEqual(["sol"]);
    await expect(service.confirmCardMatch({ cardName: "Sol Ring" })).resolves.toEqual({ confirmed: true });
    await expect(service.suggestZoneChange({ cardName: "Sol Ring" })).resolves.toEqual([
      "battlefield",
      "graveyard",
      "exile"
    ]);
  });
});
