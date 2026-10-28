/**
 * The browsers' one sideways row of cards (iOS ScrollView(.horizontal) in ArenaAbilityBrowser, ArenaStackBrowser and
 * BoardCardChoiceView.arenaCardRow), made for a mouse: the row centres when it fits; when it doesn't, a vertical wheel
 * moves it sideways, a held press drags it, a trackpad swipes it, and the edge with more cards beyond fades out under a
 * glass arrow that moves it most of a view along. A drag never picks the card it started on.
 */
import { useCallback, useLayoutEffect, useRef, useState } from "react";
import { DRAG_SLOP, EDGE_SLOP, pageTarget, rowEdges, wheelSideways } from "./hscroll";

export function HScroller({ children }: {
  /** The cards, or a function that sizes them from the row's height in board points (undefined until measured). */
  children: React.ReactNode | ((rowHeight: number | undefined) => React.ReactNode);
}) {
  const track = useRef<HTMLDivElement>(null);
  const row = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ before: false, after: false });
  const [height, setHeight] = useState<number>();
  const measure = useCallback(() => {
    const element = track.current;
    if (!element) return;
    const next = rowEdges(element);
    setEdges((current) => (current.before === next.before && current.after === next.after ? current : next));
    setHeight(element.clientHeight);
  }, []);
  useLayoutEffect(() => {
    const element = track.current;
    if (!element) return;
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    if (row.current) observer.observe(row.current);
    const wheel = (event: WheelEvent) => {
      if (event.ctrlKey) return;
      const sideways = wheelSideways(event.deltaX, event.deltaY, event.deltaMode, element.clientWidth);
      if (sideways === undefined || element.scrollWidth <= element.clientWidth + EDGE_SLOP) return;
      event.preventDefault();
      element.scrollLeft += sideways;
    };
    element.addEventListener("wheel", wheel, { passive: false });
    return () => { observer.disconnect(); element.removeEventListener("wheel", wheel); };
  }, [measure]);

  const drag = (event: React.PointerEvent) => {
    const element = track.current;
    // A finger or pen pans the row natively; a mouse needs the drag.
    if (!element || event.pointerType !== "mouse" || event.button !== 0 || element.scrollWidth <= element.clientWidth + EDGE_SLOP) return;
    // Pointer moves are in window pixels; the board is scaled, the row scrolls in board points.
    const scale = element.getBoundingClientRect().width / Math.max(1, element.offsetWidth) || 1;
    const start = { x: event.clientX, left: element.scrollLeft };
    let dragging = false;
    const move = (e: PointerEvent) => {
      if (!dragging && Math.abs(e.clientX - start.x) < DRAG_SLOP) return;
      dragging = true;
      element.classList.add("dragging");
      element.scrollLeft = start.left - (e.clientX - start.x) / scale;
    };
    const end = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
      element.classList.remove("dragging");
      if (!dragging) return;
      // The click that ends a drag picks nothing.
      const swallow = (click: MouseEvent) => { click.stopPropagation(); click.preventDefault(); };
      window.addEventListener("click", swallow, { capture: true, once: true });
      window.setTimeout(() => window.removeEventListener("click", swallow, { capture: true }), 0);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", end);
    window.addEventListener("pointercancel", end);
  };

  const page = (direction: -1 | 1) => {
    const element = track.current;
    if (!element) return;
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true;
    element.scrollTo({ left: pageTarget(element, direction), behavior: reduce ? "auto" : "smooth" });
  };

  return (
    <div className={`hscroll ${edges.before ? "before" : ""} ${edges.after ? "after" : ""}`} data-veil="">
      <div className="hstrack" ref={track} data-veil="" onScroll={measure} onPointerDown={drag}>
        <div className="hsrow" ref={row} data-veil="">{typeof children === "function" ? children(height) : children}</div>
      </div>
      {edges.before && <button type="button" className="hsarrow prev" aria-label="Earlier cards" onClick={() => page(-1)}>‹</button>}
      {edges.after && <button type="button" className="hsarrow next" aria-label="More cards" onClick={() => page(1)}>›</button>}
    </div>
  );
}
