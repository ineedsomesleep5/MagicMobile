import type { GameCommand } from "@magicmobile/shared";
import { createRuntimeEngineAdapter } from "@/lib/engine";

interface CommandsRouteContext {
  params: Promise<{ gameId: string }>;
}

export async function POST(request: Request, context: CommandsRouteContext): Promise<Response> {
  const { gameId } = await context.params;
  const command = (await request.json()) as GameCommand;
  if (command.gameId !== gameId) {
    return Response.json({ error: "Command gameId does not match route gameId" }, { status: 400 });
  }

  const engine = createRuntimeEngineAdapter();
  return Response.json(await engine.submitGameCommand(command));
}
