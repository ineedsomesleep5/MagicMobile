import { roomService } from "../../../../../features/rooms/server";

interface RoomRouteContext {
  params: Promise<{ roomId: string }>;
}

export async function POST(request: Request, context: RoomRouteContext): Promise<Response> {
  const { roomId } = await context.params;
  const body = (await request.json()) as {
    playerId?: string;
    ready?: boolean;
  };

  if (!body.playerId || typeof body.ready !== "boolean") {
    return Response.json({ error: "playerId and ready are required" }, { status: 400 });
  }

  const room = await roomService.setReady({
    playerId: body.playerId,
    ready: body.ready,
    roomId
  });

  return Response.json(room);
}
