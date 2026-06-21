import type { CommanderGameConfig } from "@magicmobile/shared";
import { createCommanderRuntimeEngineAdapter } from "@/lib/engine";
import { validateCommanderGameConfig } from "@/lib/commander-validation";

export async function POST(request: Request) {
  const config = (await request.json()) as CommanderGameConfig;
  if (config.simulatorPreset !== "arena-battlefield") {
    const validationErrors = await validateCommanderGameConfig(config);
    if (validationErrors.length > 0) {
      return Response.json({ error: "Commander deck validation failed.", validationErrors }, { status: 400 });
    }
  }

  const engine = createCommanderRuntimeEngineAdapter(config);
  return Response.json(await engine.createCommanderGame(config), { status: 201 });
}
