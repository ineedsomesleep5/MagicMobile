import { randomUUID } from "node:crypto";
import type { GameCommand } from "@magicmobile/shared";
import { createRuntimeEngineAdapter } from "@/lib/engine";

interface CommandsRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function POST(request: Request, context: CommandsRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const requestId = request.headers.get("x-request-id") ?? randomUUID();
  const startedAt = Date.now();
  const command = (await request.json()) as GameCommand & { requestId?: string };
  command.requestId = requestId;
  if (command.gameId !== gameId) {
    return Response.json({ error: "Command gameId does not match route gameId" }, { status: 400 });
  }

  const engine = createRuntimeEngineAdapter();
  try {
    const snapshot = await engine.submitGameCommand(command);
    console.info(`command ${requestId} ${command.type} ${gameId} completed in ${Date.now() - startedAt}ms`);
    return Response.json(snapshot);
  } catch (error) {
    const maybeGatewayError = error as { status?: number; body?: unknown; message?: string };
    console.warn(`command ${requestId} ${command.type} ${gameId} failed in ${Date.now() - startedAt}ms`, maybeGatewayError.message);
    if (maybeGatewayError.status && maybeGatewayError.body) {
      return Response.json(maybeGatewayError.body, { status: maybeGatewayError.status });
    }
    return Response.json(
      { error: error instanceof Error ? error.message : "Command failed" },
      { status: 500 }
    );
  }
}
