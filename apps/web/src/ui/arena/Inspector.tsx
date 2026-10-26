/**
 * Reading a card, the reference's way (CardInspector.arenaBody): the table dims, the card stands large with no panel round
 * it, and beside it glass notes say what it is right now, what its keywords mean, its rules when the picture can't show
 * them, and what is attached to it. Opened by a right-click or a held mouse button; a click anywhere or Esc closes it.
 * A card fastened to others shows them as tabs over the notes (InspectorTabStrip): click one, or slide a held press onto
 * it, to read that card without letting go.
 */
import { useCallback, useEffect, useState } from "react";
import { glossaryEntries, liveState, rulesReminder } from "../../core/arenaBoard";
import type { ZoneCard } from "../../core/models";
import { CardArt } from "../cardArt";
import { FaceDownMark } from "./ArenaCard";
import { RulesText } from "./Symbols";

/** The held card with what it is attached to (first) and what is attached to it; one card, no tabs. */
export function inspectorTabs(card: ZoneCard | undefined, battlefield: ZoneCard[]): ZoneCard[] {
  if (!card) return [];
  const parent = card.attachedToInstanceId !== undefined ? battlefield.find((c) => c.instanceId === card.attachedToInstanceId) : undefined;
  const carried = battlefield.filter((c) => c.attachedToInstanceId === card.instanceId && c.instanceId !== card.instanceId);
  return [...(parent ? [parent] : []), card, ...carried];
}

export function Inspector({ card: held, name: heldName, battlefield, height, holding = false, close }: {
  card?: ZoneCard; name: string; battlefield: ZoneCard[]; height: number;
  /** A held press opened it: sliding that press onto a tab shows the tab's card. */
  holding?: boolean;
  close: () => void;
}) {
  const tabs = inspectorTabs(held, battlefield);
  // The tab shown, for the card held: a different card inspected starts again on itself.
  const [focus, setFocus] = useState<{ held?: string; id: string }>();
  const card = (focus && focus.held === held?.instanceId ? tabs.find((t) => t.instanceId === focus.id) : undefined) ?? held;
  const name = card === held ? heldName : card?.card.name ?? heldName;
  const choose = useCallback((id: string) => setFocus({ held: held?.instanceId, id }), [held?.instanceId]);
  const [missingFor, setMissingFor] = useState<string>();
  const artMissing = missingFor === (card?.instanceId ?? name);
  const missing = useCallback(() => setMissingFor(card?.instanceId ?? name), [card?.instanceId, name]);
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.key === "Escape") close(); };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [close]);
  useEffect(() => {
    if (!holding || tabs.length < 2) return;
    const slide = (event: PointerEvent) => {
      const id = document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>("[data-tab]")?.dataset.tab;
      if (id && id !== card?.instanceId) choose(id);
    };
    window.addEventListener("pointermove", slide);
    return () => window.removeEventListener("pointermove", slide);
  }, [holding, tabs.length, card?.instanceId, choose]);
  const rules = (card?.card.oracleText ?? "").trim();
  const glossary = glossaryEntries(rules);
  const state = card ? liveState(card, battlefield) : [];
  const reminder = card ? rulesReminder(card) : undefined;
  const attached = card ? battlefield.filter((c) => c.attachedToInstanceId === card.instanceId && c.instanceId !== card.instanceId) : [];
  const showsRules = (artMissing || card?.card.isToken === true) && rules.length > 0;
  const hasNotes = tabs.length > 1 || state.length > 0 || glossary.length > 0 || showsRules || reminder !== undefined || attached.length > 0;
  const cardHeight = Math.min(height * 0.86, 520);
  return (
    <div className="ainspector" onClick={(e) => { e.stopPropagation(); close(); }} role="dialog" aria-label={`${name}, inspector`}>
      <div className="row" style={{ height: cardHeight }}>
        <div className="big" style={{ width: cardHeight / 1.395, height: cardHeight }}>
          {artMissing ? <div className="fallback">{name}</div>
            : <CardArt key={card?.instanceId ?? name} card={card?.card ?? { name, typeLine: "" }} version="large" onMissing={missing} />}
        </div>
        {hasNotes && (
          <div className="notes">
            {tabs.length > 1 && held && (
              <div className="itabs" role="group" aria-label="Attached cards" data-id="inspector.tabs">
                {tabs.map((tab) => {
                  const on = tab.instanceId === card?.instanceId;
                  return (
                    <button key={tab.instanceId} type="button" className={`itab ${on ? "on" : ""}`} data-tab={tab.instanceId} data-id={`inspector.tab.${tab.instanceId}`}
                      aria-pressed={on} aria-label={tab.instanceId === held.instanceId ? tab.card.name : `${tab.card.name}, attached`}
                      onClick={(e) => { e.stopPropagation(); choose(tab.instanceId); }}>
                      <CardArt card={tab.card} version="art_crop" />
                      {tab.card.faceDown === true && <FaceDownMark />}
                    </button>
                  );
                })}
              </div>
            )}
            {state.length > 0 && <div className="glass note"><b className="label">NOW</b>{state.map((line) => <span key={line}>{line}</span>)}</div>}
            {glossary.length > 0 && (
              <div className="glass note">{glossary.map(([keyword, meaning]) => <p key={keyword}><b>{keyword}</b> {meaning}</p>)}</div>
            )}
            {showsRules && <div className="glass note rules"><RulesText text={rules} /></div>}
            {reminder && <div className="glass note"><p>{reminder}</p></div>}
            {attached.length > 0 && <div className="glass note"><b className="label">ATTACHED</b>{attached.map((c) => <span key={c.instanceId}>{c.card.name}</span>)}</div>}
          </div>
        )}
      </div>
    </div>
  );
}
