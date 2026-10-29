/// <reference lib="webworker" />
/**
 * The real XMage adapter compiled with GraalVM Web Image (packages/web-engine), off the main thread. Classic
 * worker: the image's wrapper is a plain script, loaded with importScripts(). Once Java's main starts, this
 * worker's thread belongs to the engine and never returns to the event loop. The page writes each request into a
 * SharedArrayBuffer and the engine reads it in mmHost.take (Atomics.wait while it blocks); replies go back with
 * postMessage, which works from a blocked worker.
 *
 * Before the wrapper runs, the 174 MB module is taken from the Cache API, keyed by its SHA-256 from the engine's
 * manifest, or downloaded once (with progress), checked against that hash and stored. The wrapper's own
 * fetch(wasmPath) is then answered with that response, so the engine bundle needs no change.
 *
 * Only `import type` here: Vite's dev server serves a classic worker unbundled, so a runtime import would fail.
 */
import type { LoadStage, WorkerInit, WorkerOutbound } from "./protocol";

// Equal to protocol.ts (see above).
const CHANNEL_HEADER_BYTES = 8;
const STATE_EMPTY = 0;
const CACHE_NAME = "magicmobile-engine";

const scope = self as unknown as DedicatedWorkerGlobalScope & {
  mmHost?: { take(block: boolean): string | null; reply(json: string): void };
  mmEngineConfig?: Record<string, unknown>;
  mmEngineMarks?: Record<string, number>;
};
const nativeFetch = scope.fetch.bind(scope);

const post = (message: WorkerOutbound) => scope.postMessage(message);
const stage = (value: LoadStage, cached?: boolean) => post({ type: "stage", stage: value, cached });
const hex = (bytes: ArrayBuffer) => Array.from(new Uint8Array(bytes), (b) => b.toString(16).padStart(2, "0")).join("");
const reason = (error: unknown) => (error instanceof Error ? error.message : String(error));

async function openCache(): Promise<Cache | undefined> {
  try { return await scope.caches.open(CACHE_NAME); } catch { return undefined; }
}

/** Drops engines other than this one: an old build is never used again once the manifest moved on. */
async function prune(cache: Cache, sha256: string) {
  try {
    for (const request of await cache.keys()) if (!request.url.includes(`/${sha256}/`)) await cache.delete(request);
  } catch { /* best effort */ }
}

/**
 * The module, downloaded with progress. A hosted copy comes gzipped (Vercel's free plan takes no file over 100 MB)
 * and is unpacked here, unless the server already sent it with Content-Encoding and the browser unpacked it.
 */
async function download(init: WorkerInit): Promise<Blob> {
  const gzip = init.wasmGzipUrl !== undefined && init.wasmGzipBytes !== undefined;
  const reply = await nativeFetch(gzip ? init.wasmGzipUrl! : init.wasmUrl, { cache: "no-store" });
  if (!reply.ok || !reply.body) throw new Error(`The engine download failed (HTTP ${reply.status}).`);
  const unpack = gzip && !/gzip/i.test(reply.headers.get("content-encoding") ?? "");
  const total = unpack ? init.wasmGzipBytes! : init.wasmBytes;
  let loaded = 0;
  let posted = 0;
  // Progress counts the bytes as they arrive, before any unpacking.
  const counted = reply.body.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      loaded += chunk.byteLength;
      const now = performance.now();
      if (now - posted > 100) { posted = now; post({ type: "progress", loaded, total }); }
      controller.enqueue(chunk);
    },
  }));
  const body = unpack ? counted.pipeThrough(new DecompressionStream("gzip") as unknown as ReadableWritablePair<Uint8Array, Uint8Array>) : counted;
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    bytes += value.byteLength;
  }
  post({ type: "progress", loaded, total });
  if (bytes !== init.wasmBytes) throw new Error(`The engine download stopped early (${bytes} of ${init.wasmBytes} bytes). Reload to try again.`);
  return new Blob(chunks as BlobPart[], { type: "application/wasm" });
}

/** The module as a Response for instantiateStreaming: from the Cache API, or downloaded, verified and stored. */
async function wasmResponse(init: WorkerInit): Promise<{ response: Response; cached: boolean; downloadMs: number }> {
  stage("checking");
  const cache = await openCache();
  const key = new URL(`/engine-cache/${init.wasmSha256}/engine.js.wasm`, scope.location.origin).href;
  const hit = await cache?.match(key).catch(() => undefined);
  if (hit && cache) {
    void prune(cache, init.wasmSha256);
    return { response: hit, cached: true, downloadMs: 0 };
  }
  stage("downloading");
  const started = performance.now();
  const blob = await download(init);
  const downloadMs = performance.now() - started;
  // The key claims this hash, so only bytes that have it are stored under it.
  stage("verifying");
  if (hex(await crypto.subtle.digest("SHA-256", await blob.arrayBuffer())) !== init.wasmSha256) {
    throw new Error("The engine download does not match its published hash. Reload to try again.");
  }
  if (cache) {
    stage("storing");
    try {
      await cache.put(key, new Response(blob, { headers: { "Content-Type": "application/wasm", "Content-Length": String(blob.size) } }));
      void prune(cache, init.wasmSha256);
    } catch (error) {
      post({ type: "warning", message: `The engine could not be kept on this computer (${reason(error)}), so it downloads again next time.` });
    }
  } else {
    post({ type: "warning", message: "This browser does not let the page keep files, so the engine downloads again next time." });
  }
  return { response: new Response(blob, { headers: { "Content-Type": "application/wasm" } }), cached: false, downloadMs };
}

scope.onmessage = async (event: MessageEvent<WorkerInit>) => {
  const init = event.data;
  if (init?.type !== "init") return;
  const t0 = performance.now();
  let wasm: Awaited<ReturnType<typeof wasmResponse>>;
  try {
    wasm = await wasmResponse(init);
  } catch (error) {
    post({ type: "fatal", message: reason(error) });
    return;
  }
  const state = new Int32Array(init.channel, 0, 2);
  const bytes = new Uint8Array(init.channel, CHANNEL_HEADER_BYTES);
  const decoder = new TextDecoder();
  let ready = false;
  scope.mmHost = {
    take(block: boolean): string | null {
      if (!ready) {
        ready = true;
        const marks = scope.mmEngineMarks ?? {};
        const now = performance.now();
        post({
          type: "ready", cached: wasm.cached,
          timings: {
            downloadMs: wasm.downloadMs,
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
  scope.mmEngineConfig = { wasm_path: init.wasmUrl };
  scope.mmEngineMarks = {};
  // The wrapper fetches config.wasm_path once and streams it into WebAssembly.instantiateStreaming.
  scope.fetch = ((input: RequestInfo | URL, options?: RequestInit) =>
    input === init.wasmUrl ? Promise.resolve(wasm.response) : nativeFetch(input, options)) as typeof fetch;
  stage("compiling", wasm.cached);
  try {
    scope.importScripts(init.engineUrl);
  } catch (error) {
    post({ type: "fatal", message: reason(error) });
  }
};
scope.addEventListener("error", (event) => post({ type: "fatal", message: String(event.message) }));
scope.addEventListener("unhandledrejection", (event) => post({ type: "fatal", message: String(event.reason?.stack ?? event.reason) }));
