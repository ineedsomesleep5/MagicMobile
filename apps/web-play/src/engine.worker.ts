/// <reference lib="webworker" />
// The real XMage adapter compiled with GraalVM Web Image (packages/web-engine), off the main thread.
// Classic worker: the image's wrapper is a plain script, loaded with importScripts(). Once Java's main starts,
// this worker's thread belongs to the engine: it never returns to the event loop. The page sends each request
// through a SharedArrayBuffer and the engine reads it in mmHost.take (Atomics.wait while it blocks); replies go
// back with postMessage, which works from a blocked worker.
import { CHANNEL_HEADER_BYTES, STATE_EMPTY, type WorkerInbound, type WorkerOutbound } from "./protocol.ts";

const scope = self as unknown as DedicatedWorkerGlobalScope & {
  mmHost?: { take(block: boolean): string | null; reply(json: string): void };
  mmEngineConfig?: Record<string, unknown>;
  mmEngineMarks?: Record<string, number>;
};

function post(message: WorkerOutbound) {
  scope.postMessage(message);
}

scope.onmessage = (event: MessageEvent<WorkerInbound>) => {
  const message = event.data;
  if (message.type !== "init") return;
  const t0 = performance.now();
  const state = new Int32Array(message.channel, 0, 2);
  const bytes = new Uint8Array(message.channel, CHANNEL_HEADER_BYTES);
  const decoder = new TextDecoder();
  let ready = false;
  scope.mmHost = {
    take(block: boolean): string | null {
      if (!ready) {
        ready = true;
        const marks = scope.mmEngineMarks ?? {};
        const now = performance.now();
        post({
          type: "ready",
          timings: {
            scriptMs: (marks.scriptLoaded ?? t0) - t0,
            fetchAndCompileMs: (marks.instantiated ?? now) - (marks.fetchStart ?? t0),
            mainToFirstTakeMs: now - (marks.instantiated ?? now),
            totalMs: now - t0,
          },
        });
      }
      if (Atomics.load(state, 0) === STATE_EMPTY) {
        if (!block) return null;
        Atomics.wait(state, 0, STATE_EMPTY, 250);
        if (Atomics.load(state, 0) === STATE_EMPTY) return null;
      }
      // TextDecoder refuses views of shared memory: copy the request out first.
      const text = decoder.decode(bytes.slice(0, state[1]));
      Atomics.store(state, 0, STATE_EMPTY);
      Atomics.notify(state, 0);
      return text;
    },
    reply(json: string) {
      post({ type: "reply", json });
    },
  };
  scope.mmEngineConfig = { wasm_path: message.wasmUrl };
  scope.mmEngineMarks = {};
  try {
    scope.importScripts(message.engineUrl);
    scope.mmEngineMarks.scriptLoaded = performance.now();
  } catch (error) {
    post({ type: "fatal", message: String((error as Error)?.stack ?? error) });
  }
};
scope.addEventListener("error", (event) => post({ type: "fatal", message: String(event.message) }));
scope.addEventListener("unhandledrejection", (event) => post({ type: "fatal", message: String(event.reason?.stack ?? event.reason) }));
