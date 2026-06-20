import { roomService } from "../../../../../features/rooms/server";

interface RoomRouteContext {
  params: Promise<{ roomId: string }>;
}

export async function POST(request: Request, context: RoomRouteContext): Promise<Response> {
  const { roomId } = await context.params;
  const body = (await request.json()) as {
    displayName?: string;
    playerId?: string;
    seatType?: "digital" | "webcam" | "hybrid" | "spectator";
  };

  if (!body.playerId || !body.displayName) {
    return Response.json({ error: "playerId and displayName are required" }, { status: 400 });
  }

  const room = await roomService.joinRoom({
    displayName: body.displayName,
    playerId: body.playerId,
    roomId,
    ...(body.seatType ? { seatType: body.seatType } : {})
  });

  return Response.json(room);
}
