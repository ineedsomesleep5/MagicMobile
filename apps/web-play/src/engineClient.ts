// SPIKE ONLY. Promise wrapper over the engine's JSON protocol, mirroring the Swift
// EngineClient (packages/ondevice-engine/swift/Sources/MagicMobileOnDevice/EngineClient.swift):
// capabilities, validateDeck, create, poll, respond, concede, destroy (+ shutdown).
import type { ReadyTimings, ResourceSummary, WorkerOutbound } from "./protocol.ts";

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
  async shutdown(): Promise<void> {
    await this.call("shutdown");
  }
}

export type WorkerEngineOptions = {
  /** CheerpJ runtime loader from Leaning Technologies' CDN (Community license terms). */
  loaderUrl: string;
  /** Same-origin path of the jar directory, e.g. "/engine/jars/". */
  jarBase: string;
  /** Classpath order from build/web/manifest.json. */
  jars: string[];
};

/** The CheerpJ engine in a dedicated worker; the page's main thread only posts JSON strings. */
export class WorkerTransport implements EngineTransport {
  private readonly worker: Worker;
  private nextId = 1;
  private readonly pending = new Map<number, { resolve: (json: string) => void; reject: (error: Error) => void }>();
  /** Java-side time of the most recent call, excluding postMessage hops. */
  lastJavaMs = 0;

  private constructor(worker: Worker) {
    this.worker = worker;
  }

  static start(options: WorkerEngineOptions): Promise<{ transport: WorkerTransport; timings: ReadyTimings }> {
    const worker = new Worker(new URL("./engine.worker.ts", import.meta.url), { name: "xmage-cheerpj" });
    const transport = new WorkerTransport(worker);
    return new Promise((resolve, reject) => {
      worker.onerror = (event) => reject(new Error("Engine worker failed: " + (event.message || "unknown error")));
      worker.onmessage = (event: MessageEvent<WorkerOutbound>) => {
        const message = event.data;
        if (message.type === "ready") {
          worker.onmessage = (next: MessageEvent<WorkerOutbound>) => transport.receive(next.data);
          resolve({ transport, timings: message.timings });
        } else if (message.type === "fatal") {
          reject(new Error("CheerpJ initialization failed: " + message.message));
        }
      };
      worker.postMessage({ type: "init", ...options });
    });
  }

  private readonly resourceWaiters = new Map<number, (summary: ResourceSummary) => void>();

  /** Network bytes the worker has fetched so far (CheerpJ runtime + jar ranges). */
  resources(): Promise<ResourceSummary> {
    const id = this.nextId++;
    return new Promise((resolve) => {
      this.resourceWaiters.set(id, resolve);
      this.worker.postMessage({ type: "resources", id });
    });
  }

  private receive(message: WorkerOutbound) {
    if (message.type === "resources") {
      this.resourceWaiters.get(message.id)?.(message.summary);
      this.resourceWaiters.delete(message.id);
      return;
    }
    if (message.type !== "reply") return;
    const waiter = this.pending.get(message.id);
    if (!waiter) return;
    this.pending.delete(message.id);
    this.lastJavaMs = message.javaMs;
    if (message.error !== undefined || message.json === undefined) waiter.reject(new Error("Java call failed: " + message.error));
    else waiter.resolve(message.json);
  }

  request(json: string): Promise<string> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.worker.postMessage({ type: "request", id, json });
    });
  }

  close() {
    this.worker.terminate();
    for (const waiter of this.pending.values()) waiter.reject(new Error("Engine worker terminated"));
    this.pending.clear();
  }
}
