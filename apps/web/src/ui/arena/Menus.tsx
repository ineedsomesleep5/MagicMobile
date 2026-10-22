/**
 * The Arena board's menus and panels on the table (docs/ARENA_STYLE.md, never a pop-over): the menu card the gear and
 * the pass-ahead pill open (ArenaMenuCard), Phase Stops (PhaseStopsGrid in a glass panel) and Game Settings.
 */
import type { ReactNode } from "react";
import { defaultStops, type SmartPassSettings, Step, type StepValue, stopKey } from "../../core/smartPass";

/** Small gold glyphs for the menu rows (the iOS SF symbols' shapes). */
export const GLYPHS: Record<string, ReactNode> = {
  skipResponses: <svg viewBox="0 0 20 20"><path d="M2 4l7 6-7 6zM9 4l7 6-7 6z" /><rect x="16" y="4" width="2.4" height="12" rx="1" /></svg>,
  toMyTurn: <svg viewBox="0 0 20 20"><path d="M3 4l6 6-6 6zM9 4l6 6-6 6z" /><path d="M16 4h2.4v12H16z" /><circle cx="17.2" cy="2.2" r="1.6" /></svg>,
  endTurn: <svg viewBox="0 0 20 20"><path d="M2 4l8 6-8 6zM10 4l8 6-8 6z" /></svg>,
  fullControl: <svg viewBox="0 0 20 20"><path d="M7 18c-2.2 0-3.6-1.4-4.4-3.4L1.4 11c-.3-.8.6-1.4 1.2-.8L4.5 12V4.2a1 1 0 0 1 2 0V9h.6V2.8a1 1 0 0 1 2 0V9h.6V3.4a1 1 0 0 1 2 0V9h.6V5a1 1 0 0 1 2 0v7c0 3.4-2.2 6-5.2 6z" /></svg>,
  log: <svg viewBox="0 0 20 20"><rect x="3" y="3" width="14" height="14" rx="2.5" fill="none" stroke="currentColor" strokeWidth="1.8" /><path d="M6 7h8M6 10h8M6 13h5" stroke="currentColor" strokeWidth="1.6" /></svg>,
  stack: <svg viewBox="0 0 20 20"><path d="M10 2l8 4-8 4-8-4z" /><path d="M2 10l8 4 8-4M2 14l8 4 8-4" fill="none" stroke="currentColor" strokeWidth="1.7" /></svg>,
  stops: <svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" strokeWidth="1.8" /><rect x="7" y="6" width="2" height="8" rx=".8" /><rect x="11" y="6" width="2" height="8" rx=".8" /></svg>,
  settings: <svg viewBox="0 0 24 24"><path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zm8.6 5.1-1.9-.3a7 7 0 0 1-.6 1.5l1.1 1.6-1.9 1.9-1.6-1.1c-.5.3-1 .5-1.5.6l-.3 1.9h-2.7l-.3-1.9a7 7 0 0 1-1.5-.6l-1.6 1.1-1.9-1.9 1.1-1.6c-.3-.5-.5-1-.6-1.5l-1.9-.3v-2.7l1.9-.3c.1-.5.3-1 .6-1.5L4.1 6.9 6 5l1.6 1.1c.5-.3 1-.5 1.5-.6l.3-1.9h2.7l.3 1.9c.5.1 1 .3 1.5.6L15.5 5l1.9 1.9-1.1 1.6c.3.5.5 1 .6 1.5l1.9.3z" /></svg>,
  chat: <svg viewBox="0 0 20 20"><path d="M3 4h14v9H8l-4 3v-3H3z" /></svg>,
};

export interface MenuItem { id: string; title: string; subtitle?: string; glyph?: string; lit?: boolean; enabled?: boolean; action: () => void }

/** A menu on the table: glass rows in a gold hairline on a glass card; a row closes the card, then acts. */
export function MenuCard({ items, close, style }: { items: MenuItem[]; close: () => void; style: React.CSSProperties }) {
  return (
    <>
      <div className="ascrim" onClick={(e) => { e.stopPropagation(); close(); }} aria-hidden="true" />
      <div className="amenucard glass" style={style} role="menu" onClick={(e) => e.stopPropagation()}>
        {items.map((item) => (
          <button key={item.id} type="button" role="menuitem" className={`arow ${item.lit ? "lit" : ""}`} disabled={item.enabled === false}
            data-id={item.id} aria-label={item.subtitle ? `${item.title}, ${item.subtitle}` : item.title} onClick={() => { close(); item.action(); }}>
            {item.glyph && <i className="glyph" aria-hidden="true">{GLYPHS[item.glyph]}</i>}
            <span><b>{item.title}</b>{item.subtitle && <small>{item.subtitle}</small>}</span>
          </button>
        ))}
      </div>
    </>
  );
}

/** A glass panel on the dimmed table (ArenaPanelOverlay): a gold serif title, its content, closes on a click outside. */
export function Panel({ title, close, children, width = 460 }: { title: string; close: () => void; children: ReactNode; width?: number }) {
  return (
    <div className="aoverlay panelveil" onClick={(e) => { e.stopPropagation(); close(); }}>
      <div className="apanel2 glass" style={{ width }} role="dialog" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <header><h3>{title}</h3><button type="button" className="close" aria-label="Close" onClick={close}>✕</button></header>
        <div className="body">{children}</div>
      </div>
    </div>
  );
}

/** Arena's check box: off a dim diamond, on an orange tick (ArenaCheckbox). */
export function Check({ on, label, onToggle }: { on: boolean; label: string; onToggle: () => void }) {
  return (
    <button type="button" role="checkbox" aria-checked={on} aria-label={label} className={`acheck ${on ? "on" : ""}`} onClick={onToggle}>
      <svg viewBox="0 0 20 20" aria-hidden="true">{on ? <path d="M4 10.5l4 4 8-9" /> : <path d="M10 3l7 7-7 7-7-7z" />}</svg>
    </button>
  );
}

const STEPS: StepValue[] = Object.values(Step);

/** Where smart pass stops when you have something to play: one row per step, your turn and theirs (PhaseStopsGrid). */
export function PhaseStops({ settings, onChange }: { settings: SmartPassSettings; onChange: (next: SmartPassSettings) => void }) {
  const toggle = (key: string) => {
    const stops = new Set(settings.stops);
    if (stops.has(key)) stops.delete(key); else stops.add(key);
    onChange({ ...settings, stops });
  };
  return (
    <div className="phasestops">
      {/* In the Arena look the grid speaks for itself; with smart pass off it says why nothing stops. */}
      {!settings.enabled && <p className="explain">Smart Auto-Pass is off, so every step waits for you. Turn it on in Game Settings to use these stops.</p>}
      <div className="grid">
        <span /><b>YOUR TURN</b><b>THEIRS</b>
        {STEPS.map((step) => (
          <div key={step.key} className="row">
            <span>{step.title}</span>
            <Check on={settings.stops.has(stopKey(step, true))} label={`${step.title}, your turn`} onToggle={() => toggle(stopKey(step, true))} />
            <Check on={settings.stops.has(stopKey(step, false))} label={`${step.title}, their turn`} onToggle={() => toggle(stopKey(step, false))} />
          </div>
        ))}
      </div>
      <button type="button" className="aplaque leather inline" onClick={() => onChange({ ...settings, stops: new Set(defaultStops) })}>Reset Stops</button>
    </div>
  );
}
