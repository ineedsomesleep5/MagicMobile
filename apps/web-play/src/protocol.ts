// Messages between the page and the Web Image engine worker (docs/WEB_ENGINE_M1.md).
// Requests travel through a SharedArrayBuffer (the worker's thread is blocked in Java, so it cannot receive
// messages); replies and boot timings come back as ordinary worker messages.

/** SharedArrayBuffer layout: Int32 [state, byteLength], then the request's UTF-8 bytes. */
export const CHANNEL_HEADER_BYTES = 8;
export const CHANNEL_BYTES = 8 << 20;
export const STATE_EMPTY = 0;
export const STATE_REQUEST = 1;

export type WorkerInbound = {
  type: "init";
  engineUrl: string; // the image's JavaScript wrapper (engine.js)
  wasmUrl: string; // engine.js.wasm
  channel: SharedArrayBuffer;
};

export type BootTimings = {
  scriptMs: number; // importScripts(engine.js)
  fetchAndCompileMs: number; // fetch + WebAssembly.instantiateStreaming (download, compile, instantiate)
  mainToFirstTakeMs: number; // Java main until it first waits for a request
  totalMs: number;
};

export type WorkerOutbound =
  | { type: "ready"; timings: BootTimings }
  | { type: "fatal"; message: string }
  | { type: "reply"; json: string }
  | { type: "log"; text: string };
