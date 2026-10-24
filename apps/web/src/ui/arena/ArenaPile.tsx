/**
 * A pile on the table, the library's look for every zone (ArenaPileStack on iOS; Caleb, 2026-10-21: graveyards and
 * exile lie like the library): slivers whose thickness follows the count, a contact shadow, the top card lying on them
 * (the back for a library, the face for a graveyard, the face under a cool veil for exile), leaning with the table, and
 * the count on Arena's count oval (ArenaCountBadge). An empty zone is a dashed slot.
 */
import type { ZoneCard } from "../../core/models";
import { cardImageURL } from "../cardArt";
import { type CardReader, readProps } from "./inspectGesture";
import { leanTransform, pileThickness } from "./layout";
import { CardBack, CountBadge } from "./Symbols";

export function ArenaPile({ x, y, size, count, top, kind, label, onOpen, reader }: {
  x: number; y: number; size: { w: number; h: number }; count: number;
  /** The face-up top card (graveyard, exile); a library shows its back. */
  top?: ZoneCard;
  kind: "library" | "graveyard" | "exile";
  label: string;
  onOpen?: () => void;
  /** Right-click or a held press reads the top card. */
  reader?: CardReader;
}) {
  const { thickness, layers } = pileThickness(count, size.h);
  const left = x - size.w / 2;
  const lean = { transform: leanTransform() };
  const lift = (i: number) => `translate(${(-thickness * 0.22 * i / Math.max(layers, 1)).toFixed(2)}px, ${(-thickness * i / Math.max(layers, 1)).toFixed(2)}px)`;
  return (
    <button type="button" className={`apile ${kind} ${count === 0 ? "empty" : ""}`} disabled={!onOpen || count === 0}
      style={{ left, top: y - size.h / 2, width: size.w, height: size.h, fontSize: size.w / 15 }}
      aria-label={count === 0 ? `${label}, empty` : `${label}, ${count} card${count === 1 ? "" : "s"}`}
      onClick={(event) => { event.stopPropagation(); onOpen?.(); }}
      {...readProps(reader, top && kind !== "library" ? { name: top.card.name, card: top } : undefined)}>
      <div className="plean" style={lean}>
        {count > 0 && <div className="pshadow" />}
        {Array.from({ length: layers }, (_, i) => {
          const f = layers > 1 ? i / (layers - 1) : 1;
          // iOS draws each sliver at hue 0.105, saturation 0.32, brightness 0.62–0.88 (every other one a shade lighter).
          const brightness = 0.62 + 0.26 * f + (i % 2 === 0 ? 0 : 0.05);
          return <i key={i} className="sliver" style={{ background: `hsl(38 32% ${(brightness * 84).toFixed(0)}%)`, transform: lift(i) }} />;
        })}
        {count > 0 && (
          <div className="ptop" style={{ transform: `translate(${(-thickness * 0.22).toFixed(2)}px, ${(-thickness).toFixed(2)}px)` }}>
            {kind === "library" || !top ? <CardBack /> : (
              <>
                <img src={cardImageURL(top.card.name, "normal")} alt="" crossOrigin="anonymous" draggable={false} />
                {kind === "exile" && <div className="veil" aria-hidden="true">✦</div>}
              </>
            )}
          </div>
        )}
      </div>
      {count > 0 && <CountBadge count={count} className="pcount" />}
    </button>
  );
}
