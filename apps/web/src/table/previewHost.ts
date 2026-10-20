/**
 * `?preview=1`: a scripted host on a fake relay, for checking the table's look without a phone.
 * It answers with one recorded engine poll (`?preview=2p-combat` picks one of apps/ios/MagicMobileTests/Fixtures/OnDevice,
 * copied by scripts/prepare_data.py) and accepts every answer. Development only; it never touches the relay.
 */
import { EngineJson, type J, type JObject } from "../core/json";
import type { RelayEvents, RelayPeer } from "../relay/relayTransport";
import { identityJSON, type BuildIdentity } from "./lobby";

const HOST = "p1-preview-host";
const GUEST = "p2-preview-guest";
const EPOCH = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0";

export class PreviewRelay {
  events: RelayEvents = {};
  localPeerID?: string;
  peers: RelayPeer[] = [];
  seats = 2;
  isFull = true;
  private poll?: JObject;

  constructor(private readonly identity: BuildIdentity) {}

  connect() {
    const fixture = new URLSearchParams(location.search).get("preview") || "2p-priority";
    void fetch(`/generated/preview/${/^[\w-]+$/.test(fixture) && fixture !== "1" ? fixture : "2p-priority"}.json`).then((r) => r.json()).then((poll: JObject) => {
      this.poll = { ...poll, viewerId: "player2" };
      this.localPeerID = GUEST;
      this.peers = [{ id: HOST, name: "Fixture Player 1", connected: true }, { id: GUEST, name: "You", connected: true }];
      this.events.onConnectionChanged?.(true);
      this.events.onRoster?.(this.peers, true);
      this.deliver(this.lobby("offer"));
    });
  }

  private lobby(type: string): JObject {
    return { type, epoch: EPOCH, build: identityJSON(this.identity), roster: [HOST, GUEST], aiSettings: { count: 0, seats: [] } };
  }

  private deliver(value: J) { setTimeout(() => this.events.onPacket?.(EngineJson.encode(value), HOST), 120); }

  send(text: string) {
    const value = EngineJson.decode(text) as JObject;
    if (value.type === "submission") {
      this.deliver({ type: "ready", epoch: EPOCH, players: [{ id: GUEST, commanders: [] }] });
      this.deliver({
        ...this.lobby("start"), matchId: "efa40d5a-f81e-46a7-aa4a-9d7c2e1d2bea",
        seatNames: { player1: "Fixture Player 2", player2: "Fixture Player 1" },
        roll: { rounds: [[{ seatId: "player1", value: 9 }, { seatId: "player2", value: 17 }]], winnerSeatId: "player2" },
      });
      setTimeout(() => this.deliver({ type: "rollAdvance", epoch: EPOCH, index: 0 }), 1500);
      setTimeout(() => this.deliver({
        type: "clock", epoch: EPOCH, paused: false, clocks: [{ seat: "player2", remainingMillis: 18000, limitMillis: 60000, strikes: 1 }],
      }), 2500);
    } else if (value.type === "rollStep") {
      this.deliver({ type: "rollAdvance", epoch: EPOCH, index: value.index });
    } else if (value.type === "request") {
      const result: J = value.operation === "hello" ? { seatId: "player2", build: identityJSON(this.identity) }
        : value.operation === "poll" ? this.poll! : { queued: true };
      this.deliver({ type: "reply", epoch: EPOCH, id: value.id, sequence: value.sequence, result, error: null });
    } else if (value.type === "chat") {
      this.deliver({ type: "emote", epoch: EPOCH, emote: "wellPlayed" });
    }
  }

  disconnect() { this.events = {}; }
}
