/**
 * Where everything sits on the horizontal Arena board: the Duel Board Prototype's landscape layout ("land": the
 * reference game's positions on the 956 x 440 Walnut Tavern plate, artifact T5NcAkjCThiA5hfd9Twwwu), filled from real
 * snapshots. Pure functions of the snapshot, so a card keeps one element as it moves between zones and glides.
 *
 * A desktop window is rarely 956 x 440, and it can be resized. The board is always 956 points wide and as tall as the
 * window's shape allows (440 to 717 points, 2.17:1 to 4:3): every y below is a point on the 440-point plate, stretched
 * in proportion (`Geometry.ky`), and cards grow a little with the extra room (`grow`). The plate is the same table
 * rendered for the nearest shape (public/arena), so it is never stretched by more than a few percent.
 */
import { isCreatureCard, type ZoneCard } from "../../core/models";

export const STAGE = { width: 956, height: 440 } as const;

/** The table rendered at several shapes (scripts: apps/web/README.md, "The Arena plates"). */
export const PLATES = [
  { src: "/arena/table.jpg", height: 440 },
  { src: "/arena/table-195.jpg", height: 490 },
  { src: "/arena/table-169.jpg", height: 538 },
  { src: "/arena/table-1610.jpg", height: 598 },
  { src: "/arena/table-43.jpg", height: 717 },
] as const;

export interface Geometry {
  /** The board's height in points (its width is always 956). */
  height: number;
  /** Plate points to board points, vertically. */
  ky: number;
  /** How much bigger tiles, piles and medallions draw than on the 440-point plate. */
  grow: number;
  /** Hand cards grow less: they already fan wide. */
  handGrow: number;
  plate: string;
  /** Points to CSS pixels, and where the board sits in the window. */
  scale: number;
  left: number;
  top: number;
}

/** The board for a window of this size: as tall as its shape allows, the nearest plate under it. */
export function geometry(width: number, height: number): Geometry {
  const tall = Math.min(717, Math.max(STAGE.height, (STAGE.width * height) / Math.max(1, width)));
  const scale = Math.min(width / STAGE.width, height / tall);
  const plate = PLATES.reduce((best, p) => (Math.abs(p.height - tall) < Math.abs(best.height - tall) ? p : best));
  const ky = tall / STAGE.height;
  return {
    height: tall, ky, grow: Math.min(1.35, 1 + (ky - 1) * 0.7), handGrow: Math.min(1.2, 1 + (ky - 1) * 0.4), plate: plate.src,
    scale, left: (width - STAGE.width * scale) / 2, top: (height - tall * scale) / 2,
  };
}

/** The 440-point plate, for tests and the first frame before the window is measured. */
export const BASE_GEOMETRY: Geometry = { height: 440, ky: 1, grow: 1, handGrow: 1, plate: PLATES[0].src, scale: 1, left: 0, top: 0 };

const sized = (size: { w: number; h: number }, grow: number) => ({ w: size.w * grow, h: size.h * grow });
/** How far battlefield cards lie back on the table (the reference's camera leans forward). */
export const TILT = 26;

export const POS = {
  stack: { x: 796, y: 171, w: 175, h: 250 }, zoom: { x: 658, y: 197, w: 244, h: 359 },
  libMe: { x: 222, y: 405 }, gyMe: { x: 174, y: 405 }, cmdMe: { x: 128, y: 405 },
  libOpp: { x: 629, y: 9 }, gyOpp: { x: 681, y: 9 }, cmdOpp: { x: 733, y: 9 },
  faceMe: { x: 478, y: 400 }, faceOpp: { x: 478, y: 25 }, handOpp: { x: 270, y: 10 },
} as const;
export const SIZE = { hand: { w: 93, h: 131 }, tile: { w: 66, h: 71 }, land: { w: 58, h: 62.5 }, pile: { w: 42, h: 59 }, opile: { w: 36, h: 50 } } as const;
/**
 * The hand. Raised, it is the prototype's fan. Resting, it follows Arena's desktop client rather than the phone: spread
 * between your piles and the corner plaques (pitch near a card's width) and tucked so the top of each card shows
 * (name, cost, art).
 */
const HAND = { cx: 476, upY: 368, upPitch: 92, upSpan: 555, drop: 2.6, tilt: 3.5, maxTilt: 11, downY: 428, downPitch: 62, downSpan: 300, downDrop: 0.8, downS: 0.92, lift: 48, liftDown: 70 };
const LANDS = { me: { x: 116, y: 325 }, opp: { x: 108, y: 90 }, step: 72, right: 690 };
const ROWS = { me: 248, opp: 146, pitch: 84, span: 430, cx: 478, left: 226, right: 655 };
export const MULLIGAN = { cx: 478, y: 200, pitch: 104, w: 112, h: 157 };
export const POOL = { x: 80, y: 372, dx: 18 };

export interface Place { x: number; y: number; w: number; h: number; r?: number; s?: number; tx?: number; z: number }

export const cardTransform = (p: Place) =>
  `translate(${(p.x - p.w / 2).toFixed(1)}px,${(p.y - p.h / 2).toFixed(1)}px) perspective(300px) rotateX(${p.tx ?? 0}deg) rotate(${p.r ?? 0}deg) scale(${p.s ?? 1})`;

const isCreature = (card: ZoneCard) => card.isCreaturePermanent ?? isCreatureCard(card);
/** The front row: creatures, planeswalkers and battles (what fights or gets attacked), as on the reference. */
const isFront = (card: ZoneCard) => isCreature(card) || /planeswalker|battle/i.test(card.card.typeLine);

/**
 * One player's permanents. Creatures, planeswalkers and battles stand in the front row near the middle; lands,
 * artifacts and enchantments lie in name groups in the back row (untapped groups first), as on the reference; auras
 * and equipment tuck behind what they are attached to. `band` splits the top half between several opponents.
 */
export function battlefieldPlaces(cards: ZoneCard[], side: "me" | "opp", band = { index: 0, count: 1 }, geo: Geometry = BASE_GEOMETRY): Map<string, Place> {
  const places = new Map<string, Place>();
  const { ky, grow } = geo;
  const tile = sized(SIZE.tile, grow);
  const land = sized(SIZE.land, grow);
  const far = side === "opp";
  const scale = far ? 0.92 : 1;
  const ids = new Set(cards.map((c) => c.instanceId));
  const attached = cards.filter((c) => c.attachedToInstanceId && ids.has(c.attachedToInstanceId) && !isFront(c));
  const loose = cards.filter((c) => !attached.includes(c));
  const front = loose.filter(isFront);
  const back = loose.filter((c) => !isFront(c));

  // A band of the table: the whole width for one opponent, a slice of it for each in a pod.
  const sliceLeft = (from: number, to: number) => from + ((to - from) * band.index) / band.count;
  const sliceRight = (from: number, to: number) => from + ((to - from) * (band.index + 1)) / band.count;

  const rowLeft = sliceLeft(far && band.count > 1 ? 120 : ROWS.left, far && band.count > 1 ? 690 : ROWS.right);
  const rowRight = sliceRight(far && band.count > 1 ? 120 : ROWS.left, far && band.count > 1 ? 690 : ROWS.right);
  const span = Math.min(ROWS.span, rowRight - rowLeft);
  const n = front.length;
  const pitch = n > 1 ? Math.min(ROWS.pitch * grow, span / (n - 1)) : 0;
  const width = (n - 1) * pitch;
  const center = band.count > 1 ? (rowLeft + rowRight) / 2 : Math.max(rowLeft + width / 2, Math.min(ROWS.cx, rowRight - width / 2));
  front.forEach((card, i) => {
    const fighting = card.isAttacking === true || (card.blocking?.length ?? 0) > 0;
    places.set(card.instanceId, {
      x: center + (i - (n - 1) / 2) * pitch, y: (far ? ROWS.opp : ROWS.me) * ky + (fighting ? (far ? 4.5 : -4.5) * grow : 0), ...tile,
      r: card.tapped && !fighting ? 12 : 0, tx: TILT, s: scale, z: card.isAttacking ? 90 : 60 + i,
    });
  });

  const groups: { key: string; cards: ZoneCard[] }[] = [];
  for (const card of back) {
    const key = card.card.name + (card.tapped ? "|tapped" : "");
    let group = groups.find((g) => g.key === key);
    if (!group) groups.push(group = { key, cards: [] });
    group.cards.push(card);
  }
  groups.sort((a, b) => Number(a.key.endsWith("|tapped")) - Number(b.key.endsWith("|tapped")));
  // A taller plate is drawn by the same leaning camera, so its far edge narrows more: their lands move inward.
  const origin = far ? { x: LANDS.opp.x + (ky - 1) * 55, y: LANDS.opp.y } : LANDS.me;
  const left = band.count > 1 ? sliceLeft(origin.x, LANDS.right) : origin.x;
  const right = band.count > 1 ? sliceRight(origin.x, LANDS.right) - land.w / 2 : LANDS.right;
  const step = LANDS.step * grow;
  const widths = groups.map((g) => step + (g.cards.length - 1) * 7 * grow);
  const total = widths.reduce((a, b) => a + b, 0) - (widths.length ? step : 0);
  const squeeze = total > right - left && total > 0 ? (right - left) / total : 1;
  let x = left + (grow - 1) * land.w * 0.4;
  groups.forEach((group, gi) => {
    group.cards.forEach((card, j) => places.set(card.instanceId, {
      x: x + j * 7 * grow * squeeze, y: origin.y * ky - j * 2 * grow, ...land, r: card.tapped ? 12 : 0, tx: TILT, s: far ? 0.94 : 1, z: 30 + j,
    }));
    x += widths[gi] * squeeze;
  });

  attached.forEach((card, i) => {
    const host = places.get(card.attachedToInstanceId!);
    if (!host) return;
    places.set(card.instanceId, { ...host, ...tile, x: host.x + (9 + i * 4) * grow, y: host.y + ((far ? 9 : -9) - i * 3) * grow, r: card.tapped ? 12 : 0, z: host.z - 1 - i });
  });
  return places;
}

/** The hand along the bottom edge: fanned up when it's yours to play, tucked low otherwise; the card under the pointer pops up. */
export function handPlaces(ids: string[], up: boolean, hovered?: string, geo: Geometry = BASE_GEOMETRY): Map<string, Place> {
  const places = new Map<string, Place>();
  const g = geo.handGrow;
  const size = sized(SIZE.hand, g);
  const n = ids.length;
  const pitch = n > 1 ? (up ? Math.min(HAND.upPitch * g, HAND.upSpan / (n - 1)) : Math.min(HAND.downPitch * g, HAND.downSpan / (n - 1))) : 0;
  // The fan keeps its distance from the board's bottom edge as the board grows taller.
  const fromBottom = (y: number) => geo.height - (STAGE.height - y) * g;
  ids.forEach((id, i) => {
    const off = i - (n - 1) / 2;
    const x = HAND.cx + off * pitch;
    let place: Place = up
      ? { x, y: fromBottom(HAND.upY) + HAND.drop * off * off, ...size, r: Math.max(-HAND.maxTilt, Math.min(HAND.maxTilt, off * HAND.tilt)), s: 1, z: 440 + i }
      : { x, y: fromBottom(HAND.downY) + off * off * HAND.downDrop, ...size, r: off * 1.2, s: HAND.downS, z: 200 + i };
    if (id === hovered) place = { ...place, y: place.y - (up ? HAND.lift : HAND.liftDown) * g, r: 0, s: up ? 1.24 : 1.04, z: 480 };
    places.set(id, place);
  });
  return places;
}

/** The opponent's hand: card backs fanned upside down along the top edge. */
export function opponentHandPlaces(count: number, band = { index: 0, count: 1 }, geo: Geometry = BASE_GEOMETRY): Place[] {
  const cx = band.count > 1 ? 150 + (520 * (band.index + 0.5)) / band.count : POS.handOpp.x;
  return Array.from({ length: Math.min(count, 12) }, (_, i) => {
    const off = i - (Math.min(count, 12) - 1) / 2;
    return { x: cx + off * 17 * geo.grow, y: POS.handOpp.y * geo.ky - off * off * 0.9, ...sized(SIZE.opile, geo.grow), r: 180 - off * 4, s: 1, z: 100 + i };
  });
}

/** The stack card on the right; older objects lean in behind the top one. Index 0 is the top. */
export const stackPlace = (depth: number, geo: Geometry = BASE_GEOMETRY): Place =>
  ({ ...POS.stack, ...sized(POS.stack, Math.min(geo.grow, 1.15)), x: POS.stack.x - depth * 12, y: POS.stack.y * geo.ky - depth * 10, r: 0, s: 1 - depth * 0.05, z: 300 - depth });

/** The opening hand, large in the middle of the table while the player decides whether to keep it. */
export function mulliganPlaces(ids: string[], geo: Geometry = BASE_GEOMETRY): Map<string, Place> {
  const places = new Map<string, Place>();
  const n = ids.length;
  const g = geo.handGrow;
  const pitch = n > 1 ? Math.min(MULLIGAN.pitch * g, 600 / (n - 1)) : 0;
  ids.forEach((id, i) => {
    const off = i - (n - 1) / 2;
    places.set(id, { x: MULLIGAN.cx + off * pitch, y: MULLIGAN.y * geo.ky + off * off * 2, w: MULLIGAN.w * g, h: MULLIGAN.h * g, r: off * 1.4, s: 1, z: 820 + i });
  });
  return places;
}

/** The reference's phase strip: the beginning, main 1, combat (opened up into its steps during combat), main 2, end. */
export type PhaseKey = "begin" | "main1" | "combat" | "attack" | "block" | "damage" | "endc" | "main2" | "end";
export function phaseStrip(step: string | undefined): { items: [PhaseKey, "dia" | "card" | "swords" | "sword" | "shield" | "burst"][]; current?: PhaseKey } {
  const raw = (step ?? "").toUpperCase();
  const current: PhaseKey | undefined =
    ["UNTAP", "UPKEEP", "DRAW"].includes(raw) ? "begin" : raw === "PRECOMBAT_MAIN" ? "main1" : raw === "BEGIN_COMBAT" ? "attack"
      : raw === "DECLARE_ATTACKERS" ? "attack" : raw === "DECLARE_BLOCKERS" ? "block" : raw.includes("COMBAT_DAMAGE") ? "damage"
        : raw === "END_COMBAT" ? "endc" : raw === "POSTCOMBAT_MAIN" ? "main2" : ["END_TURN", "CLEANUP"].includes(raw) ? "end" : undefined;
  const combat = current !== undefined && ["attack", "block", "damage", "endc"].includes(current);
  const items: ReturnType<typeof phaseStrip>["items"] = combat
    ? [["begin", "dia"], ["main1", "card"], ["attack", "sword"], ["block", "shield"], ["damage", "burst"], ["endc", "dia"], ["main2", "card"], ["end", "dia"]]
    : [["begin", "dia"], ["main1", "card"], ["combat", "swords"], ["main2", "card"], ["end", "dia"]];
  return { items, current };
}
