/**
 * A deck as Arena's deck box (iOS Menus/ArenaDeckBox.swift): a black box seen almost straight on, the commander's art on
 * its front under a lid band stamped MAGICMOBILE, a dark side with a clasp, the colours above a black name plate.
 * Choosing the deck opens the box: the lid lifts with the art on top, the front folds to half height with a lit lip, and
 * the commander card rises in front of the app's own card backs. Openness (0 shut, 1 open) animates as one CSS
 * property (`--o`), so every part moves together on the same spring.
 */
import { type CSSProperties, useState } from "react";
import { cardImageURL } from "../cardArt";
import { BrandMark } from "./BrandMark";
import { Pips } from "./kit";

export interface DeckBoxModel {
  /** The deck's selection id ("precon:…", "included:…", "local:…"). */
  id: string;
  name: string;
  commander?: string;
  colors: string[];
  /** For the hover title and screen readers: the bracket. */
  subtitle: string;
  /** A word on a shut box's corner ("PLAYING", "FIX"). */
  tag?: string;
}

/** The box's proportions from the reference: the front 1.34 times as wide as tall, a narrow side, a thin top. */
export function boxGeometry(width: number) {
  const side = width * 0.095, top = width * 0.035;
  const frontWidth = width - side, frontHeight = frontWidth / 1.34;
  return {
    width, side, top, frontWidth, frontHeight, boxHeight: top + frontHeight, lidBand: frontHeight * 0.1, cut: frontHeight * 0.48,
    rise: frontHeight * 0.36, plateHeight: Math.max(24, width * 0.17), plateOverlap: width * 0.05, pip: Math.max(13, width * 0.115),
  };
}

const TINTS: Record<string, string> = { W: "#eddba8", U: "#3375c7", B: "#5c4766", R: "#cc472e", G: "#388c52" };

/** A deck's colours as light through dark glass, standing in for art that hasn't loaded (ArenaColorGlass). */
export function ColorGlass({ colors }: { colors: string[] }) {
  const chosen = ["W", "U", "B", "R", "G"].filter((c) => colors.includes(c)).map((c) => TINTS[c]);
  const palette = chosen.length === 0 ? ["#66696f", "#292b30"] : chosen.length === 1 ? [chosen[0], `${chosen[0]}73`] : chosen;
  return <div className="mcolorglass"><i style={{ background: `linear-gradient(135deg, ${palette.join(", ")})` }} /></div>;
}

/**
 * A commander's art filling its frame (Scryfall's art crop, its sharpest art-only image), the deck's colours until it
 * loads. In a frame wider than the art, `focus` picks which band shows: 0 the top, 0.5 the middle, 1 the bottom (faces
 * usually sit in the upper third).
 */
export function DeckArt({ name, colors, focus }: { name?: string; colors: string[]; focus?: number }) {
  const [state, setState] = useState<"loading" | "ready" | "failed">(name ? "loading" : "failed");
  return (
    <div className="mdeckart">
      {state !== "ready" && <ColorGlass colors={colors} />}
      {name && state !== "failed" && (
        <img src={cardImageURL(name, "art_crop")} alt="" crossOrigin="anonymous" draggable={false} loading="lazy"
          style={{ opacity: state === "ready" ? 1 : 0, ...(focus !== undefined ? { objectPosition: `50% ${focus * 100}%` } : {}) }} onLoad={() => setState("ready")} onError={() => setState("failed")} />
      )}
    </div>
  );
}

/** The app's own card back for the cards in an open box: walnut under a gold frame line, the mark in an ember glow. */
function BoxCardBack({ style }: { style: CSSProperties }) {
  return <div className="mboxback" style={style}><i /><BrandMark size={100} /></div>;
}

export function DeckBox({ deck, selected = false, width = 120, onEdit }: { deck: DeckBoxModel; selected?: boolean; width?: number; onEdit?: () => void }) {
  const g = boxGeometry(width);
  const cardHeight = g.frontHeight * 1.12, cardWidth = cardHeight * 0.716;
  const vars = {
    "--o": selected ? 1 : 0, "--w": `${g.width}px`, "--side": `${g.side}px`, "--top": `${g.top}px`, "--fw": `${g.frontWidth}px`, "--fh": `${g.frontHeight}px`,
    "--bh": `${g.boxHeight}px`, "--band": `${g.lidBand}px`, "--cut": `${g.cut}px`, "--rise": `${g.rise}px`, "--ph": `${g.plateHeight}px`, "--po": `${g.plateOverlap}px`,
    "--ch": `${cardHeight}px`, "--cw": `${cardWidth}px`,
  } as CSSProperties;
  return (
    <div className={`mdeckbox ${selected ? "open" : ""}`} style={vars} title={deck.commander ? `${deck.name}, ${deck.commander}` : deck.name}
      role="img" aria-label={`${deck.commander ? `${deck.name}, ${deck.commander}` : deck.name}${deck.subtitle ? `. ${deck.subtitle}` : ""}`}>
      <div className="mbox">
        <div className="mboxwall" />
        <div className="mboxlid">
          <div className="mboxtop" />
          <div className="mboxband"><span style={{ fontSize: Math.max(5, g.lidBand * 0.62), letterSpacing: g.lidBand * 0.18 }}>MAGICMOBILE</span></div>
        </div>
        <div className="mboxlidart"><DeckArt name={deck.commander} colors={deck.colors} /></div>
        <div className="mboxinside">
          {([[-0.13, -5], [0.07, 3], [0.15, 6]] as const).map(([offset, angle]) => (
            <BoxCardBack key={offset} style={{ width: cardWidth * 0.84, height: cardHeight * 0.9, transform: `translateX(-50%) translateX(${g.frontWidth * offset}px) translateY(3px) rotate(${angle}deg)` }} />
          ))}
          <div className="mboxcommander" style={{ transform: `translateX(-50%) translateX(${-g.frontWidth * 0.06}px) translateY(${-g.rise * 0.1}px) rotate(-3deg)` }}>
            <ColorGlass colors={deck.colors} />
            {deck.commander && selected && <img src={cardImageURL(deck.commander, "normal")} alt="" crossOrigin="anonymous" draggable={false} loading="lazy"
              onError={(e) => { e.currentTarget.style.display = "none"; }} />}
          </div>
        </div>
        <div className="mboxfront">
          <DeckArt name={deck.commander} colors={deck.colors} />
          <i className="mboxshade" />
          <span className="mboxpips" style={{ bottom: g.plateOverlap + g.width * 0.025 }}><Pips colors={deck.colors} size={g.pip} /></span>
          <i className="mboxlip" />
        </div>
        <div className="mboxside"><i /></div>
        {deck.tag && !selected && <span className="mboxtag" style={{ top: g.top + g.lidBand + 4 }}>{deck.tag}</span>}
      </div>
      <NamePlate title={deck.name} selected={selected} width={width} onEdit={onEdit} />
    </div>
  );
}

/** The plate under a deck box: black, the name on one line, and Arena's pencil where the deck can be edited. */
export function NamePlate({ title, selected, width, onEdit }: { title: string; selected?: boolean; width: number; onEdit?: () => void }) {
  return (
    <div className={`mplate ${selected ? "on" : ""}`} style={{ width, height: boxGeometry(width).plateHeight, fontSize: Math.max(11, width * 0.098) }}>
      <span>{title}</span>
      {onEdit && (
        <button type="button" aria-label={`Edit ${title}`} onClick={(e) => { e.stopPropagation(); onEdit(); }}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20l1-4L16 5l3 3L8 19zM14.5 6.5l3 3" /></svg>
        </button>
      )}
    </div>
  );
}

/** Arena's "+" tile for a new deck: a dark rounded square with a glowing plus, as tall as a deck box. */
export function NewDeckBox({ width = 120 }: { width?: number }) {
  const g = boxGeometry(width);
  return (
    <div className="mnewdeck" style={{ width, height: g.boxHeight + g.plateHeight - g.plateOverlap }} role="img" aria-label="New deck">
      <i style={{ width: width - g.side * 0.5, borderRadius: width * 0.07 }}><b style={{ fontSize: width * 0.36 }}>+</b></i>
    </div>
  );
}
