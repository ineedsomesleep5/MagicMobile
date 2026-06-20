import type {
  ChatMessage,
  PresenceState,
  RoomEventListener,
  RoomRealtimeEvent,
  RoomRealtimeGateway
} from "./types";
import type { HybridAction, RoomId } from "@magicmobile/shared";

export class InMemoryRealtimeGateway implements RoomRealtimeGateway {
  private readonly listeners = new Map<RoomId, Set<RoomEventListener>>();
  private readonly presence = new Map<RoomId, Map<string, PresenceState>>();
  private messageCount = 0;

  subscribe(roomId: RoomId, listener: RoomEventListener): () => void {
    const roomListeners = this.listeners.get(roomId) ?? new Set<RoomEventListener>();
    roomListeners.add(listener);
    this.listeners.set(roomId, roomListeners);

    return () => {
      roomListeners.delete(listener);
    };
  }

  publish(event: RoomRealtimeEvent): void {
    const roomListeners = this.listeners.get(event.roomId);
    if (!roomListeners) {
      return;
    }

    for (const listener of roomListeners) {
      listener(event);
    }
  }

  broadcastGameEvent(roomId: RoomId, payload: { action: HybridAction }): void {
    this.publish({
      createdAt: new Date().toISOString(),
      payload,
      roomId,
      type: "game.event"
    });
  }

  updatePresence(roomId: RoomId, presence: PresenceState): void {
    const roomPresence = this.presence.get(roomId) ?? new Map<string, PresenceState>();
    roomPresence.set(presence.playerId, presence);
    this.presence.set(roomId, roomPresence);
    this.publish({
      createdAt: new Date().toISOString(),
      payload: presence,
      roomId,
      type: "presence.updated"
    });
  }

  getPresence(roomId: RoomId): PresenceState[] {
    return Array.from(this.presence.get(roomId)?.values() ?? []);
  }

  sendChatMessage(roomId: RoomId, input: { playerId: string; message: string }): ChatMessage {
    this.messageCount += 1;
    const message: ChatMessage = {
      createdAt: new Date().toISOString(),
      id: `chat-${this.messageCount}`,
      message: input.message,
      playerId: input.playerId
    };

    this.publish({
      createdAt: message.createdAt,
      payload: message,
      roomId,
      type: "chat.message"
    });

    return message;
  }
}
