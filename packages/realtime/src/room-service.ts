import type { PlayerId, RoomId, RoomSeat, RoomService, RoomState } from "@magicmobile/shared";
import { InMemoryRealtimeGateway } from "./realtime-gateway";
import type { CreateRoomInput, JoinRoomInput, RoomRecord, RoomRealtimeGateway } from "./types";

interface InMemoryRoomServiceOptions {
  gateway?: RoomRealtimeGateway;
  idPrefix?: string;
}

export class InMemoryRoomService implements RoomService {
  private readonly rooms = new Map<RoomId, RoomRecord>();
  private readonly gateway: RoomRealtimeGateway;
  private readonly idPrefix: string;
  private roomCount = 0;
  private gameCount = 0;

  constructor(options: InMemoryRoomServiceOptions = {}) {
    this.gateway = options.gateway ?? new InMemoryRealtimeGateway();
    this.idPrefix = options.idPrefix ?? "room";
  }

  async createRoom(input: CreateRoomInput): Promise<RoomState> {
    this.roomCount += 1;
    const now = new Date().toISOString();
    const room: RoomRecord = {
      createdAt: now,
      id: `${this.idPrefix}-room-${this.roomCount}`,
      name: input.name,
      seats: [
        {
          displayName: input.hostDisplayName ?? "Host",
          playerId: input.hostPlayerId,
          ready: false,
          seatType: input.seatType ?? "digital"
        }
      ],
      status: "lobby",
      updatedAt: now
    };

    this.rooms.set(room.id, room);
    this.publishRoom(room);
    return cloneRoomState(room);
  }

  async joinRoom(input: JoinRoomInput): Promise<RoomState> {
    const room = this.requireRoom(input.roomId);
    const seat: RoomSeat = {
      displayName: input.displayName,
      playerId: input.playerId,
      ready: false,
      seatType: input.seatType ?? "digital"
    };
    const existingSeatIndex = room.seats.findIndex((candidate) => candidate.playerId === input.playerId);

    if (existingSeatIndex >= 0) {
      room.seats[existingSeatIndex] = seat;
    } else {
      room.seats.push(seat);
    }

    this.touch(room);
    return cloneRoomState(room);
  }

  async setReady(input: { roomId: RoomId; playerId: PlayerId; ready: boolean }): Promise<RoomState> {
    const room = this.requireRoom(input.roomId);
    const seat = room.seats.find((candidate) => candidate.playerId === input.playerId);
    if (!seat) {
      throw new Error(`Seat not found for player ${input.playerId}`);
    }

    seat.ready = input.ready;
    this.touch(room);
    return cloneRoomState(room);
  }

  async startRoom(input: { roomId: RoomId }): Promise<RoomState> {
    const room = this.requireRoom(input.roomId);
    const playableSeats = room.seats.filter((seat) => seat.seatType !== "spectator");
    const allPlayableSeatsReady = playableSeats.length > 0 && playableSeats.every((seat) => seat.ready);

    if (!allPlayableSeatsReady) {
      throw new Error("All non-spectator seats must be ready before starting");
    }

    this.gameCount += 1;
    room.gameId = `${this.idPrefix}-game-${this.gameCount}`;
    room.status = "active";
    this.touch(room);
    return cloneRoomState(room);
  }

  async getRoom(roomId: RoomId): Promise<RoomState | undefined> {
    const room = this.rooms.get(roomId);
    return room ? cloneRoomState(room) : undefined;
  }

  getRealtimeGateway(): RoomRealtimeGateway {
    return this.gateway;
  }

  private requireRoom(roomId: RoomId): RoomRecord {
    const room = this.rooms.get(roomId);
    if (!room) {
      throw new Error(`Room not found: ${roomId}`);
    }

    return room;
  }

  private touch(room: RoomRecord): void {
    room.updatedAt = new Date().toISOString();
    this.publishRoom(room);
  }

  private publishRoom(room: RoomRecord): void {
    this.gateway.publish({
      createdAt: new Date().toISOString(),
      payload: cloneRoomState(room),
      roomId: room.id,
      type: "room.updated"
    });
  }
}

function cloneRoomState(room: RoomRecord): RoomState {
  const state: RoomState = {
    id: room.id,
    name: room.name,
    seats: room.seats.map((seat) => ({ ...seat })),
    status: room.status
  };

  if (room.gameId) {
    state.gameId = room.gameId;
  }

  return state;
}
