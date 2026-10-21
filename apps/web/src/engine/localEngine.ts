/**
 * The XMage engine on this computer: the Web Image build (packages/web-engine) in a dedicated worker, loaded
 * once per page and shared by every solo game. Speaks the same JSON protocol v1 as the phones' engine and a
 * phone host over the relay (create, poll, respond, concede, destroy), so the game session above it is the same.
 */
import type { EngineTransport } from "../core/engineClient";
import { CHANNEL_BYTES, CHANNEL_HEADER_BYTES, STATE_EMPTY, STATE_REQUEST, type BootTimings, type LoadStage, type WorkerOutbound } from "./protocol";

/** packages/web-engine/build/web/manifest.json, written by the engine build. */
export interface EngineManifest {
  engineBuild: string;
  upstream: string;
  catalogueHash: string;
  /** Content-hashed file names (builds since the CE engine); older bundles use engine.js and engine.js.wasm. */
  files?: { js: string; wasm: string };
  wasm: { bytes: number; sha256: string };
}

export interface EngineLoadState {
  stage: "idle" | "manifest" | LoadStage | "ready" | "failed";
  loaded: number;
  total: number;
  /** The module came from the Cache API rather than the network. */
  cached?: boolean;
  /** navigator.storage.persist(): true when the browser promised not to evict the cached engine. */
  persisted?: boolean;
  warning?: string;
  error?: string;
  timings?: BootTimings;
  manifest?: EngineManifest;
}

/** A tiny module with one GC struct type: validates only where WebAssembly GC (which Web Image needs) is supported. */
const WASM_GC_PROBE = new Uint8Array([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x03, 0x01, 0x5f, 0x00]);

/** Why this browser cannot run the engine, if it cannot. */
export function unsupportedReason(): string | undefined {
  if (typeof WebAssembly !== "object" || typeof WebAssembly.validate !== "function") return "This browser has no WebAssembly.";
  if (!WebAssembly.validate(WASM_GC_PROBE)) return "This browser lacks WebAssembly garbage collection, which the engine needs. Use a current Chrome, Edge or Firefox.";
  if (typeof SharedArrayBuffer === "undefined" || !globalThis.crossOriginIsolated) {
    return "This page is not cross-origin isolated, so the engine cannot share memory with it. Serve it with the COOP and COEP headers (see apps/web/README.md).";
  }
  return undefined;
}

/**
 * The worker's request channel. One request at a time: each is written into the shared buffer and the next waits
 * for the previous reply. While the AI plays, the engine answers a waiting request only at its next published
 * snapshot, so a poll sent then returns with the next board.
 */
export class WorkerTransport {
  private readonly state: Int32Array;
  private readonly bytes: Uint8Array;
  private readonly encoder = new TextEncoder();
  private queue: Promise<unknown> = Promise.resolve();
  private waiter?: { resolve: (json: string) => void; reject: (error: Error) => void };
  failure?: Error;

  constructor(private readonly worker: Worker, channel: SharedArrayBuffer, private readonly onFatal: (error: Error) => void) {
    this.state = new Int32Array(channel, 0, 2);
    this.bytes = new Uint8Array(channel, CHANNEL_HEADER_BYTES);
  }

  receive(message: WorkerOutbound) {
    if (message.type === "fatal") {
      this.fail(new Error("The engine stopped: " + message.message));
    } else if (message.type === "reply") {
      const waiter = this.waiter;
      this.waiter = undefined;
      waiter?.resolve(message.json);
    }
  }

  private fail(error: Error) {
    if (this.failure) return;
    this.failure = error;
    this.waiter?.reject(error);
    this.waiter = undefined;
    this.onFatal(error);
  }

  request: EngineTransport = (json) => {
    const run = () => new Promise<string>((resolve, reject) => {
      if (this.failure) return reject(this.failure);
      const encoded = this.encoder.encode(json);
      if (encoded.length > CHANNEL_BYTES) return reject(new Error("The request is too large for the engine channel."));
      if (Atomics.load(this.state, 0) !== STATE_EMPTY) return reject(new Error("The engine channel is busy."));
      this.waiter = { resolve, reject };
      this.bytes.set(encoded);
      this.state[1] = encoded.length;
      Atomics.store(this.state, 0, STATE_REQUEST);
      Atomics.notify(this.state, 0);
    });
    const result = this.queue.then(run, run);
    this.queue = result.catch(() => undefined);
    return result;
  };

  close() {
    this.worker.terminate();
    this.fail(new Error("The engine was closed."));
  }
}

export class LocalEngine {
  state: EngineLoadState = { stage: "idle", loaded: 0, total: 0 };
  version = 0;
  private listeners = new Set<() => void>();
  private loading?: Promise<WorkerTransport>;
  private transport?: WorkerTransport;

  /** `base` serves manifest.json and the files it names (the dev server maps it to packages/web-engine/build/web). */
  constructor(private readonly base = "/engine/") {}

  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  private set(patch: Partial<EngineLoadState>) {
    this.state = { ...this.state, ...patch };
    this.version += 1;
    this.listeners.forEach((listener) => listener());
  }

  /** Loads the engine once; every caller shares the load. After a failure, the next call starts over. */
  start(): Promise<WorkerTransport> {
    if (this.transport?.failure) this.loading = undefined;
    if (!this.loading) {
      this.loading = this.load().catch((error: unknown) => {
        this.loading = undefined;
        this.set({ stage: "failed", error: error instanceof Error ? error.message : String(error) });
        throw error;
      });
    }
    return this.loading;
  }

  private async load(): Promise<WorkerTransport> {
    this.transport?.close();
    this.transport = undefined;
    this.set({ stage: "manifest", loaded: 0, total: 0, error: undefined, warning: undefined, timings: undefined });
    const unsupported = unsupportedReason();
    if (unsupported) throw new Error(unsupported);
    void this.persist();
    const url = (path: string) => new URL(this.base + path, location.href).href;
    const reply = await fetch(url("manifest.json"), { cache: "no-cache" });
    if (!reply.ok) throw new Error(`The engine is not on this server (manifest: HTTP ${reply.status}). See apps/web/README.md for where to put it.`);
    const manifest = await reply.json() as EngineManifest;
    if (!/^[0-9a-f]{64}$/.test(manifest.wasm?.sha256 ?? "") || !(manifest.wasm?.bytes > 0)) throw new Error("The engine manifest is incomplete.");
    this.set({ manifest, total: manifest.wasm.bytes });

    const worker = new Worker(new URL("./engine.worker.ts", import.meta.url), { name: "xmage-web-image" });
    const channel = new SharedArrayBuffer(CHANNEL_HEADER_BYTES + CHANNEL_BYTES);
    const transport = new WorkerTransport(worker, channel, (error) => {
      if (this.transport === transport) this.set({ stage: "failed", error: error.message });
    });
    return new Promise<WorkerTransport>((resolve, reject) => {
      worker.onerror = (event) => { reject(new Error("The engine worker failed: " + (event.message || "unknown error"))); worker.terminate(); };
      worker.onmessage = (event: MessageEvent<WorkerOutbound>) => {
        const message = event.data;
        switch (message.type) {
          case "stage": this.set({ stage: message.stage, cached: message.cached ?? this.state.cached }); break;
          case "progress": this.set({ loaded: message.loaded, total: message.total }); break;
          case "warning": this.set({ warning: message.message }); break;
          case "ready":
            this.transport = transport;
            worker.onmessage = (next: MessageEvent<WorkerOutbound>) => transport.receive(next.data);
            this.set({ stage: "ready", cached: message.cached, timings: message.timings, loaded: this.state.total });
            resolve(transport);
            break;
          case "fatal":
            worker.terminate();
            reject(new Error(message.message));
            break;
          default: break;
        }
      };
      worker.postMessage({
        type: "init", engineUrl: url(manifest.files?.js ?? "engine.js"), wasmUrl: url(manifest.files?.wasm ?? "engine.js.wasm"), wasmSha256: manifest.wasm.sha256,
        wasmBytes: manifest.wasm.bytes, channel,
      });
    });
  }

  /** Asks the browser to keep the cached engine through storage pressure; Chrome decides without a prompt. */
  private async persist() {
    try {
      const storage = navigator.storage;
      if (!storage?.persist) return;
      const persisted = (await storage.persisted?.()) || await storage.persist();
      this.set({ persisted });
    } catch { /* not offered in this browser */ }
  }

  /** Throws the engine away, for example after it stopped; the next start() loads it again (from the cache). */
  reset() {
    this.transport?.close();
    this.transport = undefined;
    this.loading = undefined;
    this.set({ stage: "idle" });
  }
}

/**
 * One engine per page: it survives going back to the setup screen and serves every game. Kept on globalThis so a
 * development hot reload of the screens reuses it instead of starting another 1 GB worker.
 */
export const localEngine = (): LocalEngine => {
  const page = globalThis as { mmLocalEngine?: LocalEngine };
  return (page.mmLocalEngine ??= new LocalEngine());
};
