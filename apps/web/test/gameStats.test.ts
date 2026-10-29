/** game-summary-cases.json: combat credit and the top attacker, as iOS and Android run them. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { GameStats } from "../src/core/gameStats";
import type { GameSnapshot } from "../src/core/models";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const root: any = JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity/game-summary-cases.json"), "utf8"));

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function snapshot(step: any): GameSnapshot {
  const json = structuredClone(root.base);
  const battlefield = (step.battlefield ?? []).map((key: string) => structuredClone(root.cards[key]));
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  json.players = json.players.map((player: any) => {
    if (step.life?.[player.playerId] !== undefined) player.life = step.life[player.playerId];
    if (player.playerId === json.viewerPlayerId) player.zones.battlefield = battlefield;
    return player;
  });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  json.xmage.combat = (step.attacks ?? []).map((attack: any) => ({
    defenderId: attack.defender, defenderName: attack.defender, blocked: attack.blocked ?? false, blockers: [],
    attackers: attack.attackers.map((key: string) => { const card = structuredClone(root.cards[key]); delete card.card.tokenArtwork; return card; }),
  }));
  return json;
}

describe("game-summary-cases.json", () => {
  it("credits combat damage and names the top attacker like the apps", () => {
    for (const item of root.cases) {
      const stats = new GameStats();
      for (const step of item.steps) stats.record(snapshot(step));
      expect(stats.combatDamage, item.name).toBe(item.expect.combatDamage);
      expect(stats.biggestHit, item.name).toBe(item.expect.biggestHit);
      const top = stats.topCard;
      if (item.expect.top) {
        expect({ name: top?.name, damage: top?.damage, instanceId: top?.card?.instanceId, tokenArtwork: top?.card?.card.tokenArtwork?.name ?? null }, item.name)
          .toEqual({ name: item.expect.top.name, damage: item.expect.top.damage, instanceId: item.expect.top.instanceId, tokenArtwork: item.expect.top.tokenArtwork ?? null });
      } else expect(top, item.name).toBeUndefined();
    }
  });
});

describe("creatures destroyed", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const board = (battlefield: any[], graveyard: any[]): GameSnapshot => {
    const json = structuredClone(root.base);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    json.players = json.players.map((player: any) => {
      if (player.playerId !== json.viewerPlayerId) { player.zones.battlefield = battlefield; player.zones.graveyard = graveyard; }
      return player;
    });
    json.xmage.combat = [];
    return json;
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const creature = (id: string): any => { const card = structuredClone(Object.values(root.cards)[0] as any); card.instanceId = id; return card; };

  it("counts a creature that reaches the graveyard under a new object ID", () => {
    const stats = new GameStats();
    stats.record(board([creature("bear-1")], []));
    stats.record(board([], [creature("bear-2")]));
    expect(stats.creaturesDestroyed).toBe(1);
  });

  it("does not count a creature that left for somewhere else", () => {
    const stats = new GameStats();
    stats.record(board([creature("bear-1")], [creature("old")]));
    stats.record(board([], [creature("old")]));
    expect(stats.creaturesDestroyed).toBe(0);
  });
});
