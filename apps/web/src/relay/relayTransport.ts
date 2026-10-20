/**
 * The cross-play relay (services/table-relay): a browser port of RelayTransport.kt / RelayTransport.swift.
 * The relay assigns this browser's peer ID and stamps every delivered packet with its sender's ID;
 * that is the only sender identity this transport ever reports.
 */
import { arr, bool, EngineError, get, int, isObject, type J, newUuid, str } from "../core/json";

export interface RelayPeer { id: string; name: string; connected: boolean }

export const RelayWire = {
  /** Offered on every table socket; the relay answers with it. */
  SOCKET_PROTOCOL: "magicmobile.1",
  /** The resume token travels as a subprotocol, so it never appears in the socket URL. */
  socketProtocols: (resume?: string): string[] => [RelayWire.SOCKET_PROTOCOL, ...(resume ? [`magicmobile.resume.${resume}`] : [])],
  /** Frames stay well under the relay's 1,000,000-character limit after JSON escaping. */
  PART_CHARACTERS: 400_000,
  MAX_PARTS: 64,
};

/** The deployed relay; `?relay=http://127.0.0.1:8787` points a dev build at `wrangler dev`. */
export const defaultRelayURL = (): string => {
  const override = typeof location === "undefined" ? null : new URLSearchParams(location.search).get("relay");
  const env = (import.meta as { env?: Record<string, string | undefined> }).env?.VITE_RELAY_URL;
  return (override ?? env ?? "https://magicmobile-relay.calebjfeliciano.workers.dev").replace(/\/+$/, "");
};

/** Splits a packet into relay parts without ever splitting a UTF-16 surrogate pair (iOS rejects half of one). */
export const splitPacket = (text: string, partCharacters = RelayWire.PART_CHARACTERS): string[] => {
  if (text.length <= partCharacters) return [text];
  const pieces: string[] = [];
  let start = 0;
  while (start < text.length) {
    let end = Math.min(text.length, start + partCharacters);
    const code = text.charCodeAt(end - 1);
    if (end < text.length && code >= 0xd800 && code <= 0xdbff) end -= 1;
    pieces.push(text.slice(start, end));
    start = end;
  }
  if (pieces.length > RelayWire.MAX_PARTS) throw EngineError.messageTooLarge();
  return pieces;
};

/**
 * Reassembles split packets per authenticated sender and message ID (the relay's `p` field). Bounded
 * like PacketAssembler: at most 64 parts, four open messages per sender, and stale assemblies expire.
 */
export class RelayPartAssembler {
  private parts = new Map<string, { pieces: (string | undefined)[]; started: number }>();

  receive(from: string, data: string, part: J | undefined, now = Date.now()): string | undefined {
    if (part === undefined || part === null) return data;
    const id = str(get(part, "id")); const index = int(get(part, "i")); const count = int(get(part, "n"));
    if (id === undefined || index === undefined || count === undefined || count < 1 || count > RelayWire.MAX_PARTS || index < 0 || index >= count) return undefined;
    for (const [key, value] of this.parts) if (now - value.started > 60_000) this.parts.delete(key);
    const key = `${from}/${id}`;
    let entry = this.parts.get(key);
    if (!entry) {
      if ([...this.parts.keys()].filter((k) => k.startsWith(`${from}/`)).length >= 4) return undefined;
      entry = { pieces: new Array(count).fill(undefined), started: now };
      this.parts.set(key, entry);
    }
    if (entry.pieces.length !== count) { this.parts.delete(key); return undefined; }
    entry.pieces[index] = data;
    if (!entry.pieces.every((piece) => piece !== undefined)) return undefined;
    this.parts.delete(key);
    return entry.pieces.join("");
  }

  drop(from: string) { for (const key of [...this.parts.keys()]) if (key.startsWith(`${from}/`)) this.parts.delete(key); }
}

export interface RelayEvents {
  onPacket?: (text: string, from: string) => void;
  onRoster?: (peers: RelayPeer[], full: boolean) => void;
  /** A player left for good (or never came back): the match cannot continue. */
  onDisconnect?: (peer: string) => void;
  onError?: (message: string) => void;
  /** This browser lost the relay and is trying to reclaim its seat. */
  onConnectionChanged?: (connected: boolean) => void;
}

export class RelayTransport {
  events: RelayEvents = {};
  localPeerID?: string;
  code?: string;
  peers: RelayPeer[] = [];
  isFull = false;
  /** Human seats at this table, from the relay's welcome. */
  seats = 0;

  private socket?: WebSocket;
  private name = "Player";
  private token?: string;
  private closed = false;
  private generation = 0;
  private reconnectAttempts = 0;
  private assembler = new RelayPartAssembler();
  /** Frames written while the socket reconnects; sent in order once the relay returns the seat. */
  private outbox: string[] = [];
  private outboxChars = 0;
  private welcomed = false;
  private pingTimer?: ReturnType<typeof setInterval>;
  private reconnectTimer?: ReturnType<typeof setTimeout>;

  constructor(private readonly baseURL: string = defaultRelayURL(), private readonly makeSocket = (url: string, protocols: string[]) => new WebSocket(url, protocols)) {}

  /** Joins a table as a guest: the relay gives this browser the next free seat. */
  connect(code: string, name: string) {
    this.code = code.toUpperCase(); this.name = name;
    this.open();
  }

  private open(resume?: string) {
    const code = this.code;
    if (!code) return;
    const current = ++this.generation;
    const url = `${this.baseURL.replace(/^http/, "ws")}/v1/tables/${code}/socket?name=${encodeURIComponent(this.name)}`;
    let socket: WebSocket;
    try {
      socket = this.makeSocket(url, RelayWire.socketProtocols(resume));
    } catch {
      this.dropped(undefined);
      return;
    }
    this.socket = socket;
    socket.onmessage = (event) => { if (current === this.generation && !this.closed && typeof event.data === "string") this.receive(event.data); };
    socket.onclose = (event) => { if (current === this.generation) this.dropped(event.code); };
    socket.onerror = () => { /* onclose follows */ };
    clearInterval(this.pingTimer);
    // The relay answers a ping without waking the table; it keeps proxies from closing a quiet socket.
    this.pingTimer = setInterval(() => {
      if (current === this.generation && !this.closed && this.welcomed) this.socket?.send("{\"t\":\"ping\"}");
    }, 20_000);
  }

  private receive(text: string) {
    let frame: J;
    try { frame = JSON.parse(text) as J; } catch { return; }
    if (!isObject(frame)) return;
    switch (str(frame.t)) {
      case "welcome": {
        this.welcomed = true;
        this.localPeerID = str(frame.you); this.token = str(frame.token);
        this.seats = int(frame.seats) ?? this.seats;
        this.reconnectAttempts = 0;
        const queued = this.outbox;
        this.outbox = []; this.outboxChars = 0;
        queued.forEach((item) => this.socket?.send(item));
        this.updateRoster(frame.peers, bool(frame.full) === true);
        this.events.onConnectionChanged?.(true);
        break;
      }
      case "roster": this.updateRoster(frame.peers, bool(frame.full) === true); break;
      case "msg": {
        const from = str(frame.from); const data = str(frame.d);
        if (from === undefined || data === undefined) return;
        const packet = this.assembler.receive(from, data, frame.p);
        if (packet !== undefined) this.events.onPacket?.(packet, from);
        break;
      }
      case "gone": {
        const id = str(frame.id);
        if (id !== undefined) { this.assembler.drop(id); this.events.onDisconnect?.(id); }
        break;
      }
      case "error":
        this.closed = true;
        this.events.onError?.(str(frame.message) ?? "The table service closed the connection.");
        break;
      default: break; // pong and frame types this client does not know
    }
  }

  private updateRoster(value: J | undefined, full: boolean) {
    const rows = arr(value);
    if (rows) {
      this.peers = rows.flatMap((row) => {
        const id = str(get(row, "id"));
        return id === undefined ? [] : [{ id, name: str(get(row, "name")) ?? "Player", connected: bool(get(row, "connected")) === true }];
      });
    }
    this.isFull = full;
    this.events.onRoster?.(this.peers, full);
  }

  /** A dropped socket reclaims the seat with its resume token, with backoff, for about a minute. */
  private dropped(code: number | undefined) {
    this.socket = undefined; this.welcomed = false;
    clearInterval(this.pingTimer);
    if (this.closed) return;
    const resume = this.token;
    if (resume === undefined || code === 4400) { this.closed = true; this.events.onError?.("Could not connect to the table."); return; }
    this.events.onConnectionChanged?.(false);
    if (this.reconnectAttempts >= 12) { this.closed = true; this.events.onError?.("Lost the connection to the table."); return; }
    const delay = Math.min(8_000, 500 * 2 ** Math.min(this.reconnectAttempts, 4));
    this.reconnectAttempts += 1;
    this.reconnectTimer = setTimeout(() => { if (!this.closed && this.socket === undefined) this.open(resume); }, delay);
  }

  send(text: string, peer: string) {
    if (this.closed) throw EngineError.invalid("The table connection is closed.");
    const pieces = splitPacket(text);
    if (pieces.length === 1) { this.write(JSON.stringify({ t: "send", to: peer, d: text })); return; }
    const id = newUuid();
    pieces.forEach((piece, index) => this.write(JSON.stringify({ t: "send", to: peer, d: piece, p: { id, i: index, n: pieces.length } })));
  }

  /** Sends now, or holds the frame until the relay returns this browser's seat. */
  private write(frame: string) {
    if (this.socket && this.welcomed && this.socket.readyState === 1) { this.socket.send(frame); return; }
    if (this.outbox.length >= 512 || this.outboxChars + frame.length > 8_000_000) throw EngineError.invalid("Lost the connection to the table.");
    this.outbox.push(frame); this.outboxChars += frame.length;
  }

  /** Leaves the table for good; the other players are told at once. */
  disconnect() {
    if (this.closed && this.socket === undefined) return;
    this.closed = true;
    this.generation += 1;
    clearInterval(this.pingTimer); clearTimeout(this.reconnectTimer);
    const socket = this.socket;
    if (socket) {
      try { if (socket.readyState === 1) socket.send("{\"t\":\"bye\"}"); socket.close(1000, "bye"); } catch { /* already gone */ }
    }
    this.socket = undefined; this.welcomed = false; this.outbox = []; this.outboxChars = 0;
    this.events = {};
  }
}

