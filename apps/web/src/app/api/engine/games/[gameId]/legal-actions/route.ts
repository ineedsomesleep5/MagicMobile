import { createGameRuntimeEngineAdapter } from "@/lib/engine";
import { gameSessionErrorResponse, requireGameSession } from "@/lib/game-sessions";

interface LegalActionsRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function GET(request: Request, context: LegalActionsRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const playerId = new URL(request.url).searchParams.get("playerId");
  if (!playerId) {
    return Response.json({ error: "playerId is required" }, { status: 400 });
  }

  try {
    await requireGameSession(request, gameId);
    const engine = createGameRuntimeEngineAdapter(gameId);
    return Response.json(await engine.getLegalActions({ gameId, playerId }));
  } catch (error) {
    return gameSessionErrorResponse(error) ?? Response.json({ error: "Legal actions unavailable." }, { status: 500 });
  }
}
