import type { CommanderGameConfig, CommanderStartupResponse } from "@magicmobile/shared";
import { createCommanderRuntimeEngineAdapter } from "@/lib/engine";
import { cleanupOldStartups, startupStore, toStartupResponse, type StartupRecord } from "@/lib/commander-startups";
import { validateCommanderGameConfig } from "@/lib/commander-validation";

export async function POST(request: Request): Promise<Response> {
  cleanupOldStartups();
  const config = (await request.json()) as CommanderGameConfig;
  if (config.simulatorPreset !== "arena-battlefield") {
    const validationErrors = await validateCommanderGameConfig(config);
    if (validationErrors.length > 0) {
      return Response.json({ error: "Commander deck validation failed.", validationErrors }, { status: 400 });
    }
  }

  const startupId = `startup-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
  const starting: StartupRecord = {
    startupId,
    status: "starting",
    message: "Creating XMage Commander table.",
    createdAt: Date.now(),
    config
  };
  startupStore().set(startupId, starting);

  void createCommanderRuntimeEngineAdapter(config)
    .createCommanderGame(config)
    .then((snapshot) => {
      startupStore().set(startupId, {
        startupId,
        status: "ready",
        snapshot,
        message: "XMage game is ready.",
        createdAt: starting.createdAt
      });
    })
    .catch((error) => {
      const gatewayFailure = (error as { body?: { message?: unknown; deckErrors?: unknown } }).body;
      const deckErrors = Array.isArray(gatewayFailure?.deckErrors)
        ? (gatewayFailure.deckErrors as NonNullable<CommanderStartupResponse["deckErrors"]>)
        : undefined;
      const failureMessage = typeof gatewayFailure?.message === "string"
        ? gatewayFailure.message
        : error instanceof Error
          ? error.message
          : "XMage game start failed.";
      startupStore().set(startupId, {
        startupId,
        status: "failed",
        error: failureMessage,
        ...(deckErrors ? { deckErrors } : {}),
        createdAt: starting.createdAt
      });
    });

  return Response.json(toStartupResponse(starting) satisfies CommanderStartupResponse, { status: 202 });
}
