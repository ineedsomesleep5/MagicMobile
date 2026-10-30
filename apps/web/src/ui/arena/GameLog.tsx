/**
 * The Arena board's game log (GameLogDrawer, arena): oldest at the top and following the latest, a gold divider for each
 * turn, an icon for each event, smart pass's lines dimmed, card names as gold links that read the card on the table,
 * and one line of combat context under damage and deaths. "Latest actions ↓" returns to the bottom when scrolled up.
 */
import { type ReactNode, useLayoutEffect, useRef, useState } from "react";
import { arenaLogLine, type CardReference, GameLogPresentation, type LogIcon } from "../../core/gameLog";
import type { GameLogEntry } from "../../core/models";
import { RulesText } from "./Symbols";

const ICONS: Record<LogIcon, ReactNode> = {
  died: <path d="M6.5 1h7L19 6.5v7L13.5 19h-7L1 13.5v-7zM7 5.6 5.6 7l3 3-3 3L7 14.4l3-3 3 3 1.4-1.4-3-3 3-3L13 5.6l-3 3z" fillRule="evenodd" />,
  exile: <path d="M8 1l1.6 4.6L14 7.2 9.6 8.8 8 13.4 6.4 8.8 2 7.2l4.4-1.6zM15 10l.9 2.4 2.4.9-2.4.9L15 16.6l-.9-2.4-2.4-.9 2.4-.9z" />,
  steal: <path d="M10 1a9 9 0 1 1 0 18 9 9 0 0 1 0-18zm-1 4L4.5 8.5 9 12V9.6h2.2a2.4 2.4 0 0 1 0 4.8H8V16h3.2a4 4 0 0 0 0-8H9z" fillRule="evenodd" />,
  cast: <path d="M2.4 16.2 13 5.6l1.4 1.4L3.8 17.6zM15 1l.8 2.2L18 4l-2.2.8L15 7l-.8-2.2L12 4l2.2-.8zM8 1.5l.5 1.3 1.3.5-1.3.5L8 5.1l-.5-1.3-1.3-.5 1.3-.5zM17 9.5l.5 1.3 1.3.5-1.3.5-.5 1.3-.5-1.3-1.3-.5 1.3-.5z" />,
  combat: <path d="M11.5 1 4 11h5l-1.5 8L15 9h-5z" />,
  hurt: <path d="M10 18S2 12.6 2 7.2A4.2 4.2 0 0 1 10 5a4.2 4.2 0 0 1 8 2.2C18 12.6 10 18 10 18zM3 2l15 15-1.2 1.2-15-15z" />,
  heal: <path d="M10 18S2 12.6 2 7.2A4.2 4.2 0 0 1 10 5a4.2 4.2 0 0 1 8 2.2C18 12.6 10 18 10 18z" />,
  draw: <path d="M5 5h11a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM6 2h10.5A2.5 2.5 0 0 1 19 4.5V15h-1V4.5A1.5 1.5 0 0 0 16.5 3H6z" />,
  arrive: <path d="M3 3h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm12 3h1v10a1 1 0 0 1-1 1H6v-1h9zm3 3h1v8a2 2 0 0 1-2 2H9v-1h8a1 1 0 0 0 1-1z" />,
  ability: <path d="M10 1a9 9 0 1 1 0 18 9 9 0 0 1 0-18zM4.5 10.8h4.2L7.6 15l7.9-6.6H11L12.4 5z" fillRule="evenodd" />,
  dot: <circle cx="10" cy="10" r="4.5" />,
};
const FORWARD = <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M2 4l8 6-8 6zM10 4l8 6-8 6z" /></svg>;

/** One message as styled spans: players in teal, cards in gold italics, a disclosed card a link that reads it. RulesText trims, so each span's edge spaces are kept here. */
function LogText({ message, inspect }: { message: string; inspect: (reference: CardReference) => void }) {
  const presentation = new GameLogPresentation(message);
  return (
    <span className="text" aria-label={presentation.plainText}>
      {presentation.spans.map((span, index) => {
        const className = [span.role, span.bold ? "bold" : "", span.italic ? "italic" : ""].filter(Boolean).join(" ");
        const card = span.card;
        return card
          ? <button key={index} type="button" className={`${className} link`} onClick={(e) => { e.stopPropagation(); inspect(card); }}>{span.text}</button>
          : <span key={index} className={className}>{/^\s/.test(span.text) && " "}<RulesText text={span.text} />{/\S\s$/.test(span.text) && " "}</span>;
      })}
    </span>
  );
}

export function GameLog({ log, reasons, inspect }: { log: GameLogEntry[]; reasons: ReadonlyMap<string, string>; inspect: (reference: CardReference) => void }) {
  const scroller = useRef<HTMLOListElement>(null);
  const [following, setFollowing] = useState(true);
  const last = log[log.length - 1]?.id;
  // Opens on the latest action and follows new ones while the player is at the bottom.
  useLayoutEffect(() => {
    const element = scroller.current;
    if (element && following) element.scrollTo({ top: element.scrollHeight, behavior: element.scrollTop === 0 ? "auto" : "smooth" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [last]);
  const latest = () => {
    const element = scroller.current;
    if (element) element.scrollTo({ top: element.scrollHeight, behavior: "smooth" });
    setFollowing(true);
  };
  return (
    <div className="alogwrap">
      <ol className="alog" ref={scroller} onScroll={(e) => {
        const element = e.currentTarget;
        setFollowing(element.scrollHeight - element.scrollTop - element.clientHeight < 80);
      }}>
        {log.length === 0 && <li className="empty">No public game actions yet.</li>}
        {log.map((entry) => {
          const line = arenaLogLine(entry);
          if (line.kind === "turn") return <li key={entry.id} className="turn" role="heading" aria-level={4}><i /><span>{line.text}</span><i /></li>;
          if (line.kind === "autoPass") return <li key={entry.id} className="auto">{FORWARD}<span>{line.text}</span></li>;
          const reason = reasons.get(entry.id);
          return (
            <li key={entry.id} className="event">
              <svg viewBox="0 0 20 20" aria-hidden="true" style={{ color: line.tint }}>{ICONS[line.icon!]}</svg>
              <div>
                <LogText message={entry.message} inspect={inspect} />
                {reason && <small className="reason">{reason}</small>}
              </div>
            </li>
          );
        })}
      </ol>
      {!following && <button type="button" className="alatest" onClick={latest}>Latest actions ↓</button>}
    </div>
  );
}
