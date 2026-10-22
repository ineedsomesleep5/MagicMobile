/**
 * Reading a card, the reference's way (CardInspector.arenaBody): the table dims, the card stands large with no panel round
 * it, and beside it glass notes say what it is right now, what its keywords mean, its rules when the picture can't show
 * them, and what is attached to it. Opened by a right-click or a held mouse button; a click anywhere or Esc closes it.
 */
import { useCallback, useEffect, useState } from "react";
import { glossaryEntries, liveState } from "../../core/arenaBoard";
import type { ZoneCard } from "../../core/models";
import { CardArt } from "../cardArt";
import { RulesText } from "./Symbols";

export function Inspector({ card, name, battlefield, height, close }: { card?: ZoneCard; name: string; battlefield: ZoneCard[]; height: number; close: () => void }) {
  const [artMissing, setArtMissing] = useState(false);
  const missing = useCallback(() => setArtMissing(true), []);
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.key === "Escape") close(); };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [close]);
  const rules = (card?.card.oracleText ?? "").trim();
  const glossary = glossaryEntries(rules);
  const state = card ? liveState(card, battlefield) : [];
  const attached = card ? battlefield.filter((c) => c.attachedToInstanceId === card.instanceId && c.instanceId !== card.instanceId) : [];
  const showsRules = (artMissing || card?.card.isToken === true) && rules.length > 0;
  const hasNotes = state.length > 0 || glossary.length > 0 || showsRules || attached.length > 0;
  const cardHeight = Math.min(height * 0.86, 520);
  return (
    <div className="ainspector" onClick={(e) => { e.stopPropagation(); close(); }} role="dialog" aria-label={`${name}, inspector`}>
      <div className="row" style={{ height: cardHeight }}>
        <div className="big" style={{ width: cardHeight / 1.395, height: cardHeight }}>
          {artMissing ? <div className="fallback">{name}</div>
            : <CardArt card={card?.card ?? { name, typeLine: "" }} version="large" onMissing={missing} />}
        </div>
        {hasNotes && (
          <div className="notes">
            {state.length > 0 && <div className="glass note"><b className="label">NOW</b>{state.map((line) => <span key={line}>{line}</span>)}</div>}
            {glossary.length > 0 && (
              <div className="glass note">{glossary.map(([keyword, meaning]) => <p key={keyword}><b>{keyword}</b> {meaning}</p>)}</div>
            )}
            {showsRules && <div className="glass note rules"><RulesText text={rules} /></div>}
            {attached.length > 0 && <div className="glass note"><b className="label">ATTACHED</b>{attached.map((c) => <span key={c.instanceId}>{c.card.name}</span>)}</div>}
          </div>
        )}
      </div>
    </div>
  );
}
