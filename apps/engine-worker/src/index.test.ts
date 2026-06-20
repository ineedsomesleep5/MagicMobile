import { describe, expect, it } from "vitest";
import { createEngineWorkerAdapter } from "./index";

describe("createEngineWorkerAdapter", () => {
  it("creates a mock engine adapter by default", async () => {
    const adapter = createEngineWorkerAdapter();

    const snapshot = await adapter.createGame({ roomId: "room-1", playerIds: ["player-1"] });

    expect(snapshot.roomId).toBe("room-1");
    expect(snapshot.players).toHaveLength(1);
  });

  it("creates the explicit XMage gateway adapter when requested", async () => {
    const adapter = createEngineWorkerAdapter({ mode: "xmage", xmageEndpoint: "http://xmage.test" });

    await expect(adapter.getHealth()).resolves.toMatchObject({ status: "unavailable" });
  });
});
