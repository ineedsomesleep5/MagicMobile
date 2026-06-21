import { createEngineWorkerAdapter, type EngineWorkerConfig } from "@magicmobile/engine-worker";
import type { EngineAdapter } from "@magicmobile/shared";

interface EngineAdapterCache {
  adapter?: EngineAdapter;
  key: string;
}

const globalForEngine = globalThis as typeof globalThis & {
  __magicMobileEngineAdapterCache?: EngineAdapterCache;
};

export function createRuntimeEngineAdapter(options: Partial<EngineWorkerConfig> = {}) {
  const config: EngineWorkerConfig = {
    mode: options.mode ?? (process.env.ENGINE_MODE === "xmage" ? "xmage" : "mock")
  };
  const xmageEndpoint = options.xmageEndpoint ?? process.env.XMAGE_GATEWAY_URL;
  if (xmageEndpoint) {
    config.xmageEndpoint = xmageEndpoint;
  }

  const key = `${config.mode}:${config.xmageEndpoint ?? ""}`;
  const cache = globalForEngine.__magicMobileEngineAdapterCache ?? { key: "" };
  if (!cache.adapter || cache.key !== key) {
    cache.adapter = createEngineWorkerAdapter(config);
    cache.key = key;
    globalForEngine.__magicMobileEngineAdapterCache = cache;
  }

  return cache.adapter;
}

export function createCommanderRuntimeEngineAdapter(config: { simulatorPreset?: string }) {
  return createRuntimeEngineAdapter({
    mode: config.simulatorPreset === "arena-battlefield" ? "mock" : "xmage"
  });
}

export function createGameRuntimeEngineAdapter(gameId: string) {
  return createRuntimeEngineAdapter({
    mode: gameId.startsWith("mock-") ? "mock" : "xmage"
  });
}
