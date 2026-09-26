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

/** A socket with an inbox so tests can await specific frames; `protocols` are WebSocket subprotocols to offer. */
function connect(code, params, protocols) {
  const url = `${socketBase}/v1/tables/${code}/socket?${new URLSearchParams(params)}`;
  const socket = protocols ? new WebSocket(url, protocols) : new WebSocket(url);
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
        const timer = setTimeout(() => { const i = waiters.indexOf(entry); if (i >= 0) { waiters.splice(i, 1); reject(new Error("timed out waiting for a frame")); } }, timeout);
        const entry = { match, resolve: (frame) => { clearTimeout(timer); resolve(frame); } };
        waiters.push(entry);
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

/**
 * How a phone presents its host key or resume token: `query` is Android build 8's form, and
 * `subprotocol` the current apps' (offered beside "magicmobile.1"). Returns connect()'s arguments.
 */
const credentialForms = {
  query: (name, { key, resume } = {}) => [{ name, ...(key === undefined ? {} : { key }), ...(resume === undefined ? {} : { resume }) }],
  subprotocol: (name, { key, resume } = {}) => [{ name },
    ["magicmobile.1", ...(key === undefined ? [] : [`magicmobile.key.${key}`]), ...(resume === undefined ? [] : [`magicmobile.resume.${resume}`])]],
};

const random = (limit) => Math.floor(Math.random() * limit);
const localNetwork = `10.${random(256)}.${random(256)}`;
let callers = 0;
/**
 * The local relay trusts the caller address a request names (Cloudflare sets it on a deployed
 * relay), so each table gets its own caller and the creation limit never slows the other tests.
 */
const nextCaller = () => `${localNetwork}.${++callers % 256}`;

function postTable(seats, caller = nextCaller()) {
  return fetch(`${base}/v1/tables`, { method: "POST", headers: { "CF-Connecting-IP": caller }, body: JSON.stringify({ seats }) });
}

async function createTable(seats = 2) {
  let response = await postTable(seats);
  // A deployed relay sees one caller for every test, so waits out its creation limit.
  for (let retry = 0; response.status === 429 && process.env.RELAY_URL && retry < 3; retry++) {
    await sleep(Number(response.headers.get("retry-after") ?? 60) * 1000);
    response = await postTable(seats);
  }
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
  assert.equal((await postTable(9)).status, 400);
});

for (const form of ["query", "subprotocol"]) {
  test(`a host key and a resume token sent in the ${form} open the table and reclaim a seat`, async () => {
    const { code, hostKey } = await createTable(2);
    const open = (name, credential) => connect(code, ...credentialForms[form](name, credential));
    // A refusal names the subprotocol too; a WebSocket client that offered one fails a handshake without it.
    const impostor = open("Impostor", { key: "not-the-key" });
    assert.equal((await impostor.next((frame) => frame.t === "error")).error, "not_host");
    assert.equal((await impostor.closed).code, 4400);

    const host = open("Host", { key: hostKey });
    assert.match((await host.next((frame) => frame.t === "welcome")).you, /^p1-/);
    const guest = open("Guest");
    const guestWelcome = await guest.next((frame) => frame.t === "welcome");
    assert.match(guestWelcome.you, /^p2-/);
    const protocol = form === "subprotocol" ? "magicmobile.1" : "";
    assert.equal(host.socket.protocol, protocol);
    assert.equal(guest.socket.protocol, protocol);
    await host.next((frame) => frame.t === "roster" && frame.full);

    guest.socket.close();
    await host.next((frame) => frame.t === "roster" && frame.peers.some((peer) => peer.id === guestWelcome.you && !peer.connected));
    host.send({ t: "send", to: guestWelcome.you, d: "while-away" });
    await sleep(300);
    const back = open("Guest", { resume: guestWelcome.token });
    assert.equal((await back.next((frame) => frame.t === "welcome")).you, guestWelcome.you);
    assert.equal((await back.next((frame) => frame.t === "msg")).d, "while-away");
    assert.equal(back.socket.protocol, protocol);
    const late = open("Late", { resume: "not-a-token" });
    assert.equal((await late.next((frame) => frame.t === "error")).error, "resume_failed");
    back.socket.close(); host.socket.close();
  });
}

test("the host removes a joiner while the table fills: the joiner is told, its seat frees, others see a roster", async () => {
  const { code, hostKey } = await createTable(4);
  const host = connect(code, { key: hostKey, name: "Host" });
  const hostWelcome = await host.next((frame) => frame.t === "welcome");
  const stranger = connect(code, { name: "Stranger" });
  const strangerWelcome = await stranger.next((frame) => frame.t === "welcome");
  const friend = connect(code, { name: "Friend" });
  const friendWelcome = await friend.next((frame) => frame.t === "welcome");
  assert.match(strangerWelcome.you, /^p2-/);
  assert.match(friendWelcome.you, /^p3-/);
  await host.next((frame) => frame.t === "roster" && frame.peers.length === 3);

  // Only the host may remove. The relay handles one phone's frames in order, so the friend's
  // packet arriving means its remove was already ignored.
  friend.send({ t: "remove", id: strangerWelcome.you });
  friend.send({ t: "send", to: strangerWelcome.you, d: "still-here" });
  assert.equal((await stranger.next((frame) => frame.t === "msg")).d, "still-here");

  host.send({ t: "remove", id: strangerWelcome.you });
  const removed = await stranger.next((frame) => frame.t === "error");
  assert.deepEqual(removed, { t: "error", error: "removed", message: "The host removed you from this table." });
  const withoutStranger = (frame) => frame.t === "roster" && !frame.peers.some((peer) => peer.id === strangerWelcome.you);
  const hostRoster = await host.next(withoutStranger);
  assert.deepEqual(hostRoster.peers.map((peer) => peer.id), [hostWelcome.you, friendWelcome.you]);
  assert.equal(hostRoster.full, false);
  await friend.next(withoutStranger);

  // The removed phone cannot take its seat back; a newcomer gets the freed seat number.
  const retry = connect(code, { resume: strangerWelcome.token, name: "Stranger" });
  assert.equal((await retry.next((frame) => frame.t === "error")).error, "removed");
  const newcomer = connect(code, { name: "Newcomer" });
  const newcomerWelcome = await newcomer.next((frame) => frame.t === "welcome");
  assert.match(newcomerWelcome.you, /^p2-/);
  assert.notEqual(newcomerWelcome.you, strangerWelcome.you);
  // Sorted peer IDs still give seat order.
  assert.deepEqual(newcomerWelcome.peers.map((peer) => peer.id).sort(), [hostWelcome.you, newcomerWelcome.you, friendWelcome.you]);

  // Once the table is full every phone is in the match room, and the host can no longer remove anyone.
  const fourth = connect(code, { name: "Fourth" });
  assert.match((await fourth.next((frame) => frame.t === "welcome")).you, /^p4-/);
  await host.next((frame) => frame.t === "roster" && frame.full);
  host.send({ t: "remove", id: newcomerWelcome.you });
  host.send({ t: "send", to: newcomerWelcome.you, d: "after-full" });
  assert.equal((await newcomer.next((frame) => frame.t === "msg")).d, "after-full");
  for (const phone of [host, friend, newcomer, fourth]) {
    assertNoErrors(phone);
    assert.deepEqual(phone.inbox.filter((frame) => frame.t === "gone"), []);
  }
  for (const phone of [host, friend, newcomer, fourth]) phone.socket.close();
  // The relay closed the removed phone's socket with the code the apps treat as final. (The local
  // runtime completes that close slowly, so it is checked last.)
  assert.equal((await stranger.closed).code, 4400);
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
  // The relay handles one phone's frames in order, so this refusal means everything above is held.
  host.send({ t: "send", to: first.you, d: packetText("reply", "over", 120) });
  assert.equal((await host.next((frame) => frame.t === "error", 30_000)).error, "peer_backlog");
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
    assert.equal((await host.next((frame) => frame.t === "error", 30_000)).error, "peer_backlog");

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
    assert.equal((await host.next((frame) => frame.t === "error", 30_000)).error, "peer_backlog");

    const back = await resume(code, guest);
    host.send({ t: "send", to: guest.you, d: "live" });
    assert.deepEqual((await back.messagesThrough("live")).map((frame) => frame.d),
      [...Array.from({ length: 512 }, (_, n) => `count-${n}`), "live"]);
    back.socket.close(); host.socket.close();
  }
});

/**
 * Opens tables for `caller` until the relay refuses one. The local limit counts in windows aligned
 * to the clock, so a burst may straddle two of them: up to two windows' worth may open first.
 */
async function openUntilRefused(caller) {
  for (let n = 0; n <= 10; n++) {
    const response = await postTable(2, caller);
    if (response.status !== 200) return response;
    await response.body?.cancel();
  }
  assert.fail(`${caller} opened 11 tables in a row`);
}

test("each caller may open only a few tables a minute; the refusal is JSON the apps can show",
  { skip: process.env.RELAY_URL ? "a deployed relay sets the caller address itself" : false }, async () => {
    const refused = await openUntilRefused(`172.16.${random(256)}.${random(256)}`);
    assert.equal(refused.status, 429);
    assert.equal(refused.headers.get("retry-after"), "60");
    assert.deepEqual(await refused.json(),
      { error: "rate_limited", message: "You opened several tables in the last minute. Wait a minute, then try again." });
    // Another caller is not affected.
    assert.equal((await postTable(2)).status, 200);

    // An IPv6 caller counts by its /64 network, however it writes its address. A window may roll
    // over between the two requests, so the pair is tried twice.
    let sibling;
    for (let attempt = 0; attempt < 2 && sibling?.status !== 429; attempt++) {
      const network = `2001:db8:${random(0x10000).toString(16)}:${random(0x10000).toString(16)}`;
      assert.equal((await openUntilRefused(`${network}::1`)).status, 429);
      sibling = await postTable(2, `${network}:1234:5678:9abc:def0`.toUpperCase());
    }
    assert.equal(sibling.status, 429);
  });
