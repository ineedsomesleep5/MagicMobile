/** Combat on the Arena board with the real attacker prompt (fixture 2p-attackers): All Attack's queue, counts, arrows. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { combatPhase } from "../src/core/arenaBoard";
import { MatchPoll } from "../src/core/engineClient";
import type { GameSnapshot } from "../src/core/models";
import { OnDeviceSnapshotAdapter } from "../src/core/snapshotAdapter";
import { allAttackTargets, AttackQueue, combatArrows, declaredCount, finishTitle } from "../src/ui/arena/combat";

const fixture = (name: string): GameSnapshot => {
  const poll = new MatchPoll(JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/ios/MagicMobileTests/Fixtures/OnDevice", `${name}.json`), "utf8")));
  return OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID, []);
};

describe("combat", () => {
  it("reads the real attacker prompt and queues every offered creature for All Attack", () => {
    const attackers = fixture("2p-attackers");
    expect(combatPhase(attackers)).toBe("attackers");
    expect(combatPhase(fixture("2p-priority"))).toBeUndefined();
    const everyone = allAttackTargets(attackers)!;
    expect(everyone.length).toBeGreaterThan(0);
    expect(declaredCount(attackers, "attackers")).toBe(0);
    const queue = new AttackQueue([...everyone]);
    expect(queue.step(attackers, true)).toEqual({ kind: "wait" });
    expect(queue.step(attackers, false)).toEqual({ kind: "send", id: everyone[0] });
    // Leaving the declare attackers step ends the queue.
    expect(new AttackQueue(["x"]).step(fixture("2p-priority"), false)).toEqual({ kind: "end" });
  });
  it("names the finish by what was declared", () => {
    expect([finishTitle("attackers", 0), finishTitle("attackers", 1), finishTitle("attackers", 3)]).toEqual(["No Attacks", "1 Attacker", "3 Attackers"]);
    expect([finishTitle("blockers", 0), finishTitle("blockers", 1), finishTitle("blockers", 2)]).toEqual(["No Blocks", "1 Blocker", "2 Blockers"]);
  });
  it("draws attacks, blocked attacks and blocks", () => {
    const card = (id: string) => ({ instanceId: id, card: { name: id, typeLine: "Creature" } });
    expect(combatArrows([
      { defenderId: "p2", defenderName: "AI", defenderKind: "player", blocked: true, attackers: [card("a")], blockers: [card("b")] },
      { defenderId: "p2", defenderName: "AI", blocked: false, attackers: [card("c")], blockers: [] },
    ])).toEqual([
      { kind: "blockedAttack", from: "a", to: "p2", toKind: "player" }, { kind: "block", from: "b", to: "a" },
      { kind: "attack", from: "c", to: "p2", toKind: undefined },
    ]);
  });
});
