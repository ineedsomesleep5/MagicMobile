/** Port of EngineClient.kt (Swift EngineClient.swift): the JSON protocol v1 client, transport-agnostic. */
import { arr, bool, EngineError, EngineJson, get, int, type J, jsonEqual, type JObject, obj, str } from "./json";

export type EngineTransport = (request: string) => Promise<string>;

const supportedResponseTypes = new Set(["boolean", "uuid", "string", "integer", "integers", "mana"]);

export class EnginePrompt {
  readonly id: string;
  readonly revision: number;
  readonly kind: string;
  readonly payload: JObject;
  readonly submitted: boolean;
  readonly responseTypes: string[];
  readonly minimum: number;
  readonly maximum: number;

  constructor(value: J) {
    const id = str(get(value, "promptId"));
    const revision = int(get(value, "revision"));
    const kind = str(get(value, "kind"));
    const payload = get(value, "payload");
    const submitted = bool(get(value, "submitted"));
    const types = arr(get(value, "responseTypes"));
    const minimum = int(get(value, "min"));
    const maximum = int(get(value, "max"));
    if (id === undefined || revision === undefined || revision < 0 || kind === undefined || payload === undefined ||
      submitted === undefined || types === undefined || minimum === undefined || maximum === undefined) {
      throw EngineError.invalid("Malformed engine prompt");
    }
    const fields = obj(payload);
    if (id.length === 0 || kind.length === 0 || !fields || minimum > maximum || types.length === 0 || types.length > 6) {
      throw EngineError.invalid("Invalid prompt structure or bounds");
    }
    const responseTypes = types.map((type) => {
      if (typeof type !== "string") throw EngineError.invalid("Response type must be a string");
      return type;
    });
    if (new Set(responseTypes).size !== responseTypes.length || !responseTypes.every((type) => supportedResponseTypes.has(type))) {
      throw EngineError.invalid("Unknown or duplicate prompt response type");
    }
    this.id = id; this.revision = revision; this.kind = kind; this.payload = fields; this.submitted = submitted;
    this.responseTypes = responseTypes; this.minimum = minimum; this.maximum = maximum;
  }

  command(answer: J, requestID: string): J {
    return { requestId: requestID.toLowerCase(), promptId: this.id, promptRevision: this.revision, answer };
  }

  static answer(kind: string, value: J): JObject { return { kind, value }; }
}

export class MatchPoll {
  readonly raw: JObject;
  readonly matchID: string;
  readonly seatID: string;
  readonly phase: string;
  readonly revision: number;
  readonly prompt?: EnginePrompt;
  readonly snapshot?: J;
  readonly resyncRequired: boolean;

  constructor(value: J) {
    const fields = obj(value);
    const matchID = str(get(value, "matchId"));
    const seatID = str(get(value, "viewerId"));
    const revision = int(get(value, "revision"));
    const phase = str(get(value, "phase"));
    const resync = bool(get(value, "resyncRequired"));
    if (!fields || matchID === undefined || seatID === undefined || revision === undefined || revision < 0 || phase === undefined ||
      resync === undefined) throw EngineError.invalid("Malformed match poll");
    this.raw = fields; this.matchID = matchID; this.seatID = seatID; this.revision = revision; this.phase = phase;
    this.resyncRequired = resync;
    const snapshot = get(value, "snapshot");
    this.snapshot = snapshot === null ? undefined : snapshot;
    const prompt = get(value, "prompt");
    this.prompt = prompt === undefined || prompt === null ? undefined : new EnginePrompt(prompt);
  }
}

export class EngineClient {
  private lastPoll?: { request: string; reply: string; poll: MatchPoll };

  constructor(private readonly transport: EngineTransport) {}

  private request(operation: string, fields: JObject): string {
    if ("op" in fields || "protocol" in fields) throw EngineError.invalid("Reserved request keys");
    return EngineJson.encode({ ...fields, protocol: 1, op: operation });
  }

  private result(reply: J): J {
    const success = bool(get(reply, "ok"));
    if (int(get(reply, "protocol")) !== 1 || success === undefined) throw EngineError.invalid("Invalid engine response envelope");
    if (!success) {
      const error = get(reply, "error");
      throw EngineError.rejected(str(get(error, "code")) ?? "unknown", str(get(error, "message")) ?? "Engine rejected request");
    }
    const result = get(reply, "result");
    if (result === undefined) throw EngineError.invalid("Missing result");
    return result;
  }

  async call(operation: string, fields: JObject = {}): Promise<J> {
    return this.result(EngineJson.decode(await this.transport(this.request(operation, fields))));
  }

  /** A reply identical to the previous poll's, for the identical request, returns that poll again without decoding it. */
  async poll(matchID: string, seatID: string, after = 0): Promise<MatchPoll> {
    if (matchID.length === 0 || seatID.length === 0 || after < 0) throw EngineError.invalid("Invalid poll identity or revision");
    const request = this.request("poll", { matchId: matchID, viewerId: seatID, after });
    const reply = await this.transport(request);
    if (this.lastPoll && this.lastPoll.reply === reply && this.lastPoll.request === request) return this.lastPoll.poll;
    const poll = new MatchPoll(this.result(EngineJson.decode(reply)));
    // Do not let a stale/misrouted response enter another match's presentation.
    if (poll.matchID !== matchID || poll.seatID !== seatID) throw EngineError.invalid("Poll response identity mismatch");
    this.lastPoll = { request, reply, poll };
    return poll;
  }

  respond(matchID: string, seatID: string, prompt: EnginePrompt, answer: J, requestID: string): Promise<J> {
    return this.call("respond", { matchId: matchID, viewerId: seatID, command: prompt.command(answer, requestID) });
  }

  async concede(matchID: string, seatID: string): Promise<void> {
    if (matchID.length === 0 || seatID.length === 0) throw EngineError.invalid("Invalid concede identity");
    await this.call("concede", { matchId: matchID, viewerId: seatID });
  }
}

export const promptsEqual = (a: EnginePrompt | undefined, b: EnginePrompt | undefined) =>
  a === b || (a !== undefined && b !== undefined && a.id === b.id && a.revision === b.revision && a.submitted === b.submitted &&
    jsonEqual(a.payload, b.payload));
