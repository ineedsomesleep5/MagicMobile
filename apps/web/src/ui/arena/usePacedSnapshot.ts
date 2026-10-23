/**
 * The snapshot the board shows at the chosen game speed (core/gameSpeed.ts). The session keeps the live game; this hook
 * lets each opponent action stay on screen for its time before the next one shows. While the board is behind, the shown
 * snapshot carries no prompt: only the newest snapshot can be answered, and its prompt shows the moment it does.
 */
import { useEffect, useRef, useState } from "react";
import { type GameSpeed, PresentationPacer } from "../../core/gameSpeed";
import type { GameSnapshot } from "../../core/models";
import { fxNow } from "./useBoardFX";

export interface PacedSnapshot {
  snapshot?: GameSnapshot;
  /** Newer snapshots wait behind the shown one. */
  behind: boolean;
  /** When the newest snapshot will have shown and had its time on screen (undefined at the Fast speed). */
  paceUntil?: number;
}

/** A snapshot the engine has already moved past, without anything to answer. */
const withoutPrompt = (snapshot: GameSnapshot): GameSnapshot =>
  ({ ...snapshot, promptEnvelopeV2: undefined, legalActions: [], manaPayment: undefined });

export function usePacedSnapshot(live: GameSnapshot | undefined, speed: GameSpeed, maxLag?: number): PacedSnapshot {
  const pacer = useRef<PresentationPacer | undefined>(undefined);
  pacer.current ??= new PresentationPacer(speed, maxLag);
  const p = pacer.current;
  if (maxLag !== undefined) p.maxLag = maxLag;
  const [, setTick] = useState(0);
  const now = fxNow();
  p.setSpeed(speed, now);
  p.offer(live, now);
  p.advance(now);
  const nextAt = p.nextAt;
  const shown = p.shown;
  useEffect(() => {
    if (nextAt === undefined) return;
    const timer = window.setTimeout(() => setTick((t) => t + 1), Math.max(0, (nextAt - fxNow()) * 1000) + 5);
    return () => window.clearTimeout(timer);
  }, [nextAt, shown]);
  // The same stale copy for the same snapshot, so effects keyed on the snapshot don't run again.
  const stale = useRef<{ from?: GameSnapshot; copy?: GameSnapshot }>({});
  let snapshot = shown;
  if (shown && p.behind) {
    if (stale.current.from !== shown) stale.current = { from: shown, copy: withoutPrompt(shown) };
    snapshot = stale.current.copy;
  }
  return { snapshot, behind: p.behind, paceUntil: speed === "fast" ? undefined : p.settledAt(now) };
}
