import { createGameRuntimeEngineAdapter } from "@/lib/engine";

interface ResumeRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function POST(request: Request, context: ResumeRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const body = (await request.json()) as { playerId?: string };
  const playerId = body.playerId?.trim();

  if (!playerId) {
    return Response.json(
      {
        error: "resume_player_required",
        message: "A playerId is required to resume a game.",
        category: "invalid_player",
        recoverable: true
      },
      { status: 400 }
    );
  }

  const engine = createGameRuntimeEngineAdapter(gameId);
  try {
    return Response.json(await engine.resumeGame({ gameId, playerId }));
  } catch (error) {
    const gatewayError = error as { status?: number; body?: unknown; message?: string };
    if (gatewayError.status && gatewayError.body) {
      return Response.json(gatewayError.body, { status: gatewayError.status });
    }
    return Response.json(
      {
        error: "bridge_disconnected",
        message: "XMage is temporarily unavailable. Your saved game was kept; reconnect when the server is ready.",
        category: "bridge_disconnected",
        recoverable: true
      },
      { status: 503 }
    );
  }
}
