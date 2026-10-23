/** A player's status badges and their orbit round the medallion (PlayerStatusSummary, TavernEffectOrbit). */
import { describe, expect, it } from "vitest";
import type { GameSnapshot, PlayerGameState } from "../src/core/models";
import { orbitOffsets, orbitOrder, orbitShown, playerCounters, statusBadges } from "../src/core/playerStatus";

const zones = { library: [], hand: [], battlefield: [], graveyard: [], exile: [], command: [], stack: [] };
const player = (id: string, extra: Partial<PlayerGameState> = {}) => ({ playerId: id, displayName: id, life: 40, poison: 0, zones, ...extra }) as unknown as PlayerGameState;

describe("player status", () => {
  it("lists counters with poison first, the monarch, the initiative and commander damage", () => {
    const me = player("me", { poison: 7, counters: { energy: 3, Experience: 1 }, monarch: true, initiative: true });
    expect(playerCounters(me).map((c) => c.name)).toEqual(["Poison", "Experience", "energy"]);
    const ai = player("ai", { commanders: [{ id: "c1", name: "Atarka", ownerPlayerId: "ai", damageToPlayers: { me: 16 } }] } as Partial<PlayerGameState>);
    const snapshot = { players: [me, ai] } as unknown as GameSnapshot;
    const badges = statusBadges(me, snapshot);
    expect(badges.map((b) => [b.id, b.label, b.nearLethal])).toEqual([
      ["counter-poison", "Poison 7", true], ["counter-experience", "Experience 1", false], ["counter-energy", "Energy 3", false],
      ["monarch", "Monarch", false], ["initiative", "Has the initiative", false], ["commander-c1", "Atarka dealt 16 commander damage", true],
    ]);
    expect(orbitOrder(badges).map((b) => b.id).slice(0, 2)).toEqual(["commander-c1", "counter-poison"]);
    expect(orbitShown(badges, 5)).toMatchObject({ more: 2 });
    expect(orbitShown(badges, 5).badges).toHaveLength(4);
  });

  it("alternates the orbit either side of its bearing, 25 degrees apart", () => {
    const [first, second, third] = orbitOffsets(3, 10, 90);
    expect(first.x).toBeCloseTo(0); expect(first.y).toBeCloseTo(10);
    expect(second.x).toBeCloseTo(10 * Math.cos((115 * Math.PI) / 180)); expect(third.x).toBeCloseTo(10 * Math.cos((65 * Math.PI) / 180));
  });
});
