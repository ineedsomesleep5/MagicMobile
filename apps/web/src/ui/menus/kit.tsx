/**
 * The menus' pieces in MTG Arena's layout (iOS Menus/ArenaMenuKit.swift, ArenaPanels.swift; docs/ARENA_STYLE.md,
 * "Menus"): engraved emblems, gold caps, Arena's one button face, tab strips, option rows, check boxes, sliders,
 * steppers, glass panels and the Play blade's burning seam. Every menu page builds on these.
 */
import { type ReactNode, useEffect, useRef, useState } from "react";
import { gameAudio } from "../audio";
import { VoiceChat } from "../../core/voiceChat";
import { ManaSymbol } from "../arena/Symbols";

/** The SF Symbols the menus use, drawn as small filled glyphs in a 24-unit box. */
const GLYPH: Record<string, ReactNode> = {
  home: <path d="M12 3 2.5 11h2.7v9.5h5.3v-6h3v6h5.3V11h2.7z" />,
  profile: <><circle cx="12" cy="7.5" r="4.5" /><path d="M3.5 21c.6-5 4-8 8.5-8s7.9 3 8.5 8z" /></>,
  decks: <><rect x="6" y="3" width="13" height="16" rx="2" opacity=".55" /><rect x="3.5" y="6" width="13" height="16" rx="2" /></>,
  ranked: <path d="M6 3h12v2h3v2.5c0 3-2 5.2-4.7 5.6A6 6 0 0 1 13 16v2.5h3.5V21h-9v-2.5H11V16a6 6 0 0 1-3.3-2.9C5 12.7 3 10.5 3 7.5V5h3zm-1 4.2c0 1.6.9 2.8 2.2 3.3A9 9 0 0 1 6.2 7zm14 0h-1.2a9 9 0 0 1-1 3.3c1.3-.5 2.2-1.7 2.2-3.3z" />,
  learn: <path d="M4 4.5C6.5 3.3 9.4 3.4 11.2 5v15c-1.8-1.4-4.6-1.5-7.2-.4zm16 0c-2.5-1.2-5.4-1.1-7.2.5v15c1.8-1.4 4.6-1.5 7.2-.4z" />,
  messages: <path d="M2.5 5.5h19v13h-19zm1.8 1.3 7.7 6 7.7-6z" fillRule="evenodd" />,
  updates: <path d="M4 4h13v15a2 2 0 0 0 2 2H5.5A1.5 1.5 0 0 1 4 19.5zm2.5 3v3h8V7zm0 5v1.4h8V12zm0 3v1.4h8V15zM18 8h2.5v11.5a1.25 1.25 0 0 1-2.5 0z" />,
  settings: <path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zm8.6 5.1-1.9-.3a7 7 0 0 1-.6 1.5l1.1 1.6-1.9 1.9-1.6-1.1c-.5.3-1 .5-1.5.6l-.3 1.9h-2.7l-.3-1.9a7 7 0 0 1-1.5-.6l-1.6 1.1-1.9-1.9 1.1-1.6c-.3-.5-.5-1-.6-1.5l-1.9-.3v-2.7l1.9-.3c.1-.5.3-1 .6-1.5L4.1 6.9 6 5l1.6 1.1c.5-.3 1-.5 1.5-.6l.3-1.9h2.7l.3 1.9c.5.1 1 .3 1.5.6L15.5 5l1.9 1.9-1.1 1.6c.3.5.5 1 .6 1.5l1.9.3z" />,
  friends: <><circle cx="8.5" cy="8" r="3.6" /><circle cx="16.5" cy="8.6" r="3" /><path d="M1.5 20c.5-4.2 3.2-6.6 7-6.6s6.5 2.4 7 6.6zm14.8 0c-.2-2.3-1-4.2-2.4-5.4.9-.5 1.9-.7 2.8-.7 3 0 5.3 2.2 5.8 6.1z" /></>,
  find: <path d="M12 2.5 4 5.5v6c0 5 3.4 9 8 10.5 4.6-1.5 8-5.5 8-10.5v-6zm0 2.1v15.2c-3.3-1.4-6-4.5-6-8.3V6.9z" />,
  recent: <path d="M12 4a8 8 0 1 1-7.4 11l1.9-.7A6 6 0 1 0 6.2 9H9l-4 4-4-4h3.1A8 8 0 0 1 12 4zm-1 4h2v4.2l3.1 1.8-1 1.7-4.1-2.4z" />,
  quick: <path d="M13.5 2 5 13.5h5.5L9.5 22 19 9.5h-5.5z" />,
  custom: <><circle cx="12" cy="6.5" r="3.2" /><circle cx="5" cy="9" r="2.6" /><circle cx="19" cy="9" r="2.6" /><path d="M6.5 20c.4-3.6 2.6-5.8 5.5-5.8s5.1 2.2 5.5 5.8zM.8 18.5c.3-2.6 1.8-4.2 4-4.2.8 0 1.5.2 2.1.6A8 8 0 0 0 5 18.5zm22.4 0c-.3-2.6-1.8-4.2-4-4.2-.8 0-1.5.2-2.1.6A8 8 0 0 1 19 18.5z" /></>,
  dice: <path d="M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zm2.5 2.5a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2zm9 0a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2zM12 10.4a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2zm-4.5 4.9a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2zm9 0a1.6 1.6 0 1 0 0 3.2 1.6 1.6 0 0 0 0-3.2z" fillRule="evenodd" />,
  laurel: <path d="M12 21c-4.4-1.6-7.6-5.6-7.6-10.5 0-2.6.9-5 2.4-7l1 .7A10 10 0 0 0 6 10.5c0 4.2 2.6 7.6 6.4 9.1zM8 6.5c1.2 0 2 1 2 2.3-1.2 0-2-1-2-2.3zm-1.5 4c1.2.2 1.9 1.3 1.7 2.5-1.2-.2-1.9-1.3-1.7-2.5zm1.4 4c1.2-.1 2 .8 2.1 2-1.2.1-2-.8-2.1-2zm2.8 3c1.1-.4 2.2.2 2.5 1.3-1.1.4-2.2-.2-2.5-1.3z" />,
  ai: <path d="M8 2v2H6a2 2 0 0 0-2 2v2H2v2h2v4H2v2h2v2a2 2 0 0 0 2 2h2v2h2v-2h4v2h2v-2h2a2 2 0 0 0 2-2v-2h2v-2h-2v-4h2V8h-2V6a2 2 0 0 0-2-2h-2V2h-2v2h-4V2zm0 6h8v8H8z" fillRule="evenodd" />,
  online: <path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-3a15 15 0 0 0-1.3-3.7A8 8 0 0 1 18.9 8zM12 4.1c.9 1.2 1.6 2.5 2 3.9h-4c.4-1.4 1.1-2.7 2-3.9zM4.3 14a8 8 0 0 1 0-4h3.4a16 16 0 0 0 0 4zm.8 2h3a15 15 0 0 0 1.3 3.7A8 8 0 0 1 5.1 16zm3-8h-3a8 8 0 0 1 4.3-3.7A15 15 0 0 0 8.1 8zM12 19.9c-.9-1.2-1.6-2.5-2-3.9h4c-.4 1.4-1.1 2.7-2 3.9zm2.3-5.9H9.7a14 14 0 0 1 0-4h4.6a14 14 0 0 1 0 4zm.3 5.7c.6-1.1 1-2.4 1.3-3.7h3a8 8 0 0 1-4.3 3.7zM16.3 14a16 16 0 0 0 0-4h3.4a8 8 0 0 1 0 4z" />,
  choose: <path d="M9 2.5a1.5 1.5 0 0 1 1.5 1.5v6.6l.6-.1V5a1.5 1.5 0 0 1 3 0v5.6h.6V6.5a1.5 1.5 0 0 1 3 0v5h.6V9a1.5 1.5 0 0 1 3 0v6.5c0 3.6-2.8 6.5-6.5 6.5h-1.5c-2.2 0-4.2-1.2-5.3-3.1L5.2 14a1.5 1.5 0 0 1 2.6-1.5l-.3-.3V4A1.5 1.5 0 0 1 9 2.5z" />,
};

/** A menu icon as an engraved metal emblem, lit gold when chosen (ArenaEmblem). */
export function Emblem({ name, size = 19, lit = false }: { name: string; size?: number; lit?: boolean }) {
  return (
    <svg className={`memblem ${lit ? "lit" : ""}`} viewBox="0 0 24 24" width={size} height={size} aria-hidden="true">
      <g fill={lit ? "url(#mm-metal)" : "url(#mm-pewter)"}>{GLYPH[name]}</g>
    </svg>
  );
}

/** The gradients the emblems are cast in; mounted once at the menu's root. */
export function MetalDefs() {
  return (
    <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true">
      <defs>
        <linearGradient id="mm-metal" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#fff2c7" /><stop offset=".5" stopColor="#f0bf6b" /><stop offset="1" stopColor="#996324" /></linearGradient>
        <linearGradient id="mm-pewter" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#e6ddcc" /><stop offset="1" stopColor="#948a7a" /></linearGradient>
      </defs>
    </svg>
  );
}

/** Gold small capitals over a section or a value ("RANKED · GOLD II"). */
export function Caps({ text, size = 10.5, className = "" }: { text: string; size?: number; className?: string }) {
  return <span className={`mcaps ${className}`} style={{ fontSize: size, letterSpacing: size * 0.16 }} aria-label={text}>{text.toUpperCase()}</span>;
}

export type ButtonKind = "primary" | "secondary" | "danger" | "quiet" | "cool";

/** Arena's button (ArenaButtonFace, option A): the orange pill, the dark glass pill, the deep red one. */
export function Btn({ kind = "primary", children, onClick, disabled, className = "", sound, title, id, compact }: {
  kind?: ButtonKind; children: ReactNode; onClick?: () => void; disabled?: boolean; className?: string; sound?: string | false; title?: string; id?: string;
  compact?: boolean;
}) {
  const press = () => {
    if (sound !== false) gameAudio.play((sound ?? (kind === "secondary" ? "ui-back" : "ui-confirm")) as never);
    onClick?.();
  };
  return <button type="button" className={`mbtn ${kind} ${compact ? "compact" : ""} ${className}`} disabled={disabled} onClick={press} aria-label={title} data-id={id}>{children}</button>;
}

/** The Play plaque: the orange pill with its slow sweep of light; `cancel` is the dark pill a search shows. */
export function PlayButton({ children, onClick, disabled, cancel, id, size = 21 }: {
  children: ReactNode; onClick: () => void; disabled?: boolean; cancel?: boolean; id?: string; size?: number;
}) {
  return (
    <button type="button" className={`mbtn play ${cancel ? "secondary" : "primary"}`} style={{ fontSize: size }} disabled={disabled} data-id={id}
      onClick={() => { gameAudio.play(cancel ? "ui-back" : "menu-play"); onClick(); }}>
      {!cancel && <i className="mshine" aria-hidden="true" />}
      <span>{children}</span>
    </button>
  );
}

/** A small pill (filters, quiet links): dark glass, orange when lit (ArenaPillButtonStyle). */
export function Pill({ children, onClick, lit, disabled, id }: { children: ReactNode; onClick: () => void; lit?: boolean; disabled?: boolean; id?: string }) {
  return <button type="button" className={`mbtn pill ${lit ? "primary" : "secondary"}`} disabled={disabled} data-id={id}
    onClick={() => { gameAudio.play("ui-tap"); onClick(); }}>{children}</button>;
}

/** One line of a PopMenu: an action, a choice (ticked when `checked`), a heading, or a divider. */
export type PopItem =
  | { label: string; onClick: () => void; checked?: boolean; disabled?: boolean; danger?: boolean; id?: string }
  | { heading: string }
  | { divider: true };

/**
 * Arena's drop-down on glass (iOS BinderMenu): the trigger opens a list of actions and choices under it; a click outside
 * or Esc closes it. `align` puts its edge under the trigger's left or right.
 */
export function PopMenu({ trigger, items, label, align = "left", up, id }: {
  trigger: (open: boolean) => ReactNode; items: PopItem[]; label: string; align?: "left" | "right"; up?: boolean; id?: string;
}) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const outside = (e: PointerEvent) => { if (!root.current?.contains(e.target as Node)) setOpen(false); };
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); setOpen(false); } };
    window.addEventListener("pointerdown", outside);
    window.addEventListener("keydown", key, true);
    return () => { window.removeEventListener("pointerdown", outside); window.removeEventListener("keydown", key, true); };
  }, [open]);
  return (
    <div ref={root} className="mpopmenu">
      <button type="button" className="mpoptrigger" aria-haspopup="menu" aria-expanded={open} aria-label={label} data-id={id}
        onClick={() => { gameAudio.play(open ? "ui-back" : "ui-open"); setOpen(!open); }}>{trigger(open)}</button>
      {open && (
        <div className={`mpoplist glass ${align} ${up ? "up" : ""}`} role="menu" aria-label={label}>
          {items.map((item, index) => "divider" in item ? <hr key={index} />
            : "heading" in item ? <Caps key={index} text={item.heading} size={9.5} className="mhead" />
            : (
              <button key={index} type="button" role={item.checked === undefined ? "menuitem" : "menuitemradio"} aria-checked={item.checked}
                className={`${item.checked ? "on" : ""} ${item.danger ? "danger" : ""}`} disabled={item.disabled} data-id={item.id}
                onClick={() => { gameAudio.play("ui-tap"); setOpen(false); item.onClick(); }}>
                {item.checked !== undefined && <i />}{item.label}
              </button>
            ))}
        </div>
      )}
    </div>
  );
}

/** A small question on glass in place of a browser dialog (binderConfirm): what will happen, Cancel and the action. */
export function Question({ title, detail, action, danger, onConfirm, onCancel }: {
  title: string; detail?: string; action: string; danger?: boolean; onConfirm: () => void; onCancel: () => void;
}) {
  useEffect(() => {
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); onCancel(); } };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  }, [onCancel]);
  return (
    <div className="mquestionlayer" onPointerDown={(e) => { if (e.target === e.currentTarget) onCancel(); }}>
      <div className="mquestion glass" role="alertdialog" aria-label={title}>
        <b>{title}</b>
        {detail && <p>{detail}</p>}
        <div>
          <Btn kind="secondary" compact onClick={onCancel}>Cancel</Btn>
          <Btn kind={danger ? "danger" : "primary"} compact onClick={onConfirm}>{action}</Btn>
        </div>
      </div>
    </div>
  );
}

export function CloseButton({ onClose, label = "Close", id }: { onClose: () => void; label?: string; id?: string }) {
  return (
    <button type="button" className="mclose" aria-label={label} data-id={id} onClick={() => { gameAudio.play("ui-back"); onClose(); }}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7l10 10M17 7 7 17" /></svg>
    </button>
  );
}

export function BackChevron({ onBack }: { onBack: () => void }) {
  return (
    <button type="button" className="mback" aria-label="Back" onClick={() => { gameAudio.play("ui-back"); onBack(); }}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5 8 12l7 7" /></svg>
    </button>
  );
}

/** Arena's tab strip: words over a faint hairline, the chosen one bright over a glowing gold bar (ArenaSegmented). */
export function Segmented<T extends string | number>({ options, value, onChange, stretch, label }: {
  options: { label: string; value: T }[]; value: T; onChange: (value: T) => void; stretch?: boolean; label?: string;
}) {
  return (
    <div className={`msegmented ${stretch ? "stretch" : ""}`} role="radiogroup" aria-label={label}>
      {options.map((option) => (
        <button key={String(option.value)} type="button" role="radio" aria-checked={option.value === value} className={option.value === value ? "on" : ""}
          onClick={() => { gameAudio.play("ui-tap"); onChange(option.value); }}>{option.label}<i className="mtabbar" /></button>
      ))}
    </div>
  );
}

/** One option in a list: a diamond lit when chosen, the title, a value on the right (ArenaOptionRow). */
export function OptionRow({ title, detail, value, selected, chevron, onClick, id }: {
  title: string; detail?: string; value?: string; selected?: boolean; chevron?: boolean; onClick: () => void; id?: string;
}) {
  return (
    <button type="button" className={`moption ${selected === true ? "on" : selected === false ? "off" : ""}`} data-id={id}
      aria-pressed={selected} onClick={() => { gameAudio.play("ui-tap"); onClick(); }}>
      {selected !== undefined && <i className="mdiamond" aria-hidden="true" />}
      <span className="grow"><b>{title}</b>{detail && <small>{detail}</small>}</span>
      {value && <em>{value}</em>}
      {chevron && <svg className="mchev" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7" /></svg>}
    </button>
  );
}

/** Arena's Options check box: off a dim diamond, on an orange tick; the explanation is the hover title (ArenaCheckbox). */
export function Checkbox({ title, on, onChange, hint, disabled, id }: {
  title: string; on: boolean; onChange: (on: boolean) => void; hint?: string; disabled?: boolean; id?: string;
}) {
  return (
    <button type="button" role="checkbox" aria-checked={on} className={`mcheck ${on ? "on" : ""}`} disabled={disabled} title={hint} data-id={id}
      onClick={() => { if (!on) gameAudio.play("ui-toggle"); onChange(!on); }}>
      <i aria-hidden="true">{on ? <svg viewBox="0 0 24 24"><path className="under" d="M4.5 12.5l5 5 10-11" /><path d="M4.5 12.5l5 5 10-11" /></svg> : <span />}</i>
      <span>{title}</span>
    </button>
  );
}

/** A level as Arena's thin line: an ember fill and a gold diamond knob (ArenaSlider); arrow keys step it. */
export function Slider({ value, min = 0, max = 1, step, onChange, label, valueText, disabled }: {
  value: number; min?: number; max?: number; step?: number; onChange: (value: number) => void; label: string; valueText?: string; disabled?: boolean;
}) {
  const track = useRef<HTMLDivElement>(null);
  const fraction = Math.min(1, Math.max(0, (value - min) / Math.max(0.0001, max - min)));
  const set = (clientX: number) => {
    const rect = track.current?.getBoundingClientRect();
    if (!rect) return;
    const knob = 16;
    const position = Math.min(1, Math.max(0, (clientX - rect.left - knob / 2) / Math.max(1, rect.width - knob)));
    let next = min + position * (max - min);
    if (step) next = Math.round(next / step) * step;
    onChange(next);
  };
  return (
    <div ref={track} className={`mslider ${disabled ? "disabled" : ""}`} role="slider" tabIndex={disabled ? -1 : 0} aria-label={label} aria-valuemin={min}
      aria-valuemax={max} aria-valuenow={value} aria-valuetext={valueText} style={{ ["--f" as string]: fraction }}
      onPointerDown={(e) => { if (disabled) return; e.currentTarget.setPointerCapture(e.pointerId); set(e.clientX); }}
      onPointerMove={(e) => { if (!disabled && e.currentTarget.hasPointerCapture(e.pointerId)) set(e.clientX); }}
      onKeyDown={(e) => {
        const delta = step ?? (max - min) / 20;
        if (e.key === "ArrowRight" || e.key === "ArrowUp") { e.preventDefault(); onChange(Math.min(max, value + delta)); }
        if (e.key === "ArrowLeft" || e.key === "ArrowDown") { e.preventDefault(); onChange(Math.max(min, value - delta)); }
      }}>
      <i className="track" /><i className="fill" /><i className="knob" />
    </div>
  );
}

/** A count with glass − and + rings around the value (ArenaStepper). */
export function Stepper({ title, value, min, max, onChange, valueText, compact, id }: {
  title: string; value: number; min: number; max: number; onChange: (value: number) => void; valueText?: string; compact?: boolean; id?: string;
}) {
  const ring = (label: string, glyph: string, enabled: boolean, next: number) => (
    <button type="button" className="mring" aria-label={label} disabled={!enabled} onClick={() => { gameAudio.play("ui-tap"); onChange(next); }}>{glyph}</button>
  );
  return (
    <div className={`mstepper ${compact ? "compact" : ""}`} data-id={id}>
      <span className="grow">{title}</span>
      {ring(`Lower ${title}`, "−", value > min, Math.max(min, value - 1))}
      <output aria-live="polite">{valueText ?? value}</output>
      {ring(`Raise ${title}`, "+", value < max, Math.min(max, value + 1))}
    </div>
  );
}

/** A search field as a dark capsule in the gold hairline. */
export function SearchField({ placeholder, value, onChange, autoFocus }: { placeholder: string; value: string; onChange: (value: string) => void; autoFocus?: boolean }) {
  return (
    <label className="msearch">
      <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6" /><path d="M15 15l5.5 5.5" /></svg>
      <input value={value} placeholder={placeholder} spellCheck={false} autoFocus={autoFocus} onChange={(e) => onChange(e.target.value)} aria-label={placeholder} />
      {value && <button type="button" aria-label="Clear search" onClick={() => onChange("")}>✕</button>}
    </label>
  );
}

/** A heading over a shelf of deck boxes: a chevron that folds it, the title and how many (ArenaSectionHeader). */
export function SectionHeader({ title, count, collapsed, onToggle }: { title: string; count?: number; collapsed?: boolean; onToggle?: () => void }) {
  const inner = <>
    {onToggle && <svg className={`mfold ${collapsed ? "shut" : ""}`} viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" /></svg>}
    <b>{title}</b>{count !== undefined && <small>{count}</small>}
  </>;
  return onToggle
    ? <button type="button" className="msection" aria-expanded={!collapsed} onClick={onToggle}>{inner}</button>
    : <div className="msection" role="heading" aria-level={3}>{inner}</div>;
}

/** The Play blade's lit edge: an ember seam that flickers like a flame (ArenaSeam). */
export function Seam({ vertical }: { vertical: boolean }) {
  return <i className={`mseam ${vertical ? "vertical" : "horizontal"}`} aria-hidden="true" />;
}

/** The glowing gold bar under a chosen tab. */
export const TabBar = ({ on }: { on: boolean }) => <i className={`mtabbar ${on ? "on" : ""}`} aria-hidden="true" />;

/** A deck's colours as mana symbols in WUBRG order; colourless when it has none (ArenaPips). */
export function Pips({ colors, size = 15 }: { colors: string[]; size?: number }) {
  const shown = ["W", "U", "B", "R", "G"].filter((c) => colors.includes(c));
  return <span className="mpips" aria-hidden="true">{(shown.length ? shown : ["C"]).map((c) => <ManaSymbol key={c} symbol={c} size={size} />)}</span>;
}

/** Something new waiting: a small lit diamond (ArenaUnreadPip). */
export const UnreadPip = () => <i className="mpip" aria-hidden="true" />;

/**
 * The menus are laid out in the phones' points; a desktop window shows them a little larger, as a tablet would, up to
 * 1.5× on a big screen.
 */
export function useMenuZoom() {
  const measure = () => Math.min(1.5, Math.max(1, Math.min(window.innerWidth / 1100, window.innerHeight / 620)));
  const [zoom, setZoom] = useState(measure);
  useEffect(() => {
    const resize = () => setZoom(measure());
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  return zoom;
}

export type PanelPlacement = "center" | "leading" | "trailing";

/**
 * A menu page as Arena's glass panel over the dimmed menu, below the top bar (arenaPanel): centred like Options, along
 * the left like the social panel, or a blade from the right like the inbox. A click on the dim or Esc closes it unless
 * it must be answered.
 */
export function MenuPanel({ open, onClose, placement = "center", maxWidth = 680, dismissable = true, fits, children, label }: {
  open: boolean; onClose: () => void; placement?: PanelPlacement; maxWidth?: number; dismissable?: boolean; fits?: boolean; children: ReactNode; label: string;
}) {
  const [shown, setShown] = useState(open);
  const [leaving, setLeaving] = useState(false);
  useEffect(() => {
    if (open) { setShown(true); setLeaving(false); return; }
    if (!shown) return;
    setLeaving(true);
    const timer = window.setTimeout(() => { setShown(false); setLeaving(false); }, 220);
    return () => window.clearTimeout(timer);
  }, [open, shown]);
  useEffect(() => {
    if (!open || !dismissable) return;
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); gameAudio.play("ui-back"); onClose(); } };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  }, [open, dismissable, onClose]);
  if (!shown) return null;
  return (
    <div className={`mpanelhost ${placement} ${leaving ? "leaving" : ""}`}>
      <div className="mdim" onClick={() => { if (dismissable) { gameAudio.play("ui-back"); onClose(); } }} />
      <div className={`mpanel glass ${placement} ${fits ? "fits" : ""}`} style={placement === "center" ? { maxWidth } : undefined} role="dialog" aria-modal="true" aria-label={label}>
        {placement === "trailing" && <Seam vertical />}
        {children}
      </div>
    </div>
  );
}

/** A panel's head: an optional back chevron, the title, the close button, over a gold hairline (ArenaPanelHeader). */
export function PanelHeader({ title, onBack, onClose, centered }: { title: string; onBack?: () => void; onClose: () => void; centered?: boolean }) {
  return (
    <header className={`mpanelhead ${centered ? "centered" : ""}`}>
      {onBack ? <BackChevron onBack={onBack} /> : centered ? <span className="mspacer" /> : null}
      <h2>{title}</h2>
      <CloseButton onClose={onClose} />
    </header>
  );
}

/** Push to talk's key, beside its label: a click, then the next key pressed becomes it (Escape keeps the old one). */
export function TalkKeyButton({ code, onChange, id }: { code: string; onChange: (code: string) => void; id?: string }) {
  const [listening, setListening] = useState(false);
  useEffect(() => {
    if (!listening) return undefined;
    const key = (e: KeyboardEvent) => {
      e.preventDefault(); e.stopPropagation();
      if (e.code === "Escape") { setListening(false); return; }
      if (!VoiceChat.bindable(e.code)) return;
      onChange(e.code);
      setListening(false);
    };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  }, [listening, onChange]);
  return (
    <span className="mtalkkey"><span>Talk Key</span>
      <button type="button" data-id={id} aria-label={`Push-to-talk key: ${VoiceChat.keyLabel(code)}`} className={listening ? "on" : ""}
        onClick={() => { gameAudio.play("ui-tap"); setListening(true); }}>{listening ? "Press a key" : VoiceChat.keyLabel(code)}</button>
    </span>
  );
}
