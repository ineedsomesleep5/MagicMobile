/** The Arena board's lights (ArenaBattlefieldCard.arenaGlow, ArenaHeroMedallion.commanderReady on iOS). */
import { describe, expect, it } from "vitest";
import type { GameSnapshot, LegalAction, PlayerGameState, ZoneCard } from "../src/core/models";
import { castableZones, glowClasses, type GlowContext } from "../src/ui/arena/glow";

const card = (id: string, typeLine = "Creature — Human Wizard", extra: Partial<ZoneCard> = {}): ZoneCard =>
  ({ instanceId: id, card: { name: id, typeLine }, ...extra });
const action = (type: string, extra: Partial<LegalAction> = {}): LegalAction => ({ id: `${type}-${extra.cardInstanceId ?? extra.sourceInstanceId}`, type, playerId: "me", label: type, ...extra });
const live: GlowContext = { onBattlefield: true, targetable: false, combatSelect: false, answering: true, paying: false };

describe("permanent glow", () => {
  it("lights a usable non-mana ability yellow, by its source or its card", () => {
    expect(glowClasses(card("a"), [action("activate_ability", { sourceInstanceId: "a" })], live)).toEqual(["ability"]);
    expect(glowClasses(card("a"), [action("activate_ability", { cardInstanceId: "a" })], live)).toEqual(["ability"]);
  });

  it("keeps mana-only permanents and lands as they were, a land's ability softer", () => {
    expect(glowClasses(card("m"), [action("make_mana", { sourceInstanceId: "m" })], live)).toEqual([]);
    expect(glowClasses(card("l", "Land"), [action("activate_ability", { sourceInstanceId: "l" })], live)).toEqual(["ability", "landish"]);
  });

  it("lets payments, targets and combat win over the ability light", () => {
    const actions = [action("activate_ability", { sourceInstanceId: "a" }), action("make_mana", { sourceInstanceId: "a" })];
    expect(glowClasses(card("a"), actions, { ...live, paying: true })).toEqual(["payable"]);
    expect(glowClasses(card("a"), actions, { ...live, targetable: true })).toEqual(["targetable"]);
    expect(glowClasses(card("a"), actions, { ...live, targetable: true, combatSelect: true })).toEqual(["can-act"]);
    expect(glowClasses(card("a", undefined, { isAttacking: true }), actions, live)).toEqual(["atk"]);
    expect(glowClasses(card("a", undefined, { blocking: ["x"] }), actions, live)).toEqual(["blk"]);
  });

  it("keeps a card in hand cyan even with an ability, and lights nothing while an answer is on its way", () => {
    expect(glowClasses(card("h"), [action("activate_ability", { cardInstanceId: "h" })], { ...live, onBattlefield: false })).toEqual(["playable"]);
    expect(glowClasses(card("a"), [action("activate_ability", { sourceInstanceId: "a" })], { ...live, answering: false })).toEqual([]);
    expect(glowClasses(card("a", undefined, { phasedIn: false }), [action("activate_ability", { sourceInstanceId: "a" })], live)).toEqual([]);
  });
});

describe("castable zones", () => {
  const zones = (extra: Partial<PlayerGameState["zones"]>) => ({ library: [], hand: [], battlefield: [], graveyard: [], exile: [], command: [], stack: [], ...extra });
  const me: PlayerGameState = { playerId: "me", life: 40, poison: 0, commanderTax: 0, zones: zones({ command: [card("cmd")], graveyard: [card("gy")] }) };
  const snapshot = (legalActions: LegalAction[]): GameSnapshot =>
    ({ id: "g", phase: "main", turn: 1, log: [], viewerPlayerId: "me", players: [me], legalActions });

  it("lights the command zone when your commander can be cast", () => {
    expect([...castableZones(me, snapshot([action("cast_spell", { cardInstanceId: "cmd" })]))]).toEqual(["command"]);
  });
  it("lights a graveyard you can cast from, and nothing for other actions or players", () => {
    expect([...castableZones(me, snapshot([action("cast_spell", { cardInstanceId: "gy" })]))]).toEqual(["graveyard"]);
    expect(castableZones(me, snapshot([action("activate_ability", { sourceInstanceId: "cmd" })])).size).toBe(0);
    expect(castableZones(me, snapshot([{ ...action("cast_spell", { cardInstanceId: "cmd" }), playerId: "ai" }])).size).toBe(0);
    expect(castableZones({ ...me, playerId: "ai" }, snapshot([action("cast_spell", { cardInstanceId: "cmd" })])).size).toBe(0);
  });
});
