/**
 * What the board's effects paint between the flights (iOS BoardFXPainter in BoardFXOverlay.swift and
 * BoardFXCardMoments.swift, Arena look): arrival glows and rising sparks, burn embers and the exile pillar, damage and
 * life numbers, counter pieces (the Blender sprite strips), stat changes, phasing bands, transform rings, the steal's
 * chain, attack and block marks, strike trails and impacts, and the first-strike label. Times come from the scheduler.
 */
import { BoardFXScheduler, type BoardFXTint, counterLabel, type CounterKind, type ScheduledBoardFX } from "../../core/boardEvents";
import type { ZoneCard } from "../../core/models";

type Ctx = CanvasRenderingContext2D;
export interface Rect { x: number; y: number; w: number; h: number }
interface Point { x: number; y: number }
const cx = (r: Rect) => r.x + r.w / 2;
const cy = (r: Rect) => r.y + r.h / 2;

export const TINT: Record<BoardFXTint, string> = {
  white: "rgb(255,242,199)", blue: "rgb(92,168,255)", black: "rgb(184,122,242)", red: "rgb(255,107,56)", green: "rgb(107,230,115)",
  multicolor: "rgb(255,204,82)", colorless: "rgb(209,214,230)",
};
const GOLD = "rgb(255,204,92)";
const ATTACK_RED = "rgb(255,92,51)";
const BLOCK_STEEL = "rgb(140,199,255)";
const EXILE_CYAN = "rgb(184,230,255)";
const PHASE_VIOLET = "rgb(168,158,255)";
const BRASS_CHAIN = "rgb(219,168,82)";
const COUNTER_COLOR: Record<CounterKind, string> = { plusOne: "rgb(115,255,140)", minusOne: "rgb(199,128,255)", loyalty: "rgb(128,191,255)", other: GOLD };

export const easeOut = (t: number) => 1 - Math.pow(1 - Math.min(Math.max(t, 0), 1), 3);
export const easeIn = (t: number) => Math.pow(Math.min(Math.max(t, 0), 1), 2.2);
/** 0 → 1 → 0 envelope over progress with linear fades. */
export const fadeWindow = (p: number, fadeIn: number, fadeOut: number) =>
  p < fadeIn ? Math.max(0, p / fadeIn) : p > fadeOut ? Math.max(0, 1 - (p - fadeOut) / Math.max(0.001, 1 - fadeOut)) : 1;
const MASK64 = (1n << 64n) - 1n;
/**
 * Deterministic 0..1 noise, so particles need no stored state: BoardFXPainter.noise's 64-bit mix exactly, so particles
 * fall where they do on iOS. (A 32-bit version went negative after its last XOR and drew a negative radius.)
 */
export function noise(seed: number, index: number, salt: number): number {
  let x = ((BigInt(seed) * 73856093n) ^ (BigInt(index) * 19349663n) ^ (BigInt(salt) * 83492791n)) & MASK64;
  x ^= x >> 33n; x = (x * 0xff51afd7ed558ccdn) & MASK64; x ^= x >> 33n; x = (x * 0xc4ceb9fe1a85ec53n) & MASK64; x ^= x >> 33n;
  return Number(x % 10000n) / 10000;
}

function withAlpha(color: string, alpha: number) {
  return color.replace("rgb(", "rgba(").replace(")", `,${Math.max(0, Math.min(1, alpha))})`);
}
function roundRect(ctx: Ctx, r: Rect, radius: number) {
  ctx.beginPath();
  ctx.roundRect(r.x, r.y, r.w, r.h, Math.min(radius, r.w / 2, r.h / 2));
}

export function sparks(ctx: Ctx, rect: Rect, color: string, count: number, p: number, seed: number, style: "rise" | "fall" | "burst") {
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  const t = p * 0.9;
  for (let i = 0; i < count; i++) {
    const ox = rect.x + rect.w * noise(seed, i, 1); const oy = rect.y + rect.h * noise(seed, i, 2);
    const speed = 40 + 90 * noise(seed, i, 3);
    const angle = style === "rise" ? -Math.PI / 2 + (noise(seed, i, 4) - 0.5) * 0.9 : style === "fall" ? Math.PI / 2 + (noise(seed, i, 4) - 0.5) * 1.4 : noise(seed, i, 4) * 2 * Math.PI;
    const gravity = style === "rise" ? -30 : style === "fall" ? 120 : 60;
    const x = ox + Math.cos(angle) * speed * t; const y = oy + Math.sin(angle) * speed * t + gravity * t * t;
    const radius = (1.2 + 2.2 * noise(seed, i, 5)) * (1 - p * 0.6);
    ctx.globalAlpha = (1 - p) * (0.6 + 0.4 * noise(seed, i, 6));
    ctx.fillStyle = color;
    ctx.beginPath(); ctx.arc(x, y, Math.max(0.1, radius), 0, Math.PI * 2); ctx.fill();
  }
  ctx.restore();
}

export function shockwave(ctx: Ctx, at: Point, color: string, maxRadius: number, p: number) {
  if (p >= 1) return;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = 1 - p;
  ctx.strokeStyle = color; ctx.lineWidth = 1 + 5 * (1 - p);
  ctx.beginPath(); ctx.arc(at.x, at.y, Math.max(0, 8 + (maxRadius - 8) * easeOut(p)), 0, Math.PI * 2); ctx.stroke();
  ctx.restore();
}

export function flash(ctx: Ctx, rect: Rect, color: string, p: number) {
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = 0.5 * (1 - p);
  ctx.fillStyle = color;
  roundRect(ctx, rect, 6); ctx.fill();
  ctx.restore();
}

export function number(ctx: Ctx, value: string, at: Point, color: string, size: number, p: number, motion: boolean) {
  const pop = motion && p < 0.18 ? 1 + 0.45 * (1 - p / 0.18) : 1;
  const rise = motion ? -34 * easeOut(p) : -8 * p;
  ctx.save();
  ctx.globalAlpha = p > 0.65 ? (1 - p) / 0.35 : 1;
  ctx.translate(at.x, at.y + rise);
  ctx.scale(pop, pop);
  ctx.font = `900 ${size}px ui-rounded, "SF Pro Rounded", system-ui, sans-serif`;
  ctx.textAlign = "center"; ctx.textBaseline = "middle";
  ctx.fillStyle = "rgba(0,0,0,.8)"; ctx.fillText(value, 1.5, 2);
  ctx.fillStyle = color; ctx.fillText(value, 0, 0);
  ctx.restore();
}

export function arrivalGlow(ctx: Ctx, rect: Rect, color: string, p: number, motion: boolean) {
  const grow = motion ? 14 * easeOut(p) : 0;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = 1 - p;
  ctx.strokeStyle = color; ctx.lineWidth = 1 + 3 * (1 - p);
  roundRect(ctx, { x: rect.x - grow, y: rect.y - grow, w: rect.w + 2 * grow, h: rect.h + 2 * grow }, 8 + grow / 2); ctx.stroke();
  ctx.globalAlpha = 0.35 * (1 - p);
  ctx.fillStyle = color;
  roundRect(ctx, rect, 6); ctx.fill();
  ctx.restore();
}

function slash(ctx: Ctx, rect: Rect, color: string, p: number) {
  if (p >= 0.6) return;
  const q = p / 0.6;
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = 1 - q;
  ctx.strokeStyle = color; ctx.lineWidth = 2.5; ctx.lineCap = "round";
  for (const offset of [-8, 0, 8]) {
    const sx = rect.x + 4 + offset; const sy = rect.y + 4;
    const ex = rect.x + rect.w - 4 + offset; const ey = rect.y + rect.h - 4;
    const k = easeOut(q * 1.6);
    ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(sx + (ex - sx) * k, sy + (ey - sy) * k); ctx.stroke();
  }
  ctx.restore();
}

function link(ctx: Ctx, a: Rect, b: Rect, color: string, p: number) {
  const reach = easeOut(p / 0.35);
  const s = { x: cx(a), y: cy(a) }; const e = { x: cx(b), y: cy(b) };
  const end = { x: s.x + (e.x - s.x) * reach, y: s.y + (e.y - s.y) * reach };
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = fadeWindow(p, 0.15, 0.7);
  ctx.lineCap = "round";
  ctx.strokeStyle = withAlpha(color, 0.35); ctx.lineWidth = 9;
  ctx.beginPath(); ctx.moveTo(s.x, s.y); ctx.lineTo(end.x, end.y); ctx.stroke();
  ctx.strokeStyle = color; ctx.lineWidth = 2.5; ctx.setLineDash([7, 5]); ctx.lineDashOffset = p * 60;
  ctx.beginPath(); ctx.moveTo(s.x, s.y); ctx.lineTo(end.x, end.y); ctx.stroke();
  ctx.restore();
}

function trail(ctx: Ctx, from: Point, to: Point, color: string, p: number) {
  const head = easeIn(p) * 0.82; const tail = Math.max(0, head - 0.3);
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = 0.8; ctx.lineCap = "round";
  const a = { x: from.x + (to.x - from.x) * tail, y: from.y + (to.y - from.y) * tail };
  const b = { x: from.x + (to.x - from.x) * head, y: from.y + (to.y - from.y) * head };
  ctx.strokeStyle = withAlpha(color, 0.4); ctx.lineWidth = 18;
  ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,.7)"; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
  ctx.restore();
}

function banner(ctx: Ctx, title: string, at: Point, color: string, p: number) {
  const fade = fadeWindow(p, 0.08, 0.82);
  if (fade <= 0) return;
  ctx.save();
  ctx.globalAlpha = fade;
  ctx.font = "800 16px Georgia, 'Source Serif 4', serif";
  const w = ctx.measureText(title).width + 28; const h = 30;
  roundRect(ctx, { x: at.x - w / 2, y: at.y - h / 2, w, h }, 12);
  ctx.fillStyle = "rgba(0,0,0,.78)"; ctx.fill();
  ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.stroke();
  ctx.fillStyle = "#fff"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
  ctx.fillText(title, at.x, at.y + 1);
  ctx.restore();
}

/** The Blender sprite strips: twelve square frames side by side. */
const sprites = new Map<string, HTMLImageElement>();
function sprite(ctx: Ctx, name: string, frame: number, rect: Rect, alpha = 1) {
  if (alpha <= 0.01 || rect.w <= 1 || typeof Image === "undefined") return;
  let image = sprites.get(name);
  if (!image) { image = new Image(); image.src = `/generated/fx/${name}.png`; sprites.set(name, image); }
  if (!image.complete || image.naturalWidth === 0) return;
  const frames = 12; const index = ((frame % frames) + frames) % frames; const side = image.naturalHeight;
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.drawImage(image, index * side, 0, side, side, rect.x, rect.y, rect.w, rect.h);
  ctx.restore();
}
const SPRITE: Record<CounterKind, string> = { plusOne: "tavern-fx-counter-plus", minusOne: "tavern-fx-counter-minus", loyalty: "tavern-fx-counter-loyalty", other: "tavern-fx-counter-coin" };
function bounce(t: number) {
  const x = Math.min(Math.max(t, 0), 1);
  if (x < 0.6) return easeIn(x / 0.6);
  const k = (x - 0.6) / 0.4;
  return 1 - 0.18 * Math.sin(k * Math.PI) * (1 - k);
}

function counterMoment(ctx: Ctx, kind: CounterKind, delta: number, rect: Rect, p: number, motion: boolean, seed: number) {
  const color = COUNTER_COLOR[kind];
  const side = Math.min(rect.w * 0.5, 46);
  const rest = { x: rect.x + rect.w - side * 0.42, y: rect.y + side * 0.5 };
  const label = counterLabel(kind, delta);
  const box = (s: number, y = rest.y) => ({ x: rest.x - s / 2, y: y - s / 2, w: s, h: s });
  if (!motion) {
    sprite(ctx, SPRITE[kind], 0, box(side), fadeWindow(p, 0.15, 0.7));
    number(ctx, label, { x: rest.x, y: rest.y + side * 0.55 }, color, 18, p, false);
    return;
  }
  const impact = 0.42;
  if (delta > 0) {
    const fall = bounce(p / impact);
    const y = rest.y - (1 - fall) * (rect.h * 0.9 + 30);
    const turn = p < impact ? Math.floor(easeOut(p / impact) * 24) : 0;
    const scale = p < impact ? 0.7 + 0.3 * fall : 1 + 0.12 * Math.max(0, 1 - (p - impact) / 0.12);
    sprite(ctx, SPRITE[kind], turn, box(side * scale, y), p > 0.82 ? (1 - p) / 0.18 : 1);
    if (p >= impact) {
      const q = (p - impact) / (1 - impact);
      shockwave(ctx, rest, color, side * 1.1, Math.min(1, q * 1.6));
      sparks(ctx, box(side), color, 12, q, seed, "burst");
      if (kind === "minusOne") { flash(ctx, rect, withAlpha(color, 0.7), q); shockwave(ctx, { x: cx(rect), y: cy(rect) }, withAlpha(color, 0.7), rect.w * 0.8, q); }
      number(ctx, label, { x: rest.x, y: rest.y + side * 0.6 }, color, 22, q, true);
    }
  } else {
    const q = easeOut(p);
    sprite(ctx, SPRITE[kind], Math.floor(q * 12), box(side * (1 - 0.35 * q), rest.y - q * 46), 1 - p);
    number(ctx, label, { x: rest.x, y: rest.y + side * 0.6 }, withAlpha(color, 0.85), 20, p, true);
  }
}

function statsMoment(ctx: Ctx, power: number, toughness: number, rect: Rect, p: number, motion: boolean) {
  const signed = (v: number) => (v >= 0 ? `+${v}` : `${v}`);
  const total = power + toughness;
  const color = total > 0 ? "rgb(115,255,140)" : total < 0 ? "rgb(199,128,255)" : GOLD;
  shockwave(ctx, { x: rect.x + rect.w - 12, y: rect.y + rect.h - 12 }, color, motion ? 34 : 20, Math.min(1, p * 1.5));
  if (motion) arrivalGlow(ctx, rect, withAlpha(color, 0.6), Math.min(1, p * 1.3), false);
  number(ctx, `${signed(power)}/${signed(toughness)}`, { x: cx(rect), y: cy(rect) }, color, 22, p, motion);
}

function phaseMoment(ctx: Ctx, out: boolean, rect: Rect, p: number, motion: boolean, seed: number) {
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  roundRect(ctx, { x: rect.x - 4, y: rect.y - 4, w: rect.w + 8, h: rect.h + 8 }, 10); ctx.clip();
  const fade = fadeWindow(p, 0.12, 0.7);
  const bands = motion ? 4 : 2;
  for (let i = 0; i < bands; i++) {
    const phase = (p * 1.6 + i / bands) % 1;
    const y = out ? rect.y + rect.h * phase : rect.y + rect.h - rect.h * phase;
    const gradient = ctx.createLinearGradient(0, y - 6, 0, y + 6);
    gradient.addColorStop(0, withAlpha(PHASE_VIOLET, 0)); gradient.addColorStop(0.5, PHASE_VIOLET); gradient.addColorStop(1, withAlpha(PHASE_VIOLET, 0));
    ctx.globalAlpha = 0.55 * fade; ctx.fillStyle = gradient;
    ctx.fillRect(rect.x - 4, y - 6, rect.w + 8, 12);
  }
  ctx.restore();
  if (motion) {
    shockwave(ctx, { x: cx(rect), y: cy(rect) }, withAlpha(PHASE_VIOLET, 0.8), rect.w * 0.9, out ? p : 1 - p);
    sparks(ctx, rect, PHASE_VIOLET, 14, p, seed, out ? "rise" : "fall");
  }
}

function exileMoment(ctx: Ctx, rect: Rect, p: number, motion: boolean, elapsed: number, seed: number) {
  const fade = fadeWindow(p, 0.1, 0.65);
  const height = rect.h * (motion ? 2.6 : 1.4) * easeOut(Math.min(1, p / 0.35));
  const pillar = { x: cx(rect) - rect.w * 0.38, y: rect.y + rect.h - height, w: rect.w * 0.76, h: height };
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.filter = "blur(6px)";
  ctx.globalAlpha = 0.75 * fade;
  const gradient = ctx.createLinearGradient(0, pillar.y, 0, pillar.y + pillar.h);
  gradient.addColorStop(0, withAlpha(EXILE_CYAN, 0)); gradient.addColorStop(0.6, EXILE_CYAN); gradient.addColorStop(1, "#fff");
  ctx.fillStyle = gradient;
  roundRect(ctx, pillar, pillar.w / 2); ctx.fill();
  ctx.restore();
  if (!motion) return;
  const ring = rect.w * 1.7;
  ctx.save(); ctx.globalCompositeOperation = "lighter";
  sprite(ctx, "tavern-fx-exile-ring", Math.floor(elapsed * 16), { x: cx(rect) - ring / 2, y: rect.y + rect.h - ring * 0.62, w: ring, h: ring }, fade);
  ctx.restore();
  sparks(ctx, rect, EXILE_CYAN, 18, p, seed + 31, "rise");
}

function chainMoment(ctx: Ctx, taker: Point, grab: Rect, rect: Rect, p: number, motion: boolean, seed: number) {
  const hook = BoardFXScheduler.stealHookFraction; const land = BoardFXScheduler.stealLandingFraction;
  const g = { x: cx(grab), y: cy(grab) };
  let end: Point;
  if (p < hook) { const k = easeOut(p / hook); end = { x: taker.x + (g.x - taker.x) * k, y: taker.y + (g.y - taker.y) * k }; }
  else {
    const u = Math.min(Math.max((p - hook) / (land - hook), 0), 1); const t = u * u * (3 - 2 * u);
    const to = { x: cx(rect), y: cy(rect) };
    const c = { x: (g.x + to.x) / 2, y: Math.min(g.y, to.y) - 24 };
    end = { x: (1 - t) ** 2 * g.x + 2 * (1 - t) * t * c.x + t * t * to.x, y: (1 - t) ** 2 * g.y + 2 * (1 - t) * t * c.y + t * t * to.y };
  }
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  ctx.globalAlpha = p < land ? 1 : Math.max(0, 1 - (p - land) / 0.16);
  ctx.lineCap = "round";
  ctx.strokeStyle = withAlpha(BRASS_CHAIN, 0.35); ctx.lineWidth = 10;
  ctx.beginPath(); ctx.moveTo(taker.x, taker.y); ctx.lineTo(end.x, end.y); ctx.stroke();
  ctx.setLineDash([9, 5]);
  ctx.strokeStyle = BRASS_CHAIN; ctx.lineWidth = 4; ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,.55)"; ctx.lineWidth = 1.2; ctx.stroke();
  ctx.setLineDash([]);
  ctx.strokeStyle = BRASS_CHAIN; ctx.lineWidth = 2.5;
  ctx.beginPath(); ctx.arc(end.x, end.y, 6, 0, Math.PI * 2); ctx.stroke();
  ctx.restore();
  const bite = (p - hook * 0.85) / 0.22;
  if (motion && bite > 0 && bite < 1) sparks(ctx, grab, BRASS_CHAIN, 10, bite, seed, "burst");
  if (p > land) {
    const q = (p - land) / (1 - land);
    arrivalGlow(ctx, rect, BRASS_CHAIN, q, motion);
    if (motion) sparks(ctx, rect, GOLD, 14, q, seed + 1, "burst");
  }
}

function gather(ctx: Ctx, rect: Rect, color: string, count: number, p: number, seed: number) {
  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  const q = easeOut(Math.min(1, p / 0.7));
  for (let i = 0; i < count; i++) {
    const angle = noise(seed, i, 11) * 2 * Math.PI;
    const distance = (rect.w * 0.9 + 40 * noise(seed, i, 12)) * (1 - q);
    const r = 1.5 + 2.5 * noise(seed, i, 13);
    ctx.globalAlpha = fadeWindow(p, 0.1, 0.75); ctx.fillStyle = color;
    ctx.beginPath(); ctx.arc(cx(rect) + Math.cos(angle) * distance, cy(rect) + Math.sin(angle) * distance * 1.2, r, 0, Math.PI * 2); ctx.fill();
  }
  ctx.restore();
}

export interface PaintContext {
  rect(id: string): Rect | undefined;
  player(id: string): Point;
  stack: Point;
  viewerID?: string;
  subjects: Map<string, ZoneCard>;
  /** Where a stolen card was taken from. */
  grabbed(id: string): Rect | undefined;
}

/** One scheduled effect at progress `p` (BoardFXOverlay.draw, Arena look). */
export function paint(ctx: Ctx, fx: ScheduledBoardFX, p: number, k: PaintContext) {
  const event = fx.event;
  const motion = fx.usesMotion;
  const elapsed = p * fx.duration;
  switch (event.type) {
    case "spellCast": return; // the stack card plays its own landing
    case "enteredBattlefield": {
      const rect = k.rect(event.cardID);
      if (!rect) return;
      const flying = motion && k.subjects.has(event.cardID);
      const landing = flying ? BoardFXScheduler.landingFraction("plain") : 0;
      if (flying && p < landing) return;
      const glow = flying ? (p - landing) / (1 - landing) : p;
      const color = event.entrance === "commander" ? GOLD : TINT[event.tint];
      arrivalGlow(ctx, rect, color, glow, motion);
      if (motion && k.subjects.get(event.cardID)?.card.isToken === true) gather(ctx, rect, color, 20, glow, fx.id + 3);
      if (motion) {
        sparks(ctx, rect, color, event.entrance === "commander" ? 34 : 16, glow, fx.id, "rise");
        if (event.entrance === "commander") shockwave(ctx, { x: cx(rect), y: cy(rect) }, color, 150, glow);
      }
      return;
    }
    case "leftBattlefield": {
      const rect = k.rect(event.cardID);
      if (!rect) return;
      if (event.to === "exile") exileMoment(ctx, rect, p, motion, elapsed, fx.id);
      if (!(motion && k.subjects.has(event.cardID))) {
        ctx.save();
        ctx.globalAlpha = 0.7 * (1 - p);
        roundRect(ctx, rect, 6); ctx.fillStyle = "rgba(0,0,0,.55)"; ctx.fill(); ctx.strokeStyle = TINT[event.tint]; ctx.lineWidth = 2; ctx.stroke();
        ctx.restore();
      }
      if (motion) sparks(ctx, rect, event.to === "exile" ? EXILE_CYAN : "rgb(255,115,41)", 22, p, fx.id, event.to === "exile" ? "rise" : "fall");
      return;
    }
    case "damageMarked": {
      const rect = k.rect(event.cardID);
      if (!rect) return;
      flash(ctx, rect, "rgb(255,0,0)", p);
      if (motion) sparks(ctx, rect, "rgb(255,77,51)", 12, p, fx.id, "burst");
      number(ctx, `-${event.amount}`, { x: cx(rect), y: cy(rect) }, "rgb(255,82,71)", 26, p, motion);
      return;
    }
    case "countersChanged": { const rect = k.rect(event.cardID); if (rect) counterMoment(ctx, event.kind, event.delta, rect, p, motion, fx.id); return; }
    case "statsChanged": { const rect = k.rect(event.cardID); if (rect) statsMoment(ctx, event.power, event.toughness, rect, p, motion); return; }
    case "phased": { const rect = k.rect(event.cardID); if (rect) phaseMoment(ctx, event.out, rect, p, motion, fx.id); return; }
    case "transformed": {
      const rect = k.rect(event.cardID);
      if (!rect) return;
      arrivalGlow(ctx, rect, GOLD, p, motion);
      if (motion) { shockwave(ctx, { x: cx(rect), y: cy(rect) }, GOLD, rect.w, p); sparks(ctx, rect, GOLD, 12, p, fx.id, "burst"); }
      return;
    }
    case "controlChanged": {
      const rect = k.rect(event.cardID);
      if (rect) chainMoment(ctx, k.player(event.to), motion ? k.grabbed(event.cardID) ?? rect : rect, rect, p, motion, fx.id);
      return;
    }
    case "attackDeclared": {
      const rect = k.rect(event.cardID);
      if (!rect) return;
      arrivalGlow(ctx, rect, ATTACK_RED, p, motion);
      if (motion) { sparks(ctx, rect, TINT[event.tint], 10, p, fx.id, "burst"); slash(ctx, rect, ATTACK_RED, p); }
      return;
    }
    case "blockDeclared": {
      const blocker = k.rect(event.cardID);
      if (!blocker) return;
      arrivalGlow(ctx, blocker, BLOCK_STEEL, p, motion);
      const attacker = k.rect(event.attackerID);
      if (attacker) link(ctx, blocker, attacker, BLOCK_STEEL, p);
      return;
    }
    case "firstStrikeBeat": banner(ctx, "First strike", k.stack, ATTACK_RED, p); return;
    case "combatStrike": {
      const origin = k.rect(event.attackerID);
      const target = "card" in event.target ? k.rect(event.target.card) : undefined;
      const hit = target ? { x: cx(target), y: cy(target) } : "player" in event.target ? k.player(event.target.player) : undefined;
      if (!origin || !hit) return;
      const impact = BoardFXScheduler.strikeImpactFraction;
      if (motion && p > 0.15 && p < impact + 0.05) trail(ctx, { x: cx(origin), y: cy(origin) }, hit, TINT[event.tint], (p - 0.15) / (impact - 0.15));
      if (p >= impact) {
        const q = (p - impact) / (1 - impact);
        shockwave(ctx, hit, ATTACK_RED, motion ? 70 : 40, q);
        if (motion) sparks(ctx, { x: hit.x - 30, y: hit.y - 30, w: 60, h: 60 }, "rgb(255,191,89)", 20, q, fx.id, "burst");
      }
      return;
    }
    case "lifeChanged": {
      const at = k.player(event.playerID);
      const color = event.delta < 0 ? "rgb(255,77,66)" : "rgb(115,255,140)";
      number(ctx, event.delta < 0 ? `${event.delta}` : `+${event.delta}`, at, color, Math.min(64, 34 + Math.abs(event.delta) * 2.5), p, motion);
      return;
    }
  }
}
