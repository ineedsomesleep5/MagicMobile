import { roomService } from "../../../../../features/rooms/server";

interface RoomRouteContext {
  params: Promise<{ roomId: string }>;
}

export async function POST(_request: Request, context: RoomRouteContext): Promise<Response> {
  const { roomId } = await context.params;
  const room = await roomService.startRoom({ roomId });

  return Response.json(room);
}
