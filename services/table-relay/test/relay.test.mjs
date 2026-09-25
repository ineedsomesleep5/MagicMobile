// Integration tests for the table relay against a local `wrangler dev` (no Cloudflare account used).
// Run: node --test services/table-relay/test/relay.test.mjs
// Against a deployed relay: RELAY_URL=https://… node --test services/table-relay/test/relay.test.mjs
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const port = 8900 + Math.floor(Math.random() * 90);
const base = process.env.RELAY_URL?.replace(/\/$/, "") ?? `http://127.0.0.1:${port}`;
const socketBase = base.replace(/^http/, "ws");
let server;

before(async () => {
  if (process.env.RELAY_URL) return;
  server = spawn("npx", ["--yes", "wrangler", "dev", "--local", "--port", String(port), "--ip", "127.0.0.1", "--persist-to", path.join(root, ".wrangler/test-state")],
    { cwd: root, stdio: ["ignore", "pipe", "pipe"] });
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    try { if ((await fetch(`${base}/health`)).ok) return; } catch { /* starting */ }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error("wrangler dev did not start");
});

after(() => server?.kill("SIGTERM"));

/** A socket with an inbox so tests can await specific frames. */
function connect(code, params) {
  const url = `${socketBase}/v1/tables/${code}/socket?${new URLSearchParams(params)}`;
  const socket = new WebSocket(url);
  const inbox = [];
  const waiters = [];
  socket.addEventListener("message", (event) => {
    const frame = JSON.parse(event.data);
    const waiter = waiters.findIndex((entry) => entry.match(frame));
    if (waiter >= 0) waiters.splice(waiter, 1)[0].resolve(frame);
    else inbox.push(frame);
  });
  const closed = new Promise((resolve) => socket.addEventListener("close", (event) => resolve(event)));
  return {
    socket, closed,
    next(match = () => true, timeout = 5000) {
      const index = inbox.findIndex(match);
      if (index >= 0) return Promise.resolve(inbox.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const entry = { match, resolve };
        waiters.push(entry);
        setTimeout(() => { const i = waiters.indexOf(entry); if (i >= 0) { waiters.splice(i, 1); reject(new Error("timed out waiting for a frame")); } }, timeout);
      });
    },
    send(value) { socket.send(JSON.stringify(value)); },
  };
}

async function createTable(seats = 2) {
  const response = await fetch(`${base}/v1/tables`, { method: "POST", body: JSON.stringify({ seats }) });
  assert.equal(response.status, 200);
  return response.json();
}

test("a host opens a table, a guest joins, and messages carry the relay's sender ID", async () => {
  const { code, hostKey } = await createTable(2);
  assert.match(code, /^[A-Z2-9]{6}$/);
  const host = connect(code, { key: hostKey, name: "Caleb" });
  const welcome = await host.next((frame) => frame.t === "welcome");
  assert.match(welcome.you, /^p1-/);
  assert.equal(welcome.full, false);

  const guest = connect(code, { name: "Guest\u0007 Player" });
  const guestWelcome = await guest.next((frame) => frame.t === "welcome");
  assert.match(guestWelcome.you, /^p2-/);
  assert.equal(guestWelcome.full, true);
  assert.deepEqual(guestWelcome.peers.map((peer) => peer.name), ["Caleb", "Guest Player"]);
  const roster = await host.next((frame) => frame.t === "roster");
  assert.equal(roster.full, true);

  // A forged "from" is ignored: the relay stamps the authenticated sender.
  guest.send({ t: "send", to: welcome.you, d: "{\"type\":\"submission\"}", from: welcome.you });
  const delivered = await host.next((frame) => frame.t === "msg");
  assert.equal(delivered.from, guestWelcome.you);
  assert.equal(delivered.d, "{\"type\":\"submission\"}");

  // Split packets keep their part header.
  host.send({ t: "send", to: guestWelcome.you, d: "abc", p: { id: "packet-1", i: 0, n: 2 } });
  const part = await guest.next((frame) => frame.t === "msg");
  assert.deepEqual(part.p, { id: "packet-1", i: 0, n: 2 });

  const third = connect(code, { name: "Late" });
  const refused = await third.next((frame) => frame.t === "error");
  assert.equal(refused.error, "table_full");
  host.socket.close(); guest.socket.close();
});

test("a dropped phone resumes its seat and receives what it missed", async () => {
  const { code, hostKey } = await createTable(2);
  const host = connect(code, { key: hostKey, name: "Host" });
  const hostWelcome = await host.next((frame) => frame.t === "welcome");
  const guest = connect(code, { name: "Guest" });
  const guestWelcome = await guest.next((frame) => frame.t === "welcome");
  await host.next((frame) => frame.t === "roster" && frame.full);

  guest.socket.close();
  const away = await host.next((frame) => frame.t === "roster" && frame.peers.some((peer) => peer.id === guestWelcome.you && !peer.connected));
  assert.ok(away);
  host.send({ t: "send", to: guestWelcome.you, d: "while-away-1" });
  host.send({ t: "send", to: guestWelcome.you, d: "while-away-2" });
  await new Promise((resolve) => setTimeout(resolve, 300));

  const resumed = connect(code, { resume: guestWelcome.token, name: "Guest" });
  const again = await resumed.next((frame) => frame.t === "welcome");
  assert.equal(again.you, guestWelcome.you);
  assert.equal((await resumed.next((frame) => frame.t === "msg")).d, "while-away-1");
  assert.equal((await resumed.next((frame) => frame.t === "msg")).d, "while-away-2");

  resumed.send({ t: "bye" });
  const gone = await host.next((frame) => frame.t === "gone");
  assert.equal(gone.id, guestWelcome.you);
  assert.equal(hostWelcome.you.startsWith("p1-"), true);
  host.socket.close();
});

test("codes are checked and only the creator can host", async () => {
  assert.equal((await fetch(`${base}/v1/tables/abc/socket`)).status, 400);
  const missing = connect("ZZZZZZ", { name: "Nobody" });
  assert.equal((await missing.next((frame) => frame.t === "error")).error, "no_table");
  const { code } = await createTable(3);
  const early = connect(code, { name: "Early" });
  assert.equal((await early.next((frame) => frame.t === "error")).error, "host_missing");
  const impostor = connect(code, { key: "not-the-key", name: "Impostor" });
  assert.equal((await impostor.next((frame) => frame.t === "error")).error, "not_host");
  assert.equal((await fetch(`${base}/v1/tables`, { method: "POST", body: JSON.stringify({ seats: 9 }) })).status, 400);
});
