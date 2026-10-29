/**
 * One status badge (TavernStatusBadge): a leather coin in a brass ring with its symbol, its count on a brass coin at
 * the corner; a red ring when the player is close to losing to it. A commander's badge shows its art.
 */
import type { ReactNode } from "react";
import type { BadgeIcon, StatusBadge as Badge } from "../../core/playerStatus";
import { CardArt } from "../cardArt";

const SYMBOLS: Record<Exclude<BadgeIcon, "commander">, ReactNode> = {
  // The Phyrexian glyph, stroked.
  poison: <g fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><ellipse cx="10" cy="10.5" rx="4.6" ry="5.4" /><path d="M10 2.5v15" /></g>,
  energy: <path d="M11.5 1 4 11h5l-1.5 8L15 9h-5z" />,
  experience: <path d="M8 1l1.6 4.6L14 7.2 9.6 8.8 8 13.4 6.4 8.8 2 7.2l4.4-1.6zM15 10l.9 2.4 2.4.9-2.4.9L15 16.6l-.9-2.4-2.4-.9 2.4-.9z" />,
  rad: <g fill="none" stroke="currentColor" strokeWidth="1.4"><ellipse cx="10" cy="10" rx="8" ry="3.2" /><ellipse cx="10" cy="10" rx="8" ry="3.2" transform="rotate(60 10 10)" /><ellipse cx="10" cy="10" rx="8" ry="3.2" transform="rotate(-60 10 10)" /><circle cx="10" cy="10" r="1.4" fill="currentColor" /></g>,
  ticket: <path d="M2 5h16v3a2 2 0 0 0 0 4v3H2v-3a2 2 0 0 0 0-4z" />,
  counter: <path d="M10 1.5l2.2 1.9 2.9-.4.8 2.8 2.6 1.4-1 2.8 1 2.8-2.6 1.4-.8 2.8-2.9-.4L10 18.5l-2.2-1.9-2.9.4-.8-2.8L1.5 12.8l1-2.8-1-2.8 2.6-1.4.8-2.8 2.9.4z" />,
  monarch: <path d="M2 15h16l1-9-5 4-4-6-4 6-5-4zM2 16.5h16V18H2z" />,
  initiative: <path d="M4 2h1.6v16H4zM6.4 3h10l-2.6 3.6 2.6 3.6h-10z" />,
  designation: <path d="M10 1.5 18 5.5v1.5H2V5.5zM3.5 8h2v7h-2zM9 8h2v7H9zM14.5 8h2v7h-2zM2 16h16v2.5H2z" />,
};
const CROWN = SYMBOLS.monarch;
const SHIELD = <svg className="shield" viewBox="0 0 20 20" aria-hidden="true"><path d="M10 1.5 17 4v5.5c0 4.2-3 7.4-7 9-4-1.6-7-4.8-7-9V4z" /></svg>;

export function StatusBadge({ badge, size }: { badge: Badge; size: number }) {
  return (
    <span className={`astatus ${badge.nearLethal ? "lethal" : ""}`} style={{ width: size, height: size, ["--tint" as string]: badge.tint }} role="img" aria-label={badge.label}>
      {badge.icon === "commander" ? (
        <>
          {badge.card ? <span className="art"><CardArt card={badge.card.card} version="art_crop" /></span>
            : <svg viewBox="0 0 20 20" aria-hidden="true">{CROWN}</svg>}
          {SHIELD}
        </>
      ) : <svg viewBox="0 0 20 20" aria-hidden="true">{SYMBOLS[badge.icon]}</svg>}
      {badge.count !== undefined && <b className="count">{badge.count}</b>}
    </span>
  );
}
