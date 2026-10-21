/**
 * One card on the Arena board, kept as the same element while it moves between hand, stack and battlefield so it
 * glides there (the prototype's cards). Faces are Scryfall's printed card; battlefield tiles are the tavern frame
 * painted by tileArt.paintTile, whose glow is a drop-shadow tracing the frame (the frame-outline glow).
 */
import { memo, useEffect, useRef, useState } from "react";
import { type ZoneCard } from "../../core/models";
import { paintTile, TILE, tileKey } from "../../board/tileArt";
import { cardImageURL, manaSymbols } from "../cardArt";
import { cardTransform, type Place } from "./layout";

export type CardView = "face" | "tile" | "back";

const TAPMARK = (
  <svg className="tapmark" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M12 3a9 9 0 1 0 9 9h-3a6 6 0 1 1-6-6v3l5-4.5L12 0z" fill="#fff" stroke="rgba(0,0,0,.35)" strokeWidth=".6" />
  </svg>
);
const SICK = (
  <svg className="sick" viewBox="0 0 24 24" aria-hidden="true">
    <path d="M6 2h12v2c0 3-2.2 5.2-4.3 8 2.1 2.8 4.3 5 4.3 8v2H6v-2c0-3 2.2-5.2 4.3-8C8.2 9.2 6 7 6 4zm2 2c0 2 1.6 3.8 4 6.6C14.4 7.8 16 6 16 4z" fill="#ffdb8f" />
  </svg>
);

function Tile({ card }: { card: ZoneCard }) {
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
      {/* A new look gets a new canvas, so a slow paint of the old one can never draw over it. */}
      <canvas key={key} ref={ref} width={TILE.width} height={TILE.height} />
      {card.tapped && !card.isAttacking && TAPMARK}
      {card.summoningSickness && SICK}
    </div>
  );
}

function Face({ name, cost, showCost }: { name: string; cost?: string; showCost: boolean }) {
  const [failed, setFailed] = useState(false);
  const symbols = showCost ? manaSymbols(cost) : [];
  return (
    <>
      <div className="face">
        {failed ? <div className="fallback">{name}</div>
          : <img src={cardImageURL(name, "normal")} alt="" crossOrigin="anonymous" draggable={false} onError={() => setFailed(true)} />}
      </div>
      {symbols.length > 0 && (
        <div className="mcost">{symbols.map((symbol, index) => /^[WUBRGC]$/.test(symbol)
          ? <span key={index} className="sym" style={{ backgroundImage: `url(/tavern/mana-${symbol}.webp)` }} />
          : <span key={index} className="sym" style={{ backgroundImage: "url(/tavern/mana-generic.webp)" }}>{symbol === "//" ? "" : symbol}</span>)}
        </div>
      )}
    </>
  );
}

export interface ArenaCardProps {
  id: string;
  place: Place;
  view: CardView;
  card?: ZoneCard;
  /** For faces without a ZoneCard (stack objects): the printed card to show. */
  name?: string;
  owner?: "me" | "opp";
  inHand?: boolean;
  classes?: string;
  label?: string;
  onClick?: (id: string, event: React.MouseEvent) => void;
  onHover?: (id: string | undefined) => void;
}

export const ArenaCard = memo(function ArenaCard({ id, place, view, card, name, owner, inHand, classes, label, onClick, onHover }: ArenaCardProps) {
  const style: React.CSSProperties = {
    width: place.w, height: place.h, fontSize: place.w / 15, transform: cardTransform(place), zIndex: place.z,
  };
  const printed = name ?? card?.card.name ?? "";
  return (
    <div className={`acard ${classes ?? ""}`} data-view={view} data-o={owner} style={style} role={onClick ? "button" : undefined}
      aria-label={label ?? (view === "back" ? "Card" : printed)} tabIndex={onClick ? 0 : undefined}
      onClick={onClick ? (event) => onClick(id, event) : undefined}
      onKeyDown={onClick ? (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); onClick(id, event as unknown as React.MouseEvent); } } : undefined}
      onMouseEnter={onHover && view !== "back" ? () => onHover(id) : undefined}
      onMouseLeave={onHover && view !== "back" ? () => onHover(undefined) : undefined}>
      {view === "tile" && card && <Tile card={card} />}
      {view === "face" && <Face name={printed} cost={card?.card.manaCost} showCost={inHand === true} />}
      {view === "back" && <div className="back" />}
    </div>
  );
});
