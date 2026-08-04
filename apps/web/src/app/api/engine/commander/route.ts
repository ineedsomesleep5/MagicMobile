import type { CommanderGameConfig } from "@magicmobile/shared";
import { createCommanderRuntimeEngineAdapter } from "@/lib/engine";
import { validateCommanderGameConfig } from "@/lib/commander-validation";
import { createSocketToken, gameSessionErrorResponse, saveGameSession } from "@/lib/game-sessions";
import { createSupabaseRequestContext } from "@/lib/supabase/request";

export async function POST(request: Request) {
  try {
    const context = await createSupabaseRequestContext(request);
    const config = (await request.json()) as CommanderGameConfig;
    if (config.simulatorPreset !== "arena-battlefield") {
      const validationErrors = await validateCommanderGameConfig(config);
      if (validationErrors.length > 0) {
        return Response.json({ error: "Commander deck validation failed.", validationErrors }, { status: 400 });
      }
    }

    const engine = createCommanderRuntimeEngineAdapter(config);
    const snapshot = await engine.createCommanderGame(config);
    await saveGameSession(context, snapshot);
    const socketToken = createSocketToken(context, snapshot.id);
    return Response.json(snapshot, socketToken
      ? { status: 201, headers: { "X-MagicMobile-Socket-Token": socketToken } }
      : { status: 201 });
  } catch (error) {
    return gameSessionErrorResponse(error) ?? Response.json(
      { error: error instanceof Error ? error.message : "Commander game could not be started." },
      { status: 500 }
    );
  }
}
