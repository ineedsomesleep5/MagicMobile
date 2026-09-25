// MagicMobile table relay (Cloudflare Worker + one Durable Object per table).
//
// Phones at one table exchange the same packets they send over Game Center. The relay
// assigns every connection its peer ID and stamps each delivered message with the
// sender's ID, so a phone can trust who sent a packet the way GKMatch lets it trust a
// GKPlayer. It stores nothing but the short-lived table roster and messages waiting
// for a phone that briefly dropped its connection.

import { DurableObject } from "cloudflare:workers";

const PROTOCOL = 1;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_PATTERN = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/;
const MAX_FRAME_CHARS = 1_000_000;
const MAX_QUEUE_MESSAGES = 512;
const MAX_QUEUE_CHARS = 8_000_000;
/** A phone that loses its connection keeps its seat this long. */
const RESUME_GRACE_MS = 90_000;
/** An unopened or abandoned table closes after this long. */
const IDLE_MS = 30 * 60_000;
const NAME_LIMIT = 40;

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function randomToken(bytes = 18) {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomCode() {
  const data = crypto.getRandomValues(new Uint8Array(6));
  return Array.from(data, (byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

/** Table names are shown to other players: trim, drop control characters, bound the length. */
function cleanName(raw) {
  const name = String(raw ?? "").replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g, "").trim();
  return Array.from(name).slice(0, NAME_LIMIT).join("") || "Player";
}

function validPart(part) {
  if (part === undefined) return undefined;
  if (!part || typeof part !== "object") return null;
  const { id, i, n } = part;
  if (typeof id !== "string" || id.length === 0 || id.length > 64) return null;
  if (!Number.isInteger(n) || n < 1 || n > 64 || !Number.isInteger(i) || i < 0 || i >= n) return null;
  return { id, i, n };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === "/health") {
      return json({ ok: true, service: "magicmobile-table-relay", protocol: PROTOCOL });
    }
    if (url.pathname === "/v1/tables") {
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
      const body = await request.json().catch(() => null);
      const seats = body?.seats;
      if (!Number.isInteger(seats) || seats < 2 || seats > 4) {
        return json({ error: "bad_request", message: "A table has 2–4 player seats." }, 400);
      }
      for (let attempt = 0; attempt < 8; attempt++) {
        const code = randomCode();
        const stub = env.TABLES.get(env.TABLES.idFromName(code));
        const response = await stub.fetch("https://table/claim", {
          method: "POST",
          body: JSON.stringify({ code, seats }),
        });
        if (response.status !== 409) return response;
      }
      return json({ error: "busy", message: "No table code is free right now. Try again." }, 503);
    }
    const match = url.pathname.match(/^\/v1\/tables\/([^/]+)\/socket$/);
    if (match) {
      const code = match[1].toUpperCase();
      if (!CODE_PATTERN.test(code)) return json({ error: "bad_code", message: "Table codes have six letters and numbers." }, 400);
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return json({ error: "upgrade_required" }, 426);
      }
      const stub = env.TABLES.get(env.TABLES.idFromName(code));
      return stub.fetch(request);
    }
    return json({ error: "not_found" }, 404);
  },
};

/**
 * One table. The roster lives in storage (the object may hibernate between messages);
 * each socket's tag is its peer ID, which is the only sender identity ever delivered.
 */
export class TableRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.table = undefined;
    // Keep-alive pings are answered without waking a hibernating table.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}'));
  }

  async load() {
    if (this.table === undefined) this.table = (await this.ctx.storage.get("table")) ?? null;
    return this.table;
  }

  async save() {
    await this.ctx.storage.put("table", this.table);
  }

  livePeers() {
    return (this.table?.peers ?? []).filter((peer) => !peer.gone);
  }

  roster() {
    return this.livePeers().map((peer) => ({ id: peer.id, name: peer.name, connected: peer.connected }));
  }

  send(socket, value) {
    try { socket.send(typeof value === "string" ? value : JSON.stringify(value)); } catch { /* A closing socket is replaced on resume. */ }
  }

  broadcast(value, except) {
    const text = JSON.stringify(value);
    for (const socket of this.ctx.getWebSockets()) {
      const id = socket.deserializeAttachment()?.id;
      if (id && id !== except) this.send(socket, text);
    }
  }

  broadcastRoster(except) {
    const peers = this.roster();
    this.broadcast({ t: "roster", peers, full: peers.length === this.table.seats }, except);
  }

  /** Accepts the socket so a phone can read why it was turned away, then closes it. */
  refuse(error, message) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();
    server.send(JSON.stringify({ t: "error", error, message }));
    server.close(4400, error);
    return new Response(null, { status: 101, webSocket: client });
  }

  async scheduleAlarm(at) {
    const current = await this.ctx.storage.getAlarm();
    if (current === null || at < current) await this.ctx.storage.setAlarm(at);
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/claim") {
      const { code, seats } = await request.json();
      if (await this.load()) return json({ error: "taken" }, 409);
      this.table = { code, seats, hostKey: randomToken(), createdAt: Date.now(), activeAt: Date.now(), next: 1, peers: [] };
      await this.save();
      await this.scheduleAlarm(Date.now() + IDLE_MS);
      return json({ code, hostKey: this.table.hostKey, seats, protocol: PROTOCOL });
    }

    const table = await this.load();
    if (!table || table.closed) return this.refuse("no_table", "No table uses that code. Check it with the host.");
    const name = cleanName(url.searchParams.get("name"));
    const resume = url.searchParams.get("resume");
    const key = url.searchParams.get("key");
    let peer;
    if (resume) {
      peer = table.peers.find((candidate) => candidate.token === resume && !candidate.gone);
      if (!peer) return this.refuse("resume_failed", "Your seat at this table has closed. Leave and start a new match.");
    } else if (key !== null) {
      if (key !== table.hostKey) return this.refuse("not_host", "Only the phone that created this table can host it.");
      if (table.peers.length > 0) return this.refuse("host_taken", "This table is already open.");
      peer = { id: `p1-${randomToken(6)}`, name, token: randomToken(), connected: false, gone: false, lastSeen: Date.now() };
      table.peers.push(peer);
      table.next = 2;
    } else {
      if (table.peers.length === 0) return this.refuse("host_missing", "The host has not opened this table yet.");
      if (table.peers[0].gone) return this.refuse("host_left", "The host left this table.");
      if (this.livePeers().length >= table.seats || table.next > table.seats) {
        return this.refuse("table_full", "This table is already full.");
      }
      peer = { id: `p${table.next}-${randomToken(6)}`, name, token: randomToken(), connected: false, gone: false, lastSeen: Date.now() };
      table.next += 1;
      table.peers.push(peer);
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    for (const old of this.ctx.getWebSockets(peer.id)) {
      try { old.close(4001, "replaced"); } catch { /* already closed */ }
    }
    this.ctx.acceptWebSocket(server, [peer.id]);
    server.serializeAttachment({ id: peer.id });
    peer.connected = true;
    peer.lastSeen = Date.now();
    table.activeAt = Date.now();
    await this.save();
    this.send(server, { t: "welcome", protocol: PROTOCOL, you: peer.id, token: peer.token, code: table.code, seats: table.seats,
      peers: this.roster(), full: this.livePeers().length === table.seats });
    const queued = (await this.ctx.storage.get(`q:${peer.id}`)) ?? [];
    for (const text of queued) this.send(server, text);
    if (queued.length) await this.ctx.storage.delete(`q:${peer.id}`);
    this.broadcastRoster(peer.id);
    return new Response(null, { status: 101, webSocket: client });
  }

  async enqueue(peerID, text) {
    const key = `q:${peerID}`;
    const queue = (await this.ctx.storage.get(key)) ?? [];
    const size = queue.reduce((total, item) => total + item.length, 0);
    if (queue.length >= MAX_QUEUE_MESSAGES || size + text.length > MAX_QUEUE_CHARS) return false;
    queue.push(text);
    await this.ctx.storage.put(key, queue);
    return true;
  }

  async webSocketMessage(socket, message) {
    const id = socket.deserializeAttachment()?.id;
    const table = await this.load();
    if (!id || !table) { socket.close(4404, "no_table"); return; }
    if (typeof message !== "string" || message.length > MAX_FRAME_CHARS) {
      this.send(socket, { t: "error", error: "too_large", message: "A message was too large for the relay." });
      return;
    }
    let frame;
    try { frame = JSON.parse(message); } catch { return; }
    if (frame?.t === "send") {
      const target = table.peers.find((peer) => peer.id === frame.to && !peer.gone);
      const part = validPart(frame.p);
      if (!target || target.id === id || typeof frame.d !== "string" || part === null) return;
      const out = { t: "msg", from: id, d: frame.d };
      if (part) out.p = part;
      const text = JSON.stringify(out);
      const sockets = this.ctx.getWebSockets(target.id);
      if (sockets.length > 0) {
        for (const destination of sockets) this.send(destination, text);
      } else if (!(await this.enqueue(target.id, text))) {
        this.send(socket, { t: "error", error: "peer_backlog", message: "Another player has been away too long." });
      }
    } else if (frame?.t === "bye") {
      const peer = table.peers.find((candidate) => candidate.id === id);
      if (peer && !peer.gone) {
        peer.gone = true; peer.connected = false;
        await this.ctx.storage.delete(`q:${peer.id}`);
        await this.save();
        this.broadcast({ t: "gone", id: peer.id }, id);
        this.broadcastRoster(id);
      }
      try { socket.close(1000, "bye"); } catch { /* closed */ }
      await this.closeIfEmpty();
    }
  }

  async webSocketClose(socket, code) {
    await this.disconnected(socket);
  }

  async webSocketError(socket) {
    await this.disconnected(socket);
  }

  async disconnected(socket) {
    const id = socket.deserializeAttachment()?.id;
    const table = await this.load();
    if (!id || !table) return;
    const peer = table.peers.find((candidate) => candidate.id === id);
    if (!peer || peer.gone) return;
    const stillOpen = this.ctx.getWebSockets(id).some((other) => other !== socket);
    if (stillOpen) return;
    peer.connected = false;
    peer.lastSeen = Date.now();
    table.activeAt = Date.now();
    await this.save();
    this.broadcastRoster(id);
    await this.scheduleAlarm(Date.now() + RESUME_GRACE_MS);
  }

  async closeIfEmpty() {
    if (this.livePeers().length === 0 && this.ctx.getWebSockets().length === 0) {
      await this.ctx.storage.deleteAll();
      this.table = null;
    }
  }

  async alarm() {
    const table = await this.load();
    if (!table) return;
    const now = Date.now();
    let changed = false;
    for (const peer of table.peers) {
      if (!peer.gone && !peer.connected && this.ctx.getWebSockets(peer.id).length === 0 && now - peer.lastSeen >= RESUME_GRACE_MS) {
        peer.gone = true;
        changed = true;
        await this.ctx.storage.delete(`q:${peer.id}`);
        this.broadcast({ t: "gone", id: peer.id }, peer.id);
      }
    }
    if (changed) { await this.save(); this.broadcastRoster(); }
    const sockets = this.ctx.getWebSockets().length;
    if (sockets === 0 && (this.livePeers().length === 0 || now - table.activeAt >= IDLE_MS)) {
      for (const peer of table.peers) await this.ctx.storage.delete(`q:${peer.id}`);
      await this.ctx.storage.deleteAll();
      this.table = null;
      return;
    }
    const waiting = this.livePeers().filter((peer) => !peer.connected).map((peer) => peer.lastSeen + RESUME_GRACE_MS);
    const next = Math.min(now + IDLE_MS, ...waiting.map((at) => Math.max(at, now + 1000)));
    await this.ctx.storage.setAlarm(next);
  }
}
