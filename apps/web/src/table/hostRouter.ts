/**
 * Port of HostRouter.swift / HostRouter.kt. Only the HOST constructs this router. The authenticated peer ID is an
 * out-of-band argument (the relay's stamp on a packet), never a value read from a peer-supplied JSON field. A peer can
 * say hello, poll, answer and concede only as its own bound seat; no create/destroy/record/diagnostics reaches the engine.
 */
import type { EngineClient } from "../core/engineClient";
import { EngineError, EngineJson, int, type J, jsonEqual, keysEqual, obj, sameUuid } from "../core/json";
import { type BuildIdentity, identityJSON } from "./lobby";

export interface PeerFrame { epoch: string; sequence: number; operation: string; payload: J }

interface Binding { seat: string; ready: boolean; lastSequence: number }

export class HostRouter {
  private peers = new Map<string, Binding>();
  private suspended = false;
  private suspensionRevision = 0;

  constructor(private readonly engine: EngineClient, private readonly matchID: string, private readonly identity: BuildIdentity,
    readonly epoch: string) {}

  bind(authenticatedPeerID: string, seatID: string) {
    if (authenticatedPeerID.length === 0 || seatID.length === 0 || this.peers.size >= 3 || this.peers.has(authenticatedPeerID) ||
      [...this.peers.values()].some((binding) => binding.seat === seatID)) throw EngineError.invalid("Duplicate/invalid peer binding or a full match");
    this.peers.set(authenticatedPeerID, { seat: seatID, ready: false, lastSequence: 0 });
  }

  setSuspended(value: boolean, revision?: number) {
    if (revision === undefined) { this.suspended = value; return; }
    if (revision <= this.suspensionRevision) return;
    this.suspensionRevision = revision; this.suspended = value;
  }

  async handle(frame: PeerFrame, authenticatedPeerID: string): Promise<J> {
    const binding = this.peers.get(authenticatedPeerID);
    if (!binding) throw EngineError.unboundPeer();
    if (!sameUuid(frame.epoch, this.epoch)) throw EngineError.incompatibleBuild();
    if (!Number.isSafeInteger(frame.sequence) || frame.sequence <= binding.lastSequence) throw EngineError.replayed();
    EngineJson.validated(frame.payload);
    // Advance before awaiting the engine so concurrent requests cannot reuse a sequence.
    binding.lastSequence = frame.sequence;
    if (frame.operation === "hello") {
      if (!jsonEqual(frame.payload, identityJSON(this.identity))) throw EngineError.incompatibleBuild();
      binding.ready = true;
      return { seatId: binding.seat, build: identityJSON(this.identity) };
    }
    if (!binding.ready) throw EngineError.incompatibleBuild();
    const fields = obj(frame.payload);
    switch (frame.operation) {
      case "poll": {
        const after = int(fields?.after);
        if (!fields || !keysEqual(fields, ["after"]) || after === undefined) throw EngineError.invalid("Invalid poll payload");
        return (await this.engine.poll(this.matchID, binding.seat, after)).raw;
      }
      case "respond":
        if (this.suspended) throw EngineError.hostSuspended();
        if (!fields || !keysEqual(fields, ["requestId", "promptId", "promptRevision", "answer"])) throw EngineError.invalid("Invalid answer payload");
        return this.engine.call("respond", { matchId: this.matchID, viewerId: binding.seat, command: frame.payload });
      case "concede":
        // Always allowed, even while suspended: a peer may only concede its own bound seat.
        if (!fields || !keysEqual(fields, [])) throw EngineError.invalid("Invalid concede payload");
        return this.engine.call("concede", { matchId: this.matchID, viewerId: binding.seat });
      default:
        throw EngineError.invalid("Remote operation not allowed");
    }
  }
}
