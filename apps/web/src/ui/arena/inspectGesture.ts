/**
 * Reading a card with a mouse (iOS HoldCardInspection and CardInspector): a right-click opens the inspector until a click
 * elsewhere or Esc; a press held still for 0.45 s opens it until the button is let go, and that release is not a click
 * on whatever lies under the pointer. Hovering never opens it (Caleb, 2026-10-23): hover only lifts or outlines a card.
 * A press that moves more than 8 px before then (a drag from the hand) never inspects.
 */
import type { ZoneCard } from "../../core/models";

export const HOLD_INSPECT = { millis: 450, slop: 8 };

export interface InspectTarget { name: string; card?: ZoneCard }

/** The board's inspector: `held` when a press opened it, so letting go closes it (`release`). */
export interface CardReader {
  open(target: InspectTarget, held: boolean): void;
  release(): void;
}

/** One press on a card, with its timer injected (test/inspectGesture.test.ts). */
export class HoldPress {
  private timer?: unknown;
  private origin?: { x: number; y: number };
  /** The hold opened the inspector. */
  opened = false;

  constructor(private readonly schedule: (run: () => void, millis: number) => unknown, private readonly cancel: (timer: unknown) => void) {}

  down(x: number, y: number, onHold: () => void) {
    this.clear();
    this.opened = false;
    this.origin = { x, y };
    this.timer = this.schedule(() => { this.timer = undefined; this.opened = true; onHold(); }, HOLD_INSPECT.millis);
  }

  /** The pointer moved: far enough before the hold, and the press is a drag or a slip, not a read. */
  move(x: number, y: number) {
    if (this.timer !== undefined && this.origin && Math.hypot(x - this.origin.x, y - this.origin.y) > HOLD_INSPECT.slop) this.clear();
  }

  /** The press ended; true when its hold had opened the inspector (the release closes it). */
  up(): boolean {
    const opened = this.opened;
    this.clear();
    this.opened = false;
    return opened;
  }

  private clear() {
    if (this.timer !== undefined) this.cancel(this.timer);
    this.timer = undefined;
  }
}

/** Starts watching a press for a hold: `open` when it is held, `release` when a held press ends. */
export function watchHold(event: { clientX: number; clientY: number }, open: () => void, release: () => void) {
  const press = new HoldPress((run, millis) => window.setTimeout(run, millis), (timer) => window.clearTimeout(timer as number));
  press.down(event.clientX, event.clientY, open);
  const move = (e: PointerEvent) => press.move(e.clientX, e.clientY);
  const end = () => {
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", end);
    window.removeEventListener("pointercancel", end);
    if (!press.up()) return;
    release();
    // The click that ends a hold reads nothing else: swallow it before React sees it.
    const swallow = (click: MouseEvent) => { click.stopPropagation(); click.preventDefault(); };
    window.addEventListener("click", swallow, { capture: true, once: true });
    window.setTimeout(() => window.removeEventListener("click", swallow, { capture: true }), 0);
  };
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", end);
  window.addEventListener("pointercancel", end);
}

/** Right-click and press-and-hold handlers that read `target` (nothing when there is no reader or nothing to read). */
export function readProps(reader: CardReader | undefined, target: InspectTarget | undefined) {
  if (!reader || !target || target.name.length === 0) return {};
  return {
    onContextMenu: (event: React.MouseEvent) => { event.preventDefault(); event.stopPropagation(); reader.open(target, false); },
    onPointerDown: (event: React.PointerEvent) => {
      if (event.button === 0) watchHold(event, () => reader.open(target, true), () => reader.release());
    },
  };
}
