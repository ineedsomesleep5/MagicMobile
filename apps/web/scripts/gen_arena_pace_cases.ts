/**
 * Writes the expectations of parity/arena-pace-cases.json from its inputs with the TypeScript port. iOS is the
 * reference: after a run, `swift test --package-path apps/ios --filter ParityGoldenTests` must pass the same file, so a
 * difference there means this port (or the inputs) is wrong, never the Swift code. Run:
 *   npx --prefix apps/web vite-node apps/web/scripts/gen_arena_pace_cases.ts
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { BoardEventDiffer, BoardFXScheduler, type BoardFXLevel, sweepRecap } from "../src/core/boardEvents";
import { arenaSummary, caseState } from "../test/paceCases";

const file = join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity/arena-pace-cases.json");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const root: any = JSON.parse(readFileSync(file, "utf8"));
const three = (value: number) => value.toFixed(3);
root.scheduler = {
  sweepStep: BoardFXScheduler.sweepStep, sweepSpread: BoardFXScheduler.sweepSpread, sweepMinimum: BoardFXScheduler.sweepMinimum,
  maximumHold: BoardFXScheduler.maximumHold, arenaStrikeSpacing: BoardFXScheduler.arenaStrikeSpacing,
};
for (const item of root.transitions) {
  const events = BoardEventDiffer.events(caseState(item.old, "arena"), caseState(item.new, "arena"), new Set(item.commanders ?? []));
  item.events = events.map(arenaSummary);
  for (const level of ["full", "reduced"] as BoardFXLevel[]) {
    const scheduled = BoardFXScheduler.schedule(events, level, 0, item.hold ?? 0, item.pace ?? "arena", item.viewer);
    const holds = scheduled.filter((fx) => fx.holdsSmartPass).map((fx) => fx.end);
    const later = scheduled.flatMap((fx) => (fx.holdsLaterBatchesUntil === undefined ? [] : [fx.holdsLaterBatchesUntil]));
    item[level] = {
      plan: scheduled.map((fx) => `${arenaSummary(fx.event)} @${three(fx.delay)} +${three(fx.duration)}`),
      smartPassHold: holds.length > 0 ? three(Math.max(...holds)) : null,
      holdsLater: later.length > 0 ? three(Math.max(...later)) : null,
    };
  }
  if ("recap" in item) item.recap = sweepRecap(item.spell, events) ?? null;
}
writeFileSync(file, JSON.stringify(root, null, 2) + "\n");
console.log(`wrote ${root.transitions.length} transitions`);
