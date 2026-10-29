/**
 * HostRouter (HostRouter.swift / HostRouter.kt): the Swift SafetyTests router cases and Android's HostRouterPrivacyTest.
 * A peer reaches the host's engine only as its own bound seat, with hello, poll, respond and concede.
 */
import { describe, expect, it } from "vitest";
import { EngineClient } from "../src/core/engineClient";
import { EngineError, EngineJson, type J, type JObject } from "../src/core/json";
import { HostRouter } from "../src/table/hostRouter";
import { type BuildIdentity, identityJSON } from "../src/table/lobby";

const identity: BuildIdentity = { upstreamCommit: "sha", catalogueHash: "hash", adapterVersion: "ondevice-0.1" };
const EPOCH = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0";
const pollValue: J = { matchId: "match", viewerId: "seat-2", revision: 3, phase: "running", resyncRequired: false, snapshot: null, prompt: null };

const setup = async (reply: J = pollValue) => {
  const calls: JObject[] = [];
  const engine = new EngineClient(async (text) => {
    calls.push(EngineJson.decode(text) as JObject);
    return EngineJson.encode({ protocol: 1, ok: true, result: reply });
  });
  const router = new HostRouter(engine, "match", identity, EPOCH);
  router.bind("peer", "seat-2");
  await router.handle({ epoch: EPOCH, sequence: 1, operation: "hello", payload: identityJSON(identity) }, "peer");
  return { router, calls };
};

const code = async (run: Promise<unknown>) => {
  try { await run; } catch (error) { return error instanceof EngineError ? error.code : "other"; }
  return "ok";
};

const answer: J = { requestId: "a8f5f167-f44f-4964-8f8e-7b1c3a4d5e6f", promptId: "prompt", promptRevision: 7, answer: true };

describe("host router", () => {
  it("polls as the peer's bound seat", async () => {
    const { router, calls } = await setup();
    await router.handle({ epoch: EPOCH, sequence: 2, operation: "poll", payload: { after: 0 } }, "peer");
    expect(calls.at(-1)).toMatchObject({ op: "poll", viewerId: "seat-2", matchId: "match", after: 0 });
  });

  it("answers hello with the seat and build", async () => {
    const engine = new EngineClient(async () => { throw new Error("engine reached"); });
    const router = new HostRouter(engine, "match", identity, EPOCH);
    router.bind("peer", "seat-2");
    expect(await router.handle({ epoch: EPOCH.toLowerCase(), sequence: 1, operation: "hello", payload: identityJSON(identity) }, "peer"))
      .toEqual({ seatId: "seat-2", build: identityJSON(identity) });
  });

  it("refuses a spoofed viewer, an unbound peer, replays, other epochs and other builds", async () => {
    const { router } = await setup();
    expect(await code(router.handle({ epoch: EPOCH, sequence: 2, operation: "poll", payload: { after: 0, viewerId: "host" } }, "peer"))).toBe("invalid_message");
    expect(await code(router.handle({ epoch: EPOCH, sequence: 3, operation: "poll", payload: null }, "intruder"))).toBe("unbound_peer");
    expect(await code(router.handle({ epoch: EPOCH, sequence: 1, operation: "hello", payload: identityJSON(identity) }, "peer"))).toBe("replayed");
    expect(await code(router.handle({ epoch: "11111111-2222-3333-4444-555555555555", sequence: 4, operation: "hello", payload: identityJSON(identity) }, "peer")))
      .toBe("incompatible_build");
    expect(await code(router.handle({ epoch: EPOCH, sequence: 5, operation: "hello", payload: {} }, "peer"))).toBe("incompatible_build");
  });

  it("needs hello before anything else", async () => {
    const router = new HostRouter(new EngineClient(async () => { throw new Error("engine reached"); }), "match", identity, EPOCH);
    router.bind("peer", "seat-2");
    expect(await code(router.handle({ epoch: EPOCH, sequence: 1, operation: "poll", payload: { after: 0 } }, "peer"))).toBe("incompatible_build");
  });

  it("never lets a peer reach administrative operations, diagnostics or the game record", async () => {
    // The game record shows every hand and library order (docs/PROTOCOL.md "Game record").
    for (const operation of ["destroy", "diagnostics", "clearDiagnostics", "record", "create", "shutdown"]) {
      const { router, calls } = await setup();
      expect(await code(router.handle({ epoch: EPOCH, sequence: 2, operation, payload: {} }, "peer")), operation).toBe("invalid_message");
      expect(calls, operation).toEqual([]);
    }
  });

  it("blocks answers while suspended and ignores stale suspension updates", async () => {
    const { router } = await setup({ queued: true });
    router.setSuspended(true);
    expect(await code(router.handle({ epoch: EPOCH, sequence: 2, operation: "respond", payload: {} }, "peer"))).toBe("host_suspended");
    router.setSuspended(false, 2);
    router.setSuspended(true, 1);
    expect(await code(router.handle({ epoch: EPOCH, sequence: 3, operation: "respond", payload: answer }, "peer"))).toBe("ok");
    router.setSuspended(true, 3);
    router.setSuspended(false, 2);
    expect(await code(router.handle({ epoch: EPOCH, sequence: 4, operation: "respond", payload: answer }, "peer"))).toBe("host_suspended");
  });

  it("lets a peer concede only its own seat, even while suspended", async () => {
    const { router, calls } = await setup({});
    router.setSuspended(true);
    await router.handle({ epoch: EPOCH, sequence: 2, operation: "concede", payload: {} }, "peer");
    expect(calls.at(-1)).toEqual({ protocol: 1, op: "concede", matchId: "match", viewerId: "seat-2" });
    expect(await code(router.handle({ epoch: EPOCH, sequence: 3, operation: "concede", payload: { viewerId: "host" } }, "peer"))).toBe("invalid_message");
    expect(await code(router.handle({ epoch: EPOCH, sequence: 4, operation: "concede", payload: {} }, "intruder"))).toBe("unbound_peer");
  });

  it("refuses a duplicate seat binding and a fourth guest", async () => {
    const { router } = await setup();
    expect(() => router.bind("other", "seat-2")).toThrow();
    expect(() => router.bind("peer", "seat-3")).toThrow();
    router.bind("b", "seat-3"); router.bind("c", "seat-4");
    expect(() => router.bind("d", "seat-5")).toThrow();
  });
});
