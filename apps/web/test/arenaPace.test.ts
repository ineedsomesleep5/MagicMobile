/** combat-cases.json (keywords, beats) and arena-pace-cases.json: the board's events and the Arena pace, as iOS runs them. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  BoardEventDiffer, type BoardFXEvent, BoardFXScheduler, type BoardFXLevel, type BoardFXPace, CombatKeywords, type ScheduledBoardFX, sweepRecap,
} from "../src/core/boardEvents";
import { arenaSummary, caseState, eventSummary } from "./paceCases";

const parity = join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const load = (name: string): any => JSON.parse(readFileSync(join(parity, name), "utf8"));

const three = (value: number) => value.toFixed(3);
const planned = (fx: ScheduledBoardFX, summary: (e: BoardFXEvent) => string) => `${summary(fx.event)} @${three(fx.delay)} +${three(fx.duration)}`;

describe("combat-cases.json", () => {
  const root = load("combat-cases.json");
  it("reads combat keywords like the apps", () => {
    for (const item of root.keywords) {
      expect(CombatKeywords.of(item.icons?.map((iconType: string) => ({ iconType })), item.rules ?? undefined), item.name).toEqual(item.expect);
    }
  });
  it("plays first-strike beats like the apps", () => {
    for (const item of root.beats) {
      const events = BoardEventDiffer.events(caseState(item.old), caseState(item.new));
      expect(events.map(eventSummary), item.name).toEqual(item.events);
      for (const level of ["full", "reduced"] as BoardFXLevel[]) {
        expect(BoardFXScheduler.schedule(events, level).map((fx) => planned(fx, eventSummary)), `${item.name} · ${level}`).toEqual(item[level]);
      }
    }
  });
});

describe("arena-pace-cases.json", () => {
  const root = load("arena-pace-cases.json");
  it("keeps the shared constants", () => {
    expect({
      sweepStep: BoardFXScheduler.sweepStep, sweepSpread: BoardFXScheduler.sweepSpread, sweepMinimum: BoardFXScheduler.sweepMinimum,
      maximumHold: BoardFXScheduler.maximumHold, arenaStrikeSpacing: BoardFXScheduler.arenaStrikeSpacing,
    }).toEqual(root.scheduler);
  });
  it("schedules each transition at the Arena pace", () => {
    for (const item of root.transitions) {
      const pace: BoardFXPace = item.pace ?? "arena";
      const events = BoardEventDiffer.events(caseState(item.old, "arena"), caseState(item.new, "arena"), new Set(item.commanders ?? []));
      expect(events.map(arenaSummary), item.name).toEqual(item.events);
      for (const level of ["full", "reduced"] as BoardFXLevel[]) {
        if (!item[level]) continue;
        const scheduled = BoardFXScheduler.schedule(events, level, 0, item.hold ?? 0, pace, item.viewer);
        expect(scheduled.map((fx) => planned(fx, arenaSummary)), `${item.name} · ${level}`).toEqual(item[level].plan);
        const holds = scheduled.filter((fx) => fx.holdsSmartPass).map((fx) => fx.end);
        expect(holds.length > 0 ? three(Math.max(...holds)) : null, `${item.name} · ${level} · hold`).toEqual(item[level].smartPassHold);
        const later = scheduled.flatMap((fx) => (fx.holdsLaterBatchesUntil === undefined ? [] : [fx.holdsLaterBatchesUntil]));
        expect(later.length > 0 ? three(Math.max(...later)) : null, `${item.name} · ${level} · later`).toEqual(item[level].holdsLater);
      }
      if ("recap" in item) expect(sweepRecap(item.spell, events) ?? null, `${item.name} · recap`).toEqual(item.recap);
    }
  });
});
