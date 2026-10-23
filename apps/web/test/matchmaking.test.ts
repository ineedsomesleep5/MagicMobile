/**
 * Friend challenges and the ranked queue against fake services and a fake clock (iOS FriendChallengeTests and
 * RankedMatchmakerTests' cases: answers, expiry, a late accept, AI fallback, the guest's wait for the table code).
 */
import { describe, expect, it } from "vitest";
import type { FriendChallenge, FriendChallengeService, RankedQueueService, RankedTicket } from "../src/core/account";
import { decodeChallenge, decodeTicket, FriendChallengeCoordinator, FriendChallengeRules, RankedMatchmaker } from "../src/core/matchmaking";

const ID = "11111111-2222-4333-8444-555555555555";
const MATCH = "99999999-2222-4333-8444-555555555555";

/** A clock that only moves when the code under test sleeps. */
function fakeTime() {
  let now = 1_800_000_000_000;
  return { clock: () => now, sleep: async (seconds: number) => { now += seconds * 1000; } };
}

function challenges(statuses: string[], cancelTo = "cancelled") {
  const calls: string[] = [];
  const at = (status: string): FriendChallenge => ({ id: ID, mode: "quick", status, ...(status === "accepted" ? { tableCode: "ABC234" } : {}) });
  let index = 0;
  const service: FriendChallengeService = {
    send: async () => { calls.push("send"); return at("pending"); },
    status: async () => { calls.push("status"); return at(statuses[Math.min(index++, statuses.length - 1)]); },
    cancel: async () => { calls.push("cancel"); return at(cancelTo); },
    incoming: async () => [at("pending"), { ...at("pending"), id: "22222222-2222-4333-8444-555555555555" }],
    accept: async () => at("accepted"),
    decline: async () => { calls.push("decline"); },
  };
  return { service, calls };
}

describe("FriendChallengeCoordinator", () => {
  it("waits for an accept and hands back the table", async () => {
    const time = fakeTime();
    const { service } = challenges(["pending", "accepted"]);
    const coordinator = new FriendChallengeCoordinator(service, time.sleep, time.clock);
    const answer = await coordinator.challenge("Friend", "quick", "p", 0, "ABC234");
    expect(answer).toEqual({ kind: "accepted", challenge: expect.objectContaining({ status: "accepted", tableCode: "ABC234" }) });
    expect(coordinator.isWaiting).toBe(false);
  });

  it("reads declined, and expires after the server's two minutes, cancelling on the way out", async () => {
    const declined = await new FriendChallengeCoordinator(challenges(["declined"]).service, fakeTime().sleep).challenge("F", "quick", "p", 0, "C");
    expect(declined).toEqual({ kind: "declined" });
    const time = fakeTime();
    const fake = challenges(["pending"]);
    const expired = await new FriendChallengeCoordinator(fake.service, time.sleep, time.clock).challenge("F", "quick", "p", 0, "C");
    expect(expired).toEqual({ kind: "expired" });
    expect(fake.calls.at(-1)).toBe("cancel");
  });

  it("keeps an accept that arrived while cancelling", async () => {
    const time = fakeTime();
    const coordinator = new FriendChallengeCoordinator(challenges(["pending"], "accepted").service, time.sleep, time.clock);
    const pending = coordinator.challenge("F", "quick", "p", 0, "C");
    coordinator.cancelOutgoing();
    expect((await pending).kind).toBe("accepted");
  });

  it("lists incoming challenges once, and not again after an answer", async () => {
    const { service, calls } = challenges(["pending"]);
    const coordinator = new FriendChallengeCoordinator(service, fakeTime().sleep);
    await coordinator.refreshIncoming();
    expect(coordinator.incoming).toHaveLength(2);
    await coordinator.decline(coordinator.incoming[0]);
    await coordinator.refreshIncoming();
    expect(coordinator.incoming.map((c) => c.id)).toEqual(["22222222-2222-4333-8444-555555555555"]);
    expect(calls).toContain("decline");
  });

  it("ranks friends of the same tier only, and words the server's refusals", () => {
    expect(FriendChallengeRules.mayRank(0, undefined)).toBe(true);
    expect(FriendChallengeRules.mayRank(4, 0)).toBe(false);
    expect(FriendChallengeRules.message("rank_mismatch")).toBe("Ranked challenges need the same tier.");
    expect(decodeChallenge({ id: ID, mode: "ranked", status: "accepted", matchId: MATCH, challengerStep: 3 }))
      .toEqual({ id: ID, mode: "ranked", status: "accepted", matchId: MATCH, challengerStep: 3 });
    expect(decodeChallenge({ id: "nope", mode: "quick", status: "pending" })).toBeUndefined();
  });
});

function queue(tickets: RankedTicket[], cancelTo: RankedTicket = { status: "cancelled" }) {
  const reports: string[] = [];
  let index = 0;
  const service: RankedQueueService = {
    enqueue: async () => ({ status: "searching", ticket: ID }),
    poll: async () => tickets[Math.min(index++, tickets.length - 1)],
    cancel: async () => cancelTo,
    setTable: async () => {},
    report: async (match, outcome) => { reports.push(`${match}:${outcome}`); },
  };
  return { service, reports };
}

describe("RankedMatchmaker", () => {
  it("pairs as host at once, or as guest after the host's table code arrives", async () => {
    const host = await new RankedMatchmaker(queue([{ status: "matched", ticket: ID, matchId: MATCH, role: "host" }]).service, fakeTime().sleep).search("p", 0, 2);
    expect(host).toEqual({ kind: "human", ticket: expect.objectContaining({ role: "host" }) });
    const guestQueue = queue([{ status: "matched", ticket: ID, matchId: MATCH, role: "guest" }, { status: "matched", ticket: ID, matchId: MATCH, role: "guest", tableCode: "XYZ789" }]);
    const guest = await new RankedMatchmaker(guestQueue.service, fakeTime().sleep).search("p", 0, 2);
    expect(guest).toEqual({ kind: "human", ticket: expect.objectContaining({ tableCode: "XYZ789" }) });
  });

  it("falls back to the AI after 40 seconds, and after 30 seconds without a table code", async () => {
    const time = fakeTime();
    const searching = await new RankedMatchmaker(queue([{ status: "searching", ticket: ID }]).service, time.sleep, time.clock).search("p", 0, 2);
    expect(searching).toEqual({ kind: "ai" });
    const later = fakeTime();
    const noCode = await new RankedMatchmaker(queue([{ status: "matched", ticket: ID, matchId: MATCH, role: "guest" }]).service, later.sleep, later.clock).search("p", 0, 2);
    expect(noCode).toEqual({ kind: "ai" });
  });

  it("a match made while the player cancels is reported lost, so the other side isn't left waiting", async () => {
    const time = fakeTime();
    const fake = queue([{ status: "searching", ticket: ID }], { status: "matched", ticket: ID, matchId: MATCH, role: "guest" });
    const matchmaker = new RankedMatchmaker(fake.service, time.sleep, time.clock);
    const pending = matchmaker.search("p", 0, 2);
    matchmaker.cancel();
    expect(await pending).toEqual({ kind: "cancelled" });
    expect(fake.reports).toEqual([`${MATCH}:loss`]);
    expect(matchmaker.isSearching).toBe(false);
  });

  it("without a profile every search is an AI game, and tickets decode as the server sends them", async () => {
    expect(await new RankedMatchmaker(undefined).search("p", 0, 2)).toEqual({ kind: "ai" });
    expect(decodeTicket({ status: "matched", ticket: ID, matchId: MATCH, role: "host", opponent: "Ana", opponentStep: 5 }))
      .toEqual({ status: "matched", ticket: ID, matchId: MATCH, role: "host", opponent: "Ana", opponentStep: 5 });
  });
});
