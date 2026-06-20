import type { CommanderGameConfig } from "@magicmobile/shared";
import { createRuntimeEngineAdapter } from "@/lib/engine";

export async function POST(request: Request) {
  const config = (await request.json()) as CommanderGameConfig;
  const engine = createRuntimeEngineAdapter();
  return Response.json(await engine.createCommanderGame(config), { status: 201 });
}
