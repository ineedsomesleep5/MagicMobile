import type { PlayerId, RoomId, RoomState, SeatType } from "@magicmobile/shared";

async function parseRoomResponse(response: Response): Promise<RoomState> {
  if (!response.ok) {
    throw new Error(await response.text());
  }

  return response.json() as Promise<RoomState>;
}

export async function createRoom(input: {
  name: string;
  hostPlayerId: PlayerId;
  hostDisplayName?: string;
  seatType?: SeatType;
}): Promise<RoomState> {
  return parseRoomResponse(
    await fetch("/api/rooms", {
      body: JSON.stringify(input),
      headers: { "content-type": "application/json" },
      method: "POST"
    })
  );
}

export async function getRoom(roomId: RoomId): Promise<RoomState> {
  return parseRoomResponse(await fetch(`/api/rooms/${roomId}`));
}

export async function joinRoom(input: {
  roomId: RoomId;
  playerId: PlayerId;
  displayName: string;
  seatType?: SeatType;
}): Promise<RoomState> {
  return parseRoomResponse(
    await fetch(`/api/rooms/${input.roomId}/join`, {
      body: JSON.stringify(input),
      headers: { "content-type": "application/json" },
      method: "POST"
    })
  );
}

export async function setReady(input: { roomId: RoomId; playerId: PlayerId; ready: boolean }): Promise<RoomState> {
  return parseRoomResponse(
    await fetch(`/api/rooms/${input.roomId}/ready`, {
      body: JSON.stringify(input),
      headers: { "content-type": "application/json" },
      method: "POST"
    })
  );
}

export async function startRoom(roomId: RoomId): Promise<RoomState> {
  return parseRoomResponse(
    await fetch(`/api/rooms/${roomId}/start`, {
      method: "POST"
    })
  );
}
