/**
 * Battlefield tiles in the Walnut Tavern frames (TavernFrameKind in TavernSockets.kt): the card's
 * art crop in the frame's arched window, the frame on top, the name ribbon and the power and
 * toughness gems. Drawn once per look on a canvas the Arena board shows as the tile; its glow is a CSS
 * drop-shadow that traces the frame's alpha (the frame-outline glow, apps/web/src/ui/arena/arena.css).
 */
import { displayPower, displayToughness, isCreatureCard, type ZoneCard } from "../core/models";
import { loadCardImage, permitsArtLookup, tokenArtURL } from "../ui/cardArt";

export type FrameKind = "creature" | "token" | "artifact" | "enchantment" | "land" | "spell";
export const TILE = { width: 330, height: 356 } as const;

const windows: Record<FrameKind, [number, number, number, number]> = {
  creature: [0.078, 0.156, 0.847, 0.75], token: [0.087, 0.142, 0.835, 0.762], artifact: [0.093, 0.164, 0.829, 0.728],
  enchantment: [0.084, 0.17, 0.829, 0.733], land: [0.09, 0.15, 0.82, 0.756], spell: [0.093, 0.164, 0.814, 0.736],
};

export const frameKind = (card: ZoneCard): FrameKind => {
  const identity = card.card;
  const type = identity.typeLine.toLowerCase();
  if (isCreatureCard(card)) return identity.isToken === true || type.includes("token") ? "token" : "creature";
  if (type.includes("land")) return "land";
  if (type.includes("artifact")) return "artifact";
  if (type.includes("enchantment")) return "enchantment";
  if (type.includes("instant") || type.includes("sorcery")) return "spell";
  return "creature";
};

const chrome = new Map<string, Promise<HTMLImageElement>>();
const tavernImage = (name: string) => {
  let pending = chrome.get(name);
  if (!pending) {
    pending = new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = reject;
      image.src = `/tavern/${name}.webp`;
    });
    chrome.set(name, pending);
  }
  return pending;
};

/** What a tile looks like; equal keys share one texture. */
export const tileKey = (card: ZoneCard) => {
  const counters = Object.entries(card.counters ?? {}).filter(([, n]) => n > 0).map(([k, n]) => `${k}${n}`).join(",");
  return [card.card.name, frameKind(card), displayPower(card) ?? "", displayToughness(card) ?? "", card.damage ?? 0, counters,
    card.card.isToken ? card.card.tokenArtwork?.name ?? "" : "", permitsArtLookup(card) ? "" : "hidden"].join("|");
};

const fitText = (ctx: CanvasRenderingContext2D, text: string, maxWidth: number, size: number) => {
  let fontSize = size;
  for (; fontSize > 12; fontSize -= 1) {
    ctx.font = `700 ${fontSize}px "Source Serif 4 Variable", Georgia, serif`;
    if (ctx.measureText(text).width <= maxWidth) break;
  }
  return fontSize;
};

/** Paints the tile now with what is loaded, then again as the art and frames arrive. */
export const paintTile = (canvas: HTMLCanvasElement, card: ZoneCard, onUpdate: () => void) => {
  const ctx = canvas.getContext("2d")!;
  const kind = frameKind(card);
  const [wx, wy, ww, wh] = windows[kind];
  const W = TILE.width; const H = TILE.height;
  let art: HTMLImageElement | undefined;
  let frame: HTMLImageElement | undefined;
  let ribbon: HTMLImageElement | undefined;
  let gems: [HTMLImageElement, HTMLImageElement] | undefined;

  const draw = () => {
    ctx.clearRect(0, 0, W, H);
    // Art window: the crop covers the arch; parchment until it arrives.
    const x = wx * W; const y = wy * H; const w = ww * W; const h = wh * H;
    ctx.save();
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, [w / 2, w / 2, 6, 6]);
    ctx.clip();
    if (art) {
      const scale = Math.max(w / art.width, h / art.height);
      const dw = art.width * scale; const dh = art.height * scale;
      ctx.drawImage(art, x + (w - dw) / 2, y + (h - dh) / 2.6, dw, dh);
    } else {
      const gradient = ctx.createLinearGradient(0, y, 0, y + h);
      gradient.addColorStop(0, "#5c3814"); gradient.addColorStop(1, "#29140b");
      ctx.fillStyle = gradient; ctx.fillRect(x, y, w, h);
    }
    ctx.restore();
    if (frame) ctx.drawImage(frame, 0, 0, W, H);
    const basicLand = kind === "land" && /basic/i.test(card.card.typeLine);
    if (!basicLand) {
      const ribbonH = W * (116 / 600);
      const cy = H * 0.72;
      if (ribbon) ctx.drawImage(ribbon, 0, cy - ribbonH / 2, W, ribbonH);
      ctx.fillStyle = "#3d1f0d";
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      const size = fitText(ctx, card.card.name, W * 0.6, 30);
      ctx.font = `700 ${size}px "Source Serif 4 Variable", Georgia, serif`;
      ctx.fillText(card.card.name, W / 2, cy - 4);
    }
    const power = displayPower(card); const toughness = displayToughness(card);
    if (gems && isCreatureCard(card) && power !== undefined && toughness !== undefined) {
      const gw = W * 0.27; const gh = gw * (138 / 120); const gy = H - gh - 2;
      ctx.drawImage(gems[0], -4, gy, gw, gh);
      ctx.drawImage(gems[1], W - gw + 4, gy, gw, gh);
      ctx.font = `900 46px "Source Serif 4 Variable", Georgia, serif`;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.lineWidth = 6; ctx.strokeStyle = "#000";
      const damaged = (card.damage ?? 0) > 0;
      for (const [text, cx, hurt] of [[power, gw / 2 - 4, false], [toughness, W - gw / 2 + 4, damaged]] as [string, number, boolean][]) {
        ctx.strokeText(text, cx, gy + gh / 2 + 2);
        ctx.fillStyle = hurt ? "#ffb4a4" : "#fff6e0";
        ctx.fillText(text, cx, gy + gh / 2 + 2);
      }
    }
    const counters = Object.entries(card.counters ?? {}).filter(([, n]) => n > 0);
    if (counters.length > 0) {
      const [name, count] = counters[0];
      const label = /\+1/.test(name) ? `+${count}` : /-1/.test(name) ? `−${count}` : String(count);
      ctx.beginPath(); ctx.arc(W - 40, 54, 30, 0, Math.PI * 2);
      ctx.fillStyle = /-1/.test(name) ? "#7a1f12" : "#127a2a"; ctx.fill();
      ctx.lineWidth = 5; ctx.strokeStyle = "#dba34c"; ctx.stroke();
      ctx.fillStyle = "#fff"; ctx.font = `900 30px "Source Serif 4 Variable", Georgia, serif`;
      ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(label, W - 40, 56);
    }
    onUpdate();
  };

  draw();
  const artName = card.card.isToken && card.card.tokenArtwork ? card.card.tokenArtwork.name : card.card.copySourceArtworkName ?? card.card.name;
  void Promise.all([tavernImage(`frame-${kind}`), tavernImage("ribbon"), tavernImage("gem-power"), tavernImage("gem-toughness")])
    .then(([f, r, p, t]) => { frame = f; ribbon = r; gems = [p, t]; draw(); }).catch(() => undefined);
  // A token's picture is the printing that matches it (tokenArtURL); a copy shows its source card.
  const token = card.card.isToken === true && !card.card.copySourceArtworkName ? card.card.tokenArtwork : undefined;
  const url = token ? tokenArtURL(token, "art_crop") : Promise.resolve(undefined);
  if (permitsArtLookup(card)) {
    void url.then((found) => (token && !found ? undefined : loadCardImage(artName, "art_crop", found)))
      .then((image) => { if (image) { art = image; draw(); } });
  }
};
