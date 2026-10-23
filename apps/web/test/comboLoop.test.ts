/** The combo loop shortcut (src/core/comboLoop.ts): parity/combo-loop-cases.json and the iOS ComboLoopTests cases. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  type ComboCommand, ComboLoop, ComboLoopStop, ComboNote, ComboRepeat, type ComboStanding, ComboStep, type ComboStepKind, ComboTarget,
  ComboWinForecast, commandFromAction, withoutPrompts,
} from "../src/core/comboLoop";
import type { GameSnapshot, LegalAction, ZoneCard } from "../src/core/models";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const json: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/combo-loop-cases.json"), "utf8"));

function target(code: string): ComboTarget {
  const parts = code.split("@");
  if (parts.length !== 2) return ComboTarget.make(code);
  const detail = parts[1].split("/");
  return ComboTarget.make(parts[0], detail[0], detail[1], detail[2] === "token");
}

function step(code: string): ComboStep {
  const parts = code.split("|");
  return ComboStep.make(parts[0] as ComboStepKind, parts[1], parts[2].length === 0 ? undefined : parts[2], parts[3],
    parts[4].length === 0 ? [] : parts[4].split(";").map(target));
}

// A small game: Chatterfang, a Treasure and two Squirrel tokens; the opponent has two creatures and 12 life.
function snapshot({ prompt = false, callerAlive = true, chatterfangAction = true, ownTrigger = false, opponentStack = false, opponentLife = 12,
  callerToughness = 3, passOffered = false } = {}): GameSnapshot {
  const card = (id: string, name: string, type: string, token = false, toughness?: number): ZoneCard => ({
    instanceId: id, card: { name, typeLine: type, ...(token ? { isToken: true } : {}) },
    ...(toughness !== undefined ? { toughness, power: 1 } : {}),
  });
  const zones = (battlefield: ZoneCard[], stack: ZoneCard[] = []) => ({ library: [], hand: [], battlefield, graveyard: [], exile: [], command: [], stack });
  const theirs = [card("zac-1", "Zacama, Primal Calamity", "Legendary Creature — Elder Dinosaur", false, 4)];
  if (callerAlive) theirs.unshift(card("cal-1", "Kinjalli's Caller", "Creature — Human Cleric", false, callerToughness));
  const actions: LegalAction[] = [];
  if (chatterfangAction) {
    actions.push({ id: "act-77", type: "activate_ability", playerId: "me", label: "{B}, Sacrifice X Squirrels: Target creature gets +X/-X until end of turn.",
      sourceInstanceId: "chat-1", abilityId: "ab-1", promptId: "p-1", messageId: 3 });
  }
  if (passOffered) actions.push({ id: "p-1:pass_priority", type: "pass_priority", playerId: "me", label: "Pass priority", promptId: "p-1", messageId: 3 });
  const root: GameSnapshot = {
    id: "game-1", phase: "main1", turn: 15, log: [], viewerPlayerId: "me", bridgeRevision: 7,
    players: [
      { playerId: "me", displayName: "Caleb", life: 20, poison: 0, commanderTax: 0,
        zones: zones([card("chat-1", "Chatterfang, Squirrel General", "Legendary Creature — Squirrel Warrior"),
          card("tr-1", "Treasure Token", "Token Artifact — Treasure", true),
          card("sq-9", "Squirrel Token", "Token Creature — Squirrel", true),
          card("sov-1", "Squirrel Sovereign", "Creature — Squirrel Noble")]) },
      { playerId: "ai", displayName: "Tavern AI", life: opponentLife, poison: 0, commanderTax: 0,
        zones: zones(theirs, opponentStack ? [card("bolt-1", "Lightning Bolt", "Instant")] : []) },
    ],
    legalActions: actions,
  };
  if (ownTrigger) {
    root.xmage = { schemaVersion: 1, gameId: "game-1", bridgeRevision: 7, callbackCoverage: [],
      stack: [{ id: "st-1", name: "Pitiless Plunderer trigger", sourceInstanceId: "plu-1", controllerId: "me" }],
      combat: [], players: [], exileZones: [], revealed: [], lookedAt: [], companion: [], playableObjects: [],
      panels: { stack: true, command: false, graveyard: false, exile: false, revealed: false, lookedAt: false, search: false } };
  }
  if (prompt) {
    const targets = [{ id: "zac-1", label: "Zacama, Primal Calamity", cardInstanceId: "zac-1" }, { id: "sq-9", label: "Squirrel Token", cardInstanceId: "sq-9" }];
    if (callerAlive) targets.unshift({ id: "cal-1", label: "Kinjalli's Caller", cardInstanceId: "cal-1" });
    root.promptEnvelopeV2 = { id: "p-2", method: "GAME_TARGET", messageId: 4, playerId: "me", responseKind: "target", message: "Select a creature", targets,
      responseCommand: { type: "choose_target", promptId: "p-2", messageId: 4 } };
  }
  return root;
}

describe("combo loop", () => {
  it("runs the shared cases", () => {
    const steps = new Map<string, ComboStep>(Object.entries(json.steps as Record<string, string>).map(([key, code]) => [key, step(code)]));
    const cases = json.cases as { name: string; history: string; expected: number }[];
    expect(cases.length).toBe(16);
    for (const item of cases) {
      const history = [...item.history].map((letter) => steps.get(letter)!);
      expect(ComboLoop.cycle(history)?.length ?? 0, item.name).toBe(item.expected);
    }
  });

  it("keeps kinds and replays the same target until it's gone", () => {
    const decision = snapshot();
    const activate = commandFromAction(decision.legalActions![0], "game-1", 7);
    const found = ComboLoop.step(activate, "x", "act-77", decision)!;
    expect(found).toBeDefined();
    expect(found.source).toBe("Chatterfang, Squirrel General");
    expect(found.stackEmpty).toBe(true);
    expect(ComboLoop.command(found, decision)?.actionID).toBe("act-77");

    const asked = snapshot({ prompt: true });
    const pick: ComboCommand = { type: "choose_target", gameId: "game-1", playerId: "me", promptId: "p-2", messageId: 4, targetIds: ["cal-1"] };
    const chosen = ComboLoop.step(pick, "Kinjalli's Caller", "t", asked)!;
    expect(chosen).toBeDefined();
    const caller = ComboTarget.make("Kinjalli's Caller", "opponent", "creature", false);
    expect(chosen.targets.length).toBe(1);
    expect(ComboTarget.equals(chosen.targets[0], caller)).toBe(true);
    expect(chosen.targets).toEqual([caller]);
    // While it lives, the same creature; once it's gone, another opponent's creature (never your own Squirrel).
    const same = ComboLoop.command(chosen, asked, ["Kinjalli's Caller"])!;
    expect(same).toBeDefined();
    expect(same.command.targetIds).toEqual(["cal-1"]);
    expect(same.retargeted).toBeUndefined();
    const next = ComboLoop.command(chosen, snapshot({ prompt: true, callerAlive: false }), ["Kinjalli's Caller"])!;
    expect(next).toBeDefined();
    expect(next.command.targetIds).toEqual(["zac-1"]);
    expect(next.retargeted?.from).toBe("Kinjalli's Caller");
    expect(next.retargeted?.to).toBe("Zacama, Primal Calamity");
    // A Squirrel token choice never takes Squirrel Sovereign.
    const squirrel = ComboStep.make("prompt", "choose_target", undefined, "GAME_TARGET", [ComboTarget.make("Squirrel Token", "you", "creature", true)]);
    expect(ComboLoop.command(squirrel, asked)?.command.targetIds).toEqual(["sq-9"]);
    expect(ComboLoop.missing(squirrel)).toBe("no Squirrel Token token left");
    expect(ComboLoop.missing(chosen)).toBe("no opponent's creature left to choose");
  });

  it("ignores passes and lets its own triggers resolve first", () => {
    const decision = snapshot({ passOffered: true });
    const pass: ComboCommand = { type: "pass_priority", gameId: "game-1", playerId: "me", promptId: "p-1", messageId: 3 };
    expect(ComboLoop.note(pass, "Pass priority", "p-1:pass_priority", decision)).toEqual(ComboNote.ignore);
    const attack: ComboCommand = { type: "declare_attackers", gameId: "game-1", playerId: "me" };
    expect(ComboLoop.note(attack, "Attack", "x", decision)).toEqual(ComboNote.breaks);
    const found = ComboLoop.step(commandFromAction(decision.legalActions![0], "game-1", 7), "x", "act-77", decision)!;
    expect(found).toBeDefined();
    const resolving = snapshot({ ownTrigger: true, passOffered: true });
    expect(ComboLoop.waitsForStack(found, resolving), "the round started with an empty stack").toBe(true);
    expect(ComboLoop.opponentResponded(resolving), "the trigger is ours").toBe(false);
    expect(ComboLoop.pass(resolving)?.command.type).toBe("pass_priority");
    expect(ComboLoop.waitsForStack(found, decision)).toBe(false);
  });

  it("digests toughness and writes summaries", () => {
    const before = snapshot();
    expect(ComboLoop.digest(before), "−1/−1 until end of turn is progress").not.toBe(ComboLoop.digest(snapshot({ callerToughness: 2 })));
    expect(ComboLoop.digest(before)).toBe(ComboLoop.digest(snapshot()));
    expect(ComboLoop.opponentResponded(snapshot({ opponentStack: true }))).toBe(true);
    expect(ComboLoop.summary(12, before, snapshot({ opponentLife: 0 }))).toBe("Repeated 12 times · Tavern AI 12 → 0");
    const round = [ComboStep.make("action", "activate_ability", "Chatterfang", "x"),
      ComboStep.make("prompt", "choose_target", undefined, "GAME_TARGET", [ComboTarget.make("Kinjalli's Caller", "opponent", "creature")])];
    expect(ComboLoop.preview(round)).toEqual(["Activate Chatterfang", "Choose an opponent's creature"]);
    expect(ComboLoop.roundLine(3, round, ["Kinjalli's Caller"])).toBe("Round 3 · Activate Chatterfang → Kinjalli's Caller");
    expect(ComboRepeat.watchable(ComboRepeat.times(10))).toBe(true);
    expect(ComboRepeat.watchable(ComboRepeat.times(20))).toBe(false);
    expect(ComboRepeat.watchable(ComboRepeat.untilWin)).toBe(false);
  });

  it("forecasts a win only from a steady drain and no answer", () => {
    const S = (life: number, poison: number): ComboStanding => ({ life, poison });
    // Round starts at 20, 18, 16: the third round takes them to 14, then 7 more rounds.
    const drain = [{ ai: S(20, 0) }, { ai: S(18, 0) }, { ai: S(16, 0) }];
    const forecast = ComboWinForecast.forecast(drain, false);
    expect(forecast?.rounds).toBe(7);
    expect(forecast?.canFinish).toBe(true);
    expect(ComboWinForecast.forecast(drain, true)?.canFinish, "an opponent with cards and open mana could answer").toBe(false);
    // Poison 1, 2, 3: the third round makes 4, then 6 more.
    const poison = [{ ai: S(20, 1) }, { ai: S(20, 2) }, { ai: S(20, 3) }];
    expect(ComboWinForecast.forecast(poison, false)?.rounds).toBe(6);
    const lastRound = [{ ai: S(6, 0) }, { ai: S(4, 0) }, { ai: S(2, 0) }];
    expect(ComboWinForecast.forecast(lastRound, false)?.rounds, "the round under way wins").toBe(0);
    const uneven = [{ ai: S(20, 0) }, { ai: S(18, 0) }, { ai: S(17, 0) }];
    expect(ComboWinForecast.forecast(uneven, false)).toBeUndefined();
    expect(ComboWinForecast.forecast(drain.slice(0, 2), false), "two rounds are not a pattern yet").toBeUndefined();
    const slow = [{ ai: S(1000, 0) }, { ai: S(999, 0) }, { ai: S(998, 0) }];
    expect(ComboWinForecast.forecast(slow, false, 200)).toBeUndefined();
  });

  // Web-only checks of the port's value forms (no Swift counterpart).
  it("keys steps by meaning and keeps the stop messages", () => {
    const a = ComboStep.make("prompt", "choose_target", undefined, "GAME_TARGET", [target("Kinjalli's Caller@opponent/creature/card")]);
    const z = ComboStep.make("prompt", "choose_target", undefined, "GAME_TARGET", [target("Zacama, Primal Calamity@opponent/creature/card")], { stackEmpty: true });
    expect(ComboStep.equals(a, z)).toBe(true);
    expect(ComboStep.key(a)).toBe(ComboStep.key(z));
    expect(ComboTarget.equals(target("Mode A"), target("Mode B"))).toBe(false);
    expect(ComboLoopStop.message(ComboLoopStop.reachedLimit)).toBe("Stopped after 300 rounds.");
    expect(ComboLoopStop.message(ComboLoopStop.stepMissing("no Squirrel Token token left"))).toBe("Stopped: no Squirrel Token token left.");
    const shown = withoutPrompts(snapshot({ prompt: true, passOffered: true }));
    expect(shown.legalActions).toBeUndefined();
    expect(shown.promptEnvelopeV2).toBeUndefined();
  });
});
