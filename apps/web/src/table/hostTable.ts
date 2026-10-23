/**
 * The host half of RelayTable (OnDeviceMultiplayer.swift `hostRelay` … `leave`, OnDeviceMultiplayer.kt): this browser
 * opens a cross-play table on the relay, fills it, runs the match room, creates the game on its own engine (the Web
 * Image worker, as a solo game does) and serves every guest's engine requests through HostRouter. The host plays its own
 * seat through the same GuestSession a solo game uses; guests reach the engine only through the router.
 *
 * Engine concurrency: the worker answers one request at a time (WorkerTransport.request is one FIFO queue), and while
 * the AI thinks it answers a waiting request only at its next published snapshot (docs/WEB_ENGINE_M1.md). So every
 * request the host adds costs the guests time. Each guest's requests are drained one at a time (the iOS per-peer
 * dispatcher, four queued at most, `busy` beyond), so a guest never has more than one request in the engine queue: ahead
 * of it wait at most the other guests' one each, the host's own poll (and answer) and one clock read, never a backlog,
 * and the queue is first come, first served, so neither side starves the other. The turn clock reads a seat from the
 * polls the host's session and the guests already made at the newest announced revision, and polls the engine itself
 * only for a seat whose read is older, whose clock ran out, or that has not been read for 5 s.
 */
import { EngineClient, type EnginePrompt, type EngineTransport, MatchPoll } from "../core/engineClient";
import { arr, EngineError, EngineJson, get, int, isUuid, type J, type JObject, keysEqual, newUuid, obj, sameUuid, str } from "../core/json";
import type { GameSnapshot } from "../core/models";
import { loadSmartPass } from "../core/smartPass";
import { OnDeviceStartingPlayerChoice, OnDeviceStartingRoll, OnDeviceStartingRollProgress } from "../core/startingRoll";
import { gameEmote, type GameEmote, TableChatText } from "../core/tableChat";
import { TurnClock, TurnClockBoard, TurnClockWire } from "../core/turnClock";
import { type RelayPeer, RelayTransport } from "../relay/relayTransport";
import { storage } from "../ui/storage";
import type { GameTable } from "./gameTable";
import { GuestSession } from "./guestSession";
import type { TableState } from "./guestTable";
import { HostRouter, type PeerFrame } from "./hostRouter";
import { type AISeat, type BuildIdentity, HandshakeFailure, HostLobby, Lobby } from "./lobby";

/** What a host needs of the page's engine: LocalEngine (or a test double). */
export interface HostEngine {
  start(): Promise<{ request: EngineTransport; failure?: Error }>;
  subscribe?(listener: () => void): () => void;
  readonly state?: { stage: string; error?: string };
}

export type HostKind = "custom" | "challenge" | "ranked";
export interface HostOptions {
  /** A challenge or ranked table is for one invited player: it is never offered to friends (onOpenSeats). */
  kind?: HostKind;
  /** A ranked game's server seed, sent when the engine keeps game records (as soloConfiguration does). */
  seed?: bigint;
  /** AI seats after the humans (OnDeviceMultiplayerAISeatDescriptor); humans + AI seats ≤ 4. */
  aiSeats?: AISeat[];
}

const now = () => performance.now() / 1000;
const message = (error: unknown) => (error instanceof Error ? error.message : String(error));
const sleep = (millis: number) => new Promise((resolve) => setTimeout(resolve, millis));
/** How long a revealed die waits before the host rolls the next AI die (OnDeviceRootView.advanceAIRollIfNeeded). */
const AI_DIE_MILLIS = 650;
const CONNECTED = "Connected as host. Every player must keep the app in the foreground.";

/**
 * OnDeviceHostRequestDispatcher: one drain per authenticated peer keeps arrival order through the router's await. Queued
 * and running requests share the four-request limit; a fifth is answered `busy` (the guest keeps its pending command).
 */
export class HostRequestDispatcher {
  private queues = new Map<string, { id: string; frame: PeerFrame }[]>();
  private pending = new Map<string, Set<string>>();
  private draining = new Set<string>();
  private closed = false;

  constructor(private readonly router: HostRouter, private readonly epoch: string, private readonly peerIDs: Set<string>,
    private readonly send: (value: J, peer: string) => void, private readonly onError: (message: string) => void,
    /** Told every successful answer (the host's clock reads a guest's seat from its polls). */
    private readonly onResult?: (peer: string, operation: string, result: J) => void) {}

  receive(value: J, peer: string) {
    if (this.closed || !this.peerIDs.has(peer)) throw EngineError.unboundPeer();
    const fields = obj(value);
    const id = str(fields?.id); const sequence = int(fields?.sequence); const operation = str(fields?.operation);
    if (!fields || !keysEqual(fields, ["type", "epoch", "id", "sequence", "operation", "payload"]) || str(fields.type) !== "request" ||
      !sameUuid(str(fields.epoch), this.epoch) || !isUuid(id) || sequence === undefined || sequence <= 0 || operation === undefined ||
      fields.payload === undefined) throw EngineError.invalid("Invalid host request.");
    const request = { id: id.toUpperCase(), frame: { epoch: this.epoch, sequence, operation, payload: fields.payload } };
    const pending = this.pending.get(peer) ?? new Set<string>();
    if (pending.has(request.id)) throw EngineError.replayed();
    if (pending.size >= 4) {
      this.reply(request, peer, null, { code: "busy", message: "The host is busy. Retry the same action." });
      return;
    }
    pending.add(request.id);
    this.pending.set(peer, pending);
    this.queues.set(peer, [...(this.queues.get(peer) ?? []), request]);
    if (!this.draining.has(peer)) void this.drain(peer);
  }

  private async drain(peer: string) {
    this.draining.add(peer);
    try {
      while (!this.closed && (this.queues.get(peer)?.length ?? 0) > 0) {
        const request = this.queues.get(peer)!.shift()!;
        let result: J = null; let error: J = null;
        try {
          result = await this.router.handle(request.frame, peer);
        } catch (failure) {
          result = null; error = [...message(failure)].slice(0, 240).join("");
        }
        if (this.closed) return;
        if (error === null) this.onResult?.(peer, request.frame.operation, result);
        this.reply(request, peer, result, error);
        this.pending.get(peer)?.delete(request.id);
      }
    } finally {
      this.draining.delete(peer); this.pending.delete(peer); this.queues.delete(peer);
    }
  }

  private reply(request: { id: string; frame: PeerFrame }, peer: string, result: J, error: J) {
    try {
      this.send({ type: "reply", epoch: this.epoch, id: request.id, sequence: request.frame.sequence, result, error }, peer);
    } catch (failure) { this.onError(message(failure)); }
  }

  cancel() { this.closed = true; this.queues.clear(); }
}

export class HostTable implements GameTable {
  readonly solo = false;
  state: TableState = this.initial();
  session?: GuestSession;
  version = 0;
  kind: HostKind = "custom";
  /** The table's code and open seats while it fills (a custom table only), for publishing hosting to friends; undefined after. */
  onOpenSeats?: (code: string | undefined, openSeats: number) => void;

  private listeners = new Set<() => void>();
  private relay?: RelayTransport;
  private lobby?: HostLobby;
  private aiSeats: AISeat[] = [];
  private seed?: bigint;
  private epoch?: string;
  private localReady = false;
  private playerNames = new Map<string, string>();
  private progress?: OnDeviceStartingRollProgress;
  private rollTimer?: ReturnType<typeof setTimeout>;
  private aiRollTimer?: ReturnType<typeof setTimeout>;
  private offerTimer?: ReturnType<typeof setInterval>;
  private offerTicks = 0;
  private starting = false;
  private transport?: { request: EngineTransport; failure?: Error };
  private client?: EngineClient;
  private matchID?: string;
  private keepsRecords = false;
  private router?: HostRouter;
  private dispatcher?: HostRequestDispatcher;
  private unsubscribeEngine?: () => void;
  private suspendedPeers = new Set<string>();
  private relayAway = new Set<string>();
  private presenceSequence = 0;
  private suspensionRevision = 0;
  private peerPresence = new Map<string, number>();
  private lastEmoteFrom = new Map<string, number>();
  private lastChatFrom = new Map<string, number>();
  private chatSequence = 0;
  private generation = 0;
  private hostClock = new TurnClock();
  private clockReads = new Map<string, { revision: number; at: number }>();
  private clockChanged = false;
  private clockOver = false;
  private announcedRevision = -1;
  private openSeatsKey = "";

  constructor(readonly identity: BuildIdentity, private readonly engine: HostEngine, private readonly makeRelay = () => new RelayTransport()) {}

  private initial(): TableState {
    return {
      stage: "idle", status: "Open a table and share its code.", seatsTaken: 0, seatsWanted: 0, waiting: [], seatNames: {}, tableSeats: [],
      turnClock: new TurnClockBoard(), isSuspended: false, reconnecting: false, chat: [], bubbles: {}, isHost: true,
    };
  }

  get localPeerID() { return this.relay?.localPeerID; }

  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  private changed = () => { this.version += 1; this.listeners.forEach((l) => l()); };
  private set(patch: Partial<TableState>) {
    this.state = { ...this.state, ...patch };
    this.changed();
    const open = this.kind === "custom" ? this.openHostedTable : undefined;
    const key = open ? `${open.code}:${open.openSeats}` : "";
    if (key !== this.openSeatsKey) { this.openSeatsKey = key; this.onOpenSeats?.(open?.code, open?.openSeats ?? 0); }
  }

  /** The table while seats are open (OnDeviceMultiplayer.openHostedTable): its code and up to three open seats, once the relay seated the host. */
  get openHostedTable(): { code: string; openSeats: number } | undefined {
    const { tableCode, seatsWanted, seatsTaken, stage } = this.state;
    if (!tableCode || this.matchID || this.lobby || stage === "failed" || stage === "closed" || stage === "idle" || seatsTaken === 0 || seatsWanted <= seatsTaken) return undefined;
    return { code: tableCode, openSeats: Math.min(3, seatsWanted - seatsTaken) };
  }

  /**
   * Opens a relay table for `seats` people (plus any AI seats) and connects as its host. Rejects when the input is invalid
   * or the relay does not open a table (the state then shows why); afterwards the state tells the story.
   */
  async host(name: string, deck: J, seats: 2 | 3 | 4, options: HostOptions = {}) {
    if (this.relay) throw EngineError.invalid("Leave the current table before opening another.");
    if (!Number.isInteger(seats) || seats < 2 || seats > 4) throw EngineError.invalid("A table has 2–4 player seats.");
    const value = { name: name.trim(), deck };
    Lobby.validateSubmission(value);
    const aiSeats = options.aiSeats ?? [];
    Lobby.makeAISettings(aiSeats, seats);
    this.kind = options.kind ?? "custom"; this.seed = options.seed; this.aiSeats = aiSeats;
    this.generation += 1;
    const token = this.generation;
    const relay = this.makeRelay();
    this.relay = relay;
    this.set({ ...this.initial(), stage: "joining", seatsWanted: seats, status: "Opening a table…" });
    // The engine loads while the table fills; a failure shows when the game starts.
    void this.engine.start().catch(() => undefined);
    let table: { code: string; hostKey: string };
    try {
      table = await relay.createTable(seats);
    } catch (error) {
      if (token === this.generation) { this.relay = undefined; this.set({ stage: "failed", status: message(error) }); }
      throw error;
    }
    if (token !== this.generation) return;
    relay.events = {
      onRoster: (peers, full) => { if (token === this.generation) this.roster(peers, full); },
      onPacket: (text, peer) => { if (token === this.generation) this.packet(text, peer); },
      onDisconnect: (peer) => {
        if (token !== this.generation || peer === relay.localPeerID) return;
        this.fail("A player left. This match cannot continue. Leave and start a new match.");
      },
      onError: (text) => { if (token === this.generation) this.fail(text); },
      onConnectionChanged: (connected) => {
        if (token !== this.generation) return;
        this.set({ reconnecting: !connected, ...(this.state.stage === "playing" ? { status: connected ? CONNECTED : "Reconnecting to the table…" } : {}) });
      },
    };
    this.set({ stage: "waiting", tableCode: table.code, status: `Share code ${table.code}. Waiting for players…` });
    relay.connect(table.code, value.name, table.hostKey);
  }

  /** The host turns a joiner away while the table still fills; the relay confirms with a roster without them. */
  remove(peerID: string) {
    const relay = this.relay;
    if (!relay || this.lobby || this.state.stage !== "waiting" || peerID === relay.localPeerID || !this.state.waiting.some((p) => p.id === peerID)) return;
    relay.remove(peerID);
  }

  private roster(peers: RelayPeer[], full: boolean) {
    const relay = this.relay!;
    peers.forEach((p) => this.playerNames.set(p.id, p.name));
    const seatsWanted = relay.seats > 0 ? relay.seats : Math.max(this.state.seatsWanted, peers.length);
    if (!this.lobby) {
      const waiting = full ? [] : [...peers].sort((a, b) => (a.id < b.id ? -1 : 1));
      this.set({ seatsTaken: peers.length, seatsWanted, waiting });
      if (full && relay.localPeerID) this.beginLobby(peers.map((p) => p.id), relay.localPeerID);
      else this.set({ stage: "waiting", status: `Share code ${this.state.tableCode ?? ""}. Waiting for players (${peers.length}/${seatsWanted})…` });
      return;
    }
    this.set({ seatsTaken: peers.length, seatsWanted });
    // A dropped phone pauses the match like a backgrounded app, until it returns or the relay gives up on it. Before the
    // match starts, the repeating offer covers a brief drop.
    const lobby = this.lobby;
    const away = new Set(peers.filter((p) => !p.connected && p.id !== lobby.localPeerID).map((p) => p.id));
    if ([...away].sort().join() !== [...this.relayAway].sort().join()) {
      this.relayAway = away;
      if (this.matchID) this.updateSuspension();
    }
  }

  /** The match room once the table is full: the host repeats its offer every second for ten minutes. */
  private beginLobby(peerIDs: string[], localID: string) {
    try {
      this.lobby = new HostLobby(peerIDs, localID, this.aiSeats);
    } catch (error) {
      this.fail(message(error));
      return;
    }
    // Nobody's deck counts until that player taps Ready in the match room.
    this.epoch = newUuid();
    this.localReady = false;
    this.set({ stage: "room", waiting: [], status: "Match room: choose your deck, then tap Ready. The game starts when everyone is ready." });
    this.updateRoom();
    const token = this.generation;
    this.offerTicks = 0;
    const tick = () => {
      if (token !== this.generation || this.state.stage !== "room" || this.starting) return;
      if (this.offerTicks >= 600) { this.fail("The table timed out before everyone was ready. Leave and open a new table."); return; }
      this.offerTicks += 1;
      try {
        this.broadcast(this.lobby!.packet("offer", this.epoch!, this.identity));
        // Late joiners also learn who is already ready.
        this.broadcastReadyRoster();
      } catch (error) { this.fail(message(error)); }
    };
    tick();
    this.offerTimer = setInterval(tick, 1_000);
  }

  private packet(text: string, peer: string) {
    if (this.state.stage === "failed" || this.state.stage === "closed") return;
    try {
      this.receive(EngineJson.decode(text), peer);
    } catch (error) {
      if (error instanceof HandshakeFailure) {
        if (error.kind === "settings" && this.epoch) this.tryBroadcast({ type: "reject", epoch: this.epoch, reason: "aiSettings" });
        this.fail(error.message);
      }
      // Reject malformed, stale or unauthorized packets without ending the match.
    }
  }

  private receive(value: J, peer: string) {
    const lobby = this.lobby;
    if (!lobby || !this.epoch) throw EngineError.unboundPeer();
    lobby.seatID(peer);
    const fields = obj(value);
    const type = str(fields?.type);
    if (!fields || type === undefined) throw EngineError.invalid("Invalid multiplayer packet.");
    // Only the host offers or starts a match.
    if (type === "offer" || type === "start") throw EngineError.unboundPeer();
    if (type === "submission") {
      const player = lobby.verifySubmission(value, peer, this.identity, this.epoch);
      lobby.submit(player, peer);
      if (this.state.stage !== "room") return;
      this.broadcastReadyRoster();
      this.updateRoom();
      if (lobby.isReady) this.startHost();
      return;
    }
    if (!sameUuid(str(fields.epoch), this.epoch)) throw EngineError.incompatibleBuild();
    switch (type) {
      case "request":
        if (!this.dispatcher) throw EngineError.unboundPeer();
        this.dispatcher.receive(value, peer);
        break;
      case "rollStep": {
        const index = int(fields.index);
        if (!keysEqual(fields, ["type", "epoch", "index"]) || !this.matchID || index === undefined || index < 0) throw EngineError.unboundPeer();
        this.advanceHumanRoll(peer, index);
        break;
      }
      case "presence": {
        const sequence = int(fields.sequence);
        const suspended = fields.suspended;
        if (!keysEqual(fields, ["type", "epoch", "sequence", "suspended"]) || sequence === undefined || sequence <= (this.peerPresence.get(peer) ?? 0) ||
          typeof suspended !== "boolean") throw EngineError.replayed();
        this.peerPresence.set(peer, sequence);
        if (suspended) this.suspendedPeers.add(peer); else this.suspendedPeers.delete(peer);
        if (this.matchID) this.updateSuspension();
        break;
      }
      case "emote": {
        const emote = gameEmote(str(fields.emote));
        if (!keysEqual(fields, ["type", "epoch", "emote"]) || !this.matchID || !emote) throw EngineError.invalid("Invalid emote.");
        // Cosmetic only: a flood from one player is dropped, never an error.
        const at = Date.now();
        if (at - (this.lastEmoteFrom.get(peer) ?? -Infinity) < 1500) return;
        this.lastEmoteFrom.set(peer, at);
        this.addChat(this.nameOf(peer), emote.text, false, emote);
        this.set({ bubbles: { ...this.state.bubbles, [lobby.seatID(peer)]: { emote, at } } });
        break;
      }
      case "chat": {
        const raw = str(fields.text);
        const text = raw !== undefined && TableChatText.codePoints(raw) <= TableChatText.MAX_CODE_POINTS ? TableChatText.sanitize(raw) : undefined;
        if (!keysEqual(fields, ["type", "epoch", "text"]) || !this.matchID || text === undefined) throw EngineError.invalid("Invalid chat message.");
        const at = Date.now();
        if (at - (this.lastChatFrom.get(peer) ?? -Infinity) < 500) return;
        this.lastChatFrom.set(peer, at);
        this.addChat(this.nameOf(peer), text, false);
        break;
      }
      case "end":
        if (!keysEqual(fields, ["type", "epoch"])) throw EngineError.invalid("Invalid match ending.");
        this.fail("A player left. Start a new match to play again.");
        break;
      case "reject":
        if (!keysEqual(fields, ["type", "epoch", "reason"]) || str(fields.reason) !== "aiSettings") throw EngineError.unboundPeer();
        this.tryBroadcast({ type: "reject", epoch: this.epoch, reason: "aiSettings" });
        this.fail(HandshakeFailure.differentSettings().message);
        break;
      // reply, revision, rollAdvance, clock and ready come only from a host.
      default:
        throw EngineError.unboundPeer();
    }
  }

  private nameOf(peer: string): string {
    const lobby = this.lobby;
    let seat: string | undefined;
    try { seat = lobby?.seatID(peer); } catch { seat = undefined; }
    return (seat && this.state.seatNames[seat]) ?? this.playerNames.get(peer) ?? "Player";
  }

  private addChat(name: string, text: string, isLocal: boolean, emote?: GameEmote) {
    this.chatSequence += 1;
    this.set({ chat: [...this.state.chat, { id: this.chatSequence, name, text, isLocal, emote }].slice(-100) });
  }

  /** The host confirms its deck in the match room. Once every player is ready the game starts. */
  markReady(name: string, deck: J) {
    const lobby = this.lobby;
    if (!lobby || this.localReady || this.state.stage !== "room") return;
    const value = { name: name.trim(), deck };
    Lobby.validateSubmission(value);
    lobby.submit(value, lobby.localPeerID);
    this.localReady = true;
    this.broadcastReadyRoster();
    this.set({ status: "Ready. Waiting for the other players…" });
    this.updateRoom();
    if (lobby.isReady) this.startHost();
  }

  private broadcastReadyRoster() {
    if (this.lobby && this.epoch) this.broadcast(this.lobby.readyPacket(this.epoch));
  }

  private updateRoom() {
    const lobby = this.lobby;
    if (!lobby || this.state.stage !== "room") return;
    const players = lobby.peerIDs.map((peer) => {
      const local = peer === lobby.localPeerID;
      const submitted = lobby.submission(peer);
      return {
        id: peer, name: local ? "You" : this.playerNames.get(peer) ?? "Player", isHost: peer === lobby.hostID, isLocal: local,
        isReady: submitted !== undefined, commanders: Lobby.commanderNames(submitted),
      };
    });
    this.set({ room: { players, localReady: this.localReady, aiSummary: lobby.hostAISeatSummary } });
  }

  /** The roster the versus intro shows: humans in seat order, then AI seats. */
  private captureTableSeats(names: Map<string, string>) {
    const lobby = this.lobby!;
    const humans = lobby.peerIDs.map((peer, index) => {
      const seat = `player${index + 1}`;
      return { id: seat, name: names.get(seat) ?? this.playerNames.get(peer) ?? "Player", isLocal: peer === lobby.localPeerID, commanders: Lobby.commanderNames(lobby.submission(peer)) };
    });
    const bots = lobby.aiSeats.map((deck, index) => {
      const seat = `player${lobby.peerIDs.length + index + 1}`;
      return { id: seat, name: names.get(seat) ?? `AI ${index + 1}`, isLocal: false, commanders: Lobby.commanderNames(deck) };
    });
    this.set({ tableSeats: [...humans, ...bots] });
  }

  /** Creates the game on this page's engine, binds the guests, shares the D20 plan and starts the host's own seat. */
  private startHost() {
    const lobby = this.lobby; const epoch = this.epoch;
    if (!lobby || !epoch || this.starting || !lobby.isReady) return;
    this.starting = true;
    const token = this.generation;
    this.set({ stage: "starting", room: undefined, status: "Starting the game…" });
    void (async () => {
      try {
        const transport = await this.engine.start();
        if (token !== this.generation) return;
        const client = new EngineClient(transport.request);
        const capabilities = await client.call("capabilities").catch(() => undefined);
        if (token !== this.generation) return;
        const answerActions = (arr(get(capabilities, "answerActions")) ?? []).map((a) => str(a)).filter((a): a is string => a !== undefined);
        const keepsRecords = get(capabilities, "gameRecord") !== undefined;
        const created = await client.call("create", { configuration: lobby.configuration(this.seed, keepsRecords) });
        const matchID = str(get(created, "matchId"));
        if (matchID !== undefined && token !== this.generation) { void HostTable.release(transport, matchID); return; }
        if (!isUuid(matchID)) {
          if (matchID !== undefined) void HostTable.release(transport, matchID);
          throw EngineError.invalid("The engine returned an invalid match.");
        }
        this.transport = transport; this.client = client; this.keepsRecords = keepsRecords; this.matchID = matchID;
        this.unsubscribeEngine = this.engine.subscribe?.(() => {
          if (this.engine.state?.stage === "failed") this.fail(this.engine.state.error ?? "The engine stopped.");
        });
        const router = new HostRouter(new EngineClient(transport.request), matchID, this.identity, epoch);
        const guests = lobby.peerIDs.filter((peer) => peer !== lobby.hostID);
        guests.forEach((peer) => router.bind(peer, lobby.seatID(peer)));
        this.router = router;
        this.dispatcher = new HostRequestDispatcher(router, epoch, new Set(guests), (value, peer) => {
          if (token === this.generation) this.send(value, peer);
        }, (text) => { if (token === this.generation) this.fail(text); }, (peer, operation, result) => {
          if (operation !== "poll" || token !== this.generation) return;
          let poll: MatchPoll;
          try { poll = new MatchPoll(result); } catch { return; /* the guest validates its own poll */ }
          // The other guests hear of a move a guest's poll saw first.
          this.announceRevision(poll.revision);
          this.observeClock(lobby.seatID(peer), poll);
        });
        this.suspensionRevision += 1;
        router.setSuspended(this.suspendedPeers.size > 0 || this.relayAway.size > 0, this.suspensionRevision);

        const names = lobby.seatNames();
        const seatNames: JObject = Object.fromEntries(names);
        Lobby.validatedSeatNames(seatNames, lobby.totalSeats);
        const seats = Array.from({ length: names.size }, (_, i) => `player${i + 1}`);
        const roll = OnDeviceStartingRoll.generate(seats);
        this.broadcast({ ...lobby.packet("start", epoch, this.identity), matchId: matchID, seatNames, roll: roll.encoded(seats) });
        this.progress = new OnDeviceStartingRollProgress(roll, new Set(lobby.peerIDs.map((_, i) => `player${i + 1}`)));
        const hostSeat = lobby.seatID(lobby.localPeerID);
        this.set({ seatNames: Object.fromEntries(names), localSeatID: hostSeat });
        this.captureTableSeats(names);

        const session = new GuestSession(transport.request, matchID, hostSeat, this.changed, "local");
        session.autoCommand = (snapshot) => this.startingPlayerCommand(snapshot);
        session.smartPass = loadSmartPass(storage.get);
        session.supportedAnswerActions = new Set(answerActions);
        session.setAutoPassAfterCast(storage.get("mm.web.autoPassAfterCast") !== "off");
        session.onPoll = (poll) => {
          if (token !== this.generation) return;
          this.announceRevision(poll.revision);
          this.observeClock(hostSeat, poll);
        };
        this.session = session;
        clearInterval(this.offerTimer);
        this.set({ stage: "playing", room: undefined, status: CONNECTED });
        session.start();
        this.updateRoll();
        void this.runHostClock(token, matchID, client, lobby.peerIDs.map((_, i) => `player${i + 1}`));
      } catch (error) {
        if (token === this.generation) this.fail(message(error));
      }
    })();
  }

  /** Once every die is shown, XMage's starting-player question is answered with the shared winner. */
  private startingPlayerCommand(snapshot: GameSnapshot) {
    const progress = this.progress;
    if (!progress || !progress.isComplete) return undefined;
    const winner = this.state.seatNames[progress.roll.winnerSeatID];
    return winner === undefined ? undefined : OnDeviceStartingPlayerChoice.commandForName(snapshot, winner);
  }

  private advanceHumanRoll(peer: string, index: number) {
    const lobby = this.lobby; const progress = this.progress;
    if (!lobby || !progress || index !== progress.revealedCount) throw EngineError.replayed();
    progress.advance(lobby.seatID(peer), false);
    this.broadcast({ type: "rollAdvance", epoch: this.epoch!, index });
    this.updateRoll();
  }

  /** The host rolls each AI seat's die after the preceding die settled (advanceAISeatIfNeeded). */
  private advanceAISeat() {
    const progress = this.progress; const seat = progress?.nextSeatID;
    if (!progress || seat === undefined || progress.humanSeatIDs.has(seat)) return;
    if (this.state.isSuspended) { this.scheduleAIRoll(); return; }
    const index = progress.advance(seat, true);
    this.broadcast({ type: "rollAdvance", epoch: this.epoch!, index });
    this.updateRoll();
  }

  private scheduleAIRoll() {
    clearTimeout(this.aiRollTimer);
    const token = this.generation;
    this.aiRollTimer = setTimeout(() => {
      if (token !== this.generation) return;
      try { this.advanceAISeat(); } catch (error) { this.fail(message(error)); }
    }, AI_DIE_MILLIS);
  }

  private updateRoll() {
    const progress = this.progress;
    if (!progress) return;
    const next = progress.nextSeatID;
    const status = next !== undefined ? `Waiting for ${this.state.seatNames[next] ?? "the next player"} to roll.` : "Starting player decided by D20.";
    this.set({ roll: { roll: progress.roll, revealed: progress.revealedCount, nextSeatID: next, hasRolled: false, status } });
    clearTimeout(this.rollTimer);
    if (next !== undefined) {
      const token = this.generation;
      this.rollTimer = setTimeout(() => {
        if (token === this.generation && !progress.isComplete) this.fail("Starting roll timed out. Leave and start a new match.");
      }, 300_000);
      if (!progress.humanSeatIDs.has(next)) this.scheduleAIRoll();
    } else {
      // The last die settles on every screen; answer the starting-player question now.
      this.session?.wake();
    }
  }

  /** The host's own tap: shown here and to every guest at once. */
  rollStartingPlayer() {
    const lobby = this.lobby; const progress = this.progress;
    if (!lobby || !this.epoch || !progress || this.state.stage !== "playing" || this.state.isSuspended ||
      progress.nextSeatID !== this.state.localSeatID) throw EngineError.invalid("Wait for your turn to roll.");
    this.advanceHumanRoll(lobby.localPeerID, progress.revealedCount);
  }

  /** Tells each connected guest that the game moved on. Best effort: a guest that misses a notice polls on its heartbeat. */
  private announceRevision(revision: number) {
    const lobby = this.lobby;
    if (!lobby || !this.epoch || revision <= this.announcedRevision) return;
    this.announcedRevision = revision;
    for (const peer of lobby.peerIDs) {
      if (peer !== lobby.hostID && !this.relayAway.has(peer)) this.trySend({ type: "revision", epoch: this.epoch, revision }, peer);
    }
  }

  /** A seat's newest poll, from the host's session, a guest's own poll or the clock's read. */
  private observeClock(seat: string, poll: MatchPoll) {
    const last = this.clockReads.get(seat);
    if (this.clockOver || (last && poll.revision < last.revision)) return;
    this.clockReads.set(seat, { revision: poll.revision, at: now() });
    if (["ended", "failed", "closed"].includes(poll.phase)) {
      this.clockOver = true;
      this.hostClock.clear();
      this.publishHostClock();
      return;
    }
    if (this.hostClock.observe(seat, TurnClock.prompt(poll), now())) this.clockChanged = true;
  }

  /** The turn timer for every human seat (beginHostClock): one tick a second until the game is over. */
  private async runHostClock(token: number, matchID: string, client: EngineClient, seats: string[]) {
    while (token === this.generation && !this.clockOver) {
      await sleep(1_000);
      if (token !== this.generation || this.clockOver) return;
      await this.tickHostClock(token, matchID, client, seats);
    }
  }

  private async tickHostClock(token: number, matchID: string, client: EngineClient, seats: string[]) {
    let changed = this.hostClock.setPaused(this.state.isSuspended || this.progress?.isComplete === false, now());
    const due = new Set(this.hostClock.expired(now()).map(([seat]) => seat));
    const prompts = new Map<string, EnginePrompt | undefined>();
    for (const seat of seats) {
      const last = this.clockReads.get(seat);
      const stale = last === undefined || now() - last.at >= 5 || last.revision < this.announcedRevision;
      if (!due.has(seat) && !stale) continue;
      let poll: MatchPoll;
      try { poll = await client.poll(matchID, seat, last?.revision ?? 0); } catch { continue; }
      if (token !== this.generation) return;
      this.observeClock(seat, poll);
      if (this.clockOver) return;
      prompts.set(seat, poll.prompt);
    }
    changed = this.clockChanged || changed;
    this.clockChanged = false;
    for (const [seat, expired] of this.hostClock.expired(now())) {
      // Act only on the question this tick just read for that seat.
      const prompt = prompts.get(seat);
      if (!prompt || prompt.id !== expired.id || prompt.revision !== expired.revision) continue;
      const answer = TurnClock.defaultAnswer(prompt);
      const outcome = this.hostClock.timeout(seat, expired, answer !== undefined, now());
      if (!outcome) continue;
      changed = true;
      if (outcome === "answer") {
        try { await client.respond(matchID, seat, prompt, answer ?? null, newUuid()); } catch { this.hostClock.answerFailed(seat, expired, now()); }
      } else if (outcome === "forfeit") {
        try { await client.concede(matchID, seat); } catch { /* already over */ }
      }
      if (token !== this.generation) return;
    }
    if (changed) this.publishHostClock();
  }

  /** Shows the host's clocks here and sends them to every connected guest. Best effort, like revision notices. */
  private publishHostClock() {
    const at = now();
    const entries = this.hostClock.entries(at);
    this.set({ turnClock: TurnClockBoard.from(this.hostClock.paused, entries, at) });
    const lobby = this.lobby;
    if (!lobby || !this.epoch) return;
    const packet = TurnClockWire.packet(this.epoch, this.hostClock.paused, entries);
    for (const peer of lobby.peerIDs) if (peer !== lobby.hostID && !this.relayAway.has(peer)) this.trySend(packet, peer);
  }

  /** The tab was hidden or shown: the match pauses like a backgrounded phone (only once it runs; a hidden tab keeps the room). */
  setForeground(active: boolean) {
    const lobby = this.lobby;
    if (!lobby || !this.matchID || this.state.stage !== "playing") return;
    if (active) this.suspendedPeers.delete(lobby.localPeerID); else this.suspendedPeers.add(lobby.localPeerID);
    this.updateSuspension();
  }

  private updateSuspension() {
    const lobby = this.lobby;
    if (!lobby || this.state.stage === "failed" || this.state.stage === "closed") return;
    const paused = this.suspendedPeers.size > 0 || this.relayAway.size > 0;
    let status: string;
    if (this.relayAway.size > 0) status = `Waiting for ${[...this.relayAway].sort().map((p) => this.nameOf(p)).join(", ")}…`;
    else status = paused ? "Match paused. Every player must return to the foreground." : CONNECTED;
    this.set({ isSuspended: paused, status });
    this.suspensionRevision += 1;
    this.router?.setSuspended(paused, this.suspensionRevision);
    for (const peer of lobby.peerIDs) {
      if (peer === lobby.hostID || !this.epoch) continue;
      this.presenceSequence += 1;
      try { this.send({ type: "presence", epoch: this.epoch, sequence: this.presenceSequence, suspended: paused }, peer); } catch (error) {
        this.fail(message(error));
        return;
      }
    }
  }

  /** Quick chat to every other player in the running match. */
  sendEmote(emote: GameEmote) {
    if (!this.epoch || !this.matchID) return;
    this.tryBroadcast({ type: "emote", epoch: this.epoch, emote: emote.raw });
    this.addChat("You", emote.text, true, emote);
    if (this.state.localSeatID) this.set({ bubbles: { ...this.state.bubbles, [this.state.localSeatID]: { emote, at: Date.now() } } });
  }

  /** A typed chat line to every other player in the running match. */
  sendChat(text: string) {
    if (!this.epoch || !this.matchID) return;
    const clean = TableChatText.sanitize(text);
    if (clean === undefined) return;
    this.tryBroadcast({ type: "chat", epoch: this.epoch, text: clean });
    this.addChat("You", clean, true);
  }

  async concede() {
    if (!this.session) throw EngineError.invalid("The game has not started.");
    await this.session.concede();
  }

  /**
   * The finished game's record (the engine's `record` op), before the match is destroyed on leave; undefined on engines
   * without game records or when recording stopped. Local only, never sent to a guest (HostRouter refuses `record`).
   */
  async gameRecord(): Promise<J | undefined> {
    if (!this.keepsRecords || !this.client || !this.matchID) return undefined;
    try {
      const record = await this.client.call("record", { matchId: this.matchID });
      return get(record, "format") === "magicmobile-game-record" && get(record, "broken") === undefined ? record : undefined;
    } catch { return undefined; }
  }

  private send(value: J, peer: string) {
    const relay = this.relay;
    if (!relay) throw EngineError.unboundPeer();
    relay.send(EngineJson.encode(value), peer);
  }

  private trySend(value: J, peer: string) {
    try { this.send(value, peer); } catch { /* the relay resumes the seat or the table fails */ }
  }

  private broadcast(value: J) {
    const lobby = this.lobby;
    if (!lobby) return;
    for (const peer of lobby.peerIDs) if (peer !== lobby.localPeerID) this.send(value, peer);
  }

  private tryBroadcast(value: J) {
    try { this.broadcast(value); } catch { /* the relay resumes the seat or the table fails */ }
  }

  private fail(status: string) {
    if (this.state.stage === "failed" || this.state.stage === "closed") return;
    this.teardown();
    this.set({ stage: "failed", status, room: undefined, roll: undefined, waiting: [], turnClock: new TurnClockBoard() });
  }

  private teardown() {
    clearTimeout(this.rollTimer); clearTimeout(this.aiRollTimer); clearInterval(this.offerTimer);
    this.session?.stop();
    this.dispatcher?.cancel();
    this.unsubscribeEngine?.();
    this.unsubscribeEngine = undefined;
    if (this.epoch && this.lobby) this.tryBroadcast({ type: "end", epoch: this.epoch });
    this.relay?.disconnect();
    this.generation += 1;
  }

  /** Concedes a seat (the host's, when the game still runs), then destroys the match; destroy waits while the game unwinds. */
  private static async release(transport: { request: EngineTransport; failure?: Error }, matchID: string, concedeSeat?: string) {
    if (transport.failure) return;
    const client = new EngineClient(transport.request);
    if (concedeSeat) { try { await client.concede(matchID, concedeSeat); } catch { /* already over */ } }
    for (let attempt = 0; attempt < 150; attempt += 1) {
      try {
        await client.call("destroy", { matchId: matchID });
        return;
      } catch (error) {
        if (error instanceof EngineError && error.code === "engine_busy_shutdown") { await sleep(200); continue; }
        return; // unknown_match: already gone
      }
    }
  }

  /** Leaves the table for good: the guests are told at once and the engine lets go of the match. */
  leave() {
    if (this.state.stage !== "failed") this.teardown();
    if (this.transport && this.matchID) {
      const phase = this.session?.state.phase;
      const running = this.session !== undefined && !["ended", "failed", "closed"].includes(phase ?? "");
      void HostTable.release(this.transport, this.matchID, running ? this.state.localSeatID : undefined);
    }
    this.relay = undefined; this.lobby = undefined; this.session = undefined; this.epoch = undefined; this.router = undefined; this.dispatcher = undefined;
    this.progress = undefined; this.localReady = false; this.starting = false; this.matchID = undefined; this.client = undefined;
    this.transport = undefined; this.keepsRecords = false;
    this.suspendedPeers = new Set(); this.relayAway = new Set(); this.peerPresence = new Map(); this.presenceSequence = 0; this.suspensionRevision = 0;
    this.hostClock = new TurnClock(); this.clockReads = new Map(); this.clockChanged = false; this.clockOver = false; this.announcedRevision = -1;
    this.playerNames = new Map(); this.seed = undefined; this.aiSeats = [];
    this.set({ ...this.initial(), stage: "idle", status: "Match closed." });
  }
}
