/**
 * The Arena board's flights (iOS BoardFXOverlay with `arena`, and BoardFXFlight): a card that arrives flies from the
 * stack card to its slot while its tile waits, a card that leaves burns away where it lay (graveyard, exile) or flies
 * home (hand, library), an attacker charges what it hits, a stolen card is dragged across, and a spell that never
 * reached the stack card is shown there. Placements follow BoardFXFlight.placement; times come from the scheduler.
 */
import { Component, type ReactNode, useEffect, useRef, useState } from "react";
import type { ActiveBoardFX, BoardFXZone } from "../../core/boardEvents";
import { BoardFXScheduler, subjectID } from "../../core/boardEvents";
import type { ZoneCard } from "../../core/models";
import { Face, PlainTile, Tile } from "./ArenaCard";
import { paint } from "./fxPainter";
import { LEAN, type Place, STAGE } from "./layout";
import { fxNow } from "./useBoardFX";

interface Point { x: number; y: number }
export interface FXAnchors {
  viewerID?: string;
  stack: Point;
  player(id: string): Point;
  hand(id: string): Point;
}

const easeOut = (t: number) => 1 - Math.pow(1 - Math.min(Math.max(t, 0), 1), 3);
const easeIn = (t: number) => Math.pow(Math.min(Math.max(t, 0), 1), 2.2);
/** Quadratic arc between two points, lifted toward the top of the board. */
const arc = (a: Point, b: Point, lift: number, t: number): Point => {
  const c = { x: (a.x + b.x) / 2, y: Math.min(a.y, b.y) - lift };
  const u = 1 - t;
  return { x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y };
};
const lerp = (a: Point, b: Point, t: number): Point => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
const centre = (p: Place): Point => ({ x: p.x, y: p.y });

/** Graveyard (or unknown) and exile departures burn away; bounces fly. */
const dissolves = (to: BoardFXZone | undefined) => to === undefined || to === "graveyard" || to === "exile";

type Kind =
  | { kind: "arrive"; from: Point; to: Place }
  | { kind: "depart"; from: Place; to: Point; destination?: BoardFXZone }
  | { kind: "cast"; at: Point; big: boolean }
  | { kind: "strike"; from: Place; to: Point }
  | { kind: "pulled"; from: Place; to: Place };

interface Placement { x: number; y: number; w: number; h: number; scale: number; rotation: number; opacity: number; lift: number; lean: number; full?: boolean; burn?: number }

function placement(kind: Kind, p: number, duration: number): Placement | undefined {
  switch (kind.kind) {
    case "arrive": {
      const landing = BoardFXScheduler.arrivalFlightFraction;
      if (p >= landing) return undefined;
      const t = easeOut(p / landing);
      const at = arc(kind.from, centre(kind.to), 60, t);
      return { ...at, w: kind.to.w, h: kind.to.h, scale: 1.35 - 0.35 * t, rotation: -8 * (1 - t), opacity: Math.min(1, (p / landing) * 4), lift: 1 - t, lean: t };
    }
    case "depart": {
      if (dissolves(kind.destination)) {
        // Burn away in place with a slight lift.
        const t = easeOut(p);
        return { x: kind.from.x, y: kind.from.y - 10 * t, w: kind.from.w, h: kind.from.h, scale: (kind.from.s ?? 1) * (1 + 0.06 * t), rotation: kind.from.r ?? 0,
          opacity: 1, lift: t * 0.3, lean: 1, burn: p };
      }
      const t = p * p;
      const at = arc(centre(kind.from), kind.to, 30, t);
      return { ...at, w: kind.from.w, h: kind.from.h, scale: 1 - 0.6 * t, rotation: 14 * t, opacity: 1 - t, lift: 0.4, lean: 1 - t };
    }
    case "cast": {
      const w = kind.big ? 166 : 150; const h = kind.big ? 232 : 210;
      const exit = 1 - Math.min(0.3, 0.35 / duration);
      const rise = Math.min(0.3, 0.42 / duration);
      if (p < rise) {
        const t = easeOut(p / rise);
        return { ...kind.at, w, h, scale: 0.45 + 0.6 * t, rotation: -8 * (1 - t), opacity: Math.min(1, (p / rise) * 3), lift: t, lean: 0, full: true };
      }
      if (p < exit) {
        const hold = (p - rise) / Math.max(0.001, exit - rise);
        return { x: kind.at.x, y: kind.at.y + Math.sin(Math.min(hold, 1) * Math.PI * 2) * 3, w, h, scale: 1.05 - 0.05 * Math.min(hold, 1), rotation: 0, opacity: 1, lift: 1, lean: 0, full: true };
      }
      const t = easeIn((p - exit) / (1 - exit));
      return { ...kind.at, w, h, scale: 1 - 0.45 * t, rotation: 0, opacity: 1 - t, lift: 1 - t, lean: 0, full: true };
    }
    case "strike": {
      const home = centre(kind.from);
      const dx = kind.to.x - home.x; const dy = kind.to.y - home.y;
      const distance = Math.max(1, Math.hypot(dx, dy));
      const unit = { x: dx / distance, y: dy / distance };
      const windup = 0.15; const impact = BoardFXScheduler.strikeImpactFraction; const recoil = impact + 0.1;
      const reach = Math.max(0, distance - kind.from.h * 0.45);
      const hit = { x: home.x + unit.x * reach, y: home.y + unit.y * reach };
      const back = { x: home.x - unit.x * 14, y: home.y - unit.y * 14 };
      const tilt = unit.x >= 0 ? 1 : -1;
      const base = { w: kind.from.w, h: kind.from.h, opacity: 1, lean: 1 };
      if (p < windup) { const t = easeOut(p / windup); return { ...base, ...lerp(home, back, t), scale: 1 + 0.1 * t, rotation: -5 * tilt * t, lift: t }; }
      if (p < impact) {
        const t = easeIn((p - windup) / (impact - windup));
        return { ...base, ...lerp(back, hit, t), scale: 1.1 + 0.08 * t, rotation: -5 * tilt * (1 - t) + 6 * tilt * t, lift: 1 };
      }
      if (p < recoil) return { ...base, ...hit, scale: 1.12, rotation: 6 * tilt, lift: 0.8 };
      const t = easeOut((p - recoil) / (1 - recoil));
      return { ...base, ...lerp(hit, home, t), scale: 1.12 - 0.12 * t, rotation: 6 * tilt * (1 - t), lift: 0.8 * (1 - t) };
    }
    case "pulled": {
      const hook = BoardFXScheduler.stealHookFraction; const land = BoardFXScheduler.stealLandingFraction;
      if (p >= land) return undefined;
      const u = Math.min(Math.max((p - hook) / (land - hook), 0), 1);
      const t = u * u * (3 - 2 * u);
      const bite = Math.min(Math.max((p - hook * 0.85) / 0.12, 0), 1);
      const jolt = Math.sin(bite * Math.PI * 3) * 4 * (1 - t);
      const lean = (kind.to.x >= kind.from.x ? 7 : -7) * Math.sin(t * Math.PI);
      const at = arc(centre(kind.from), centre(kind.to), 24, t);
      return { x: at.x + jolt, y: at.y, w: kind.from.w + (kind.to.w - kind.from.w) * t, h: kind.from.h + (kind.to.h - kind.from.h) * t,
        scale: 1 + 0.1 * Math.sin(t * Math.PI), rotation: lean, opacity: 1, lift: Math.sin(t * Math.PI), lean: 1 };
    }
  }
}

export interface BoardFXOverlayProps {
  active: ActiveBoardFX[];
  subjects: Map<string, ZoneCard>;
  /** Where each card lies now, or lay before it left (board points). */
  rect(id: string): Place | undefined;
  anchors: FXAnchors;
  frames: boolean;
  /** Objects on the stack now: a spell the stack card never showed is shown there only with nothing else on it. */
  stackIDs: Set<string>;
  /** The board's height in points, and how many device pixels a point takes (for a sharp canvas). */
  height: number;
  pixelRatio: number;
  /** Where a stolen card was before it moved. */
  grabbed(id: string): Place | undefined;
}

/** Effects decorate the board: one that fails drops out for the rest of the game, and the game goes on. */
export class FXBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  componentDidCatch(error: unknown) { console.warn("board effects stopped", error); }
  render() { return this.state.failed ? null : this.props.children; }
}

export function BoardFXOverlay({ active, subjects, rect, anchors, frames, stackIDs, height, pixelRatio, grabbed }: BoardFXOverlayProps) {
  const [now, setNow] = useState(fxNow);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  // The marks between the flights, painted every frame while effects play (BoardFXOverlay's Canvas).
  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;
    const ratio = Math.max(1, Math.min(3, pixelRatio));
    if (canvas.width !== Math.round(STAGE.width * ratio) || canvas.height !== Math.round(height * ratio)) {
      canvas.width = Math.round(STAGE.width * ratio); canvas.height = Math.round(height * ratio);
    }
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, STAGE.width, height);
    const box = (place: Place | undefined) => place && { x: place.x - place.w / 2, y: place.y - place.h / 2, w: place.w, h: place.h };
    for (const fx of active) {
      const elapsed = now - fx.start - fx.scheduled.delay;
      if (elapsed < 0 || elapsed > fx.scheduled.duration) continue;
      // A mark that cannot be drawn (a degenerate shape) is skipped; effects never stop the game.
      try {
        paint(ctx, fx.scheduled, elapsed / fx.scheduled.duration, {
          rect: (id) => box(rect(id)), player: anchors.player, stack: anchors.stack, viewerID: anchors.viewerID, subjects, grabbed: (id) => box(grabbed(id)),
        });
      } catch (error) {
        ctx.restore();
        console.warn("board effect skipped", error);
      }
    }
  });
  const running = active.some((fx) => fx.start + fx.scheduled.end > now - 0.05);
  useEffect(() => {
    if (!running) return;
    let frame = 0;
    const step = () => { setNow(fxNow()); frame = requestAnimationFrame(step); };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [running, active.length]);

  const flights: { id: number; kind: Kind; card: ZoneCard; p: number; duration: number }[] = [];
  for (const fx of active) {
    const scheduled = fx.scheduled;
    if (!scheduled.usesMotion) continue;
    const elapsed = now - fx.start - scheduled.delay;
    if (elapsed < 0 || elapsed > scheduled.duration) continue;
    const p = elapsed / scheduled.duration;
    const event = scheduled.event;
    const card = subjects.get(subjectID(event));
    if (!card) continue;
    let kind: Kind | undefined;
    switch (event.type) {
      case "enteredBattlefield": {
        const to = rect(event.cardID);
        if (to) kind = { kind: "arrive", from: event.from === "stack" ? anchors.stack : anchors.hand(event.playerID), to };
        break;
      }
      case "leftBattlefield": {
        const from = rect(event.cardID);
        if (from) kind = { kind: "depart", from, to: event.to === "hand" ? anchors.hand(event.playerID) : anchors.player(event.playerID), destination: event.to };
        break;
      }
      case "spellCast":
        // The stack card carries every spell; one that never reached it (cast and resolved between two polls) is shown there.
        if (event.weight !== "ability" && stackIDs.size === 0) kind = { kind: "cast", at: anchors.stack, big: event.weight !== "spell" };
        break;
      case "combatStrike": {
        const from = rect(event.attackerID);
        const target = "card" in event.target ? rect(event.target.card) : anchors.player(event.target.player);
        if (from && target) kind = { kind: "strike", from, to: { x: target.x, y: target.y } };
        break;
      }
      case "controlChanged": {
        const to = rect(event.cardID);
        if (to) kind = { kind: "pulled", from: grabbed(event.cardID) ?? to, to };
        break;
      }
      default: break;
    }
    if (kind) flights.push({ id: scheduled.id, kind, card, p, duration: scheduled.duration });
  }

  return (
    <div className="afx" aria-hidden="true">
      <canvas ref={canvasRef} className="afxpaint" style={{ width: STAGE.width, height }} />
      {flights.map(({ id, kind, card, p, duration }) => {
        const at = placement(kind, p, duration);
        if (!at) return null;
        const left = at.x - at.w / 2;
        const leanStyle: React.CSSProperties | undefined = at.lean > 0
          ? { transform: `perspective(${LEAN.distance.toFixed(0)}px) rotateX(${(LEAN.pitch * at.lean).toFixed(2)}deg)`, transformOrigin: `${(LEAN.centerX - left).toFixed(1)}px 50%` }
          : undefined;
        const burn = at.burn;
        const exile = kind.kind === "depart" && kind.destination === "exile";
        return (
          <div key={id} className={`acard fxflight ${burn !== undefined ? (exile ? "burn exile" : "burn") : ""}`}
            style={{ width: at.w, height: at.h, fontSize: at.w / 15, transform: `translate(${left.toFixed(1)}px,${(at.y - at.h / 2).toFixed(1)}px)`, opacity: at.opacity,
              zIndex: 700, ["--burn" as string]: burn ?? 0, ["--lift" as string]: at.lift }}>
            <div className="lean" style={leanStyle}>
              <div className="spin" style={{ transform: `rotate(${at.rotation.toFixed(2)}deg) scale(${at.scale.toFixed(3)})` }}>
                {at.full ? <Face name={card.card.name} showCost={false} /> : frames ? <Tile card={card} /> : <PlainTile card={card} />}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
