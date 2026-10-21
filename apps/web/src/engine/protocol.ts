/**
 * Messages between the page and the Web Image engine worker (docs/WEB_ENGINE_M1.md, apps/web-play's bench).
 * Requests travel through a SharedArrayBuffer, because the worker's thread is blocked inside Java and cannot
 * receive messages; replies, load progress and boot timings come back as ordinary worker messages.
 */

/** SharedArrayBuffer layout: Int32 [state, byteLength], then the request's UTF-8 bytes. */
export const CHANNEL_HEADER_BYTES = 8;
export const CHANNEL_BYTES = 8 << 20;
export const STATE_EMPTY = 0;
export const STATE_REQUEST = 1;

export interface WorkerInit {
  type: "init";
  engineUrl: string; // the image's JavaScript wrapper (engine.js), revalidated over HTTP
  wasmUrl: string; // engine.js.wasm, kept in the Cache API under its content hash
  wasmSha256: string; // from the engine's manifest.json
  wasmBytes: number;
  channel: SharedArrayBuffer;
}

export interface BootTimings {
  downloadMs: number; // 0 when the module came from the Cache API
  fetchAndCompileMs: number; // WebAssembly.instantiateStreaming (compile and instantiate)
  mainToFirstTakeMs: number; // Java main until it first waits for a request
  totalMs: number;
}

export type LoadStage = "checking" | "downloading" | "verifying" | "storing" | "compiling";

export type WorkerOutbound =
  | { type: "stage"; stage: LoadStage; cached?: boolean }
  | { type: "progress"; loaded: number; total: number }
  | { type: "warning"; message: string }
  | { type: "ready"; timings: BootTimings; cached: boolean }
  | { type: "fatal"; message: string }
  | { type: "reply"; json: string };
