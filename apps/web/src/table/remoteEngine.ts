/**
 * Port of OnDeviceRemoteEngineTransport: a guest's engine is the host's, reached through
 * request/reply packets bound to the host's peer ID, the epoch and each request's sequence.
 * Through HostRouter a guest may only send hello, poll, respond and concede.
 */
import { EngineError, EngineJson, get, int, isUuid, type J, jsonEqual, keysEqual, newUuid, obj, sameUuid, str, utf8Length } from "../core/json";
import { type BuildIdentity, identityJSON } from "./lobby";

/** The request may still run on the host, so only polls and hello, which change nothing, are retried. */
export class HostUnavailable extends EngineError {
  constructor() { super("The host did not answer in time. Keep every player’s app in the foreground.", "host_unavailable"); }
}

/** OnDeviceHostRetryPolicy: hello and polls back off 1, 2, 4 s after the host misses an answer. */
export class HostRetryPolicy {
  attempts = 0;
  constructor(private readonly delays = [1_000, 2_000, 4_000]) {}
  delayAfter(error: unknown): number | undefined {
    if (!(error instanceof HostUnavailable) || this.attempts >= this.delays.length) return undefined;
    this.attempts += 1;
    return this.delays[this.attempts - 1];
  }
  reset() { this.attempts = 0; }
}

interface Pending { sequence: number; resolve: (value: J) => void; reject: (error: unknown) => void; timer: ReturnType<typeof setTimeout> }

export class RemoteEngineTransport {
  private sequence = 0;
  private pending = new Map<string, Pending>();
  private closed = false;
  private ready = false;

  constructor(private readonly hostID: string, private readonly matchID: string, private readonly seatID: string,
    private readonly epoch: string, private readonly send: (text: string, peer: string) => void, private readonly timeoutMillis = 15_000) {}

  async hello(identity: BuildIdentity) {
    const result = await this.exchange("hello", identityJSON(identity));
    if (str(get(result, "seatId")) !== this.seatID || !jsonEqual(get(result, "build"), identityJSON(identity))) throw EngineError.incompatibleBuild();
    this.ready = true;
  }

  /** The EngineClient transport: a protocol-1 request for this seat, answered with the host's result. */
  request = async (text: string): Promise<string> => {
    if (!this.ready || this.closed) throw EngineError.invalid("Multiplayer connection is not ready.");
    const fields = obj(EngineJson.decode(text));
    const operation = str(fields?.op);
    if (!fields || int(fields.protocol) !== 1 || str(fields.matchId) !== this.matchID || str(fields.viewerId) !== this.seatID || operation === undefined) {
      throw EngineError.unboundPeer();
    }
    let payload: J;
    switch (operation) {
      case "poll": {
        const after = int(fields.after);
        if (!keysEqual(fields, ["protocol", "op", "matchId", "viewerId", "after"]) || after === undefined || after < 0) throw EngineError.invalid("Invalid remote poll.");
        payload = { after };
        break;
      }
      case "respond":
        if (!keysEqual(fields, ["protocol", "op", "matchId", "viewerId", "command"]) || fields.command === undefined) throw EngineError.invalid("Invalid remote response.");
        payload = fields.command;
        break;
      // The host's router concedes only this peer's bound seat.
      case "concede":
        if (!keysEqual(fields, ["protocol", "op", "matchId", "viewerId"])) throw EngineError.invalid("Invalid remote concede.");
        payload = {};
        break;
      default:
        throw EngineError.invalid("Only the host may create or close the native match.");
    }
    const result = await this.exchange(operation, payload);
    if (operation === "poll" && (str(get(result, "matchId")) !== this.matchID || str(get(result, "viewerId")) !== this.seatID)) throw EngineError.unboundPeer();
    return EngineJson.encode({ protocol: 1, ok: true, result });
  };

  private exchange(operation: string, payload: J): Promise<J> {
    if (this.closed || this.pending.size >= 4) return Promise.reject(EngineError.invalid("Multiplayer connection is closed or busy."));
    this.sequence += 1;
    const sequence = this.sequence;
    const id = newUuid();
    const text = EngineJson.encode({ type: "request", id, epoch: this.epoch, sequence, operation, payload });
    return new Promise<J>((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new HostUnavailable()); }, this.timeoutMillis);
      this.pending.set(id, {
        sequence, timer,
        resolve: (value) => { clearTimeout(timer); this.pending.delete(id); resolve(value); },
        reject: (error) => { clearTimeout(timer); this.pending.delete(id); reject(error); },
      });
      try { this.send(text, this.hostID); } catch (error) { this.pending.get(id)?.reject(error); }
    });
  }

  /** A `reply` packet from the host. */
  receive(value: J, from: string) {
    if (from !== this.hostID) throw EngineError.unboundPeer();
    const fields = obj(value);
    const id = str(get(value, "id"));
    const sequence = int(get(value, "sequence"));
    if (!fields || !keysEqual(fields, ["type", "id", "epoch", "sequence", "result", "error"]) || str(fields.type) !== "reply" ||
      !sameUuid(str(fields.epoch), this.epoch) || !isUuid(id) || sequence === undefined || sequence <= 0) throw EngineError.incompatibleBuild();
    const request = [...this.pending.entries()].find(([key]) => key.toLowerCase() === id.toLowerCase())?.[1];
    if (!request || request.sequence !== sequence) throw EngineError.replayed();
    const error = fields.error;
    if (obj(error)) {
      const message = str(get(error, "message"));
      if (!keysEqual(obj(error)!, ["code", "message"]) || str(get(error, "code")) !== "busy" || message === undefined || utf8Length(message) > 1024 ||
        fields.result !== null) throw EngineError.invalid("Invalid remote transport error.");
      // Busy keeps the session's pending command and requestId: the original may still execute.
      request.reject(EngineError.rejected("rpc_busy", message));
    } else if (typeof error === "string") {
      if (utf8Length(error) > 1024 || fields.result !== null) throw EngineError.invalid("Invalid remote error.");
      request.reject(EngineError.rejected("host_rejected", error));
    } else {
      if (error !== null || fields.result === undefined) throw EngineError.invalid("Invalid remote result.");
      EngineJson.validated(fields.result);
      request.resolve(fields.result);
    }
  }

  close() {
    this.closed = true; this.ready = false;
    for (const request of [...this.pending.values()]) request.reject(EngineError.invalid("closed"));
    this.pending.clear();
  }
}
