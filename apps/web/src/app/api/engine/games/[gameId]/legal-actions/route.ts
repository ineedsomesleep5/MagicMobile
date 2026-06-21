import { createGameRuntimeEngineAdapter } from "@/lib/engine";

interface LegalActionsRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function GET(request: Request, context: LegalActionsRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const playerId = new URL(request.url).searchParams.get("playerId");
  if (!playerId) {
    return Response.json({ error: "playerId is required" }, { status: 400 });
  }

  const engine = createGameRuntimeEngineAdapter(gameId);
  return Response.json(await engine.getLegalActions({ gameId, playerId }));
}
