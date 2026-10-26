/**
 * Players who leave a table (TableLeaveRules): the shared cases in parity/table-leave-cases.json, then a three-player
 * table on a fake relay hub where a guest taps Leave (conceded at once, the others play on) and where a guest drops and
 * the two still there vote to go on without them. No network, engine or phone.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DeckResolver } from "../src/core/deckResolver";
import { EngineJson, type J, type JObject } from "../src/core/json";
import { NO_VOTE, parseVote, TableLeaveRules, votePacket } from "../src/core/tableLeave";
import type { RelayEvents, RelayPeer } from "../src/relay/relayTransport";
import { GuestTable } from "../src/table/guestTable";
import { HostTable } from "../src/table/hostTable";
import { type BuildIdentity, RELAY_ADAPTER_VERSION } from "../src/table/lobby";

const repo = join(__dirname, "..", "..", "..");
const identity: BuildIdentity = { upstreamCommit: "a".repeat(40), catalogueHash: "b".repeat(64), adapterVersion: RELAY_ADAPTER_VERSION };
const MATCH = "efa40d5a-f81e-46a7-aa4a-9d7c2e1d2bea";

describe("shared table-leave cases", () => {
  const root = JSON.parse(readFileSync(join(repo, "apps/android/core/src/test/resources/parity/table-leave-cases.json"), "utf8"));

  it("votes pass only when everyone still at the table agrees", () => {
    expect(root.voteAfterSeconds).toBe(TableLeaveRules.VOTE_AFTER_SECONDS);
    for (const item of root.passes) expect(TableLeaveRules.passes(item.yes, item.eligible), item.name).toBe(item.expect);
  });

  it("reads the host's vote packet", () => {
    for (const item of root.packets) {
      const read = () => parseVote(item.packet, { player3: "Jed" }, item.localSeat);
      if (item.expect === "invalid") expect(read, item.name).toThrow();
      else if (item.expect === null) expect(read(), item.name).toBeUndefined();
      else expect(read(), item.name).toMatchObject({ seatID: item.expect.seat, voters: item.expect.voters, needed: item.expect.needed, voted: item.expect.voted });
    }
    const vote = { seatID: "player3", name: "Jed", voters: ["player1"], needed: 2, voted: false };
    expect(parseVote(votePacket(vote, "E"), { player3: "Jed" }, "player1")).toEqual({ ...vote, voted: true });
    expect(parseVote(votePacket(NO_VOTE, "E"), {})).toBeUndefined();
    expect(TableLeaveRules.buttonTitle(vote)).toBe("Continue without Jed (1/2)");
  });
});

/** The relay: stamps senders, keeps the roster (with who dropped), delivers on a later microtask like a network would. */
class Hub {
  relays = new Map<string, HubRelay>();
  away = new Set<string>();
  seats = 3;
  log: { from: string; to: string; value: JObject }[] = [];
  peers(): RelayPeer[] { return [...this.relays.values()].map((r) => ({ id: r.localPeerID!, name: r.name, connected: !this.away.has(r.localPeerID!) })); }
  roster() {
    const peers = this.peers();
    for (const relay of this.relays.values()) { relay.events.onRoster?.(peers, peers.length === this.seats); }
  }
  deliver(from: string, to: string, text: string) {
    this.log.push({ from, to, value: EngineJson.decode(text) as JObject });
    if (this.away.has(to)) return;
    queueMicrotask(() => this.relays.get(to)?.events.onPacket?.(text, from));
  }
  drop(id: string) { this.away.add(id); this.roster(); }
  gone(id: string) {
    this.relays.delete(id);
    queueMicrotask(() => { for (const relay of this.relays.values()) relay.events.onDisconnect?.(id); });
  }
}

class HubRelay {
  events: RelayEvents = {};
  localPeerID?: string;
  name = "";
  constructor(private readonly hub: Hub, private readonly id: string) {}
  get seats() { return this.hub.seats; }
  async createTable(seats: number) { this.hub.seats = seats; return { code: "ABC234", hostKey: "secret" }; }
  connect(_code: string, name: string) {
    this.name = name; this.localPeerID = this.id;
    this.hub.relays.set(this.id, this);
    this.events.onConnectionChanged?.(true);
    this.hub.roster();
  }
  send(text: string, to: string) { this.hub.deliver(this.id, to, text); }
  remove() {}
  disconnect() { if (this.hub.relays.get(this.id) === this) this.hub.gone(this.id); this.events = {}; }
}

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
  concededSeats() { return this.requests.filter((r) => r.op === "concede").map((r) => r.viewerId); }
}

const deck = (index: number): J => {
  const resolver = new DeckResolver(readFileSync(join(__dirname, "..", "public/generated/printings.tsv"), "utf8"));
  const precons = JSON.parse(readFileSync(join(__dirname, "..", "public/generated/precons.json"), "utf8"));
  return resolver.resolve(precons.decks[index]);
};

const flush = async () => { for (let i = 0; i < 40; i += 1) await Promise.resolve(); };

/** Host, Webby and Jed at a started three-player table, every die rolled. */
async function threeAtTheTable() {
  const hub = new Hub();
  const engine = new FakeEngine();
  const host = new HostTable(identity, engine, () => new HubRelay(hub, "p1-host") as never);
  const webby = new GuestTable(identity, () => new HubRelay(hub, "p2-webby") as never);
  const jed = new GuestTable(identity, () => new HubRelay(hub, "p3-jed") as never);
  await host.host("Hosty", deck(0), 3);
  webby.join("ABC234", "Webby", deck(1));
  jed.join("ABC234", "Jed", deck(2));
  await flush();
  webby.markReady("Webby", deck(1));
  jed.markReady("Jed", deck(2));
  await flush();
  const rolls = [0.9, 0.5, 0.2];
  vi.spyOn(Math, "random").mockImplementation(() => rolls.shift() ?? 0.5);
  host.markReady("Hosty", deck(0));
  await flush(); await flush(); await flush();
  const tables = [host, webby, jed];
  for (let turns = 0; turns < 6 && host.state.roll?.nextSeatID !== undefined; turns += 1) {
    tables.find((t) => t.state.localSeatID === host.state.roll?.nextSeatID)?.rollStartingPlayer();
    await flush();
  }
  return { hub, engine, host, webby, jed };
}

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

describe("a player leaves a table with people", () => {
  it("a guest who taps Leave is conceded and the other two play on", async () => {
    vi.useFakeTimers();
    const { engine, host, webby, jed } = await threeAtTheTable();
    expect([host.state.stage, webby.state.stage, jed.state.stage]).toEqual(["playing", "playing", "playing"]);
    expect(host.state.roll?.nextSeatID).toBeUndefined();

    jed.leave();
    await flush(); await flush();
    expect(engine.concededSeats()).toEqual(["player3"]);
    expect(host.state.stage).toBe("playing");
    expect(webby.state.stage).toBe("playing");
    expect(host.state.isSuspended).toBe(false);
    expect(webby.state.isSuspended).toBe(false);
    expect(webby.state.tableNotice).toBe("Jed left. The game goes on.");
    webby.clearTableNotice();
    expect(webby.state.tableNotice).toBeUndefined();

    // The host leaving still ends it for everyone.
    host.leave();
    await flush(); await flush();
    expect(webby.state.stage).toBe("failed");
    expect(webby.state.status).toBe("The host ended this match.");
  });

  it("a guest who drops is waited for, then the two still there vote to go on without them", async () => {
    vi.useFakeTimers();
    const { hub, engine, host, webby } = await threeAtTheTable();
    hub.drop("p3-jed");
    await flush();
    expect(host.state.isSuspended).toBe(true);
    expect(webby.state.status).toBe("Waiting for Jed…");
    expect(host.state.continueVote).toBeUndefined();

    // After 15 s the vote opens on both screens.
    await vi.advanceTimersByTimeAsync(16_000);
    await flush();
    expect(host.state.continueVote).toMatchObject({ seatID: "player3", name: "Jed", voters: [], needed: 2, voted: false });
    expect(webby.state.continueVote).toMatchObject({ seatID: "player3", voters: [], needed: 2, voted: false });

    webby.voteToContinue();
    await flush();
    expect(webby.state.continueVote?.voted).toBe(true);
    expect(host.state.continueVote).toMatchObject({ voters: ["player2"], voted: false });
    expect(engine.concededSeats()).toEqual([]);

    host.voteToContinue();
    await flush(); await flush();
    expect(engine.concededSeats()).toEqual(["player3"]);
    expect(host.state.continueVote).toBeUndefined();
    expect(webby.state.continueVote).toBeUndefined();
    expect(host.state.isSuspended).toBe(false);
    expect(webby.state.isSuspended).toBe(false);
    expect(webby.state.tableNotice).toBe("Jed left. The game goes on.");
    // Jed's own phone hears it should it come back.
    expect(hub.log.some((m) => m.to === "p3-jed" && m.value.type === "left" && m.value.seat === "player3")).toBe(true);
    host.leave();
  });
});
