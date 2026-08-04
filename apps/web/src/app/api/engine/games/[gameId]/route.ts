import { createGameRuntimeEngineAdapter } from "@/lib/engine";
import { gameSessionErrorResponse, requireGameSession } from "@/lib/game-sessions";

interface GameRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function GET(request: Request, context: GameRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const engine = createGameRuntimeEngineAdapter(gameId);

  try {
    await requireGameSession(request, gameId);
    return Response.json(await engine.getSnapshot(gameId));
  } catch (error) {
    const sessionResponse = gameSessionErrorResponse(error);
    if (sessionResponse) return sessionResponse;
    return Response.json(
      { error: error instanceof Error ? error.message : "Game snapshot unavailable" },
      { status: 404 }
    );
  }
}
