import type { PlayerId, RoomId, VideoProvider, VideoSession } from "@magicmobile/shared";

export class MockVideoProvider implements VideoProvider {
  async createSession(input: { roomId: RoomId }): Promise<VideoSession> {
    return {
      joinUrl: `mock://video/${input.roomId}`,
      provider: "mock",
      roomId: input.roomId
    };
  }

  async getJoinToken(input: { roomId: RoomId; playerId: PlayerId }): Promise<VideoSession> {
    return {
      joinUrl: `mock://video/${input.roomId}?playerId=${input.playerId}`,
      provider: "mock",
      roomId: input.roomId,
      token: `mock-video-token:${input.roomId}:${input.playerId}`
    };
  }
}

export class LiveKitVideoProvider implements VideoProvider {
  async createSession(_input: { roomId: RoomId }): Promise<VideoSession> {
    throw new Error("LiveKit video is not configured");
  }

  async getJoinToken(_input: { roomId: RoomId; playerId: PlayerId }): Promise<VideoSession> {
    throw new Error("LiveKit video is not configured");
  }
}
