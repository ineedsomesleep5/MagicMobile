/** arena-board-cases.json: the Arena board's small helpers, as iOS runs them (ParityGoldenTests). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { commandersTaken, commanderTakenNotice, extraHandCards, glossaryEntries, handPosture } from "../src/core/arenaBoard";
import type { GameSnapshot, LegalAction, PlayerGameState, ZoneCard } from "../src/core/models";
import { splitLoyalty } from "../src/ui/arena/AbilityCard";
import { affordableX, amountValues, choiceOptions, clampAmount, colorSymbol, lethalDamage, splitName, stepAmount } from "../src/ui/arena/Browsers";
import { drops } from "../src/ui/arena/layout";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity/arena-board-cases.json"), "utf8"));
const card = (id: string, name: string, typeLine = "Sorcery"): ZoneCard => ({ instanceId: id, card: { name, typeLine } });
const zones = (battlefield: ZoneCard[] = []) => ({ library: [], hand: [], battlefield, graveyard: [], exile: [], command: [], stack: [], handCount: 1, libraryCount: 50 });

describe("arena-board-cases.json", () => {
  it("drops a carried card like the apps", () => {
    for (const item of cases.drops) {
      expect(drops({ x: item.point[0], y: item.point[1] }, { x: item.start[0], y: item.start[1] }), item.name).toBe(item.drops);
    }
  });
  it("explains keywords like the apps", () => {
    for (const item of cases.glossary) expect(glossaryEntries(item.rules).map(([k]) => k), item.rules).toEqual(item.keywords);
  });
  it("notices a taken commander like the apps", () => {
    for (const item of cases.commanderTaken) {
      const snapshot = {
        id: "match", phase: "PRECOMBAT_MAIN", turn: 9, activePlayerId: "b", viewerPlayerId: "a", log: [],
        players: [{ playerId: "a", displayName: "You", life: 40, poison: 0, commanderTax: 0, zones: zones(), commanders: [{ id: "c1", name: "Chatterfang, Squirrel General", ownerPlayerId: "a" }] },
          { playerId: "b", displayName: "AI 1", life: 32, poison: 0, commanderTax: 0, zones: zones(item.theirs.map((n: string, i: number) => card(`x${i}`, n, "Legendary Creature"))) }],
      } as unknown as GameSnapshot;
      const taken = commandersTaken(snapshot);
      expect(taken, item.name).toEqual(item.taken);
      if (item.noticeStarts) expect(commanderTakenNotice(taken[0], snapshot).startsWith(item.noticeStarts), item.name).toBe(true);
    }
  });
  it("finds cards playable from other zones like the apps", () => {
    const player = { playerId: "p1", life: 40, poison: 0, commanderTax: 0,
      zones: { ...zones(), hand: [card("h1", "Shock")], graveyard: [card("g1", "Think Twice"), card("g2", "Lava Spike")], exile: [card("e1", "Light Up the Stage"), card("e2", "Gone")] } } as PlayerGameState;
    for (const item of cases.extraHand) {
      const actions: LegalAction[] = item.casts.map((id: string) => ({ id: `cast-${id}`, type: "cast_spell", playerId: "p1", label: "Cast", cardInstanceId: id }));
      expect(extraHandCards(player, actions).map((c) => c.instanceId), item.name).toEqual(item.cards);
    }
  });
  it("rests and raises the hand like the apps", () => {
    for (const item of cases.handPosture) expect(handPosture(item.situation), JSON.stringify(item.situation)).toBe(item.posture);
  });
  it("reads loyalty, amounts, splits and choices like the apps", () => {
    for (const item of cases.loyalty) {
      const split = splitLoyalty(item.text);
      expect(split.cost ?? null, item.text).toBe(item.cost);
      if (item.cost !== null) expect(split.text, item.text).toBe(item.rest);
    }
    for (const item of cases.amounts) {
      const values = amountValues(item.amounts ?? undefined, item.minimum ?? undefined, item.maximum ?? undefined);
      for (const [from, by, to] of item.steps ?? []) expect(stepAmount(values, from, by)).toBe(to);
      if ("max" in item) expect(values.at(-1)).toBe(item.max);
      if (item.values) expect(values).toEqual(item.values);
      for (const [value, to] of item.clamp ?? []) expect(clampAmount(values, value)).toBe(to);
    }
    for (const item of cases.affordableX) expect(affordableX(item.cost, item.sources) ?? null, item.cost).toBe(item.x);
    for (const item of cases.split) expect(splitName(item.label)).toBe(item.name);
    for (const item of cases.lethal) expect(lethalDamage(item.toughness, item.damage, item.deathtouch)).toBe(item.lethal);
    for (const item of cases.choices) {
      const options = choiceOptions(item.options.map(([id, label]: [string, string]) => ({ id, label })));
      expect(options.map((o) => o.id)).toEqual(item.ids);
      expect(options.map((o) => o.rememberID ?? null)).toEqual(item.remember);
      expect(options.map((o) => o.name ?? null)).toEqual(item.names);
    }
    for (const [label, symbol] of cases.colors) expect(colorSymbol(label) ?? null, label).toBe(symbol);
  });
});

describe("tile ability badges", () => {
  it("fits as many icons as the tile allows, at most four, with a +N coin for the rest", async () => {
    const { abilityBadgePlan } = await import("../src/core/models");
    const icons = ["ABILITY_FLYING", "ABILITY_TRAMPLE", "ABILITY_LIFELINK", "ABILITY_REACH", "ABILITY_VIGILANCE"].map((iconType) => ({ iconType }));
    expect(abilityBadgePlan(icons, 66)).toMatchObject({ hiddenCount: 3 });
    expect(abilityBadgePlan(icons, 66).visible).toHaveLength(2);
    expect(abilityBadgePlan(icons.slice(0, 3), 66)).toMatchObject({ hiddenCount: 0 });
    expect(abilityBadgePlan(icons, 93)).toMatchObject({ size: 15, hiddenCount: 2 });
    expect(abilityBadgePlan([], 93)).toMatchObject({ hiddenCount: 0, visible: [] });
  });
});
