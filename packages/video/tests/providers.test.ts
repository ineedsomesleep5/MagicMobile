import { describe, expect, it } from "vitest";
import { LiveKitVideoProvider, MockVideoProvider } from "../src";

describe("video providers", () => {
  it("creates deterministic mock sessions and join tokens", async () => {
    const provider = new MockVideoProvider();

    await expect(provider.createSession({ roomId: "room-1" })).resolves.toEqual({
      joinUrl: "mock://video/room-1",
      provider: "mock",
      roomId: "room-1"
    });
    await expect(provider.getJoinToken({ playerId: "player-1", roomId: "room-1" })).resolves.toEqual({
      joinUrl: "mock://video/room-1?playerId=player-1",
      provider: "mock",
      roomId: "room-1",
      token: "mock-video-token:room-1:player-1"
    });
  });

  it("keeps LiveKit behind an explicit disabled stub", async () => {
    const provider = new LiveKitVideoProvider();

    await expect(provider.createSession({ roomId: "room-1" })).rejects.toThrow("LiveKit video is not configured");
    await expect(provider.getJoinToken({ playerId: "player-1", roomId: "room-1" })).rejects.toThrow(
      "LiveKit video is not configured"
    );
  });
});
