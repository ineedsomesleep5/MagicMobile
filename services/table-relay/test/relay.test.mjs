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
let serverLog = "";

before(async () => {
  if (process.env.RELAY_URL) return;
  // test/strict-storage.js is the relay with production's storage entry limit enforced locally.
  // Its own process group, so stopping it also stops wrangler and workerd under npx.
  server = spawn("npx", ["--yes", "wrangler@4", "dev", "test/strict-storage.js", "--local", "--port", String(port), "--ip", "127.0.0.1",
    "--persist-to", path.join(root, ".wrangler/test-state")],
    { cwd: root, stdio: ["ignore", "ignore", "pipe"], detached: true });
  server.stderr.on("data", (chunk) => { serverLog = (serverLog + chunk).slice(-4000); });
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    try { if ((await fetch(`${base}/health`)).ok) return; } catch { /* starting */ }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`wrangler dev did not start:\n${serverLog}`);
});

after(() => {
  if (!server) return;
  try { process.kill(-server.pid, "SIGTERM"); } catch { /* already stopped */ }
  server.stderr.destroy();
  server.unref();
});

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
    socket, closed, inbox,
    next(match = () => true, timeout = 5000) {
      const index = inbox.findIndex(match);
      if (index >= 0) return Promise.resolve(inbox.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const entry = { match, resolve };
        waiters.push(entry);
        setTimeout(() => { const i = waiters.indexOf(entry); if (i >= 0) { waiters.splice(i, 1); reject(new Error("timed out waiting for a frame")); } }, timeout);
      });
    },
    /** Every delivered packet up to and including the one whose text is `last`. */
    async messagesThrough(last, timeout = 30_000) {
      const frames = [];
      while (frames.at(-1)?.d !== last) frames.push(await this.next((frame) => frame.t === "msg", timeout));
      return frames;
    },
    send(value) { socket.send(JSON.stringify(value)); },
  };
}

async function createTable(seats = 2) {
  const response = await fetch(`${base}/v1/tables`, { method: "POST", body: JSON.stringify({ seats }) });
  assert.equal(response.status, 200);
  return response.json();
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** A host and `count` guests at a table, with every guest's connection dropped. */
async function tableWithAwayGuests(count = 1) {
  const { code, hostKey } = await createTable(count + 1);
  const host = connect(code, { key: hostKey, name: "Host" });
  const hostWelcome = await host.next((frame) => frame.t === "welcome");
  const guests = [];
  for (let n = 0; n < count; n++) {
    const guest = connect(code, { name: `Guest ${n + 1}` });
    const welcome = await guest.next((frame) => frame.t === "welcome");
    guests.push(welcome);
    await host.next((frame) => frame.t === "roster" && frame.peers.some((peer) => peer.id === welcome.you && peer.connected));
    guest.socket.close();
    await host.next((frame) => frame.t === "roster" && frame.peers.some((peer) => peer.id === welcome.you && !peer.connected));
  }
  return { code, host, hostWelcome, guests };
}

async function resume(code, welcome) {
  const phone = connect(code, { resume: welcome.token, name: "Back" });
  assert.equal((await phone.next((frame) => frame.t === "welcome")).you, welcome.you);
  return phone;
}

/** Packet text of exactly `size` characters in the apps' shape: sorted keys, so "type" comes last. */
function packetText(type, label, size) {
  const head = `{"epoch":"E","label":"${label}","pad":"`;
  const tail = `","type":"${type}"}`;
  return head + "x".repeat(size - head.length - tail.length) + tail;
}

function assertNoErrors(phone) {
  assert.deepEqual(phone.inbox.filter((frame) => frame.t === "error"), []);
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

test("three ~900 KB packets for an away phone all arrive, in order, when it returns", async () => {
  const { code, host, hostWelcome, guests: [guest] } = await tableWithAwayGuests(1);
  // Runs of emoji (surrogate pairs), in both alignments, cross the point where the relay splits a
  // held packet for storage, and make those packets two-byte strings in storage.
  const packets = [0, 524_200, 524_201].map((at, n) => {
    const text = packetText("state", `big-${n}`, 900_000);
    return at ? text.slice(0, at) + "\u{1F0A1}".repeat(64) + text.slice(at + 128) : text;
  });
  for (const d of packets) host.send({ t: "send", to: guest.you, d });
  await sleep(1000);
  assertNoErrors(host);

  const back = await resume(code, guest);
  host.send({ t: "send", to: guest.you, d: "live" });
  const delivered = await back.messagesThrough("live");
  assert.deepEqual(delivered.map((frame) => frame.d.length), [...packets.map((d) => d.length), 4]);
  packets.forEach((d, n) => {
    assert.equal(delivered[n].from, hostWelcome.you);
    assert.ok(delivered[n].d === d, `packet ${n} arrived changed`);
  });
  back.socket.close(); host.socket.close();
});

test("host answers older than the guests' 15 s request timeout are dropped; everything else arrives", async () => {
  const { code, host, guests: [first, second] } = await tableWithAwayGuests(2);
  const sendSplit = (to, text, id) => {
    const half = Math.floor(text.length / 2);
    host.send({ t: "send", to, d: text.slice(0, half), p: { id, i: 0, n: 2 } });
    host.send({ t: "send", to, d: text.slice(half), p: { id, i: 1, n: 2 } });
  };
  const kept = packetText("rollAdvance", "kept", 200);
  const splitKept = packetText("presence", "split-kept", 900);
  const staleReply = packetText("reply", "stale", 200);
  sendSplit(first.you, packetText("reply", "stale-split", 900), "stale-split");
  host.send({ t: "send", to: first.you, d: kept });
  sendSplit(first.you, splitKept, "split-kept");
  host.send({ t: "send", to: first.you, d: staleReply });
  // Replies fill the first guest's backlog to its 512-message cap.
  for (let n = 0; n < 512 - 6; n++) host.send({ t: "send", to: first.you, d: packetText("reply", `fill-${n}`, 120) });
  host.send({ t: "send", to: second.you, d: staleReply });
  host.send({ t: "send", to: second.you, d: kept });
  await sleep(16_000);

  // The stale answers make room for a new one in the full backlog.
  const fresh = packetText("reply", "fresh", 200);
  host.send({ t: "send", to: first.you, d: fresh });
  await sleep(500);
  assertNoErrors(host);

  const firstBack = await resume(code, first);
  host.send({ t: "send", to: first.you, d: "live" });
  const firstGot = await firstBack.messagesThrough("live");
  const half = Math.floor(splitKept.length / 2);
  assert.deepEqual(firstGot.map((frame) => [frame.d, frame.p?.i]),
    [[kept, undefined], [splitKept.slice(0, half), 0], [splitKept.slice(half), 1], [fresh, undefined], ["live", undefined]]);

  // The second guest's backlog was never touched again: its stale answer is dropped on return.
  const secondBack = await resume(code, second);
  host.send({ t: "send", to: second.you, d: "live" });
  assert.deepEqual((await secondBack.messagesThrough("live")).map((frame) => frame.d), [kept, "live"]);
  firstBack.socket.close(); secondBack.socket.close(); host.socket.close();
});

test("a full backlog sends the sender peer_backlog and keeps what it accepted", async () => {
  // Size: eight ~900 KB packets fit within 8,000,000 characters; the ninth does not.
  {
    const { code, host, guests: [guest] } = await tableWithAwayGuests(1);
    const packets = Array.from({ length: 9 }, (_, n) => packetText("state", `size-${n}`, 900_000));
    for (const d of packets.slice(0, 8)) host.send({ t: "send", to: guest.you, d });
    await sleep(1500);
    assertNoErrors(host);
    host.send({ t: "send", to: guest.you, d: packets[8] });
    assert.equal((await host.next((frame) => frame.t === "error", 10_000)).error, "peer_backlog");

    const back = await resume(code, guest);
    host.send({ t: "send", to: guest.you, d: "live" });
    const delivered = await back.messagesThrough("live");
    assert.equal(delivered.length, 9);
    packets.slice(0, 8).forEach((d, n) => assert.ok(delivered[n].d === d, `packet ${n} arrived changed`));
    back.socket.close(); host.socket.close();
  }
  // Count: 512 packets fit; the 513th does not.
  {
    const { code, host, guests: [guest] } = await tableWithAwayGuests(1);
    for (let n = 0; n < 512; n++) host.send({ t: "send", to: guest.you, d: `count-${n}` });
    await sleep(1000);
    assertNoErrors(host);
    host.send({ t: "send", to: guest.you, d: "count-512" });
    assert.equal((await host.next((frame) => frame.t === "error", 10_000)).error, "peer_backlog");

    const back = await resume(code, guest);
    host.send({ t: "send", to: guest.you, d: "live" });
    assert.deepEqual((await back.messagesThrough("live")).map((frame) => frame.d),
      [...Array.from({ length: 512 }, (_, n) => `count-${n}`), "live"]);
    back.socket.close(); host.socket.close();
  }
});
