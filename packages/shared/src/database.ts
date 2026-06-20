import type { DeckId, GameId, PlayerId, RoomId, SeatType } from "./types";

export interface UserModel {
  id: PlayerId;
  displayName: string;
  createdAt: string;
}

export interface DeckModel {
  id: DeckId;
  ownerId: PlayerId;
  name: string;
  commanderName?: string;
  rawList: string;
  createdAt: string;
  updatedAt: string;
}

export interface RoomModel {
  id: RoomId;
  name: string;
  status: "lobby" | "starting" | "active" | "complete";
  createdAt: string;
}

export interface RoomSeatModel {
  roomId: RoomId;
  playerId: PlayerId;
  seatType: SeatType;
  ready: boolean;
}

export interface GameModel {
  id: GameId;
  roomId: RoomId;
  engine: "mock" | "xmage";
  snapshotJson: string;
  createdAt: string;
  updatedAt: string;
}
