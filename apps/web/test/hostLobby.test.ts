/**
 * The host's side of the match room and the relay (ports of OnDeviceMultiplayerTests.swift and RelayLobbyTest.kt):
 * HostLobby, the per-peer request dispatcher, and RelayTransport's create/host-key/remove additions.
 */
import { describe, expect, it } from "vitest";
import { EngineClient } from "../src/core/engineClient";
import { EngineJson, type J, type JObject } from "../src/core/json";
import { OnDeviceStartingRoll, OnDeviceStartingRollProgress } from "../src/core/startingRoll";
import { RelayTransport, RelayWire } from "../src/relay/relayTransport";
import { HostRequestDispatcher } from "../src/table/hostTable";
import { HostRouter } from "../src/table/hostRouter";
import { type BuildIdentity, GuestLobby, HandshakeFailure, HostLobby, identityJSON, Lobby } from "../src/table/lobby";

const identity: BuildIdentity = { upstreamCommit: "commit", catalogueHash: "catalogue", adapterVersion: "ondevice-0.1" };
const EPOCH = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0";
const deck: J = { main: [], commanders: [] };
const commanderDeck: J = { main: [], commanders: [{ name: "Chatterfang, Squirrel General", setCode: "MH2", collectorNumber: "151", count: 1 }] };
const flush = async () => { for (let i = 0; i < 50; i += 1) await Promise.resolve(); };

describe("host lobby", () => {
  it("lets only the first sorted peer host and seats the others in order", () => {
    const lobby = new HostLobby(["charlie", "alice", "bob"], "alice");
    expect(lobby.hostID).toBe("alice");
    expect(lobby.seatID("bob")).toBe("player2");
    expect(() => lobby.seatID("intruder")).toThrow();
    expect(() => new HostLobby(["alice", "alice"], "alice")).toThrow();
    expect(() => new HostLobby(["alice", "bob"], "bob")).toThrow();
    expect(() => new GuestLobby(["alice", "bob"], "alice")).toThrow();
  });

  it("builds the engine configuration from every readied deck, humans then AI seats", () => {
    for (const [humans, ais] of [[2, 1], [2, 2], [3, 1], [4, 0]]) {
      const peers = ["dana", "alice", "charlie", "bob"].slice(0, humans);
      const aiSeats = Array.from({ length: ais }, (_, i) => ({ deck, skill: i + 3 }));
      const lobby = new HostLobby(peers, [...peers].sort()[0], aiSeats);
      expect(lobby.isReady).toBe(false);
      expect(() => lobby.configuration()).toThrow();
      peers.forEach((peer) => lobby.submit({ name: peer, deck }, peer));
      expect(lobby.isReady).toBe(true);
      const seats = lobby.configuration().seats as JObject[];
      expect(seats).toHaveLength(humans + ais);
      const names = lobby.seatNames();
      seats.forEach((seat) => expect(seat.name).toBe(names.get(seat.seatId as string)));
      lobby.peerIDs.forEach((peer, index) => {
        expect(seats[index]).toMatchObject({ seatId: lobby.seatID(peer), controller: "human" });
        expect(seats[index].aiSkill).toBeUndefined();
      });
      for (let index = 0; index < ais; index += 1) {
        expect(seats[humans + index]).toEqual({ seatId: `player${humans + index + 1}`, controller: "ai", name: `AI ${index + 1}`, deck, aiSkill: index + 3 });
      }
    }
    expect(() => new HostLobby(["alice", "bob"], "alice", [0, 1, 2].map(() => ({ deck, skill: 2 })))).toThrow();
    expect(() => new HostLobby(["alice", "bob", "charlie", "dana"], "alice", [{ deck, skill: 2 }])).toThrow();
    expect(() => new HostLobby(["alice", "bob"], "alice", [{ deck, skill: 11 }])).toThrow();
  });

  it("sends a ranked seed only to an engine that keeps game records", () => {
    const lobby = new HostLobby(["alice", "bob"], "alice");
    lobby.submit({ name: "Alice", deck }, "alice"); lobby.submit({ name: "Bob", deck }, "bob");
    expect(lobby.configuration(12345678901234567890n).seed).toBeUndefined();
    expect(EngineJson.encode(lobby.configuration(12345678901234567890n, true))).toContain("\"seed\":12345678901234567890");
  });

  it("makes duplicate human and AI names unique, within 40 characters", () => {
    const lobby = new HostLobby(["bob", "alice"], "alice", [{ deck, skill: 2 }]);
    lobby.submit({ name: "AI 1", deck }, "alice");
    lobby.submit({ name: "AI 1 (player1)", deck }, "bob");
    expect(Object.fromEntries(lobby.seatNames())).toEqual({ player1: "AI 1 (player1)", player2: "AI 1 (player1) (player2)", player3: "AI 1 (player3)" });
    const robins = new HostLobby(["p1-a", "p2-b"], "p1-a");
    robins.submit({ name: "Robin", deck }, "p1-a"); robins.submit({ name: "robin", deck }, "p2-b");
    expect(Object.fromEntries(robins.seatNames())).toEqual({ player1: "Robin (player1)", player2: "robin (player2)" });
    const long = new HostLobby(["alice", "bob"], "alice");
    long.submit({ name: "A".repeat(40), deck }, "alice"); long.submit({ name: "A".repeat(40), deck }, "bob");
    const names = [...long.seatNames().values()];
    expect(new Set(names).size).toBe(2);
    expect(names.every((name) => [...name].length <= 40)).toBe(true);
    Lobby.validatedSeatNames(Object.fromEntries(long.seatNames()), 2);
  });

  it("keeps a submitted deck and refuses another seat or controller", () => {
    const lobby = new HostLobby(["alice", "bob"], "alice");
    const own = { name: "Alice", deck: { name: "Test", main: [], commanders: [], companions: [] } };
    expect(() => lobby.submit({ ...own, seatId: "player1" }, "bob")).toThrow();
    expect(() => lobby.submit(own, "unknown")).toThrow();
    lobby.submit(own, "alice");
    lobby.submit(own, "alice");
    expect(() => lobby.submit({ name: "Alice", deck }, "alice")).toThrow("changed");
    lobby.submit({ name: "Bob", deck }, "bob");
    expect((lobby.configuration().seats as JObject[])[1]).toMatchObject({ seatId: "player2", controller: "human", name: "Bob" });
  });

  it("verifies a guest's submission schema before reporting a build or settings mismatch", () => {
    const lobby = new HostLobby(["alice", "bob"], "alice", [{ deck, skill: 4 }]);
    const packet = (patch: JObject = {}): J => ({
      type: "submission", epoch: EPOCH, build: identityJSON(identity), roster: ["alice", "bob"], aiSettings: lobby.aiSettings,
      player: { name: "Bob", deck }, ...patch,
    });
    expect(lobby.verifySubmission(packet(), "bob", identity, EPOCH.toLowerCase())).toEqual({ name: "Bob", deck });
    const other = { ...identityJSON(identity), adapterVersion: "other-build" };
    expect(() => lobby.verifySubmission(packet({ build: other }), "bob", identity, EPOCH)).toThrow(HandshakeFailure);
    const wrongAI = Lobby.makeAISettings([{ deck, skill: 5 }], 2);
    expect(() => lobby.verifySubmission(packet({ aiSettings: wrongAI }), "bob", identity, EPOCH)).toThrow("AI settings");
    for (const player of [null, "Bob", { name: "Bob" }, { name: "Bob", deck: { main: "bad", commanders: [] } }] as J[]) {
      for (const build of [identityJSON(identity), other]) {
        let error: unknown;
        try { lobby.verifySubmission(packet({ player, build }), "bob", identity, EPOCH); } catch (e) { error = e; }
        expect(error).toBeDefined();
        expect(error).not.toBeInstanceOf(HandshakeFailure);
      }
    }
    expect(() => lobby.verifySubmission(packet(), "alice", identity, EPOCH)).toThrow();
    expect(() => lobby.verifySubmission(packet(), "intruder", identity, EPOCH)).toThrow();
    expect(() => lobby.verifySubmission(packet(), "bob", identity, "11111111-2222-3333-4444-555555555555")).toThrow();
    expect(() => lobby.verifySubmission(packet({ roster: ["alice"] }), "bob", identity, EPOCH)).toThrow();
    expect(() => lobby.verifySubmission(packet({ peerID: "alice" }), "bob", identity, EPOCH)).toThrow();
  });

  it("reports readiness and public commanders only from the host, and a guest accepts it", () => {
    const host = new HostLobby(["bob", "alice", "carol"], "alice");
    const guest = new GuestLobby(["bob", "alice", "carol"], "bob");
    expect(get(host.readyPacket(EPOCH), "players")).toEqual([]);
    host.submit({ name: "Alice", deck: commanderDeck }, "alice");
    expect(host.isReady).toBe(false);
    const packet = host.readyPacket(EPOCH);
    expect(Object.fromEntries(guest.acceptReadyPacket(packet, "alice"))).toEqual({ alice: ["Chatterfang, Squirrel General"] });
    expect(() => guest.acceptReadyPacket(packet, "carol")).toThrow();
  });

  it("encodes the shared roll in the phones' format and advances only the right seat", () => {
    const seats = ["player1", "player2", "player3"];
    const values = [12, 12, 7, 20, 14];
    const roll = OnDeviceStartingRoll.generate(seats, () => values.shift()!);
    const decoded = OnDeviceStartingRoll.decode(EngineJson.decode(EngineJson.encode(roll.encoded(seats))), seats);
    expect(decoded.winnerSeatID).toBe("player1");
    expect(decoded.steps).toEqual(roll.steps);
    const progress = new OnDeviceStartingRollProgress(roll, new Set(["player1", "player2"]));
    expect(() => progress.advance("player2", false)).toThrow();
    expect(() => progress.advance("player1", true)).toThrow();
    expect(progress.advance("player1", false)).toBe(0);
    expect(progress.advance("player2", false)).toBe(1);
    expect(() => progress.advance("player3", false)).toThrow();
    expect(progress.advance("player3", true)).toBe(2);
  });
});

const get = (value: J, key: string) => (value as JObject)[key];

/** An engine whose first request waits until released (MultiplayerRecordingEngine). */
const holdingEngine = () => {
  const requests: JObject[] = [];
  let release: () => void = () => undefined;
  const held = new Promise<void>((resolve) => { release = resolve; });
  let first = true;
  const transport = async (text: string) => {
    const request = EngineJson.decode(text) as JObject;
    requests.push(request);
    if (first) { first = false; await held; }
    const result: J = request.op === "poll" ? { matchId: "match", viewerId: request.viewerId, revision: 1, phase: "running", resyncRequired: false, snapshot: null, prompt: null } : {};
    return EngineJson.encode({ protocol: 1, ok: true, result });
  };
  return { requests, release: () => release(), transport };
};

const request = (sequence: number, operation: string, payload: J, epoch = EPOCH, id = crypto.randomUUID()): J =>
  ({ type: "request", id, epoch, sequence, operation, payload });

describe("host request dispatcher", () => {
  const setup = (send: (value: JObject) => void) => {
    const engine = holdingEngine();
    const router = new HostRouter(new EngineClient(engine.transport), "match", identity, EPOCH);
    router.bind("client", "player2");
    const errors: string[] = [];
    const dispatcher = new HostRequestDispatcher(router, EPOCH, new Set(["client"]), (value) => send(value as JObject), (m) => errors.push(m));
    return { engine, dispatcher, errors };
  };

  it("drains one peer's requests in arrival order, one in the engine at a time", async () => {
    const replies: JObject[] = [];
    const { engine, dispatcher, errors } = setup((value) => replies.push(value));
    dispatcher.receive(request(1, "hello", identityJSON(identity)), "client");
    for (const sequence of [2, 3, 4]) dispatcher.receive(request(sequence, "poll", { after: 0 }), "client");
    await flush();
    expect(engine.requests).toHaveLength(1);
    expect(replies).toHaveLength(1);
    engine.release();
    await flush();
    expect(replies.map((r) => r.sequence)).toEqual([1, 2, 3, 4]);
    expect(replies.every((r) => r.error === null)).toBe(true);
    expect(errors).toEqual([]);
  });

  it("answers busy past four pending requests, with the request's id and sequence", async () => {
    const replies: JObject[] = [];
    const { engine, dispatcher } = setup((value) => replies.push(value));
    dispatcher.receive(request(1, "hello", identityJSON(identity)), "client");
    await flush();
    for (const sequence of [2, 3, 4, 5]) dispatcher.receive(request(sequence, "poll", { after: 0 }), "client");
    const id = crypto.randomUUID();
    dispatcher.receive(request(6, "poll", { after: 0 }, EPOCH, id), "client");
    expect(replies.at(-1)).toEqual({ type: "reply", epoch: EPOCH, id: id.toUpperCase(), sequence: 6, result: null,
      error: { code: "busy", message: "The host is busy. Retry the same action." } });
    engine.release();
    await flush();
    expect(replies).toHaveLength(6);
  });

  it("keeps epoch, peer and replay checks and does not wait for sequence gaps", async () => {
    const replies: JObject[] = [];
    const { engine, dispatcher } = setup((value) => replies.push(value));
    engine.release();
    expect(() => dispatcher.receive(request(1, "hello", identityJSON(identity)), "intruder")).toThrow();
    expect(() => dispatcher.receive(request(1, "hello", identityJSON(identity), "11111111-2222-3333-4444-555555555555"), "client")).toThrow();
    dispatcher.receive(request(1, "hello", identityJSON(identity)), "client");
    // A missing sequence 2 cannot stall the drain; replay validation stays in HostRouter.
    dispatcher.receive(request(3, "poll", { after: 0 }), "client");
    dispatcher.receive(request(2, "poll", { after: 0 }), "client");
    dispatcher.receive(request(4, "poll", { after: 0, viewerId: "player1" }), "client");
    await flush();
    expect(replies).toHaveLength(4);
    expect(get(replies[1].result, "viewerId")).toBe("player2");
    expect(replies[2].error).toBe("Duplicate or out-of-order transport message.");
    expect(typeof replies[3].error).toBe("string");
    expect(engine.requests).toHaveLength(1);
  });

  it("sends nothing late after cancel", async () => {
    const replies: JObject[] = [];
    const { engine, dispatcher } = setup((value) => replies.push(value));
    dispatcher.receive(request(1, "hello", identityJSON(identity)), "client");
    dispatcher.receive(request(2, "poll", { after: 0 }), "client");
    dispatcher.receive(request(3, "poll", { after: 0 }), "client");
    await flush();
    dispatcher.cancel();
    expect(() => dispatcher.receive(request(4, "poll", { after: 0 }), "client")).toThrow();
    engine.release();
    await flush();
    expect(replies).toHaveLength(1);
    expect(engine.requests).toHaveLength(1);
  });
});

describe("relay host wire", () => {
  it("offers the host key and resume token as subprotocols, never in the URL", () => {
    expect(RelayWire.socketProtocols()).toEqual(["magicmobile.1"]);
    expect(RelayWire.socketProtocols(undefined, "Ab-9_x")).toEqual(["magicmobile.1", "magicmobile.key.Ab-9_x"]);
    expect(RelayWire.socketProtocols("tok_EN-1")).toEqual(["magicmobile.1", "magicmobile.resume.tok_EN-1"]);
  });

  it("shows the relay's message or a friendly one when a table does not open", () => {
    expect(RelayWire.createFailureMessage(429, "Wait a minute.")).toBe("Wait a minute.");
    expect(RelayWire.createFailureMessage(429, undefined)).toBe("You opened several tables in the last minute. Wait a minute, then try again.");
    expect(RelayWire.createFailureMessage(503, "  ")).toBe("The table service could not open a table. Try again.");
    expect(RelayWire.createFailureMessage(undefined, undefined)).toBe("The table service could not open a table. Try again.");
  });

  it("creates a table through this origin, connects with the host key and removes a joiner", async () => {
    const calls: { url: string; init?: RequestInit }[] = [];
    const sockets: { url: string; protocols: string[]; sent: string[]; socket: FakeSocket }[] = [];
    class FakeSocket {
      readyState = 1; onmessage?: (event: { data: string }) => void; onclose?: () => void; onerror?: () => void;
      sent: string[] = [];
      send(text: string) { this.sent.push(text); }
      close() { /* closed */ }
    }
    const relay = new RelayTransport("https://relay.example", (url, protocols) => {
      const socket = new FakeSocket();
      sockets.push({ url, protocols, sent: socket.sent, socket });
      return socket as unknown as WebSocket;
    }, "/relay", async (url, init) => {
      calls.push({ url: String(url), init });
      return new Response(JSON.stringify({ code: "ABC234", hostKey: "secret", seats: 3 }), { status: 200 });
    });
    expect(await relay.createTable(3)).toEqual({ code: "ABC234", hostKey: "secret" });
    expect(calls[0].url).toBe("/relay/v1/tables");
    expect(calls[0].init?.method).toBe("POST");
    expect(JSON.parse(String(calls[0].init?.body))).toEqual({ seats: 3 });
    relay.connect("abc234", "Caleb", "secret");
    expect(sockets[0].url).toBe("wss://relay.example/v1/tables/ABC234/socket?name=Caleb");
    expect(sockets[0].protocols).toEqual(["magicmobile.1", "magicmobile.key.secret"]);
    sockets[0].socket.onmessage?.({ data: JSON.stringify({ t: "welcome", you: "p1-aaa", token: "tok", seats: 3, peers: [], full: false }) });
    relay.remove("p2-\"x\"");
    expect(JSON.parse(sockets[0].sent.at(-1)!)).toEqual({ t: "remove", id: "p2-\"x\"" });

    const limited = new RelayTransport("https://relay.example", () => { throw new Error("no socket"); }, "/relay",
      async () => new Response(JSON.stringify({ error: "rate_limited", message: "Too many tables." }), { status: 429 }));
    await expect(limited.createTable(2)).rejects.toThrow("Too many tables.");
    const offline = new RelayTransport("https://relay.example", () => { throw new Error("no socket"); }, "/relay", async () => { throw new TypeError("offline"); });
    await expect(offline.createTable(2)).rejects.toThrow("Could not reach the table service");
  });
});
