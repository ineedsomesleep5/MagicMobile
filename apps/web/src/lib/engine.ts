import { createEngineWorkerAdapter, type EngineWorkerConfig } from "@magicmobile/engine-worker";
import type { EngineAdapter } from "@magicmobile/shared";

interface EngineAdapterCache {
  adapter?: EngineAdapter;
  key: string;
}

const globalForEngine = globalThis as typeof globalThis & {
  __magicMobileEngineAdapterCache?: EngineAdapterCache;
};

export function createRuntimeEngineAdapter() {
  const config: EngineWorkerConfig = {
    mode: process.env.ENGINE_MODE === "xmage" ? "xmage" : "mock"
  };
  if (process.env.XMAGE_GATEWAY_URL) {
    config.xmageEndpoint = process.env.XMAGE_GATEWAY_URL;
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
