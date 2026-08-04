import type { DeckEntry, DeckId, DeckSourceKind, GameId, PlayerId, RoomId, SeatType } from "./types";

export interface UserModel {
  id: PlayerId;
  displayName: string;
  createdAt: string;
}

export interface DeckModel {
  id: DeckId;
  ownerId: PlayerId;
  name: string;
  format: "commander";
  commanderName?: string;
  rawList: string;
  sourceKind: DeckSourceKind;
  sourceUrl?: string;
  sourceFilename?: string;
  revision: number;
  createdAt: string;
  updatedAt: string;
}

export interface DeckEntryModel extends DeckEntry {
  id: string;
  deckId: DeckId;
  ownerId: PlayerId;
  position: number;
}

export interface GameSessionModel {
  id: string;
  ownerId: PlayerId;
  gameId: GameId;
  status: "starting" | "active" | "complete" | "failed";
  revision: number;
  snapshotJson?: string;
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
