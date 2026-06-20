import { roomService } from "../../../../features/rooms/server";

interface RoomRouteContext {
  params: Promise<{ roomId: string }>;
}

export async function GET(_request: Request, context: RoomRouteContext): Promise<Response> {
  const { roomId } = await context.params;
  const room = await roomService.getRoom(roomId);
  if (!room) {
    return Response.json({ error: "Room not found" }, { status: 404 });
  }

  return Response.json(room);
}
