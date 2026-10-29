/** The board's sound cues (iOS BoardFXSound.cues) and the cue table (GameAudio). */
import { describe, expect, it } from "vitest";
import { BoardFXScheduler, type BoardFXEvent } from "../src/core/boardEvents";
import { arrivalCue, boardCues, drawCues, soundCooldown, soundFile, soundVolume } from "../src/ui/audio";

const cues = (events: BoardFXEvent[], arrivals = new Map(), casts = new Map()) =>
  boardCues(BoardFXScheduler.schedule(events, "full", 0, 0, "arena", "me"), "me", arrivals, casts).map((c) => `${c.sound}@${c.at.toFixed(3)}${c.volume !== 1 ? `x${c.volume}` : ""}${c.endsBy !== undefined ? `~${c.endsBy.toFixed(3)}` : ""}`);

describe("board sounds", () => {
  it("casts sound like their card type, quieter for opponents; only your abilities chime", () => {
    const casts = new Map([["s1", { name: "Lightning Bolt", typeLine: "Instant" }], ["s2", { name: "Wrath", typeLine: "Sorcery" }]]);
    expect(cues([{ type: "spellCast", stackID: "s1", name: "Lightning Bolt", controllerID: "me", tint: "red", weight: "spell" }], new Map(), casts)).toEqual(["cast-instant@0.000"]);
    expect(cues([{ type: "spellCast", stackID: "s2", name: "Wrath", controllerID: "ai", tint: "white", weight: "big" }], new Map(), casts))
      .toEqual(["cast-sorcery@0.000x0.75", "spell-big@0.050x0.75"]);
    expect(cues([{ type: "spellCast", stackID: "t", name: "Ability", controllerID: "ai", tint: "colorless", weight: "ability" }])).toEqual([]);
    expect(cues([{ type: "spellCast", stackID: "t", name: "Ability", controllerID: "me", tint: "colorless", weight: "ability" }])).toEqual(["ability@0.000"]);
  });
  it("arrivals sound like what arrived: a basic land's place, a creature's voice ending as it lands", () => {
    expect(arrivalCue({ kind: "basicLand", land: "forest" })).toBe("land-forest");
    expect(arrivalCue({ kind: "creature", heavy: true })).toBe("arrive-creature-heavy");
    const arrivals = new Map([["e1", { card: { name: "Gisa's Bidding", typeLine: "Creature — Zombie" }, isToken: true }]]);
    expect(cues([{ type: "enteredBattlefield", cardID: "e1", playerID: "me", from: "stack", tint: "black", entrance: "plain" }], arrivals))
      .toEqual(["creature-zombie@0.000~0.252"]);
  });
  it("strikes, deaths, exile and life", () => {
    expect(cues([{ type: "combatStrike", attackerID: "x", target: { player: "me" }, tint: "red", firstStrike: false }, { type: "lifeChanged", playerID: "me", delta: -3 }]))
      .toEqual(["player-hit@0.189"]);
    expect(cues([{ type: "leftBattlefield", cardID: "a", playerID: "me", to: "exile", tint: "red" }, { type: "leftBattlefield", cardID: "b", playerID: "me", to: "hand", tint: "red" }]))
      .toEqual(["exile@0.000", "card-pickup@0.070"]);
    expect(cues([{ type: "lifeChanged", playerID: "ai", delta: 2 }])).toEqual(["life-gain@0.000x0.55"]);
  });
  it("keeps the iOS table: levels, cooldowns, variants, draws", () => {
    expect([soundVolume("ui-tap"), soundVolume("strike"), soundVolume("death"), soundVolume("land-forest")]).toEqual([0.5, 0.9, 0.75, 0.85]);
    expect([soundCooldown("card-draw"), soundCooldown("ability"), soundCooldown("cast-instant")]).toEqual([0.1, 0.8, 0.25]);
    expect(soundFile("creature-giant", () => 2)).toBe("creature-orc-2");
    expect(soundFile("attack", () => 3)).toBe("attack-3");
    expect(soundFile("strike")).toBe("strike");
    expect(drawCues(5, 12)).toEqual(["card-draw", "card-draw"]);
    expect(drawCues(5, 4)).toEqual([]);
  });
});
