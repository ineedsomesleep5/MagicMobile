/**
 * An ability the reference game's way (ArenaAbilityCard on iOS): its source's frame colour and art, a type line that says
 * "Ability" (or "Mode 2"), only the ability's own text, and a loyalty shield at its foot for a planeswalker's ability.
 * Used on the stack card, in the stack browser and in the ability and trigger browsers. Sized by font-size: 15em wide.
 */
import type { ZoneCard } from "../../core/models";
import { EngineDisplayText } from "../../core/displayText";
import { cardImageURL } from "../cardArt";
import { RulesText } from "./Symbols";

/** XMage marks spells; everything else on the stack is an activated or triggered ability (ArenaStackCard.isAbility). */
export const isStackAbility = (item: { objectType?: string }) => item.objectType !== undefined && item.objectType.toUpperCase() !== "SPELL";

/** A card's frame colour: its one colour, gold for several, grey for none (lands take their basic types). */
export function frameColor(card: ZoneCard | undefined): string {
  if (!card) return "#9e9ea8";
  const colors = new Set<string>();
  const cost = (card.card.manaCost ?? "").toUpperCase();
  for (const symbol of ["W", "U", "B", "R", "G"]) if (cost.includes(symbol)) colors.add(symbol);
  for (const color of card.card.tokenColors ?? []) {
    const symbol = ({ w: "W", white: "W", u: "U", blue: "U", b: "B", black: "B", r: "R", red: "R", g: "G", green: "G" } as Record<string, string>)[color.toLowerCase()];
    if (symbol) colors.add(symbol);
  }
  if (colors.size === 0) {
    for (const [land, symbol] of [["Plains", "W"], ["Island", "U"], ["Swamp", "B"], ["Mountain", "R"], ["Forest", "G"]]) {
      if (card.card.typeLine.includes(land)) colors.add(symbol);
    }
  }
  if (colors.size > 1) return "#edbd52";
  return ({ W: "#ede0b8", U: "#4085f2", B: "#6b4d7a", R: "#db3824", G: "#38a84d" } as Record<string, string>)[[...colors][0] ?? ""] ?? "#9e9ea8";
}

/** "+1: Put a +1/+1 counter…" → the loyalty cost and the rest, as the reference's shield shows it. */
export function splitLoyalty(text: string): { cost?: string; text: string } {
  const match = /^\s*([+−-]?\d+|0)\s*:\s*(.*)$/s.exec(text);
  return match ? { cost: match[1].replace("-", "−"), text: match[2] } : { text };
}

export function AbilityCard({ source, name, kind = "Ability", text, width }: {
  source?: ZoneCard; name?: string; kind?: string; text: string;
  /** Width in the parent's units (px or board points); the card is 0.72 as wide as it is tall. */
  width?: number;
}) {
  const { cost, text: rules } = splitLoyalty(EngineDisplayText.text(text).replace(/\s*\[[0-9a-f]{3,}\]/gi, ""));
  const frame = frameColor(source);
  const art = source ? (source.card.isToken && source.card.tokenArtwork ? source.card.tokenArtwork.name : source.card.name) : undefined;
  return (
    <div className="ability-card" style={{ ["--frame" as string]: frame, ...(width ? { width, height: width / 0.72, fontSize: width / 15 } : {}) }}
      aria-label={`Ability of ${source?.card.name ?? name ?? "a permanent"}: ${rules}`}>
      <div className="ab-inner">
        <div className="ab-name">{source?.card.name ?? name ?? "Ability"}</div>
        <div className="ab-art">{art ? <img src={cardImageURL(art, "art_crop")} alt="" crossOrigin="anonymous" draggable={false} /> : <span>✦</span>}</div>
        <div className="ab-type">{kind}</div>
        <div className="ab-text"><RulesText text={rules} /></div>
      </div>
      {cost && <div className="ab-loyalty">{cost}</div>}
    </div>
  );
}
