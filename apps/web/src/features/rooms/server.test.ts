import { describe, expect, it, vi } from "vitest";

describe("room server runtime", () => {
  it("keeps in-memory room state across route module boundaries", async () => {
    const firstRuntime = await import("./server");
    const room = await firstRuntime.roomService.createRoom({
      hostDisplayName: "Ari",
      hostPlayerId: "player-1",
      name: "QA Room"
    });

    vi.resetModules();
    const secondRuntime = await import("./server");

    await expect(secondRuntime.roomService.getRoom(room.id)).resolves.toMatchObject({
      id: room.id,
      name: "QA Room"
    });
  });
});
