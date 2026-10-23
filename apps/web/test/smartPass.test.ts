/** The cases of apps/android/core/src/test/.../OnDeviceSmartPassTest.kt (iOS OnDeviceYieldPolicyTests.swift), for the TypeScript port. */
import { describe, expect, it } from "vitest";
import type { J } from "../src/core/json";
import { OnDeviceMessageLog } from "../src/core/messageLog";
import {
  defaultSmartPass, defaultStops, hasPlay, hasResponse, manaFloating, passPrompt, type Situation, Step, stepFromEngine, stopKey, topStackIsMine,
  type YieldContext,
} from "../src/core/smartPass";

const context = (myTurn = true, emptyStack = true): YieldContext => ({
  matchID: "match", seatID: "seat", viewerID: "viewer", activePlayerID: myTurn ? "viewer" : "other", turn: 3, phase: "running",
  localHumanEnabled: true, foreground: true, emptyStack, selfAuthority: true, resyncRequired: false,
  prompt: { id: "prompt", revision: 10, kind: "SELECT", selectMode: "priority", allowsBoolean: true, submitted: false, manaPlayerID: "viewer" },
});
const situation = (play: boolean, step: string | undefined = "PRECOMBAT_MAIN", myTurn = true, emptyStack = true): Situation =>
  ({ context: context(myTurn, emptyStack), step, hasPlay: play, manaFloating: false, hasResponse: true });
const settings = defaultSmartPass;

describe("smart pass", () => {
  it("passes with nothing to play and stops where marked", () => {
    expect(passPrompt(situation(false), settings)).toBeDefined();
    expect(passPrompt(situation(false, undefined, true, false), settings)).toBeDefined();
    expect(passPrompt(situation(true), settings)).toBeUndefined();
    expect(passPrompt(situation(true, "POSTCOMBAT_MAIN"), settings)).toBeUndefined();
    expect(passPrompt(situation(true, "END_TURN", false), settings)).toBeUndefined();
    expect(passPrompt(situation(true, "DECLARE_ATTACKERS", false), settings)).toBeUndefined();
    expect(passPrompt(situation(true, "UPKEEP"), settings)).toBeDefined();
    expect(passPrompt(situation(true, "PRECOMBAT_MAIN", false), settings)).toBeDefined();
    expect(passPrompt(situation(true, "UPKEEP", true, false), settings)).toBeUndefined();
    expect(passPrompt(situation(true, "mystery"), settings)).toBeUndefined();
    const custom = { ...settings, stops: new Set([stopKey(Step.UPKEEP, true)]) };
    expect(passPrompt(situation(true, "UPKEEP"), custom)).toBeUndefined();
    expect(passPrompt(situation(true), custom)).toBeDefined();
  });

  it("never answers a choice, floating mana or when off", () => {
    expect(passPrompt({ ...situation(false), manaFloating: true }, settings)).toBeUndefined();
    expect(passPrompt(situation(false), { ...settings, enabled: false })).toBeUndefined();
    const base = situation(false);
    const prompt = base.context.prompt!;
    const changes: YieldContext[] = [
      { ...base.context, prompt: { ...prompt, kind: "ASK" } }, { ...base.context, prompt: { ...prompt, selectMode: "attackers" } },
      { ...base.context, prompt: { ...prompt, selectMode: "blockers" } }, { ...base.context, prompt: { ...prompt, submitted: true } },
      { ...base.context, prompt: { ...prompt, manaPlayerID: "other" } }, { ...base.context, prompt: undefined },
      { ...base.context, selfAuthority: false }, { ...base.context, resyncRequired: true }, { ...base.context, foreground: false },
      { ...base.context, localHumanEnabled: false }, { ...base.context, phase: "ended" },
    ];
    for (const change of changes) expect(passPrompt({ ...base, context: change }, settings)).toBeUndefined();
  });

  it("reads playables, mana and steps", () => {
    const view = (category: string, row: J): J => ({ canPlayObjects: { objects: { card: { [category]: [row] } } } });
    expect(hasPlay(undefined)).toBe(false);
    expect(hasPlay(view("basicManaAbilities", { id: "a" }))).toBe(false);
    expect(hasPlay(view("other", { id: "a", manaAbility: true }))).toBe(false);
    expect(hasPlay(view("other", { id: "a" }))).toBe(true);
    expect(hasPlay(view("basicPlayAbilities", { id: "a" }))).toBe(true);
    expect(manaFloating({ manaPool: { black: 0, green: 0 } })).toBe(false);
    expect(manaFloating({ manaPool: { black: 0, green: 1 } })).toBe(true);
    const steps: [string, (typeof Step)[keyof typeof Step]][] = [["UPKEEP", Step.UPKEEP], ["precombat-main", Step.MAIN1],
      ["BEGIN_COMBAT", Step.BEGIN_COMBAT], ["FIRST_COMBAT_DAMAGE", Step.COMBAT_DAMAGE], ["END_TURN", Step.END], ["POSTCOMBAT_MAIN", Step.MAIN2]];
    for (const [raw, step] of steps) expect(stepFromEngine(raw)).toBe(step);
    expect(stepFromEngine("UNTAP")).toBeUndefined();
    // The stored keys are the iOS raw values, so every app reads the same words.
    expect(stopKey(Step.DECLARE_ATTACKERS, true)).toBe("mine.declareAttackers");
    expect([...defaultStops].sort()).toEqual(["mine.main1", "mine.main2", "theirs.declareAttackers", "theirs.end"]);
  });

  it("uses stack controllers and responses", () => {
    const value = (step: string, empty: boolean, mine: boolean | undefined, response: boolean, myTurn = true): Situation =>
      ({ ...situation(true, step, myTurn, empty), topStackIsMine: mine, hasResponse: response });
    expect(passPrompt(value("UPKEEP", false, true, true), settings)).toBeDefined(); // own trigger resolves
    expect(passPrompt(value("UPKEEP", false, true, true), { ...settings, stopForOwnSpells: true })).toBeUndefined();
    expect(passPrompt(value("UPKEEP", false, false, true), settings)).toBeUndefined(); // an answer to their spell stops
    expect(passPrompt(value("UPKEEP", false, false, false), settings)).toBeDefined(); // nothing answers it
    expect(passPrompt(value("UPKEEP", false, undefined, true), settings)).toBeUndefined(); // older engine: today's stop
    expect(passPrompt(value("DECLARE_ATTACKERS", true, undefined, true, false), settings)).toBeUndefined();
    expect(passPrompt(value("DECLARE_ATTACKERS", true, undefined, false, false), settings)).toBeDefined();
    expect(passPrompt(value("PRECOMBAT_MAIN", true, undefined, false), settings)).toBeUndefined();
  });

  it("reads engine controllers and response flags", () => {
    const root: J = { stackOrder: ["s2", "s1"], stackControllers: { s2: "viewer", s1: "other" } };
    expect(topStackIsMine(root, "viewer")).toBe(true);
    expect(topStackIsMine(root, "other")).toBe(false);
    expect(topStackIsMine({ stackOrder: ["s2"] }, "viewer")).toBeUndefined();
    const view = (rows: J[]): J => ({ canPlayObjects: { objects: { c1: { spells: rows } } } });
    expect(hasResponse(view([{ respondsToStack: false }]))).toBe(false);
    expect(hasResponse(view([{ respondsToStack: false }, { respondsToStack: true }]))).toBe(true);
    expect(hasResponse(view([{}]))).toBe(true); // a missing flag counts as a response
    expect(hasResponse(view([{ manaAbility: true }]))).toBe(false); // mana abilities never count
  });

  it("notes a run of automatic passes on one log line", () => {
    const log = new OnDeviceMessageLog();
    log.noteAutoPass("Upkeep", "p1");
    log.noteAutoPass("Draw", "p2");
    log.noteAutoPass("Draw", "p3");
    expect(log.entries.map((e) => e.message)).toEqual(["Auto-passed: Upkeep · Draw"]);
  });
});

// ---------------- smart-pass-cases.json: the same cases iOS runs (ParityGoldenTests) ----------------
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { GameSnapshot } from "../src/core/models";
import {
  decodeStops, encodeStops, isAutomaticPass, type SmartPassSettings, threatensViewer, YieldModes, YieldPolicy, type YieldMode,
} from "../src/core/smartPass";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity/smart-pass-cases.json"), "utf8"));

/** A context patch over the cases' base: a prompt patch merges into its prompt, null removes it. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function patched(patch: any = {}): YieldContext {
  const base = cases.context;
  const prompt = "prompt" in patch ? (patch.prompt === null ? undefined : { ...base.prompt, ...patch.prompt }) : { ...base.prompt };
  const value = { ...base, ...patch, prompt };
  if (value.activePlayerID === null) delete value.activePlayerID;
  return value;
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const caseSettings = (patch: any = {}): SmartPassSettings => {
  const merged = { ...cases.settings, ...patch };
  return { ...merged, stops: new Set(merged.stops) };
};

describe("smart-pass-cases.json", () => {
  it("names steps and stores stops like the apps", () => {
    for (const [raw, key] of Object.entries(cases.steps)) expect(stepFromEngine(raw)?.key ?? null, raw).toBe(key);
    expect([...defaultSmartPass.stops].sort()).toEqual([...cases.settings.stops].sort());
    expect({ ...defaultSmartPass, stops: [...defaultSmartPass.stops].sort() }).toEqual({ ...cases.settings, stops: [...cases.settings.stops].sort() });
    expect(decodeStops(undefined)).toEqual(new Set(cases.settings.stops));
    expect(decodeStops("")).toEqual(new Set());
    expect(decodeStops(encodeStops(defaultStops))).toEqual(defaultStops);
    for (const [mode, value] of Object.entries(cases.modes)) {
      const { duration, passLimit } = YieldModes[mode as YieldMode];
      expect({ duration, passLimit }, mode).toEqual(value);
    }
    for (const [id, automatic] of Object.entries(cases.automaticPass)) expect(isAutomaticPass(id), id).toBe(automatic);
  });

  it("passes or stops like the apps", () => {
    for (const item of cases.passPrompt) {
      const s = item.situation;
      const value: Situation = {
        context: patched(item.context), step: s.step, hasPlay: s.hasPlay ?? false, manaFloating: s.manaFloating ?? false,
        topStackIsMine: s.topStackIsMine, hasResponse: s.hasResponse ?? true, threatensMe: s.threatensMe ?? false,
      };
      expect(passPrompt(value, caseSettings(item.settings)) !== undefined, item.name).toBe(item.pass);
    }
  });

  it("reads threats like the apps", () => {
    for (const item of cases.threats) {
      const zones = (battlefield: string[]) => ({
        library: [], hand: [], graveyard: [], exile: [], command: [], stack: [], handCount: 1, libraryCount: 50,
        battlefield: battlefield.map((id) => ({ instanceId: id, card: { name: "Bear", typeLine: "Creature" } })),
      });
      const snapshot = {
        id: "match", source: "xmage-ondevice", phase: "PRECOMBAT_MAIN", turn: 3, activePlayerId: "b", viewerPlayerId: "a", log: [],
        players: [{ playerId: "a", life: 40, poison: 0, commanderTax: 0, zones: zones(item.battlefield) },
          { playerId: "b", life: 40, poison: 0, commanderTax: 0, zones: zones([]) }],
        xmage: { stack: [{ id: "s1", objectId: "s1", objectType: item.objectType, name: "Spell", rulesText: item.text, controllerId: item.controller, targetIds: item.targets }] },
      } as unknown as GameSnapshot;
      expect(threatensViewer(snapshot), item.name).toBe(item.threatens);
    }
  });

  it("skips like the apps", () => {
    for (const scenario of cases.yield) {
      const policy = new YieldPolicy();
      const start = patched(scenario.start);
      expect(YieldPolicy.canStart(start, scenario.mode), `${scenario.name} · canStart`).toBe(scenario.started);
      expect(policy.start(start, 0, scenario.mode), `${scenario.name} · start`).toBe(scenario.started);
      for (const [index, step] of scenario.steps.entries()) {
        const at = `${scenario.name} · step ${index}`;
        if (step.stop) { policy.stop(); continue; }
        const value = patched(step.context);
        const decision = policy.evaluate(value, step.now);
        const summary = decision.kind === "stop" ? `stop:${decision.reason}` : decision.kind;
        expect(summary, at).toBe(step.expect);
        if (decision.kind === "pass") {
          expect(decision.prompt, at).toEqual(value.prompt);
          if (step.record) policy.recordPass(decision.prompt);
        }
      }
    }
  });
});
