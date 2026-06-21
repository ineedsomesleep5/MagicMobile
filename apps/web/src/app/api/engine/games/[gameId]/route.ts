import { createGameRuntimeEngineAdapter } from "@/lib/engine";

interface GameRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function GET(_request: Request, context: GameRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const engine = createGameRuntimeEngineAdapter(gameId);

  try {
    return Response.json(await engine.getSnapshot(gameId));
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Game snapshot unavailable" },
      { status: 404 }
    );
  }
}
