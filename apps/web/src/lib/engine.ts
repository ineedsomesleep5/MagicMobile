import { createEngineWorkerAdapter, type EngineWorkerConfig } from "@magicmobile/engine-worker";

export function createRuntimeEngineAdapter() {
  const config: EngineWorkerConfig = {
    mode: process.env.ENGINE_MODE === "xmage" ? "xmage" : "mock"
  };
  if (process.env.XMAGE_GATEWAY_URL) {
    config.xmageEndpoint = process.env.XMAGE_GATEWAY_URL;
  }
  return createEngineWorkerAdapter(config);
}
