import { roomService } from "../../../features/rooms/server";

export async function POST(request: Request): Promise<Response> {
  const body = (await request.json()) as {
    hostDisplayName?: string;
    hostPlayerId?: string;
    name?: string;
    seatType?: "digital" | "webcam" | "hybrid" | "spectator";
  };

  if (!body.name || !body.hostPlayerId) {
    return Response.json({ error: "name and hostPlayerId are required" }, { status: 400 });
  }

  const input = {
    hostPlayerId: body.hostPlayerId,
    name: body.name
  };

  const room = await roomService.createRoom({
    ...input,
    ...(body.hostDisplayName ? { hostDisplayName: body.hostDisplayName } : {}),
    ...(body.seatType ? { seatType: body.seatType } : {})
  });

  return Response.json(room, { status: 201 });
}
