/**
 * Where everything sits on the horizontal Arena board: the iOS Arena board's landscape layout (`ArenaLayout.landscape`
 * in apps/ios/MagicMobile/ArenaBoardModel.swift on claude/arena-mode, after the Duel Board Prototype and Caleb's calls
 * of 2026-10-20/21), on the 956 x 440 plate, filled from real snapshots. Pure functions of the snapshot, so a card keeps
 * one element as it moves between zones and glides.
 *
 * A desktop window is rarely 956 x 440, and it can be resized. As on iOS (`ArenaCanvas`: positions scale per axis, sizes
 * by the smaller scale), the board is always 956 points wide and as tall as the window's shape allows (440 to 717
 * points, 2.17:1 to 4:3): every y below is a point on the 440-point plate, stretched in proportion (`Geometry.ky`), and
 * cards grow a little with the extra room (`grow`). The plate is the same table rendered for the nearest shape
 * (public/arena), so it is never stretched by more than a few percent.
 */
import { isCreatureCard, type ZoneCard } from "../../core/models";

export const STAGE = { width: 956, height: 440 } as const;

/** The table rendered at several shapes (apps/web/README.md, "Any window shape"). */
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
  /** How much bigger cards, piles and medallions draw than on the 440-point plate. */
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

/** ArenaLayout.landscape, in plate points. Rectangles are { x, y, w, h } from their top-left corner. */
export const ARENA = {
  hand: { cx: 490, upY: 368, upPitch: 92, upSpan: 520, upDrop: 2.6, tilt: 3.5, maxTilt: 11, downY: 432, downPitch: 50, downSpan: 317,
    downDrop: 1.2, lift: 48, liftDown: 92, maxDrop: 14, upFloor: 437, card: { w: 93, h: 131 } },
  opponentHand: { x: 478, y: 4, card: { w: 36, h: 50 }, pitch: 30 },
  viewerMedallion: { x: 84, y: 402, d: 56 },
  opponentMedallion: { x: 478, y: 25, d: 50 },
  viewerPiles: { graveyard: { x: 147, y: 404 }, library: { x: 201, y: 404 }, exile: { x: 255, y: 404 }, size: { w: 42, h: 59 } },
  opponentPiles: { exile: { x: 652, y: 30 }, library: { x: 704, y: 30 }, graveyard: { x: 756, y: 30 }, size: { w: 36, h: 50 } },
  opponentLands: { x: 80, y: 54, w: 360, h: 66 }, viewerLands: { x: 80, y: 290, w: 360, h: 70 },
  opponentSupport: { x: 540, y: 54, w: 332, h: 66 }, viewerSupport: { x: 540, y: 290, w: 160, h: 70 },
  opponentSideY: 116, viewerSideY: 248, opponentCreatureY: 146, viewerCreatureY: 248, creatureLane: { left: 84, right: 872 },
  /** Tavern frames (Card Frames on) are nearly square; the reference game's cropped cards (off, the default) are wider than tall. */
  tile: { w: 66, h: 71 }, land: { w: 58, h: 62.5 },
  plainTile: { w: 84, h: 70 }, plainLand: { w: 68, h: 57 },
  stack: { x: 716, y: 60, w: 158, h: 222 },
  zoom: { x: 658, y: 197, w: 244, h: 359 },
  primary: { x: 708, y: 388, w: 176, h: 36 }, secondary: { x: 708, y: 335, w: 176, h: 37 },
  phaseStrip: { x: 708, w: 176, y: 368, raisedY: 314 },
  passAhead: { x: 890, y: 392, w: 40, h: 28 },
  menu: { x: 876, y: 23 }, log: { x: 842, y: 23 },
  floatingMana: { x: 60, y: 362, dx: 18 },
  captionY: 197,
} as const;
export const MULLIGAN = { cx: 478, y: 200, pitch: 104, w: 112, h: 157 };

/**
 * The table's camera (ArenaTableLean): cards lying on the table lean back by the plate's pitch, all converging on the
 * table's vanishing point under the board's centre line, as the rendered plate does.
 */
export const LEAN = {
  pitch: 22,
  /** The camera's distance: half the long side over tan 27° (a 35 mm lens across a 36 mm sensor). */
  distance: STAGE.width / 2 / Math.tan((27 * Math.PI) / 180),
  centerX: STAGE.width / 2,
} as const;

export interface Place {
  x: number; y: number; w: number; h: number; r?: number; s?: number; z: number;
  /** Lies on the table: leans back with the table's camera (battlefield, piles). Hand, stack and zoom stand flat. */
  lean?: boolean;
}

const sized = (size: { w: number; h: number }, grow: number) => ({ w: size.w * grow, h: size.h * grow });

const isCreature = (card: ZoneCard) => card.isCreaturePermanent ?? isCreatureCard(card);
const isLand = (card: ZoneCard) => /\bland\b/i.test(card.card.typeLine) && !isCreature(card);
/** ArenaFrontSection: creatures across the front row; planeswalkers, battles and sagas at its right edge; the rest in the back row. */
const section = (card: ZoneCard): "creatures" | "side" | "support" | "lands" => {
  if (isCreature(card)) return "creatures";
  if (/planeswalker|battle|saga/i.test(card.card.typeLine)) return "side";
  return isLand(card) ? "lands" : "support";
};
const sideRank = (card: ZoneCard) => (/planeswalker|battle/i.test(card.card.typeLine) ? 1 : 0);

/** ArenaRowFit's spacing: 8 points of padding at each end of a section, 4 between piles, 10 between sections. */
const ROW = { padding: 8, spacing: 4, gap: 10, minScale: 0.7 } as const;
/** How much wider than one card a pile of n same cards is (7 points of offset per extra card on a 66-point card). */
const pileUnits = (n: number) => 1 + (n - 1) * 0.11;

interface Pile { cards: ZoneCard[]; units: number }

/**
 * Same-name cards with the same tapped state share a pile (BattlefieldRow's grouping). Each name keeps its place in
 * XMage's order, as on iOS, with its untapped pile before its tapped one: tapping a land never moves another under the
 * pointer (sorting every untapped pile first put the next land where the tapped one had been).
 */
function pilesOf(cards: ZoneCard[]): Pile[] {
  const piles: (Pile & { key: string; name: string; tapped: boolean })[] = [];
  const place = new Map<string, number>();
  for (const card of cards) {
    if (!place.has(card.card.name)) place.set(card.card.name, place.size);
    const tapped = card.tapped === true;
    const key = card.card.name + (tapped ? "|tapped" : "");
    const pile = piles.find((p) => p.key === key);
    if (pile) pile.cards.push(card); else piles.push({ key, name: card.card.name, tapped, cards: [card], units: 1 });
  }
  for (const pile of piles) pile.units = pileUnits(pile.cards.length);
  return piles.sort((a, b) => place.get(a.name)! - place.get(b.name)! || Number(a.tapped) - Number(b.tapped));
}

const sectionWidth = (piles: Pile[], card: number, spacing: number = ROW.spacing) =>
  piles.length === 0 ? 0 : 2 * ROW.padding + piles.reduce((n, p) => n + p.units, 0) * card + (piles.length - 1) * spacing;

/**
 * The largest card (up to `maxCard`, down to 70% of it) at which the sections fit `width` side by side; below that
 * the spacing goes negative so the piles overlap instead of scrolling (a web board has no room to scroll a row).
 */
function fitRow(sections: Pile[][], width: number, maxCard: number): { card: number; spacing: number } {
  const filled = sections.filter((s) => s.length > 0);
  const units = filled.reduce((n, s) => n + s.reduce((m, p) => m + p.units, 0), 0);
  if (units === 0) return { card: maxCard, spacing: ROW.spacing };
  const fixed = filled.reduce((n, s) => n + 2 * ROW.padding + (s.length - 1) * ROW.spacing, 0) + (filled.length - 1) * ROW.gap;
  const card = Math.min(maxCard, (width - fixed) / units);
  if (card >= maxCard * ROW.minScale) return { card, spacing: ROW.spacing };
  const small = maxCard * ROW.minScale;
  const gaps = filled.reduce((n, s) => n + s.length - 1, 0);
  const left = width - filled.length * 2 * ROW.padding - (filled.length - 1) * ROW.gap - units * small;
  return { card: small, spacing: gaps > 0 ? left / gaps : ROW.spacing };
}

/** Lays piles from `left` (or centred on `center`) along a row at `y`; tapped cards tilt 12°. */
function layPiles(piles: Pile[], places: Map<string, Place>, at: { left?: number; center?: number }, y: number, card: { w: number; h: number },
  spacing: number, z: number, scale: number, fighting = 0) {
  const width = sectionWidth(piles, card.w, spacing);
  let x = (at.left ?? (at.center! - width / 2)) + ROW.padding;
  piles.forEach((pile, pi) => {
    const step = (card.w * (pile.units - 1)) / Math.max(1, pile.cards.length - 1);
    pile.cards.forEach((c, j) => {
      const inFight = c.isAttacking === true || (c.blocking?.length ?? 0) > 0;
      places.set(c.instanceId, {
        x: x + card.w / 2 + j * step, y: y - j * 2 + (inFight ? fighting : 0), ...card,
        r: c.tapped && !inFight ? 12 : 0, s: scale, z: (c.isAttacking ? 90 : z) + pi + j, lean: true,
      });
    });
    x += pile.units * card.w + spacing;
  });
}

/**
 * One player's permanents, the current reference game's way (ArenaFrontSection): creatures across the front row,
 * planeswalkers, battles and sagas standing at its right edge, lands in name piles from the left of the back row,
 * artifacts and enchantments in the back row's own section right of centre; an Aura or Equipment tucks behind what it
 * is attached to. Cards shrink as a row fills. `band` splits the top half between several opponents in a pod.
 */
export function battlefieldPlaces(cards: ZoneCard[], side: "me" | "opp", band = { index: 0, count: 1 }, geo: Geometry = BASE_GEOMETRY,
  frames = false): Map<string, Place> {
  const places = new Map<string, Place>();
  const far = side === "opp";
  const { ky, grow } = geo;
  const TILE = frames ? ARENA.tile : ARENA.plainTile;
  const LAND = frames ? ARENA.land : ARENA.plainLand;
  const ids = new Set(cards.map((c) => c.instanceId));
  const attached = cards.filter((c) => c.attachedToInstanceId && ids.has(c.attachedToInstanceId) && section(c) !== "creatures");
  const loose = cards.filter((c) => !attached.includes(c));
  const by = (kind: ReturnType<typeof section>) => loose.filter((c) => section(c) === kind);
  // A pod's opponents share the top half: each gets a slice of every lane.
  const slice = (left: number, right: number) => band.count > 1
    ? { left: left + ((right - left) * band.index) / band.count, right: left + ((right - left) * (band.index + 1)) / band.count }
    : { left, right };

  // Front row: creatures, and the side section at the right edge.
  const lane = slice(ARENA.creatureLane.left, ARENA.creatureLane.right);
  const creatures = pilesOf(by("creatures")).map((p) => ({ ...p, units: p.units + (attached.some((a) => p.cards.some((c) => c.instanceId === a.attachedToInstanceId)) ? 0.15 : 0) }));
  const sides = pilesOf(by("side").sort((a, b) => sideRank(a) - sideRank(b)));
  const maxTile = TILE.w * grow;
  const front = fitRow([creatures, sides], lane.right - lane.left, maxTile);
  const tile = { w: front.card, h: (front.card * TILE.h) / TILE.w };
  const sideWidth = sectionWidth(sides, tile.w, front.spacing);
  const creatureY = (far ? ARENA.opponentCreatureY : ARENA.viewerCreatureY) * ky;
  const fight = (far ? 4.5 : -4.5) * grow;
  const creatureRight = lane.right - (sideWidth > 0 ? sideWidth + ROW.gap : 0);
  layPiles(creatures, places, { center: (lane.left + creatureRight) / 2 }, creatureY, tile, front.spacing, 60, far ? 0.92 : 1, fight);
  layPiles(sides, places, { left: lane.right - sideWidth }, (far ? ARENA.opponentSideY : ARENA.viewerSideY) * ky, tile, front.spacing, 60, far ? 0.92 : 1);

  // Back row: lands from the left, support right of centre, each in its own lane.
  const landsLane = far ? ARENA.opponentLands : ARENA.viewerLands;
  const supportLane = far ? ARENA.opponentSupport : ARENA.viewerSupport;
  const maxLand = LAND.w * grow;
  for (const [kind, rect] of [["lands", landsLane], ["support", supportLane]] as const) {
    const piles = pilesOf(by(kind));
    const range = slice(rect.x, rect.x + rect.w);
    const fit = fitRow([piles], range.right - range.left, maxLand);
    const land = { w: fit.card, h: (fit.card * LAND.h) / LAND.w };
    layPiles(piles, places, { left: range.left }, (rect.y + rect.h / 2) * ky, land, fit.spacing, 30, far ? 0.94 : 1);
  }

  attached.forEach((card, i) => {
    const host = places.get(card.attachedToInstanceId!);
    if (!host) return;
    places.set(card.instanceId, {
      ...host, x: host.x + (9 + i * 4) * grow, y: host.y + ((far ? 9 : -9) - i * 3) * grow, r: card.tapped ? 12 : 0, z: host.z - 1 - i,
    });
  });
  return places;
}

/**
 * The hand (ArenaHandFanLayout): resting, it is tucked along the bottom edge with the cards' tops just under your lands;
 * raised (the pointer on it, as on Arena's desktop client), it fans up, the arc flattening as it grows and the whole fan
 * rising until its outer corners clear the floor. The card under the pointer pops up.
 */
export function handPlaces(ids: string[], up: boolean, hovered?: string, geo: Geometry = BASE_GEOMETRY,
  /** Resting, the fan stays between your piles and the controls corner (their edges, in board points). */
  between?: { left: number; right: number }): Map<string, Place> {
  const H = ARENA.hand;
  const places = new Map<string, Place>();
  const g = geo.handGrow;
  const card = sized(H.card, g);
  const n = ids.length;
  const room = between ? Math.max(0, between.right - between.left - card.w) : H.downSpan;
  const restX = between ? (between.left + between.right) / 2 : H.cx;
  const pitch = n > 1 ? (up ? Math.min(H.upPitch * g, H.upSpan / (n - 1)) : Math.min(H.downPitch * g, Math.min(H.downSpan, room) / (n - 1))) : 0;
  // The fan keeps its distance from the board's bottom edge as the board grows taller.
  const fromBottom = (y: number) => geo.height - (STAGE.height - y) * g;
  const edge = (n - 1) / 2;
  const drop = edge > 0 ? Math.min(H.upDrop, H.maxDrop / (edge * edge)) : 0;
  const edgeTilt = (Math.min(H.maxTilt, edge * H.tilt) * Math.PI) / 180;
  const reach = drop * edge * edge + (card.h / 2) * Math.cos(edgeTilt) + (card.w / 2) * Math.sin(edgeTilt);
  const rise = Math.max(0, fromBottom(H.upY) + reach - fromBottom(H.upFloor));
  ids.forEach((id, i) => {
    const off = i - edge;
    const x = (up ? H.cx : restX) + off * pitch;
    let place: Place = up
      ? { x, y: fromBottom(H.upY) - rise + drop * off * off, ...card, r: Math.max(-H.maxTilt, Math.min(H.maxTilt, off * H.tilt)), s: 1, z: 440 + i }
      : { x, y: fromBottom(H.downY) + off * off * H.downDrop, ...card, r: off * 1.8, s: 1, z: 200 + i };
    if (id === hovered) place = { ...place, y: place.y - (up ? H.lift : H.liftDown) * g, r: 0, s: up ? 1.24 : 1.04, z: 480 };
    places.set(id, place);
  });
  return places;
}

/** The opponent's hand: card backs fanned behind their medallion along the top edge (ArenaOpponentHandFan). */
export function opponentHandPlaces(count: number, band = { index: 0, count: 1 }, geo: Geometry = BASE_GEOMETRY): Place[] {
  const O = ARENA.opponentHand;
  const card = sized(O.card, geo.grow);
  const shown = Math.min(count, 12);
  const pitch = shown > 1 ? Math.max(O.pitch * geo.grow, (card.w * 1.8) / (shown - 1)) : 0;
  const cx = band.count > 1 ? 150 + (650 * (band.index + 0.5)) / band.count : O.x;
  return Array.from({ length: shown }, (_, i) => {
    const off = i - (shown - 1) / 2;
    return { x: cx + off * pitch, y: O.y * geo.grow - off * off * 0.9, ...card, r: 180 - off * 4, s: 1, z: 100 + i };
  });
}

/** The stack card on the right, under the opponent's piles; older objects lean in behind the top one. Index 0 is the top. */
export const stackPlace = (depth: number, geo: Geometry = BASE_GEOMETRY): Place => {
  const S = ARENA.stack;
  const size = sized(S, Math.min(geo.grow, 1.15));
  return { ...size, x: S.x + S.w / 2 - depth * 12, y: (S.y + S.h / 2) * geo.ky - depth * 10, r: 0, s: 1 - depth * 0.05, z: 300 - depth };
};

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

/** ArenaPileStack: how thick a pile of `count` cards stands, and how many slivers draw it. */
export function pileThickness(count: number, height: number) {
  const thickness = count > 0 ? Math.max(1.5, count * height * 0.0055) : 0;
  return { thickness, layers: Math.min(16, Math.round(thickness / 1.1)) };
}
