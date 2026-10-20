/**
 * The guest half of RelayTable (OnDeviceMultiplayer.kt / .swift) for a browser: join a phone-hosted
 * cross-play table by its code, ready up in the match room, take part in the shared D20 roll, then
 * play through the host's engine. The browser never hosts and runs no engine in this milestone.
 */
import { EngineError, EngineJson, get, int, type J, keysEqual, obj, sameUuid, str } from "../core/json";
import type { GameSnapshot } from "../core/models";
import { OnDeviceStartingPlayerChoice, OnDeviceStartingRoll, OnDeviceStartingRollProgress } from "../core/startingRoll";
import { gameEmote, type GameEmote, TableChatText, TableJoinLink } from "../core/tableChat";
import { TurnClockBoard, TurnClockWire } from "../core/turnClock";
import { type RelayPeer, RelayTransport } from "../relay/relayTransport";
import { GuestSession } from "./guestSession";
import { type BuildIdentity, GuestLobby, HandshakeFailure, Lobby } from "./lobby";
import { HostRetryPolicy, HostUnavailable, RemoteEngineTransport } from "./remoteEngine";

export interface TableSeat { id: string; name: string; commanders: string[]; isLocal: boolean }
export interface RoomPlayer { id: string; name: string; isHost: boolean; isLocal: boolean; isReady: boolean; commanders: string[] }
export interface ChatLine { id: number; name: string; text: string; isLocal: boolean; emote?: GameEmote }

export interface TableState {
  stage: "idle" | "joining" | "waiting" | "room" | "starting" | "playing" | "failed" | "closed";
  status: string;
  tableCode?: string;
  seatsTaken: number;
  seatsWanted: number;
  waiting: RelayPeer[];
  room?: { players: RoomPlayer[]; localReady: boolean; aiSummary?: string };
  seatNames: Record<string, string>;
  tableSeats: TableSeat[];
  localSeatID?: string;
  roll?: { roll: OnDeviceStartingRoll; revealed: number; nextSeatID?: string; hasRolled: boolean; status: string };
  turnClock: TurnClockBoard;
  isSuspended: boolean;
  reconnecting: boolean;
  chat: ChatLine[];
  bubbles: Record<string, { emote: GameEmote; at: number }>;
}

const now = () => performance.now() / 1000;

export class GuestTable {
  state: TableState = this.initial();
  session?: GuestSession;
  private listeners = new Set<() => void>();
  private relay?: RelayTransport;
  private lobby?: GuestLobby;
  private remote?: RemoteEngineTransport;
  private submission?: J;
  private epoch?: string;
  private localReady = false;
  private reportedReady = new Map<string, string[]>();
  private playerNames = new Map<string, string>();
  private progress?: OnDeviceStartingRollProgress;
  private rollTimer?: ReturnType<typeof setTimeout>;
  private lobbyTimer?: ReturnType<typeof setTimeout>;
  private relayAway = new Set<string>();
  private hostSuspended = false;
  private presenceSequence = 0;
  private hostPresenceSequence = 0;
  private lastEmoteFrom = new Map<string, number>();
  private lastChatFrom = new Map<string, number>();
  private chatSequence = 0;
  private generation = 0;

  constructor(readonly identity: BuildIdentity, private readonly makeRelay = () => new RelayTransport()) {}

  private initial(): TableState {
    return {
      stage: "idle", status: "Join a table with its code.", seatsTaken: 0, seatsWanted: 0, waiting: [], seatNames: {}, tableSeats: [],
      turnClock: new TurnClockBoard(), isSuspended: false, reconnecting: false, chat: [], bubbles: {},
    };
  }

  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  private set(patch: Partial<TableState>) { this.state = { ...this.state, ...patch }; this.listeners.forEach((l) => l()); }
  private changed = () => this.listeners.forEach((l) => l());

  /** Joins a table by its code (or a join link); the host's AI choices apply once the table fills. */
  join(codeOrLink: string, name: string, deck: J) {
    if (this.relay) throw EngineError.invalid("Leave the current table before joining another.");
    const raw = codeOrLink.trim();
    const code = TableJoinLink.code(raw) ?? TableJoinLink.normalized(raw);
    if (!code) throw EngineError.invalid("Table codes have six letters and numbers.");
    const value = { name: name.trim(), deck };
    Lobby.validateSubmission(value);
    this.submission = value;
    this.generation += 1;
    const token = this.generation;
    const relay = this.makeRelay();
    this.relay = relay;
    relay.events = {
      onRoster: (peers, full) => { if (token === this.generation) this.roster(peers, full); },
      onPacket: (text, peer) => { if (token === this.generation) this.packet(text, peer); },
      onDisconnect: (peer) => {
        if (token !== this.generation || peer === relay.localPeerID) return;
        const host = this.lobby?.hostID === peer || (!this.lobby && peer.startsWith("p1-"));
        this.fail(host ? "The host left this table." : "A player left. This match cannot continue. Leave and start a new match.");
      },
      onError: (message) => { if (token === this.generation) this.fail(message); },
      onConnectionChanged: (connected) => {
        if (token !== this.generation) return;
        this.set({ reconnecting: !connected, status: connected ? this.connectedStatus() : "Reconnecting to the table…" });
      },
    };
    this.set({ ...this.initial(), stage: "joining", tableCode: code, status: `Joining table ${code}…` });
    relay.connect(code, name.trim());
  }

  private connectedStatus() {
    return this.state.stage === "playing" ? "Connected. Every player must keep the app in the foreground." : this.state.status;
  }

  private roster(peers: RelayPeer[], full: boolean) {
    const relay = this.relay!;
    peers.forEach((p) => this.playerNames.set(p.id, p.name));
    const seatsWanted = relay.seats > 0 ? relay.seats : Math.max(this.state.seatsWanted, peers.length);
    if (!this.lobby && full) { this.set({ seatsTaken: peers.length, seatsWanted, waiting: [] }); this.startLobby(peers.map((p) => p.id)); return; }
    if (!this.lobby) {
      this.set({
        stage: "waiting", seatsTaken: peers.length, seatsWanted, waiting: [...peers].sort((a, b) => (a.id < b.id ? -1 : 1)),
        status: `Waiting for players (${peers.length}/${seatsWanted})…`,
      });
      return;
    }
    // A dropped phone pauses the match like a backgrounded app, until it returns or the relay gives up on it.
    const away = new Set(peers.filter((p) => !p.connected && p.id !== this.lobby!.localPeerID).map((p) => p.id));
    if ([...away].sort().join() !== [...this.relayAway].sort().join()) { this.relayAway = away; this.updateSuspension(); }
  }

  private startLobby(peerIDs: string[]) {
    const relay = this.relay!;
    const localID = relay.localPeerID;
    if (!localID) return;
    try {
      this.lobby = new GuestLobby(peerIDs, localID);
    } catch (error) {
      this.fail(error instanceof Error ? error.message : "Could not start the table.");
      return;
    }
    this.localReady = false; this.reportedReady = new Map();
    this.set({ stage: "room", status: "Match room: tap Ready. The game starts when everyone is." });
    this.updateRoom();
    const token = this.generation;
    // The host repeats its offer every second for ten minutes; a table that never starts times out.
    this.lobbyTimer = setTimeout(() => {
      if (token === this.generation && this.state.stage === "room") this.fail("The table timed out before everyone was ready. Leave and open a new table.");
    }, 600_000);
  }

  private packet(text: string, peer: string) {
    if (this.state.stage === "failed" || this.state.stage === "closed") return;
    try {
      this.receive(EngineJson.decode(text), peer);
    } catch (error) {
      if (error instanceof HandshakeFailure) {
        if (error.kind === "settings" && this.epoch === undefined) {
          const epoch = str(get(EngineJson.decode(text), "epoch"));
          if (epoch) this.trySend({ type: "reject", epoch, reason: "aiSettings" }, peer);
        } else if (error.kind === "settings" && this.epoch) this.trySend({ type: "reject", epoch: this.epoch, reason: "aiSettings" }, peer);
        this.fail(error.message);
      }
      // Reject malformed, stale or unauthorized packets without ending the match.
    }
  }

  private receive(value: J, peer: string) {
    const lobby = this.lobby;
    if (!lobby) throw EngineError.unboundPeer();
    lobby.seatID(peer);
    const fields = obj(value);
    const type = str(fields?.type);
    if (!fields || type === undefined) throw EngineError.invalid("Invalid multiplayer packet.");
    if (type === "offer" || type === "submission" || type === "start") {
      const incoming = lobby.verifyHandshake(value, peer, this.identity, this.epoch);
      if (type === "offer") {
        lobby.acceptHostOffer(value);
        this.epoch = incoming;
        this.updateRoom();
        if (!this.remote && this.localReady) this.sendSubmission();
      } else if (type === "start") {
        if (this.remote) return;
        this.epoch = incoming;
        const total = lobby.peerIDs.length + lobby.aiSeatCount;
        const names = Lobby.validatedSeatNames(fields.seatNames, total);
        const seats = Array.from({ length: names.size }, (_, i) => `player${i + 1}`);
        const roll = OnDeviceStartingRoll.decode(fields.roll, seats);
        this.progress = new OnDeviceStartingRollProgress(roll, new Set(lobby.peerIDs.map((_, i) => `player${i + 1}`)));
        this.set({ seatNames: Object.fromEntries(names), localSeatID: lobby.seatID(lobby.localPeerID) });
        this.captureTableSeats(names);
        this.startClient(str(fields.matchId)!, incoming);
      }
      return;
    }
    if (!this.epoch || !sameUuid(str(fields.epoch), this.epoch)) throw EngineError.incompatibleBuild();
    const fromHost = peer === lobby.hostID;
    switch (type) {
      case "reply":
        if (!this.remote) throw EngineError.unboundPeer();
        this.remote.receive(value, peer);
        break;
      case "revision": {
        const revision = int(fields.revision);
        if (!fromHost || !keysEqual(fields, ["type", "epoch", "revision"]) || typeof fields.revision !== "number" || revision === undefined || revision < 0) {
          throw EngineError.invalid("Invalid revision notice.");
        }
        this.session?.noticed(revision);
        break;
      }
      case "rollAdvance": {
        const index = int(fields.index);
        if (!keysEqual(fields, ["type", "epoch", "index"]) || !fromHost || index === undefined || index < 0 || !this.progress) throw EngineError.unboundPeer();
        this.progress.acceptHostAdvance(index);
        this.updateRoll(false);
        break;
      }
      case "clock": {
        if (!fromHost) throw EngineError.unboundPeer();
        const { paused, entries } = TurnClockWire.parse(value);
        this.set({ turnClock: TurnClockBoard.from(paused, entries, now()) });
        break;
      }
      case "ready":
        this.reportedReady = lobby.acceptReadyPacket(value, peer);
        this.updateRoom();
        break;
      case "presence": {
        const sequence = int(fields.sequence);
        const suspended = fields.suspended;
        if (!keysEqual(fields, ["type", "epoch", "sequence", "suspended"]) || sequence === undefined || sequence <= this.hostPresenceSequence ||
          typeof suspended !== "boolean") throw EngineError.replayed();
        if (!fromHost) throw EngineError.unboundPeer();
        this.hostPresenceSequence = sequence;
        this.hostSuspended = suspended;
        this.updateSuspension();
        break;
      }
      case "emote": {
        const emote = gameEmote(str(fields.emote));
        if (!keysEqual(fields, ["type", "epoch", "emote"]) || !this.remote || !emote) throw EngineError.invalid("Invalid emote.");
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
        if (!keysEqual(fields, ["type", "epoch", "text"]) || !this.remote || text === undefined) throw EngineError.invalid("Invalid chat message.");
        const at = Date.now();
        if (at - (this.lastChatFrom.get(peer) ?? -Infinity) < 500) return;
        this.lastChatFrom.set(peer, at);
        this.addChat(this.nameOf(peer), text, false);
        break;
      }
      case "end":
        if (!keysEqual(fields, ["type", "epoch"])) throw EngineError.invalid("Invalid match ending.");
        this.fail(fromHost ? "The host ended this match." : "A player left. Start a new match to play again.");
        break;
      case "reject":
        if (!keysEqual(fields, ["type", "epoch", "reason"]) || str(fields.reason) !== "aiSettings" || !fromHost) throw EngineError.unboundPeer();
        this.fail(HandshakeFailure.differentSettings().message);
        break;
      default:
        throw EngineError.invalid("Unknown multiplayer packet.");
    }
  }

  private nameOf(peer: string): string {
    const lobby = this.lobby;
    return (lobby && this.state.seatNames[lobby.seatID(peer)]) ?? this.playerNames.get(peer) ?? "Player";
  }

  private addChat(name: string, text: string, isLocal: boolean, emote?: GameEmote) {
    this.chatSequence += 1;
    this.set({ chat: [...this.state.chat, { id: this.chatSequence, name, text, isLocal, emote }].slice(-100) });
  }

  /** The local player confirms their deck in the match room. */
  markReady(name: string, deck: J) {
    const lobby = this.lobby;
    if (!lobby || this.localReady || this.state.stage !== "room") return;
    const value = { name: name.trim(), deck };
    Lobby.validateSubmission(value);
    this.submission = value;
    this.localReady = true;
    if (this.epoch && lobby.acceptedHostSettings) this.sendSubmission();
    this.set({ status: this.epoch ? "Ready. Waiting for the other players…" : "Ready. Waiting for the host…" });
    this.updateRoom();
  }

  private sendSubmission() {
    const lobby = this.lobby!;
    this.trySend(lobby.submissionPacket(this.epoch!, this.identity, this.submission!), lobby.hostID);
  }

  private updateRoom() {
    const lobby = this.lobby;
    if (!lobby || this.state.stage !== "room") return;
    const players = lobby.peerIDs.map((peer) => {
      const local = peer === lobby.localPeerID;
      return {
        id: peer, name: local ? "You" : this.playerNames.get(peer) ?? "Player", isHost: peer === lobby.hostID, isLocal: local,
        isReady: local ? this.localReady : this.reportedReady.has(peer),
        commanders: local ? Lobby.commanderNames(this.localReady ? this.submission : undefined) : this.reportedReady.get(peer) ?? [],
      };
    });
    this.set({ room: { players, localReady: this.localReady, aiSummary: lobby.acceptedHostSettings ? lobby.hostAISeatSummary : undefined } });
  }

  /** The roster the versus intro shows: humans in seat order, then AI seats. */
  private captureTableSeats(names: Map<string, string>) {
    const lobby = this.lobby!;
    const humans = lobby.peerIDs.map((peer, index) => {
      const seat = `player${index + 1}`;
      const local = peer === lobby.localPeerID;
      return {
        id: seat, name: names.get(seat) ?? this.playerNames.get(peer) ?? "Player", isLocal: local,
        commanders: local ? Lobby.commanderNames(this.submission) : this.reportedReady.get(peer) ?? [],
      };
    });
    const bots = Array.from({ length: lobby.aiSeatCount }, (_, index) => {
      const seat = `player${lobby.peerIDs.length + index + 1}`;
      const deck = (get(lobby.aiSettings, "seats") as J[])[index];
      return { id: seat, name: names.get(seat) ?? `AI ${index + 1}`, isLocal: false, commanders: Lobby.commanderNames(deck) };
    });
    this.set({ tableSeats: [...humans, ...bots] });
  }

  private startClient(matchID: string, epoch: string) {
    const lobby = this.lobby!;
    const relay = this.relay!;
    const seatID = lobby.seatID(lobby.localPeerID);
    const remote = new RemoteEngineTransport(lobby.hostID, matchID, seatID, epoch, (text, peer) => relay.send(text, peer));
    this.remote = remote;
    clearTimeout(this.lobbyTimer);
    const token = this.generation;
    this.set({ stage: "starting", room: undefined, status: "Connecting to the host’s game…" });
    void (async () => {
      // Hello changes nothing on the host, so a lost answer is simply asked again.
      const retries = new HostRetryPolicy();
      for (;;) {
        try { await remote.hello(this.identity); break; } catch (error) {
          const backoff = retries.delayAfter(error);
          if (backoff === undefined || token !== this.generation) {
            if (token === this.generation) this.fail(error instanceof Error ? error.message : "Could not reach the host.");
            return;
          }
          this.set({ status: `Waiting for ${this.nameOf(lobby.hostID)}…` });
          await new Promise((resolve) => setTimeout(resolve, backoff));
        }
      }
      if (token !== this.generation) return;
      const session = new GuestSession(remote, matchID, seatID, this.changed);
      session.autoCommand = (snapshot) => this.startingPlayerCommand(snapshot);
      this.session = session;
      session.start();
      this.updateRoll(false);
      this.set({ stage: "playing", status: "Connected. Every player must keep the app in the foreground." });
    })();
  }

  /** Once every die is shown, XMage's starting-player question is answered with the shared winner. */
  private startingPlayerCommand(snapshot: GameSnapshot) {
    const progress = this.progress;
    if (!progress || !progress.isComplete) return undefined;
    const winner = this.state.seatNames[progress.roll.winnerSeatID];
    return winner === undefined ? undefined : OnDeviceStartingPlayerChoice.commandForName(snapshot, winner);
  }

  private updateRoll(hasRolled: boolean) {
    const progress = this.progress;
    if (!progress) return;
    const next = progress.nextSeatID;
    const status = next !== undefined ? `Waiting for ${this.state.seatNames[next] ?? "the next player"} to roll.` : "Starting player decided by D20.";
    this.set({ roll: { roll: progress.roll, revealed: progress.revealedCount, nextSeatID: next, hasRolled, status } });
    clearTimeout(this.rollTimer);
    if (next !== undefined) {
      const token = this.generation;
      this.rollTimer = setTimeout(() => {
        if (token === this.generation && !progress.isComplete) this.fail("Starting roll timed out. Leave and start a new match.");
      }, 300_000);
    } else {
      // The last die settles on every screen; poll for the starting-player question now.
      this.session?.wake();
    }
  }

  /** A human tap advances only that seat; the host broadcasts the next visible step to everyone. */
  rollStartingPlayer() {
    const lobby = this.lobby; const progress = this.progress; const roll = this.state.roll;
    if (!lobby || !this.epoch || !progress || this.state.stage !== "playing" || this.state.isSuspended ||
      progress.nextSeatID !== this.state.localSeatID) throw EngineError.invalid("Wait for your turn to roll.");
    if (roll?.hasRolled) return;
    this.trySend({ type: "rollStep", epoch: this.epoch, index: progress.revealedCount }, lobby.hostID);
    this.set({ roll: { ...roll!, hasRolled: true, status: "Sharing your roll with everyone…" } });
  }

  /** Quick chat to every other player in the running match. */
  sendEmote(emote: GameEmote) {
    if (!this.epoch || !this.remote) return;
    this.broadcast({ type: "emote", epoch: this.epoch, emote: emote.raw });
    this.addChat("You", emote.text, true, emote);
    if (this.state.localSeatID) this.set({ bubbles: { ...this.state.bubbles, [this.state.localSeatID]: { emote, at: Date.now() } } });
  }

  /** A typed chat line to every other player in the running match. */
  sendChat(message: string) {
    if (!this.epoch || !this.remote) return;
    const clean = TableChatText.sanitize(message);
    if (clean === undefined) return;
    this.broadcast({ type: "chat", epoch: this.epoch, text: clean });
    this.addChat("You", clean, true);
  }

  /** The tab was hidden or shown: the host pauses the match like a backgrounded phone. */
  setForeground(active: boolean) {
    const lobby = this.lobby;
    if (!lobby || !this.epoch || !this.remote || this.state.stage !== "playing") return;
    this.presenceSequence += 1;
    this.trySend({ type: "presence", epoch: this.epoch, sequence: this.presenceSequence, suspended: !active }, lobby.hostID);
  }

  private updateSuspension() {
    const paused = this.hostSuspended || this.relayAway.size > 0;
    let status: string;
    if (this.relayAway.size > 0) status = `Waiting for ${[...this.relayAway].sort().map((p) => this.nameOf(p)).join(", ")}…`;
    else if (paused) status = "Match paused. Every player must return to the foreground.";
    else status = "Connected. Every player must keep the app in the foreground.";
    this.set({ isSuspended: paused, status });
  }

  async concede() {
    if (!this.session) throw EngineError.invalid("The game has not started.");
    await this.session.concede();
  }

  private broadcast(value: J) {
    const lobby = this.lobby;
    if (!lobby) return;
    for (const peer of lobby.peerIDs) if (peer !== lobby.localPeerID) this.trySend(value, peer);
  }

  private trySend(value: J, peer: string) {
    try { this.relay?.send(EngineJson.encode(value), peer); } catch { /* the relay resumes the seat or the table fails */ }
  }

  private fail(message: string) {
    if (this.state.stage === "failed" || this.state.stage === "closed") return;
    this.teardown();
    this.set({ stage: "failed", status: message, room: undefined, roll: undefined, turnClock: new TurnClockBoard() });
  }

  private teardown() {
    clearTimeout(this.rollTimer); clearTimeout(this.lobbyTimer);
    this.session?.stop();
    this.remote?.close();
    if (this.epoch && this.lobby) this.broadcast({ type: "end", epoch: this.epoch });
    this.relay?.disconnect();
    this.generation += 1;
  }

  /** Leaves the table for good; the host is told at once. */
  leave() {
    if (this.state.stage !== "failed") this.teardown();
    this.relay = undefined; this.lobby = undefined; this.remote = undefined; this.session = undefined; this.epoch = undefined;
    this.progress = undefined; this.submission = undefined; this.localReady = false; this.reportedReady = new Map();
    this.relayAway = new Set(); this.hostSuspended = false; this.presenceSequence = 0; this.hostPresenceSequence = 0;
    this.set({ ...this.initial(), stage: "idle", status: "Match closed." });
  }
}

export { HostUnavailable };
