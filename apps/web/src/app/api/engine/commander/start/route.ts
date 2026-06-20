import type { CommanderGameConfig, CommanderStartupResponse } from "@magicmobile/shared";
import { createRuntimeEngineAdapter } from "@/lib/engine";
import { cleanupOldStartups, startupStore, toStartupResponse, type StartupRecord } from "@/lib/commander-startups";

export async function POST(request: Request): Promise<Response> {
  cleanupOldStartups();
  const config = (await request.json()) as CommanderGameConfig;
  const startupId = `startup-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
  const starting: StartupRecord = {
    startupId,
    status: "starting",
    message: "Creating XMage Commander table.",
    createdAt: Date.now(),
    config
  };
  startupStore().set(startupId, starting);

  void createRuntimeEngineAdapter()
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
      startupStore().set(startupId, {
        startupId,
        status: "failed",
        error: error instanceof Error ? error.message : "XMage game start failed.",
        createdAt: starting.createdAt
      });
    });

  return Response.json(toStartupResponse(starting) satisfies CommanderStartupResponse, { status: 202 });
}
