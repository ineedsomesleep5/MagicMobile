import type { EngineAdapter } from "@magicmobile/shared";
import { MockEngineAdapter, XmageEngineAdapter } from "@magicmobile/engine";

export interface EngineWorkerConfig {
  mode?: "mock" | "xmage";
  xmageEndpoint?: string;
}

export function createEngineWorkerAdapter(config: EngineWorkerConfig = {}): EngineAdapter {
  if (config.mode === "xmage") {
    return new XmageEngineAdapter({ endpoint: config.xmageEndpoint ?? "http://localhost:17171" });
  }

  return new MockEngineAdapter();
}
