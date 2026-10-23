/**
 * The Arena board's flat pieces (Caleb, 2026-10-21: the real Magic card back, and no 3D tavern pips in Arena mode):
 * Scryfall's mana symbols (iOS ManaSymbolView) and the Magic card back (ArenaCardBack). Both are <img> with
 * crossorigin, which the page's cross-origin isolation allows; a CSS background from another origin would be blocked.
 * Until an image loads, or if it can't, a plain stand-in shows (a coloured disc, a dark back). Also Arena's count oval.
 */
import { useState } from "react";
import { CARD_BACK_URL, manaSymbolURL } from "../cardArt";

const DISC: Record<string, [string, string]> = {
  W: ["#ebdba8", "#000"], U: ["#528cc7", "#000"], B: ["#2e2926", "#fff"], R: ["#c74029", "#000"], G: ["#408540", "#000"],
};

export function ManaSymbol({ symbol, size, inline }: { symbol: string; size?: number | string; inline?: boolean }) {
  const [failed, setFailed] = useState(false);
  const style = size === undefined ? undefined : { width: size, height: size };
  const className = `msym ${inline ? "inline" : ""}`;
  if (failed) {
    const [background, color] = DISC[symbol] ?? ["#99917f", "#000"];
    return <span className={`${className} disc`} style={{ ...style, background, color }} aria-label={`{${symbol}}`}>{symbol}</span>;
  }
  return <img className={className} src={manaSymbolURL(symbol)} alt={`{${symbol}}`} crossOrigin="anonymous" draggable={false} style={style} onError={() => setFailed(true)} />;
}

/** Text with its {W}, {2}, {X} and {T} drawn as flat symbols in the line (iOS GameRulesText). */
export function RulesText({ text }: { text: string }) {
  return <>{text.split(/(\{[^}]+\})/g).map((part, index) => {
    const symbol = /^\{([^}]+)\}$/.exec(part)?.[1];
    return symbol ? <ManaSymbol key={index} symbol={symbol} inline /> : part;
  })}</>;
}

export function CardBack() {
  const [failed, setFailed] = useState(false);
  return failed ? <div className="back" /> : <img className="mback" src={CARD_BACK_URL} alt="" crossOrigin="anonymous" draggable={false} onError={() => setFailed(true)} />;
}

/** ArenaCountBadge: a white number on a dark oval in a thin gold line (a pile, the stack's size, a card's order); `size` is its height. */
export function CountBadge({ count, size = 17, label, className = "" }: { count: number; size?: number; label?: string; className?: string }) {
  return <span className={`acount ${className}`} style={{ ["--s" as string]: `${size}px` }} aria-label={label}>{count}</span>;
}
