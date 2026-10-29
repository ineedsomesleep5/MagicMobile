/**
 * Hosting a table in this browser, end to end against the real guest code: a HostTable and a GuestTable meet on a fake
 * relay hub and the host plays on a scripted engine. create → waiting → room → submissions → start with the D20 plan →
 * a guest's requests served through HostRouter → revision and clock packets → end. No network, engine or phone.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DeckResolver } from "../src/core/deckResolver";
import { EngineJson, get, type J, type JObject } from "../src/core/json";
import type { RelayEvents, RelayPeer } from "../src/relay/relayTransport";
import { GuestTable } from "../src/table/guestTable";
import { HostTable } from "../src/table/hostTable";
import { type BuildIdentity, identityJSON, RELAY_ADAPTER_VERSION } from "../src/table/lobby";

const repo = join(__dirname, "..", "..", "..");
const identity: BuildIdentity = { upstreamCommit: "a".repeat(40), catalogueHash: "b".repeat(64), adapterVersion: RELAY_ADAPTER_VERSION };
const MATCH = "efa40d5a-f81e-46a7-aa4a-9d7c2e1d2bea";
const HOST = "p1-host";
const GUEST = "p2-guest";

/** The relay: stamps senders, keeps the roster, delivers packets on a later microtask like a network would. */
class Hub {
  relays = new Map<string, HubRelay>();
  seats = 2;
  log: { from: string; to: string; value: JObject }[] = [];
  creates: number[] = [];
  removed: string[] = [];
  peers(): RelayPeer[] { return [...this.relays.values()].map((r) => ({ id: r.localPeerID!, name: r.name, connected: true })); }
  roster() {
    const peers = this.peers();
    for (const relay of this.relays.values()) { relay.peers = peers; relay.isFull = peers.length === this.seats; relay.events.onRoster?.(peers, relay.isFull); }
  }
  deliver(from: string, to: string, text: string) {
    this.log.push({ from, to, value: EngineJson.decode(text) as JObject });
    queueMicrotask(() => this.relays.get(to)?.events.onPacket?.(text, from));
  }
  gone(id: string) {
    this.relays.delete(id);
    queueMicrotask(() => { for (const relay of this.relays.values()) relay.events.onDisconnect?.(id); });
  }
}

class HubRelay {
  events: RelayEvents = {};
  localPeerID?: string;
  peers: RelayPeer[] = [];
  isFull = false;
  name = "";
  hostKey?: string;
  constructor(private readonly hub: Hub, private readonly id: string) {}
  get seats() { return this.hub.seats; }
  async createTable(seats: number) { this.hub.creates.push(seats); this.hub.seats = seats; return { code: "ABC234", hostKey: "secret" }; }
  connect(_code: string, name: string, hostKey?: string) {
    this.name = name; this.hostKey = hostKey; this.localPeerID = this.id;
    this.hub.relays.set(this.id, this);
    this.events.onConnectionChanged?.(true);
    this.hub.roster();
  }
  send(text: string, to: string) { this.hub.deliver(this.id, to, text); }
  remove(peer: string) { this.hub.removed.push(peer); }
  disconnect() { if (this.hub.relays.get(this.id) === this) this.hub.gone(this.id); this.events = {}; }
}

/** The host's engine: one 2-player game whose every seat sees the fixture's priority question. */
class FakeEngine {
  requests: JObject[] = [];
  private poll = JSON.parse(readFileSync(join(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice/2p-priority.json"), "utf8")) as JObject;
  async start() { return { request: this.request }; }
  request = async (text: string): Promise<string> => {
    const request = EngineJson.decode(text) as JObject;
    this.requests.push(request);
    await Promise.resolve();
    const result: J = request.op === "capabilities" ? { answerActions: [] }
      : request.op === "create" ? { matchId: MATCH }
        : request.op === "poll" ? { ...this.poll, viewerId: request.viewerId as string }
          : request.op === "respond" ? { queued: true } : {};
    return EngineJson.encode({ protocol: 1, ok: true, result });
  };
  ops(op: string) { return this.requests.filter((r) => r.op === op); }
}

const deck = (index: number): J => {
  const resolver = new DeckResolver(readFileSync(join(__dirname, "..", "public/generated/printings.tsv"), "utf8"));
  const precons = JSON.parse(readFileSync(join(__dirname, "..", "public/generated/precons.json"), "utf8"));
  return resolver.resolve(precons.decks[index]);
};

const flush = async () => { for (let i = 0; i < 40; i += 1) await Promise.resolve(); };

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

describe("hosting a table", () => {
  it("opens, fills, starts and serves a guest through the router", async () => {
    vi.useFakeTimers();
    const hub = new Hub();
    const engine = new FakeEngine();
    const host = new HostTable(identity, engine, () => new HubRelay(hub, HOST) as never);
    const guest = new GuestTable(identity, () => new HubRelay(hub, GUEST) as never);
    const openSeats: [string | undefined, number][] = [];
    host.onOpenSeats = (code, open) => openSeats.push([code, open]);

    // Create → waiting room with the code; friends may see the open seat.
    await host.host("Hosty", deck(0), 2);
    expect(hub.creates).toEqual([2]);
    expect(hub.relays.get(HOST)?.hostKey).toBe("secret");
    expect(host.state.stage).toBe("waiting");
    expect(host.state.tableCode).toBe("ABC234");
    expect(host.state.waiting.map((p) => p.id)).toEqual([HOST]);
    expect(openSeats).toEqual([["ABC234", 1]]);

    // The guest joins: both open the match room, and the host offers every second.
    guest.join("ABC234", "Webby", deck(1));
    expect(host.state.stage).toBe("room");
    expect(guest.state.stage).toBe("room");
    expect(openSeats.at(-1)).toEqual([undefined, 0]);
    await flush();
    expect(guest.state.room?.aiSummary).toBe("Host chose no AI seats.");
    const offers = () => hub.log.filter((m) => m.value.type === "offer").length;
    const before = offers();
    await vi.advanceTimersByTimeAsync(2_000);
    expect(offers()).toBe(before + 2);

    // Submissions: the guest's verified deck, then the host's own Ready starts the game.
    guest.markReady("Webby", deck(1));
    await flush();
    expect(host.state.room?.players.find((p) => p.id === GUEST)?.isReady).toBe(true);
    expect(guest.state.room?.players.find((p) => p.id === GUEST)?.isReady).toBe(true);
    expect(host.state.room?.players.find((p) => p.isLocal)?.isReady).toBe(false);
    const rolls = [0.9, 0.2]; // host 19, guest 5
    vi.spyOn(Math, "random").mockImplementation(() => rolls.shift() ?? 0.5);
    host.markReady("Hosty", deck(0));
    await flush(); await flush();
    const create = engine.ops("create")[0];
    const seats = get(create.configuration, "seats") as JObject[];
    expect(seats.map((s) => [s.seatId, s.name, s.controller])).toEqual([["player1", "Hosty", "human"], ["player2", "Webby", "human"]]);
    expect(get(create.configuration, "seed")).toBeUndefined();

    // The start packet carries the D20 plan; the guest says hello through the router and plays.
    const start = hub.log.find((m) => m.value.type === "start")!.value;
    expect(Object.keys(start).sort()).toEqual(["aiSettings", "build", "epoch", "matchId", "roll", "roster", "seatNames", "type"]);
    expect(start.seatNames).toEqual({ player1: "Hosty", player2: "Webby" });
    expect(start.roll).toEqual({ rounds: [[{ seatId: "player1", value: 19 }, { seatId: "player2", value: 5 }]], winnerSeatId: "player1" });
    await flush(); await flush();
    expect(host.state.stage).toBe("playing");
    expect(guest.state.stage).toBe("playing");
    expect(host.state.localSeatID).toBe("player1");
    expect(host.state.tableSeats.map((s) => s.name)).toEqual(["Hosty", "Webby"]);
    const hello = hub.log.find((m) => m.value.type === "reply" && get(m.value.result, "seatId") === "player2");
    expect(hello?.to).toBe(GUEST);
    await vi.advanceTimersByTimeAsync(400);
    expect(engine.ops("poll").some((r) => r.viewerId === "player2")).toBe(true);
    expect(engine.ops("poll").some((r) => r.viewerId === "player1")).toBe(true);
    expect(guest.session?.state.snapshot?.promptEnvelopeV2?.responseKind).toBe("priority");
    expect(host.session?.state.snapshot?.promptEnvelopeV2?.responseKind).toBe("priority");
    // The host announced the revision it applied.
    expect(hub.log.some((m) => m.to === GUEST && m.value.type === "revision" && m.value.revision === 11)).toBe(true);

    // The roll: the host taps, then the guest; every screen advances.
    expect(host.state.roll?.nextSeatID).toBe("player1");
    expect(() => guest.rollStartingPlayer()).toThrow();
    host.rollStartingPlayer();
    await flush();
    expect(guest.state.roll?.nextSeatID).toBe("player2");
    expect(() => host.rollStartingPlayer()).toThrow();
    guest.rollStartingPlayer();
    await flush();
    expect(host.state.roll?.nextSeatID).toBeUndefined();
    expect(guest.state.roll?.nextSeatID).toBeUndefined();

    // The guest passes priority: answered by the host's engine as the guest's own seat.
    const pass = guest.session!.state.snapshot!.legalActions!.find((a) => a.type === "pass_priority")!;
    await guest.session!.send(pass);
    await flush();
    const respond = engine.ops("respond").find((r) => r.viewerId === "player2")!;
    expect(respond.matchId).toBe(MATCH);
    expect(get(respond.command, "answer")).toEqual({ kind: "boolean", value: true });

    // The turn clock runs for every human seat once the roll is shown and reaches the guest.
    await vi.advanceTimersByTimeAsync(1_100);
    const clock = hub.log.filter((m) => m.value.type === "clock" && m.to === GUEST).at(-1)?.value;
    expect(clock?.paused).toBe(false);
    expect((clock?.clocks as JObject[]).map((c) => c.seat)).toEqual(["player1", "player2"]);
    expect(guest.state.turnClock.clocks.map((c) => c.seat)).toEqual(["player1", "player2"]);
    expect(host.state.turnClock.clocks).toHaveLength(2);

    // Chat both ways.
    host.sendChat("hi there");
    await flush();
    guest.sendChat("gg");
    await flush();
    expect(guest.state.chat.map((l) => `${l.name}: ${l.text}`)).toEqual(["Hosty: hi there", "You: gg"]);
    expect(host.state.chat.map((l) => `${l.name}: ${l.text}`)).toEqual(["You: hi there", "Webby: gg"]);

    // A hidden host tab pauses the match for everyone.
    host.setForeground(false);
    await flush();
    expect(host.state.isSuspended).toBe(true);
    expect(guest.state.isSuspended).toBe(true);
    host.setForeground(true);
    await flush();
    expect(guest.state.isSuspended).toBe(false);

    // The host leaves: the guest is told at once and the engine lets go of the match.
    host.leave();
    await flush(); await flush();
    expect(guest.state.stage).toBe("failed");
    expect(guest.state.status).toBe("The host ended this match.");
    expect(host.state.stage).toBe("idle");
    expect(engine.ops("concede").some((r) => r.viewerId === "player1")).toBe(true);
    expect(engine.ops("destroy")).toHaveLength(1);
    expect(engine.ops("record")).toHaveLength(0);
  });

  it("removes joiners only while filling, keeps a challenge table private and ignores a guest's offer", async () => {
    const hub = new Hub();
    hub.seats = 3;
    const host = new HostTable(identity, new FakeEngine(), () => new HubRelay(hub, HOST) as never);
    await host.host("Hosty", deck(0), 3, { kind: "challenge" });
    const opens: (string | undefined)[] = [];
    host.onOpenSeats = (code) => opens.push(code);
    const guest = new GuestTable(identity, () => new HubRelay(hub, GUEST) as never);
    guest.join("ABC234", "Webby", deck(1));
    expect(host.state.waiting.map((p) => p.id)).toEqual([HOST, GUEST]);
    // A challenge table is for one player: never published to friends.
    expect(host.openHostedTable).toEqual({ code: "ABC234", openSeats: 1 });
    expect(opens).toEqual([]);
    host.remove(HOST);
    host.remove(GUEST);
    expect(hub.removed).toEqual([GUEST]);
    const third = new GuestTable(identity, () => new HubRelay(hub, "p3-third") as never);
    third.join("ABC234", "Thirdy", deck(2));
    expect(host.state.stage).toBe("room");
    host.remove(GUEST);
    expect(hub.removed).toEqual([GUEST]);
    const roster = [HOST, GUEST, "p3-third"];
    hub.deliver(GUEST, HOST, EngineJson.encode({ type: "offer", epoch: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0", build: identityJSON(identity), roster,
      aiSettings: { count: 0, seats: [] } }));
    await flush();
    expect(host.state.stage).toBe("room");
    expect(host.state.room?.players.map((p) => p.isHost)).toEqual([true, false, false]);
    host.leave();
  });

  it("explains a guest on another build and ends the room", async () => {
    vi.useFakeTimers();
    const hub = new Hub();
    const host = new HostTable(identity, new FakeEngine(), () => new HubRelay(hub, HOST) as never);
    await host.host("Hosty", deck(0), 2);
    const guest = new GuestTable({ ...identity, catalogueHash: "c".repeat(64) }, () => new HubRelay(hub, GUEST) as never);
    guest.join("ABC234", "Webby", deck(1));
    await flush();
    // The guest reads the host's offer as a different build and leaves; the host hears it go.
    expect(guest.state.stage).toBe("failed");
    expect(guest.state.status).toContain("different MagicMobile builds");
    await flush();
    expect(host.state.stage).toBe("failed");
  });

  it("shows why a table did not open", async () => {
    const host = new HostTable(identity, new FakeEngine(), () => ({
      createTable: async () => { throw new Error("You opened several tables in the last minute. Wait a minute, then try again."); },
    }) as never);
    await expect(host.host("Hosty", deck(0), 2)).rejects.toThrow("several tables");
    expect(host.state.stage).toBe("failed");
    expect(host.state.status).toContain("several tables");
    await expect(host.host("", deck(0), 2)).rejects.toThrow();
  });
});
