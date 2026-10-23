/**
 * The guest flow against a scripted host speaking the apps' table protocol over a fake relay:
 * offer → ready → start with a D20 plan → hello → polls → an answer → chat and clock packets.
 * No phone or relay is involved; the real-table check is the emulator run in README.md.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { DeckResolver } from "../src/core/deckResolver";
import { EngineJson, get, type J, type JObject, str } from "../src/core/json";
import type { RelayEvents, RelayPeer } from "../src/relay/relayTransport";
import { RelayPartAssembler, splitPacket } from "../src/relay/relayTransport";
import { GuestTable } from "../src/table/guestTable";
import { type BuildIdentity, identityJSON, RELAY_ADAPTER_VERSION } from "../src/table/lobby";

const repo = join(__dirname, "..", "..", "..");
const identity: BuildIdentity = { upstreamCommit: "a".repeat(40), catalogueHash: "b".repeat(64), adapterVersion: RELAY_ADAPTER_VERSION };
const HOST = "p1-host";
const GUEST = "p2-guest";
const EPOCH = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0";
const MATCH = "efa40d5a-f81e-46a7-aa4a-9d7c2e1d2bea";

class FakeRelay {
  events: RelayEvents = {};
  localPeerID?: string;
  peers: RelayPeer[] = [];
  seats = 2;
  isFull = false;
  sent: { value: JObject; to: string }[] = [];
  onSend?: (value: JObject, to: string) => void;
  connect() {
    this.localPeerID = GUEST;
    this.peers = [{ id: HOST, name: "Hosty", connected: true }, { id: GUEST, name: "Webby", connected: true }];
    this.events.onConnectionChanged?.(true);
    this.events.onRoster?.(this.peers, true);
  }
  send(text: string, to: string) {
    const value = EngineJson.decode(text) as JObject;
    this.sent.push({ value, to });
    this.onSend?.(value, to);
  }
  deliver(value: J, from = HOST) { this.events.onPacket?.(EngineJson.encode(value), from); }
  disconnect() { this.events = {}; }
}

const fixture = (): JObject => {
  const poll = JSON.parse(readFileSync(join(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice/2p-priority.json"), "utf8")) as JObject;
  return { ...poll, viewerId: "player2" };
};

const deck = (): J => {
  const resolver = new DeckResolver(readFileSync(join(__dirname, "..", "public/generated/printings.tsv"), "utf8"));
  const precons = JSON.parse(readFileSync(join(__dirname, "..", "public/generated/precons.json"), "utf8"));
  return resolver.resolve(precons.decks[0]);
};

const flush = async () => { for (let i = 0; i < 20; i += 1) await Promise.resolve(); };

describe("guest table", () => {
  it("resolves every precon against the shipped catalogue", () => {
    const resolver = new DeckResolver(readFileSync(join(__dirname, "..", "public/generated/printings.tsv"), "utf8"));
    const precons = JSON.parse(readFileSync(join(__dirname, "..", "public/generated/precons.json"), "utf8"));
    for (const precon of precons.decks) {
      const resolved = resolver.resolve(precon) as JObject;
      const rows = [...(resolved.main as J[]), ...(resolved.commanders as J[])];
      expect(rows.reduce<number>((sum, row) => sum + (get(row, "count") as number), 0), precon.name).toBe(100);
    }
  });

  it("splits and reassembles relay parts without breaking surrogate pairs", () => {
    const text = "x".repeat(9) + "😀".repeat(20);
    const parts = splitPacket(text, 10);
    expect(parts.join("")).toBe(text);
    expect(parts.every((part) => !/[\uD800-\uDBFF]$/.test(part))).toBe(true);
    const assembler = new RelayPartAssembler();
    let result: string | undefined;
    parts.slice().reverse().forEach((part, reversed) => {
      result = assembler.receive("p1-x", part, { id: "A", i: parts.length - 1 - reversed, n: parts.length });
    });
    expect(result).toBe(text);
    expect(assembler.receive("p1-x", "y", { id: "B", i: 0, n: 65 })).toBeUndefined();
  });

  it("joins, readies, rolls and plays through the host's engine", async () => {
    vi.useFakeTimers();
    const relay = new FakeRelay();
    const table = new GuestTable(identity, () => relay as never);
    const poll = fixture();
    const requests: JObject[] = [];
    relay.onSend = (value, to) => {
      expect(to).toBe(HOST);
      if (value.type === "request") {
        requests.push(value);
        const result: J = value.operation === "hello" ? { seatId: "player2", build: identityJSON(identity) }
          : value.operation === "poll" ? poll : { queued: true };
        queueMicrotask(() => relay.deliver({ type: "reply", epoch: EPOCH, id: value.id, sequence: value.sequence, result, error: null }));
      }
    };
    table.join("https://magicmobile-downloads.vercel.app/join/abc234", "Webby", deck());
    expect(table.state.stage).toBe("room");

    const lobbyPacket = (type: string) => ({
      type, epoch: EPOCH, build: identityJSON(identity), roster: [HOST, GUEST], aiSettings: { count: 0, seats: [] },
    });
    relay.deliver(lobbyPacket("offer"));
    expect(table.state.room?.aiSummary).toBe("Host chose no AI seats.");
    table.markReady("Webby", deck());
    const submission = relay.sent.find((s) => s.value.type === "submission")!.value;
    expect(Object.keys(submission).sort()).toEqual(["aiSettings", "build", "epoch", "player", "roster", "type"]);
    expect(get(submission.player, "name")).toBe("Webby");

    relay.deliver({ type: "ready", epoch: EPOCH, players: [{ id: GUEST, commanders: ["Emmara, Soul of the Accord"] }] });
    const roll = { rounds: [[{ seatId: "player1", value: 7 }, { seatId: "player2", value: 15 }]], winnerSeatId: "player2" };
    relay.deliver({ ...lobbyPacket("start"), matchId: MATCH, seatNames: { player1: "Fixture Player 1", player2: "Fixture Player 2" }, roll });
    await flush();
    expect(requests[0].operation).toBe("hello");
    expect(requests[0].payload).toEqual(identityJSON(identity));
    expect(table.state.stage).toBe("playing");
    await flush();
    expect(table.session?.state.snapshot?.promptEnvelopeV2?.responseKind).toBe("priority");

    // The host rolls first; then it is this guest's turn.
    expect(table.state.roll?.nextSeatID).toBe("player1");
    expect(() => table.rollStartingPlayer()).toThrow();
    relay.deliver({ type: "rollAdvance", epoch: EPOCH, index: 0 });
    expect(table.state.roll?.nextSeatID).toBe("player2");
    table.rollStartingPlayer();
    expect(relay.sent.at(-1)?.value).toEqual({ type: "rollStep", epoch: EPOCH, index: 1 });
    relay.deliver({ type: "rollAdvance", epoch: EPOCH, index: 1 });
    expect(table.state.roll?.nextSeatID).toBeUndefined();

    // Pass priority through the host's router.
    const pass = table.session!.state.snapshot!.legalActions!.find((a) => a.type === "pass_priority")!;
    await table.session!.send(pass);
    const respond = requests.find((r) => r.operation === "respond")!;
    expect(Object.keys(respond.payload as JObject).sort()).toEqual(["answer", "promptId", "promptRevision", "requestId"]);
    expect(get(respond.payload, "answer")).toEqual({ kind: "boolean", value: true });

    // Social packets and the host's clock.
    table.sendChat("  gg \n wp ");
    expect(relay.sent.at(-1)?.value).toEqual({ type: "chat", epoch: EPOCH, text: "gg wp" });
    relay.deliver({ type: "chat", epoch: EPOCH, text: "nice" });
    relay.deliver({ type: "emote", epoch: EPOCH, emote: "wow" });
    expect(table.state.chat.map((line) => `${line.name}: ${line.text}`)).toEqual(["You: gg wp", "Fixture Player 1: nice", "Fixture Player 1: Wow!"]);
    relay.deliver({ type: "clock", epoch: EPOCH, paused: false, clocks: [{ seat: "player2", remainingMillis: 15000, limitMillis: 60000, strikes: 1 }] });
    expect(table.state.turnClock.clocks[0]?.strikes).toBe(1);

    // A packet from the wrong epoch or a forged sender changes nothing.
    relay.deliver({ type: "end", epoch: "11111111-2222-3333-4444-555555555555" });
    expect(table.state.stage).toBe("playing");
    relay.deliver({ type: "end", epoch: EPOCH });
    expect(table.state.stage).toBe("failed");
    expect(table.state.status).toBe("The host ended this match.");
    expect(str(relay.sent.at(-1)?.value.type)).toBe("end");
    vi.useRealTimers();
  });

  it("explains a build mismatch", () => {
    const relay = new FakeRelay();
    const table = new GuestTable(identity, () => relay as never);
    table.join("ABC234", "Webby", deck());
    relay.deliver({
      type: "offer", epoch: EPOCH, build: { ...identityJSON(identity), catalogueHash: "c".repeat(64) }, roster: [HOST, GUEST],
      aiSettings: { count: 0, seats: [] },
    });
    expect(table.state.stage).toBe("failed");
    expect(table.state.status).toContain("different MagicMobile builds");
  });
});
