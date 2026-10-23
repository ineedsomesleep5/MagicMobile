// Promise wrapper over the engine's JSON protocol, mirroring the Swift
// EngineClient (packages/ondevice-engine/swift/Sources/MagicMobileOnDevice/EngineClient.swift):
// capabilities, validateDeck, create, poll, respond, concede, destroy (+ shutdown).
import { CHANNEL_BYTES, CHANNEL_HEADER_BYTES, STATE_EMPTY, STATE_REQUEST, type BootTimings, type WorkerOutbound } from "./protocol.ts";

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type JsonObject = { [key: string]: Json };

export interface EngineTransport {
  request(json: string): Promise<string>;
  close?(): void;
}

export class EngineError extends Error {
  readonly code: string;
  readonly details: Json | undefined;
  constructor(code: string, message: string, details?: Json) {
    super(`${code}: ${message}`);
    this.code = code;
    this.details = details;
  }
}

export type EnginePrompt = {
  promptId: string;
  revision: number;
  kind: string;
  payload: JsonObject;
  submitted: boolean;
  responseTypes: string[];
  min: number;
  max: number;
};

export type MatchEvent = { revision: number; kind: string; body: JsonObject };

export type MatchPoll = {
  matchId: string;
  viewerId: string;
  revision: number;
  phase: string;
  resyncRequired: boolean;
  snapshot: JsonObject | null;
  prompt: EnginePrompt | null;
  events: MatchEvent[];
  failure: JsonObject | null;
};

export type Answer = { kind: string; value: Json };

export type CallTiming = { op: string; ms: number; requestBytes: number; replyBytes: number };

export class EngineClient {
  private readonly transport: EngineTransport;
  /** Optional per-call observer (the bench records call latency and payload sizes). */
  onCall: ((timing: CallTiming) => void) | null = null;

  constructor(transport: EngineTransport) {
    this.transport = transport;
  }

  async call(op: string, fields: JsonObject = {}): Promise<Json> {
    if ("op" in fields || "protocol" in fields) throw new EngineError("invalid_message", "Reserved request keys");
    const request = JSON.stringify({ protocol: 1, op, ...fields });
    const started = performance.now();
    const text = await this.transport.request(request);
    this.onCall?.({ op, ms: performance.now() - started, requestBytes: request.length, replyBytes: text.length });
    const reply = JSON.parse(text) as JsonObject;
    if (reply.protocol !== 1 || typeof reply.ok !== "boolean") throw new EngineError("invalid_message", "Invalid engine response envelope");
    if (!reply.ok) {
      const error = (reply.error ?? {}) as JsonObject;
      throw new EngineError(String(error.code ?? "unknown"), String(error.message ?? "Engine rejected request"), error.details);
    }
    if (!("result" in reply)) throw new EngineError("invalid_message", "Missing result");
    return reply.result;
  }

  capabilities(): Promise<JsonObject> {
    return this.call("capabilities") as Promise<JsonObject>;
  }
  validateDeck(deck: JsonObject): Promise<JsonObject> {
    return this.call("validateDeck", { deck }) as Promise<JsonObject>;
  }
  create(configuration: JsonObject): Promise<JsonObject> {
    return this.call("create", { configuration }) as Promise<JsonObject>;
  }
  async poll(matchId: string, seatId: string, after = 0): Promise<MatchPoll> {
    if (!matchId || !seatId || after < 0) throw new EngineError("invalid_message", "Invalid poll identity or revision");
    const poll = (await this.call("poll", { matchId, viewerId: seatId, after })) as unknown as MatchPoll;
    // Correlation, as the Swift client: never let a misrouted reply into another match's view.
    if (poll.matchId !== matchId || poll.viewerId !== seatId) throw new EngineError("invalid_message", "Poll response identity mismatch");
    return poll;
  }
  respond(matchId: string, seatId: string, prompt: EnginePrompt, answer: Answer, requestId: string = crypto.randomUUID()): Promise<JsonObject> {
    const command = { requestId, promptId: prompt.promptId, promptRevision: prompt.revision, answer } as JsonObject;
    return this.call("respond", { matchId, viewerId: seatId, command }) as Promise<JsonObject>;
  }
  async concede(matchId: string, seatId: string): Promise<void> {
    await this.call("concede", { matchId, viewerId: seatId });
  }
  async destroy(matchId: string): Promise<void> {
    await this.call("destroy", { matchId });
  }
  /** Trusted local-only: the last captured engine failure (EngineDiagnostics), if any. */
  diagnostics(): Promise<JsonObject> {
    return this.call("diagnostics") as Promise<JsonObject>;
  }
  async shutdown(): Promise<void> {
    await this.call("shutdown");
  }
}

export type WorkerEngineOptions = {
  /** The image's JavaScript wrapper and module (packages/web-engine build/web). */
  engineUrl: string;
  wasmUrl: string;
};

/**
 * The Web Image engine in a dedicated worker. One request at a time: each is written into the shared channel and
 * the next waits for the previous reply. Needs a cross-origin isolated page (COOP same-origin + COEP require-corp)
 * for SharedArrayBuffer.
 */
export class WorkerTransport implements EngineTransport {
  private readonly worker: Worker;
  private readonly state: Int32Array;
  private readonly bytes: Uint8Array;
  private readonly encoder = new TextEncoder();
  private queue: Promise<unknown> = Promise.resolve();
  private waiter: { resolve: (json: string) => void; reject: (error: Error) => void } | null = null;
  private failure: Error | null = null;
  /** Worker console output the engine printed (Java's System.out/err go to the worker console instead). */
  readonly logs: string[] = [];

  private constructor(worker: Worker, channel: SharedArrayBuffer) {
    this.worker = worker;
    this.state = new Int32Array(channel, 0, 2);
    this.bytes = new Uint8Array(channel, CHANNEL_HEADER_BYTES);
  }

  static start(options: WorkerEngineOptions): Promise<{ transport: WorkerTransport; timings: BootTimings }> {
    if (!crossOriginIsolated) throw new Error("The page is not cross-origin isolated: SharedArrayBuffer is unavailable");
    const worker = new Worker(new URL("./engine.worker.ts", import.meta.url), { name: "xmage-web-image" });
    const channel = new SharedArrayBuffer(CHANNEL_HEADER_BYTES + CHANNEL_BYTES);
    const transport = new WorkerTransport(worker, channel);
    return new Promise((resolve, reject) => {
      worker.onerror = (event) => reject(new Error("Engine worker failed: " + (event.message || "unknown error")));
      worker.onmessage = (event: MessageEvent<WorkerOutbound>) => {
        const message = event.data;
        if (message.type === "ready") {
          worker.onmessage = (next: MessageEvent<WorkerOutbound>) => transport.receive(next.data);
          resolve({ transport, timings: message.timings });
        } else if (message.type === "fatal") {
          reject(new Error("Engine failed to start: " + message.message));
        }
      };
      worker.postMessage({ type: "init", ...options, channel });
    });
  }

  private receive(message: WorkerOutbound) {
    if (message.type === "log") {
      if (this.logs.length < 500) this.logs.push(message.text);
      return;
    }
    if (message.type === "fatal") {
      this.failure = new Error("Engine worker failed: " + message.message);
      this.waiter?.reject(this.failure);
      this.waiter = null;
      return;
    }
    if (message.type !== "reply") return;
    const waiter = this.waiter;
    this.waiter = null;
    waiter?.resolve(message.json);
  }

  request(json: string): Promise<string> {
    const run = () =>
      new Promise<string>((resolve, reject) => {
        if (this.failure) return reject(this.failure);
        const encoded = this.encoder.encode(json);
        if (encoded.length > CHANNEL_BYTES) return reject(new Error("Request too large for the engine channel"));
        if (Atomics.load(this.state, 0) !== STATE_EMPTY) return reject(new Error("Engine channel is busy"));
        this.waiter = { resolve, reject };
        this.bytes.set(encoded);
        this.state[1] = encoded.length;
        Atomics.store(this.state, 0, STATE_REQUEST);
        Atomics.notify(this.state, 0);
      });
    const result = this.queue.then(run, run);
    this.queue = result.catch(() => undefined);
    return result;
  }

  close() {
    this.worker.terminate();
    this.failure = new Error("Engine worker terminated");
    this.waiter?.reject(this.failure);
    this.waiter = null;
  }
}
