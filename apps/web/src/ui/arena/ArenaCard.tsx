/**
 * One card on the Arena board, kept as the same element while it moves between hand, stack and battlefield so it
 * glides there (the prototype's cards). Faces are Scryfall's printed card; battlefield tiles are the tavern frame
 * painted by tileArt.paintTile, whose glow is a drop-shadow tracing the frame (the frame-outline glow).
 */
import { memo, useEffect, useRef, useState } from "react";
import { abilityBadgePlan, displayPower, displayToughness, isCreatureCard, visibleXmageIcons, XmageIcons, type ZoneCard } from "../../core/models";
import { paintTile, TILE, tileKey } from "../../board/tileArt";
import { cardImageURL, manaSymbols, useCardArtURL } from "../cardArt";
import { AbilityCard } from "./AbilityCard";
import { type CardReader, readProps } from "./inspectGesture";
import { leanTransform, type Place } from "./layout";
import { CardBack, ManaSymbol } from "./Symbols";

export type CardView = "face" | "tile" | "back";

const TAPMARK = (
  <svg className="tapmark" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M12 3a9 9 0 1 0 9 9h-3a6 6 0 1 1-6-6v3l5-4.5L12 0z" fill="#fff" stroke="rgba(0,0,0,.35)" strokeWidth=".6" />
  </svg>
);
/** Summoning sickness (CardTile): an hourglass in an amber disc on the top right, creatures only. */
const SICK = (
  <svg className="sick" viewBox="0 0 24 24" role="img" aria-label="Summoning sick">
    <circle cx="12" cy="12" r="11.3" fill="#f2b33d" fillOpacity=".92" stroke="rgba(0,0,0,.32)" strokeWidth=".7" />
    <path d="M8 5.5h8v1.4c0 2-1.4 3.4-2.8 5.1 1.4 1.7 2.8 3.1 2.8 5.1v1.4H8v-1.4c0-2 1.4-3.4 2.8-5.1C9.4 10.3 8 8.9 8 6.9zm1.6 1.4c0 1.3 1 2.5 2.4 4.2 1.4-1.7 2.4-2.9 2.4-4.2z" fill="#2b2a2e" />
  </svg>
);

export function Tile({ card }: { card: ZoneCard }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const key = tileKey(card);
  useEffect(() => {
    const canvas = ref.current;
    if (canvas) paintTile(canvas, card, () => undefined);
    // Repaint only when the tile's look changes (name, frame, power/toughness, damage, counters).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  return (
    <div className="tile">
      <div className="tshadow" />
      <div className="tedge" />
      {/* A new look gets a new canvas, so a slow paint of the old one can never draw over it. */}
      <canvas key={key} ref={ref} width={TILE.width} height={TILE.height} />
      {card.tapped && !card.isAttacking && TAPMARK}
      {card.summoningSickness && isCreatureCard(card) && SICK}
    </div>
  );
}

/** The card's colours as the plain tile's edge: one colour, gold for several, grey for none; lands without a cost take their basic types. */
function colorEdge(card: ZoneCard): string {
  const colors = new Set<string>();
  const cost = (card.card.manaCost ?? "").toUpperCase();
  for (const symbol of ["W", "U", "B", "R", "G"]) if (cost.includes(symbol)) colors.add(symbol);
  for (const color of card.card.tokenColors ?? []) {
    const c = color.toLowerCase();
    const symbol = ({ w: "W", white: "W", u: "U", blue: "U", b: "B", black: "B", r: "R", red: "R", g: "G", green: "G" } as Record<string, string>)[c];
    if (symbol) colors.add(symbol);
  }
  if (colors.size === 0) {
    for (const [land, symbol] of [["Plains", "W"], ["Island", "U"], ["Swamp", "B"], ["Mountain", "R"], ["Forest", "G"]]) {
      if (card.card.typeLine.includes(land)) colors.add(symbol);
    }
  }
  if (colors.size > 1) return "#edbd52";
  return ({ W: "#f5ebc7", U: "#4085f2", B: "#6b4d7a", R: "#db3824", G: "#38a84d" } as Record<string, string>)[[...colors][0] ?? ""] ?? "#9e9ea8";
}

/**
 * Card Frames off, the default (as on the iOS Arena board): the reference game's battlefield card. The card is cropped
 * below its art: a name bar tinted by its colour, the art, a silver power/toughness box hanging off the corner (a shield
 * for a planeswalker's loyalty or a battle's defense); a token sits in an arched frame. Its glow traces this outline.
 */
export function PlainTile({ card, width = 66 }: { card: ZoneCard; width?: number }) {
  const token = card.card.isToken === true || /token/i.test(card.card.typeLine);
  const legendary = /legendary/i.test(card.card.typeLine);
  const creature = card.isCreaturePermanent ?? isCreatureCard(card);
  const power = displayPower(card);
  const toughness = displayToughness(card);
  const battle = /battle/i.test(card.card.typeLine);
  const shieldName = battle ? "defense" : "loyalty";
  const shield = !creature && (battle || /planeswalker/i.test(card.card.typeLine))
    ? Object.entries(card.counters ?? {}).find(([k]) => k.toLowerCase().includes(shieldName))?.[1] : undefined;
  const chips = Object.entries(card.counters ?? {}).filter(([k, n]) => n > 0 && !(shield !== undefined && k.toLowerCase().includes(shieldName)));
  const art = useCardArtURL(card.card, "art_crop");
  const badges = abilityBadgePlan(visibleXmageIcons(card), width);
  const [failed, setFailed] = useState(false);
  return (
    <div className={`plain ${token ? "token" : ""}`} style={{ ["--edge" as string]: colorEdge(card) }}>
      <div className="pface">
        {!token && <div className="pname">{card.card.name}</div>}
        <div className="part">
          {failed || art === null ? <span className="pfallback">{card.card.name}</span>
            : art && <img key={art} src={art} alt="" crossOrigin="anonymous" draggable={false} onError={() => setFailed(true)} />}
        </div>
      </div>
      {card.tapped && !card.isAttacking && TAPMARK}
      {card.summoningSickness && isCreatureCard(card) && SICK}
      {/* The keyword and ability icons along the bottom left (BattlefieldAbilityBadges), "+N" for those that don't fit. */}
      {badges.visible.length + badges.hiddenCount > 0 && (
        <div className="pbadges" style={{ ["--badge" as string]: `${(badges.size + 4) / (width / 15)}em` }}>
          {badges.visible.map((icon, index) => {
            const asset = XmageIcons.assetName(icon.iconType);
            return XmageIcons.textBadge(icon) === "Menace" ? <i key={index} className="menace">{MENACE}</i>
              : asset ? <i key={index} style={{ ["--icon" as string]: `url(/generated/icons/${asset}.svg)` }} /> : null;
          })}
          {badges.hiddenCount > 0 && <b>+{badges.hiddenCount}</b>}
        </div>
      )}
      {/* A token copy says so inside its frame, under the arch. */}
      {card.card.isToken === true && card.card.copySourceArtworkName && <div className="pcopy">COPY</div>}
      {chips.length > 0 && (
        <div className="pchips">{chips.slice(0, 2).map(([k, n]) => (
          <span key={k} title={`${n} ${k}`}>{/\+1\/\+1/.test(k) ? `+${n}` : /-1\/-1/.test(k) ? `−${n}` : n}</span>
        ))}</div>
      )}
      {creature && power !== undefined && toughness !== undefined ? (
        <div className={`pstats ${legendary ? "legend" : ""}`}>{power}<i>/</i><b className={(card.damage ?? 0) > 0 ? "hurt" : ""}>{toughness}</b></div>
      ) : shield !== undefined ? <div className={`pshield ${battle ? "battle" : ""}`}>{shield}</div> : null}
    </div>
  );
}

export function Face({ name, cost, showCost }: { name: string; cost?: string; showCost: boolean }) {
  const [failed, setFailed] = useState(false);
  const symbols = showCost ? manaSymbols(cost) : [];
  return (
    <>
      <div className="face">
        {failed ? <div className="fallback">{name}</div>
          : <img src={cardImageURL(name, "normal")} alt="" crossOrigin="anonymous" draggable={false} onError={() => setFailed(true)} />}
      </div>
      {symbols.length > 0 && (
        <div className="mcost">{symbols.map((symbol, index) => symbol === "//"
          ? <i key={index}>/</i> : <ManaSymbol key={index} symbol={symbol} />)}
        </div>
      )}
    </>
  );
}

const MENACE = <svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="7" cy="6" r="3" /><circle cx="13.5" cy="6.5" r="2.6" /><path d="M1.5 16c0-3.2 2.5-5.2 5.5-5.2s5.5 2 5.5 5.2zM12.6 10.9c2.8-.2 5.4 1.5 5.4 5.1h-4.3c0-2-.4-3.7-1.1-5.1z" /></svg>;
const FLAME = <svg viewBox="0 0 20 20"><path d="M10 1c1 3.2 5.5 5.6 5.5 10.4A5.5 5.5 0 0 1 4.5 11.6c0-2.3 1.1-3.9 2.3-5.1.1 1.6.8 2.8 2 3.4C8.4 6.6 9.2 3.6 10 1z" /></svg>;
const SPARKLES = <svg viewBox="0 0 20 20"><path d="M8 1l1.6 4.6L14 7.2 9.6 8.8 8 13.4 6.4 8.8 2 7.2l4.4-1.6zM15 10l.9 2.4 2.4.9-2.4.9L15 16.6l-.9-2.4-2.4-.9 2.4-.9z" /></svg>;

export interface ArenaCardProps {
  id: string;
  place: Place;
  view: CardView;
  card?: ZoneCard;
  /** Battlefield tiles in the tavern frames (Card Frames on) rather than the reference game's card (off, the default). */
  frames?: boolean;
  /** An ability on the stack: drawn as the reference's ability card instead of a printed card. */
  ability?: { source?: ZoneCard; name?: string; text: string };
  /** For faces without a ZoneCard (stack objects): the printed card to show. */
  name?: string;
  owner?: "me" | "opp";
  inHand?: boolean;
  /** A card played from your graveyard or exile, at the fan's end: its zone (ArenaExtraCardShimmer). */
  extraZone?: string;
  classes?: string;
  label?: string;
  onClick?: (id: string, event: React.MouseEvent) => void;
  /** A hand card: pressing it may start carrying it to the table. */
  onPress?: (id: string, event: React.PointerEvent) => void;
  /** Right-click or a press held still reads the card in the inspector; hovering only lifts it. */
  reader?: CardReader;
}

/**
 * Three layers: the card's place (it glides there), the table's lean for cards lying on the table (ArenaTableLean: the
 * plate's pitch, drawn flat as the iPhone draws it), and the card's own tilt and scale (tapped, fanned, lifted).
 */
export const ArenaCard = memo(function ArenaCard({ id, place, view, card, frames, ability, name, owner, inHand, extraZone, classes, label, onClick, onPress, reader }: ArenaCardProps) {
  const left = place.x - place.w / 2;
  const style: React.CSSProperties = {
    width: place.w, height: place.h, fontSize: place.w / 15, transform: `translate(${left.toFixed(1)}px,${(place.y - place.h / 2).toFixed(1)}px)`, zIndex: place.z,
  };
  const lean: React.CSSProperties | undefined = place.lean ? { transform: leanTransform() } : undefined;
  const printed = name ?? card?.card.name ?? "";
  const read = view === "back" ? {} : readProps(reader, { name: printed, card });
  return (
    <div className={`acard ${classes ?? ""} ${view === "tile" && card?.phasedIn === false ? "phased" : ""}`} data-id={id} data-view={view} data-o={owner} data-hand={inHand ? "" : undefined} style={style} role={onClick ? "button" : undefined}
      aria-label={label ?? (view === "back" ? "Card" : extraZone ? `${printed}, playable from your ${extraZone.toLowerCase()}` : printed)} tabIndex={onClick ? 0 : undefined}
      onClick={onClick ? (event) => onClick(id, event) : undefined}
      onKeyDown={onClick ? (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onClick(id, event as unknown as React.MouseEvent); } } : undefined}
      onPointerDown={onPress || read.onPointerDown ? (event) => { if (event.button === 0) onPress?.(id, event); read.onPointerDown?.(event); } : undefined}
      onContextMenu={read.onContextMenu}>
      <div className="lean" style={lean}>
        <div className="spin" style={{ transform: `rotate(${place.r ?? 0}deg) scale(${place.s ?? 1})` }}>
          {view === "tile" && card && (frames ? <Tile card={card} /> : <PlainTile card={card} width={place.w} />)}
          {view === "tile" && card?.phasedIn === false && <span className="aphased">Phased out</span>}
          {view === "face" && (ability ? <AbilityCard source={ability.source} name={ability.name} text={ability.text} />
            : <Face name={printed} cost={card?.card.manaCost} showCost={inHand === true} />)}
          {view === "face" && extraZone && (
            <div className="ashimmer" aria-hidden="true"><i>{extraZone.toLowerCase() === "graveyard" ? FLAME : SPARKLES}</i></div>
          )}
          {view === "back" && <CardBack />}
        </div>
      </div>
    </div>
  );
});
