/**
 * Recent games' length and memory in this browser (iOS GamePerformanceLog), for Options › Performance: one line per
 * game, newest first, the last 20 kept. The phone's heat has no web reading; memory is Chrome's JavaScript heap.
 */
import { storage } from "../storage";

export interface PerformanceEntry { started: number; mode: string; aiSkill?: number; minutes: number; turns: number; peakMB: number; line: string }

const KEY = "mm.web.performance";
const KEEP = 20;

export function readPerformance(): PerformanceEntry[] {
  try {
    const value = JSON.parse(storage.get(KEY) ?? "[]");
    return Array.isArray(value) ? value.filter((e) => typeof e?.line === "string") : [];
  } catch { return []; }
}

const pad = (n: number) => String(n).padStart(2, "0");

/** GamePerformanceEntry.line: "2026-10-23T14:05 quick skill 3, 18 min, 11 turns, peak 612 MB". */
export function performanceLine(entry: Omit<PerformanceEntry, "line">) {
  const d = new Date(entry.started);
  const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return [`${day} ${entry.mode}${entry.aiSkill !== undefined ? ` skill ${entry.aiSkill}` : ""}`, `${Math.round(entry.minutes)} min, ${entry.turns} turns`,
    `peak ${entry.peakMB} MB`].join(", ");
}

export function performanceReport(entries: PerformanceEntry[]): string | undefined {
  if (entries.length === 0) return undefined;
  return [`MagicMobile game performance (${entries.length} games, newest first), web 0.1.1`, ...entries.map((e) => e.line)].join("\n");
}

const heapMB = () => {
  const memory = (performance as unknown as { memory?: { usedJSHeapSize: number } }).memory;
  return memory ? Math.round(memory.usedJSHeapSize / 1_048_576) : 0;
};

/** Samples the page's memory every 10 s through one game; `finish` records it. */
export function startPerformanceSample(mode: string, aiSkill?: number) {
  const started = Date.now();
  let peak = heapMB();
  const timer = window.setInterval(() => { peak = Math.max(peak, heapMB()); }, 10_000);
  let done = false;
  return {
    finish(turns: number) {
      if (done) return;
      done = true;
      window.clearInterval(timer);
      peak = Math.max(peak, heapMB());
      const entry = { started, mode, aiSkill, minutes: (Date.now() - started) / 60_000, turns, peakMB: peak };
      const next = [{ ...entry, line: performanceLine(entry) }, ...readPerformance()].slice(0, KEEP);
      storage.set(KEY, JSON.stringify(next));
    },
    cancel() { window.clearInterval(timer); done = true; },
  };
}
