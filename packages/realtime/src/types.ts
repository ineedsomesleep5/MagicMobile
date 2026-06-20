import type { HybridAction, PlayerId, RoomId, RoomState, SeatType, ZoneName } from "@magicmobile/shared";

export interface RoomRecord extends RoomState {
  createdAt: string;
  updatedAt: string;
}

export type PresenceStatus = "online" | "offline" | "away";

export interface PresenceState {
  playerId: PlayerId;
  status: PresenceStatus;
}

export interface ChatMessage {
  id: string;
  playerId: PlayerId;
  message: string;
  createdAt: string;
}

export type RoomRealtimeEvent =
  | {
      type: "room.updated";
      roomId: RoomId;
      payload: RoomState;
      createdAt: string;
    }
  | {
      type: "game.event";
      roomId: RoomId;
      payload: { action: HybridAction };
      createdAt: string;
    }
  | {
      type: "presence.updated";
      roomId: RoomId;
      payload: PresenceState;
      createdAt: string;
    }
  | {
      type: "chat.message";
      roomId: RoomId;
      payload: ChatMessage;
      createdAt: string;
    };

export type RoomEventListener = (event: RoomRealtimeEvent) => void;

export interface RoomRealtimeGateway {
  subscribe(roomId: RoomId, listener: RoomEventListener): () => void;
  publish(event: RoomRealtimeEvent): void;
  broadcastGameEvent(roomId: RoomId, payload: { action: HybridAction }): void;
  updatePresence(roomId: RoomId, presence: PresenceState): void;
  getPresence(roomId: RoomId): PresenceState[];
  sendChatMessage(roomId: RoomId, input: { playerId: PlayerId; message: string }): ChatMessage;
}

export interface CreateRoomInput {
  name: string;
  hostPlayerId: PlayerId;
  hostDisplayName?: string;
  seatType?: SeatType;
}

export interface JoinRoomInput {
  roomId: RoomId;
  playerId: PlayerId;
  displayName: string;
  seatType?: SeatType;
}

export type HybridPaperAction = HybridAction & {
  type:
    | "play_land"
    | "cast_spell"
    | "move_card"
    | "tap_permanent"
    | "untap_permanent"
    | "attack_player"
    | "add_counter"
    | "create_token"
    | "change_life"
    | "update_commander_damage"
    | "pass_priority";
  fromZone?: ZoneName;
  toZone?: ZoneName;
};

export interface HybridActionValidation {
  valid: boolean;
  errors: string[];
}
