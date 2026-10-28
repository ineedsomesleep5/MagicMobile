/**
 * The browsers' sideways row (iOS ScrollView(.horizontal) in ArenaAbilityBrowser and BoardCardChoiceView.arenaCardRow),
 * the arithmetic a mouse needs that a phone's swipe doesn't: whether there is more to either side (the edge fades and
 * arrows), how far an arrow moves the row, and a vertical wheel turned sideways.
 */

/** What the row measures, in its own pixels. */
export interface RowMetrics { scrollLeft: number; clientWidth: number; scrollWidth: number }

/** Less than this past an edge counts as the edge (sub-pixel layouts never land exactly on it). */
export const EDGE_SLOP = 2;
/** A press that moves this far sideways is a drag of the row, not a click on a card. */
export const DRAG_SLOP = 6;

/** Cards hidden before the start and after the end of the row. */
export function rowEdges({ scrollLeft, clientWidth, scrollWidth }: RowMetrics): { before: boolean; after: boolean } {
  const overflow = scrollWidth - clientWidth;
  if (overflow <= EDGE_SLOP) return { before: false, after: false };
  return { before: scrollLeft > EDGE_SLOP, after: scrollLeft < overflow - EDGE_SLOP };
}

/** Where an arrow takes the row: most of a view along, held at the ends. */
export function pageTarget({ scrollLeft, clientWidth, scrollWidth }: RowMetrics, direction: -1 | 1, fraction = 0.8): number {
  const max = Math.max(0, scrollWidth - clientWidth);
  return Math.min(max, Math.max(0, scrollLeft + direction * Math.max(1, clientWidth * fraction)));
}

/**
 * A wheel turn as sideways pixels: a mouse's vertical wheel moves the row, a trackpad's sideways swipe is left to the
 * browser (undefined). Line and page deltas (Firefox, some mice) become pixels.
 */
export function wheelSideways(deltaX: number, deltaY: number, deltaMode: number, clientWidth: number): number | undefined {
  if (Math.abs(deltaX) >= Math.abs(deltaY)) return undefined;
  const unit = deltaMode === 1 ? 40 : deltaMode === 2 ? clientWidth : 1;
  return deltaY * unit;
}
