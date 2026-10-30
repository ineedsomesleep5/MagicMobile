/**
 * Arena browsers, the iOS Arena board's (ArenaBoardViews.swift, docs/ARENA_STYLE.md; Caleb, 2026-10-21: the phone's Arena
 * build is the baseline): no panel. The table dims, a serif title and one line sit at the top, the cards stand in the
 * middle, the answers sit under them as plaques, the card it's about stands on the right, and "View Battlefield" (top
 * right) steps the browser aside. A number is the reference's pill in the button corner instead (ArenaAmountPill), with
 * the board in view. They send exactly the commands the old prompt panel sent, so the engine never changes for a look.
 */
import { useEffect, useRef, useState } from "react";
import { commanderEntries } from "../../core/arenaBoard";
import { CardChoicePlan, CardChoicePlanRules } from "../../core/cardChoicePlan";
import { EngineDisplayText } from "../../core/displayText";
import {
  displayToughness, type GameCommand, type GameSnapshot, isCreatureCard, isOut, isUuid, type LegalAction, pileNumber, type PlayerGameState, promptKind,
  type PromptEnvelopeV2, type XmagePromptAbility, type XmagePromptPile, type XmageStackObject, type ZoneCard,
} from "../../core/models";
import { CARD_BACK_URL, cardImageURL, permitsArtName } from "../cardArt";
import { AbilityCard, isStackAbility } from "./AbilityCard";
import { HScroller } from "./HScroller";
import { Portrait } from "./avatars";
import { type CardReader, readProps } from "./inspectGesture";
import { CountBadge, ManaSymbol, RulesText } from "./Symbols";

export type Send = (command: Omit<GameCommand, "gameId" | "playerId" | "promptId" | "messageId">, label: string) => void;
export type SendAction = (action: LegalAction) => void;
export type BrowserKind = "mulligan" | "question" | "amount" | "split" | "piles" | "abilities" | "modes" | "choices" | "cards" | "players";
/** Reads a card in a browser: a right-click, or a press held still (hovering only lifts it). */
export type Inspect = CardReader;

// ---------------- reading XMage's prompts ----------------

/** XMage's text without markup or ids. */
const clean = (text: string) => EngineDisplayText.text(text).replace(/\s*\[[0-9a-f]{3,}\]/gi, "").trim();
const lines = (text: string) => clean(text).split("\n").map((s) => s.trim()).filter(Boolean);
/** "Doubling Season [8f2]" is Doubling Season. */
const stripID = (name: string) => name.replace(/\s*\[[^\]]*\]\s*$/, "").trim();

/** Every card the viewer can see: the battlefield, graveyards, exile, command zones, your hand, the stack's cards. */
export function visibleCards(snapshot: GameSnapshot): ZoneCard[] {
  const cards: ZoneCard[] = [];
  for (const player of snapshot.players) {
    const zones = player.zones;
    cards.push(...zones.battlefield, ...zones.graveyard, ...zones.exile, ...zones.command);
    if (player.playerId === snapshot.viewerPlayerId) cards.push(...zones.hand);
  }
  for (const item of snapshot.xmage?.stack ?? []) if (item.sourceCard) cards.push(item.sourceCard);
  return cards;
}

/** The card a choice names: on the battlefield first, then anywhere you can see (arenaCard(named:)). */
export function cardNamed(snapshot: GameSnapshot, name: string): ZoneCard | undefined {
  const battlefield = snapshot.players.flatMap((p) => p.zones.battlefield);
  return battlefield.find((c) => c.card.name === name) ?? visibleCards(snapshot).find((c) => c.card.name === name);
}

/** The card a stack object comes from: XMage's own, else its permanent on the table, else one of its name there. */
export function stackSource(object: XmageStackObject, snapshot: GameSnapshot): ZoneCard | undefined {
  if (object.sourceCard) return object.sourceCard;
  const battlefield = snapshot.players.flatMap((p) => p.zones.battlefield);
  const byID = object.sourceInstanceId ? battlefield.find((c) => c.instanceId === object.sourceInstanceId) : undefined;
  return byID ?? (object.sourceName ? battlefield.find((c) => c.card.name === object.sourceName) : undefined);
}
const sourceName = (object: XmageStackObject) => object.sourceCard?.card.name ?? object.sourceName ?? object.name;

const REMEMBER = "Remember answer: ";
export interface ChoiceOption { id: string; rememberID?: string; label: string; name?: string; text: string }

/**
 * XMage's named choices (ArenaChoiceList): each "Remember answer: X" pairs with its X (one "Remember my choice" toggle
 * instead of a second list), and "Doubling Season: If an effect…" splits into the card it names and that card's text.
 */
export function choiceOptions(choices: { id: string; label: string }[]): ChoiceOption[] {
  const remembered = new Map<string, string>();
  for (const choice of choices) {
    const key = choice.label.slice(REMEMBER.length);
    if (choice.label.startsWith(REMEMBER) && !remembered.has(key)) remembered.set(key, choice.id);
  }
  return choices.filter((c) => !c.label.startsWith(REMEMBER)).map((choice) => {
    const colon = choice.label.indexOf(": ");
    const named = colon > 0 && colon <= 40;
    return {
      id: choice.id, rememberID: remembered.get(choice.label), label: choice.label,
      name: named ? stripID(choice.label.slice(0, colon)) : undefined, text: named ? choice.label.slice(colon + 2) : choice.label,
    };
  });
}

/** "White" or "Red mana" as its mana symbol, for colour choices. */
export function colorSymbol(label: string): string | undefined {
  const word = label.toLowerCase().replace(" mana", "").trim();
  return ({ white: "W", blue: "U", black: "B", red: "R", green: "G", colorless: "C", colourless: "C" } as Record<string, string>)[word];
}

/** Which browser a prompt needs, or none when it is answered on the table (priority, combat, payment, table targets). */
export function browserKind(envelope: PromptEnvelopeV2 | undefined, onTable: (id: string) => boolean,
  named: (name: string) => boolean = () => false): BrowserKind | undefined {
  if (!envelope) return undefined;
  if (envelope.confirmation) return /mulligan/i.test(envelope.message) ? "mulligan" : "question";
  if (envelope.responseKind === "priority") return undefined;
  if (envelope.method === "GAME_SELECT" && envelope.responseKind === "target") return undefined;
  if (envelope.responseKind === "x_mana") return "amount";
  const kind = promptKind(envelope);
  if (kind === "payment") return undefined;
  if (envelope.multiAmounts?.length) return "split";
  if (envelope.piles?.length) return "piles";
  if (envelope.abilities?.length) return "abilities";
  if (envelope.modes?.length) return "modes";
  if (envelope.choices?.length) {
    // A few plain answers are a question (ArenaQuestionStage); a long list, one naming a card, or one with XMage's
    // "Remember answer" twins is the choice browser (arenaChoicePrompt).
    const options = choiceOptions(envelope.choices);
    const browse = envelope.choices.length > 3 || options.length < envelope.choices.length || options.some((o) => o.name !== undefined && named(o.name));
    return browse ? "choices" : "question";
  }
  if (envelope.players?.length) return "players";
  if (kind === "amount") return "amount";
  if (kind === "target") {
    const targets = envelope.targets ?? [];
    if (/starting player/i.test(envelope.message)) return "players";
    const ids = [...(envelope.cards ?? []).map((c) => c.instanceId), ...targets.map((t) => t.id), ...(envelope.targetIds ?? [])];
    return ids.length > 0 && ids.every(onTable) ? undefined : "cards";
  }
  return undefined;
}

/** "Choose target creature or player" → a title and an instruction line. */
function heading(envelope: PromptEnvelopeV2, fallback: string): { title: string; line?: string } {
  const [first, ...rest] = lines(envelope.message);
  if (!first) return { title: fallback };
  if (first.length <= 48) return { title: first, line: rest.join(" ") || undefined };
  return { title: fallback, line: [first, ...rest].join(" ") };
}

/**
 * The question in a few words, the reference's way ("Use Esper Sentinel's ability?"), with the rest of XMage's message
 * under it when it says more (ArenaQuestionStage.headline; Caleb, 2026-10-21: long questions filled the screen). Otherwise
 * its first sentence over the rest, or the whole question when it is one long sentence: never cut off, never said twice
 * (the judge, 2026-10-22).
 */
export function headline(message: string, subject: string | undefined, ability: boolean): { title: string; detail?: string } {
  const text = lines(message).join(" ");
  if (text.length <= 64 || subject === undefined) return { title: text };
  const mark = text.indexOf("?");
  if (mark >= 0 && mark < 64) {
    const rest = text.slice(mark + 1).trim();
    return { title: text.slice(0, mark + 1), detail: rest || undefined };
  }
  // "Use X's ability?" only when the message is about X; otherwise its first sentence.
  if (subject && ability && text.toLowerCase().includes(subject.toLowerCase())) return { title: `Use ${subject}'s ability?`, detail: text };
  const stop = text.indexOf(". ");
  if (stop >= 0 && stop < 70) {
    const rest = text.slice(stop + 2).trim();
    return { title: `${text.slice(0, stop)}.`, detail: rest || undefined };
  }
  return { title: text };
}

/**
 * The card a question is about (arenaQuestion): the top of the stack when it names its source, else a card of the
 * prompt's, else the card with the longest name it mentions; "you may" means the top of the stack.
 */
export function questionSubject(snapshot: GameSnapshot, envelope: PromptEnvelopeV2): { object?: XmageStackObject; card?: ZoneCard } {
  const message = envelope.message.toLowerCase();
  const top = snapshot.xmage?.stack[0];
  let object: XmageStackObject | undefined;
  let card: ZoneCard | undefined;
  if (top && (message.includes(sourceName(top).toLowerCase()) || message.includes(top.name.toLowerCase()))) object = top;
  else if (envelope.cards?.[0]) card = envelope.cards[0];
  else {
    card = visibleCards(snapshot).filter((c) => c.card.name !== "" && message.includes(c.card.name.toLowerCase()))
      .sort((a, b) => b.card.name.length - a.card.name.length)[0];
  }
  if (!object && !card && top && message.includes("you may")) object = top;
  // An ability whose card XMage didn't send shows its permanent's art from the table.
  if (object && !object.sourceCard && !card) card = stackSource(object, snapshot);
  return { object, card };
}

/** The values the amount pill steps through (ArenaAmountRange): XMage's list, else min to max (an open max stops 99 on). */
export function amountValues(amounts: number[] | undefined, minimum: number | undefined, maximum: number | undefined): number[] {
  if (amounts && amounts.length > 0) return [...new Set(amounts)].sort((a, b) => a - b);
  const low = minimum ?? 0;
  const high = Math.max(low, Math.min(maximum ?? low + 99, low + 999));
  return Array.from({ length: high - low + 1 }, (_, i) => low + i);
}
/** `places` along the allowed values, held at the ends. */
export function stepAmount(values: number[], value: number, places: number): number {
  let index = values.indexOf(value);
  if (index < 0) index = Math.max(0, values.findIndex((v) => v >= value));
  return values[Math.min(Math.max(index + places, 0), values.length - 1)];
}
/** The nearest allowed value. */
export const clampAmount = (values: number[], value: number) =>
  values.reduce((best, v) => (Math.abs(v - value) < Math.abs(best - value) ? v : best), values[0] ?? value);
/** The largest X `sources` mana pays for a spell costing `cost` (with its X), as the pill's first value. */
export function affordableX(cost: string, sources: number): number | undefined {
  const symbols = [...cost.toUpperCase().matchAll(/\{([^}]+)\}/g)].map((m) => m[1]);
  const xs = symbols.filter((s) => s === "X").length;
  if (xs === 0) return undefined;
  const fixed = symbols.reduce((total, s) => (s === "X" ? total : total + (/^\d+$/.test(s) ? Number(s) : 1)), 0);
  return Math.max(0, Math.floor((sources - fixed) / xs));
}

/** "Grizzly Bears, P/T: 2/2" or "Grizzly Bears [8f2]" is Grizzly Bears (ArenaSplit.name). */
export const splitName = (label: string) => stripID(label.split(", P/T:")[0]);
/** Damage that destroys a creature: what's left of its toughness, or 1 from a source with deathtouch. */
export const lethalDamage = (toughness: number, damage: number, deathtouch: boolean) => (deathtouch ? 1 : Math.max(1, toughness - damage));

// ---------------- pieces ----------------

const read = (inspect: Inspect | undefined, name: string | undefined, card?: ZoneCard) => readProps(inspect, name ? { name, card } : undefined);

/** The printed card, at a width in board points: a hidden card is its back, your own face-down card its face dimmed. */
function Printed({ name, card, width, inspect, className = "" }: { name: string; card?: ZoneCard; width: number; inspect?: Inspect; className?: string }) {
  return <img className={`bprinted ${card?.card.faceDown === true ? "facedown" : ""} ${className}`} src={permitsArtName(name) ? cardImageURL(name, "normal") : CARD_BACK_URL}
    alt={name} crossOrigin="anonymous" draggable={false}
    style={{ width, height: width * 1.397 }} {...read(inspect, name, card)} />;
}

/** What a question or browser is about: an ability as its ability card, a spell or card as itself. */
function Subject({ object, card, snapshot, width, inspect }: {
  object?: XmageStackObject; card?: ZoneCard; snapshot: GameSnapshot; width: number; inspect?: Inspect;
}) {
  if (object && (isStackAbility(object) || !object.sourceCard)) {
    const source = card ?? stackSource(object, snapshot);
    return (
      <div className="bsubject" {...read(inspect, source?.card.name, source)}>
        <AbilityCard source={source} name={source ? undefined : object.sourceName ?? object.name} text={object.rulesText ?? object.name} width={width} />
      </div>
    );
  }
  const shown = object?.sourceCard ?? card;
  return shown ? <Printed name={shown.card.name} card={shown} width={width} inspect={inspect} className="bsubject" /> : null;
}

/** A button that keeps stepping while it is held, after a short wait (ArenaRepeatButton); `step` says if it moved. */
function RepeatButton({ step, repeats = true, disabled, className, label, children }: {
  step: () => boolean; repeats?: boolean; disabled?: boolean; className: string; label: string; children: React.ReactNode;
}) {
  const timer = useRef<number | undefined>(undefined);
  const stop = () => { window.clearTimeout(timer.current); window.clearInterval(timer.current); timer.current = undefined; };
  useEffect(() => stop, []);
  return (
    <button type="button" className={className} disabled={disabled} aria-label={label}
      onPointerDown={(event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        stop();
        if (!step() || !repeats) return;
        timer.current = window.setTimeout(() => { timer.current = window.setInterval(() => { if (!step()) stop(); }, 90); }, 420);
      }}
      onPointerUp={stop} onPointerLeave={stop} onPointerCancel={stop}
      onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); step(); } }}>
      {children}
    </button>
  );
}

/** The dimmed table and the "View Battlefield" capsule that steps a browser aside (and back). */
function Veil({ back, onDismiss, children }: { back: string; onDismiss?: () => void; children: React.ReactNode }) {
  const [peeking, setPeeking] = useState(false);
  return (
    <div className={`aoverlay abrowse ${peeking ? "peek" : ""}`}
      onClick={(event) => { if (onDismiss && !peeking && (event.target as HTMLElement).dataset.veil !== undefined) onDismiss(); }}>
      {children}
      <button type="button" className="bview" onClick={() => setPeeking(!peeking)}>{peeking ? back : "View Battlefield"}</button>
    </div>
  );
}

interface Subjected { object?: XmageStackObject; card?: ZoneCard }

/**
 * The frame every browser shares (ArenaBrowserFrame): title and line, content, answers, the source card on the right.
 * The cards stand in one sideways row (HScroller) unless `column`; `above` and `below` sit outside it (a search field,
 * a list of non-card targets), so the row is only cards.
 */
export function Frame({ title, detail, heading, subject, snapshot, k, inspect, footer, column, above, below, back = "Back to the choice", onDismiss, children }: {
  title: string; detail?: string; subject?: Subjected; snapshot: GameSnapshot; k: number; inspect?: Inspect; footer?: React.ReactNode;
  /** A header of the browser's own in place of the title and detail lines. */
  heading?: React.ReactNode;
  column?: boolean; above?: React.ReactNode; below?: React.ReactNode; back?: string; onDismiss?: () => void;
  /** The cards, or a function sizing them from the row's height (HScroller). */
  children: React.ReactNode | ((rowHeight: number | undefined) => React.ReactNode);
}) {
  const shows = subject !== undefined && (subject.object !== undefined || subject.card !== undefined);
  return (
    <Veil back={back} onDismiss={onDismiss}>
      <div className={`bbody ${shows ? "sourced" : ""}`} data-veil="" style={shows ? { paddingRight: 124 * k + 40 } : undefined}>
        <header data-veil="">{heading ?? <><h2><RulesText text={title} /></h2>{detail && <p><RulesText text={detail} /></p>}</>}</header>
        {above}
        {column ? <div className="bcontent column" data-veil="">{typeof children === "function" ? children(undefined) : children}</div>
          : <HScroller>{children}</HScroller>}
        {below}
        {footer && <div className="bfoot">{footer}</div>}
      </div>
      {shows && <div className="bsource"><Subject {...subject} snapshot={snapshot} width={124 * k} inspect={inspect} /></div>}
    </Veil>
  );
}

// ---------------- the browsers ----------------

interface Props {
  snapshot: GameSnapshot; envelope: PromptEnvelopeV2; send: Send; sendAction: SendAction; pending: boolean;
  /** The board's height in points (440 to 717), which sizes the cards. */
  height: number;
  inspect?: Inspect;
  /** Answer actions this engine accepts (remembered answers and trigger order). */
  answerActions?: ReadonlySet<string>;
  /** Orders every trigger at once: `resolveOrder` first resolves first (the board's trigger plan answers the rest). */
  orderTriggers?: (resolveOrder: XmagePromptAbility[], remember: boolean) => void;
  /** Delivers a drafted card choice one native answer at a time (the board's CardChoicePlan driver). */
  commitPlan?: (plan: CardChoicePlan) => void;
}

/** XMage offers to remember this yes/no answer (PromptEnvelopeV2.canRememberAnswer). */
export const canRememberAnswer = (envelope: PromptEnvelopeV2) => {
  const options = envelope.options ?? {};
  const original = typeof options.originalId === "string" ? options.originalId : undefined;
  const message = typeof options.autoAnswerMessage === "string" ? options.autoAnswerMessage : undefined;
  return envelope.method === "GAME_ASK" && original !== undefined && isUuid(original) && message !== undefined && message.length > 0;
};

/** XMage's own answers to the prompt (Cancel, Done), less the ones a browser makes itself. */
const promptAnswers = (snapshot: GameSnapshot, ...except: string[]) =>
  (snapshot.legalActions ?? []).filter((a) => a.cardInstanceId === undefined && a.sourceInstanceId === undefined && !except.includes(a.type));
const plaques = (actions: LegalAction[], sendAction: SendAction, pending: boolean, kind: AnswerKind | ((label: string) => AnswerKind) = "secondary") =>
  actions.map((action) => {
    const label = EngineDisplayText.label(action.label);
    return <button key={action.id} type="button" className={`aplaque ${typeof kind === "function" ? kind(label) : kind}`} disabled={pending} onClick={() => sendAction(action)}>{label}</button>;
  });
type AnswerKind = "primary" | "secondary" | "cool" | "danger";
/**
 * The question stage's pills (CompactPromptPopup's stage, PanelActionButtonStyle): Arena's blue declines ("No", "Cancel",
 * "Decline"), the orange pill takes every other answer; words only.
 */
export const questionAnswerKind = (label: string): AnswerKind =>
  ["no", "cancel", "decline", "mulligan"].includes(label.trim().toLowerCase()) ? "cool" : "primary";

/**
 * An answer as the question stage's pill says it: no "(source: Force of Negation [c1f])", and a cast's cost in its own
 * words, since the headline already asks about alternative costs. Display only: the answer sent stays the choice's id.
 */
export const answerLabel = (label: string) =>
  clean(EngineDisplayText.label(label)).replace(/\s*\(source: [^)]*\)$/i, "")
    .replace(/^cast with no alternative cost:\s*(?=\{)/i, "Pay ")
    .replace(/^cast with alternative cost:\s*(.)/i, (_, first: string) => first.toUpperCase());

/** "Don't ask again" on the Arena board (RememberChoiceToggle): a gold diamond and light words, no system check box. */
function RememberToggle({ on, set, title }: { on: boolean; set: (on: boolean) => void; title: string }) {
  return (
    <button type="button" role="checkbox" aria-checked={on} className="bremember" onClick={() => set(!on)}>
      <i aria-hidden="true" />{title}
    </button>
  );
}

export function Browser(props: Props & { kind: Exclude<BrowserKind, "mulligan" | "amount"> }) {
  switch (props.kind) {
    case "question": return <QuestionStage {...props} />;
    case "modes": return <ModeBrowser {...props} />;
    case "abilities": return <AbilityBrowser {...props} />;
    case "choices": return <ChoiceBrowser {...props} />;
    case "players": return <PlayerChoice {...props} />;
    case "split": return <SplitBrowser {...props} />;
    case "piles": return <PileBrowser {...props} />;
    case "cards": return <CardChoice {...props} />;
  }
}

/** A question the Arena way (ArenaQuestionStage; the reference's "Pay 2 life?"): its card in the middle, answers under it. */
function QuestionStage({ snapshot, envelope, send, sendAction, pending, height, inspect, answerActions }: Props) {
  const [remember, setRemember] = useState(false);
  const rememberable = envelope.confirmation !== undefined && canRememberAnswer(envelope) && answerActions?.has("rememberAnswer") === true;
  const remembering = rememberable && remember ? { answerActions: ["rememberAnswer"] } : {};
  const { object, card } = questionSubject(snapshot, envelope);
  const subject = object ? sourceName(object) : card?.card.name;
  const { title, detail } = headline(envelope.message, subject, object !== undefined && isStackAbility(object));
  const cardHeight = Math.min(height * 0.48, 250);
  const confirmation = envelope.confirmation;
  return (
    <Veil back="Back to the question">
      <div className="bstage">
        <header><h2><RulesText text={title} /></h2>{detail && <p><RulesText text={detail} /></p>}</header>
        {(object || card) && <Subject object={object} card={card} snapshot={snapshot} width={cardHeight * 0.72} inspect={inspect} />}
        <div className="answers">
          {confirmation ? (
            <>
              <button type="button" className={`aplaque ${questionAnswerKind(confirmation.yesLabel ?? "Yes")}`} disabled={pending}
                onClick={() => send({ type: "answer_yes_no", confirmed: true, ...remembering }, confirmation.yesLabel ?? "Yes")}>{confirmation.yesLabel ?? "Yes"}</button>
              <button type="button" className={`aplaque ${questionAnswerKind(confirmation.noLabel ?? "No")}`} disabled={pending}
                onClick={() => send({ type: "answer_yes_no", confirmed: false, ...remembering }, confirmation.noLabel ?? "No")}>{confirmation.noLabel ?? "No"}</button>
            </>
          ) : (envelope.choices ?? []).map((choice) => (
            <button key={choice.id} type="button" className={`aplaque ${questionAnswerKind(EngineDisplayText.label(choice.label))}`} disabled={pending}
              onClick={() => send({ type: "resolve_choice", choiceIds: [choice.id] }, choice.label)}><span><RulesText text={answerLabel(choice.label)} /></span></button>
          ))}
          {plaques(promptAnswers(snapshot, "answer_yes_no", "resolve_choice"), sendAction, pending, questionAnswerKind)}
        </div>
        {rememberable && <RememberToggle on={remember} set={setRemember} title="Don’t ask again this game" />}
      </div>
    </Veil>
  );
}

/** A modal spell's modes (ArenaModeBrowser): each mode a card with the spell's art over its text; a click chooses it. */
function ModeBrowser({ snapshot, envelope, send, sendAction, pending, height, inspect }: Props) {
  const message = envelope.message.split("\n");
  // The spell is named on the prompt's second line ("Black Market Connections [4cb]"), else it is the top of the stack.
  const named = message.length > 1 ? visibleCards(snapshot).find((c) => c.card.name === stripID(clean(message[1]))) : undefined;
  const source = named ?? snapshot.xmage?.stack[0]?.sourceCard;
  const max = envelope.maxChoices ?? 1;
  const title = max > 1 ? "Choose modes" : "Choose a mode";
  const firstLine = lines(envelope.message)[0];
  const bounds = CardChoicePlanRules.selectionBounds(envelope.message);
  const said = bounds ? (CardChoicePlanRules.isUnbounded(bounds) ? "Any number" : bounds[0] === bounds[1] ? `Choose ${bounds[1]}`
    : bounds[0] > 0 ? `Up to ${bounds[1]}, at least ${bounds[0]}` : `Up to ${bounds[1]}`)
    : firstLine && !/^choose (a )?modes?\.?$/i.test(firstLine) ? firstLine : undefined;
  const detail = said && said.toLowerCase() !== title.toLowerCase() ? said : undefined;
  const width = Math.min(height * 0.52, 290) * 0.72;
  return (
    <Frame title={title} detail={detail} snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={plaques(promptAnswers(snapshot, "choose_mode"), sendAction, pending, "primary")}>
      {envelope.modes!.map((mode, index) => (
        <button key={mode.id} type="button" className="bpick" disabled={pending} aria-label={clean(mode.label)} {...read(inspect, source?.card.name, source)}
          onClick={() => send({ type: "choose_mode", modeIds: [mode.id] }, mode.label)}>
          <AbilityCard source={source} name={source ? undefined : `Mode ${index + 1}`} kind={source ? `Mode ${index + 1}` : "Mode"}
            text={clean(mode.label).replace(/^\d+\.\s*/, "")} width={width} />
        </button>
      ))}
    </Frame>
  );
}

/**
 * The ability browser's card height in board points: as tall as its row allows, keeping the row's padding and a picked
 * card's lift (between 150 and 340); until the row is measured, half the board as on iOS (ArenaAbilityBrowser.cardSize).
 */
export function abilityCardHeight(rowHeight: number | undefined, boardHeight: number): number {
  if (rowHeight === undefined) return Math.min(boardHeight * 0.5, 280);
  return Math.max(150, Math.min(340, (rowHeight - 36) / 1.04));
}

/**
 * Abilities and triggers as the reference's ability cards in a row (ArenaAbilityBrowser). Choosing an ability: a click
 * picks it. Ordering triggers: clicks number them in the order they resolve (1 resolves first); Done (from all but one
 * numbered) or Auto Order hands the whole order to the board, which answers XMage's one-at-a-time questions itself.
 */
function AbilityBrowser({ snapshot, envelope, send, sendAction, pending, height, inspect, answerActions, orderTriggers }: Props) {
  const ordering = envelope.method === "GAME_PICK_ABILITY" && orderTriggers !== undefined;
  const [picked, setPicked] = useState<string[]>([]);
  const [remember, setRemember] = useState(false);
  const abilities = envelope.abilities!;
  const { title, line } = ordering ? { title: "Order your triggers", line: "Tap them in the order they resolve: 1 resolves first." }
    : heading(envelope, "Choose an ability");
  const toggle = (id: string) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : [...p, id]));
  const ready = picked.length >= abilities.length - 1;
  const footer = ordering ? (
    <>
      {answerActions?.has("rememberTriggerFirst") && <RememberToggle on={remember} set={setRemember} title="Always put my last-resolving pick first" />}
      <button type="button" className="aplaque secondary" disabled={pending} onClick={() => orderTriggers!(abilities, false)}>Auto Order</button>
      <button type="button" className="aplaque primary" disabled={pending || !ready} onClick={() => {
        const chosen = picked.map((id) => abilities.find((a) => a.id === id)!).filter(Boolean);
        orderTriggers!([...chosen, ...abilities.filter((a) => !picked.includes(a.id))], remember);
      }}>{ready ? "Done" : `${picked.length} of ${abilities.length}`}</button>
    </>
  ) : plaques(promptAnswers(snapshot, "choose_ability"), sendAction, pending);
  return (
    <Frame title={title} detail={line} snapshot={snapshot} k={height / 440} inspect={inspect} footer={footer}>
      {(row) => abilities.map((ability) => {
        const number = picked.indexOf(ability.id) + 1;
        return (
          <button key={ability.id} type="button" className={`bpick ${number > 0 ? "numbered" : ""}`} disabled={pending}
            {...read(inspect, ability.sourceCard?.card.name ?? ability.sourceName, ability.sourceCard)}
            onClick={() => (ordering ? toggle(ability.id) : send({ type: "choose_ability", abilityId: ability.id }, ability.label))}>
            <AbilityCard source={ability.sourceCard} name={ability.sourceName} text={ability.rulesText ?? ability.label} width={abilityCardHeight(row, height) * 0.72} />
            {number > 0 && <CountBadge count={number} size={34} label={`Resolves ${number}`} />}
          </button>
        );
      })}
    </Frame>
  );
}

/** A list of named choices (ArenaChoiceBrowser): choices naming a card show that card with the choice's text, colours
 * their symbol, anything else a glass tile, with a search field for long lists and one "Remember my choice" toggle. */
function ChoiceBrowser({ snapshot, envelope, send, sendAction, pending, height, inspect }: Props) {
  const [remember, setRemember] = useState(false);
  const [search, setSearch] = useState("");
  const options = choiceOptions(envelope.choices!).map((option) => ({
    ...option, card: option.name ? cardNamed(snapshot, option.name) : undefined, symbol: colorSymbol(option.label),
  }));
  const asCards = options.some((o) => o.card) && options.length <= 8;
  const asSymbols = !asCards && options.every((o) => o.symbol);
  const shown = search ? options.filter((o) => o.label.toLowerCase().includes(search.toLowerCase())) : options;
  const [title, detail] = lines(envelope.message);
  const pick = (option: (typeof options)[number]) => {
    const id = remember && option.rememberID ? option.rememberID : option.id;
    send({ type: "resolve_choice", choiceIds: [id] }, option.label);
  };
  const width = Math.min(height * 0.5, 280) * 0.72;
  return (
    <Frame title={title ?? "Make a choice"} detail={detail} subject={{ object: snapshot.xmage?.stack[0] }} snapshot={snapshot} k={height / 440}
      inspect={inspect} column={!asCards && !asSymbols}
      above={options.length > 12 && !asCards && (
        <input className="bsearch" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search choices" aria-label="Search choices" />
      )}
      footer={<>
        {options.some((o) => o.rememberID) && <RememberToggle on={remember} set={setRemember} title="Remember my choice for this game" />}
        {plaques(promptAnswers(snapshot, "resolve_choice"), sendAction, pending)}
      </>}>
      {asCards ? shown.map((option) => (
        <button key={option.id} type="button" className="bpick" disabled={pending} aria-label={clean(option.label)} {...read(inspect, option.card?.card.name, option.card)}
          onClick={() => pick(option)}>
          <AbilityCard source={option.card} name={option.card ? undefined : option.label.length < 30 ? option.label : "Choice"}
            kind={option.card ? "Effect" : "Choice"} text={clean(option.text)} width={width} />
        </button>
      )) : asSymbols ? shown.map((option) => (
        <button key={option.id} type="button" className="bsymbol" disabled={pending} onClick={() => pick(option)}>
          <ManaSymbol symbol={option.symbol!} size={54} /><span>{EngineDisplayText.label(option.label)}</span>
        </button>
      )) : (
        <div className="bgrid">{shown.map((option) => (
          <button key={option.id} type="button" className="btile" disabled={pending} onClick={() => pick(option)}><RulesText text={EngineDisplayText.label(option.label)} /></button>
        ))}</div>
      )}
    </Frame>
  );
}

/** A player's medallion, large (ArenaHeroMedallion): the player and split browsers' and the result's. */
export function Medallion({ player, viewer, diameter, life = true }: { player?: PlayerGameState; viewer: boolean; diameter: number; life?: boolean }) {
  return (
    <span className="bmed" style={{ ["--d" as string]: `${diameter}px` }}>
      <span className="av"><Portrait player={player} viewer={viewer} /></span>
      {player && life && <span className={`hp ${isOut(player) ? "out" : ""}`}>{isOut(player) ? "Out" : Math.max(0, player.life)}</span>}
    </span>
  );
}

/** Choosing a player (ArenaPlayerChoice): each player's medallion with their name under it; a click chooses. */
function PlayerChoice({ snapshot, envelope, send, sendAction, pending, height, inspect }: Props) {
  const message = clean(envelope.message);
  const first = /starting player|first turn|goes first/i.test(message);
  const listed = envelope.players?.length ? envelope.players.filter((p) => p.selectable !== false).map((p) => ({ id: p.playerId, label: p.label })) : undefined;
  const seats = (listed ?? (envelope.targets ?? []).map((t) => ({ id: t.id, label: t.label }))).map((seat) => {
    const player = snapshot.players.find((p) => p.playerId === seat.id);
    const viewer = seat.id === snapshot.viewerPlayerId;
    return { ...seat, player, viewer, name: viewer ? "You" : player?.displayName ?? seat.label };
  });
  const diameter = Math.min(170, height * (seats.length > 2 ? 0.24 : 0.3));
  return (
    <Frame title={first ? "Choose who goes first" : message} snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={plaques(promptAnswers(snapshot, "choose_player", "choose_target"), sendAction, pending)}>
      {seats.map((seat) => (
        <button key={seat.id} type="button" className="bseat" disabled={pending} style={{ margin: `0 ${diameter * 0.17}px`, ["--d" as string]: `${diameter}px` }}
          onClick={() => send(listed ? { type: "choose_player", playerIds: [seat.id] } : { type: "choose_target", targetIds: [seat.id] }, `Choose ${seat.name}`)}>
          <Medallion player={seat.player} viewer={seat.viewer} diameter={diameter} />
          <span>{seat.name}</span>
        </button>
      ))}
    </Frame>
  );
}

/**
 * Splitting damage, counters or mana (ArenaSplitBrowser): each blocker or target as its card (a player as their medallion,
 * a colour as its symbol) with a big number on it and − / + under it, lethal marked; what's left to give under the title,
 * Done only when the split is legal. XMage's own split comes in filled (lethal damage first).
 */
function SplitBrowser({ snapshot, envelope, send, sendAction, pending, height, inspect }: Props) {
  const slots = envelope.multiAmounts!;
  const step = `${snapshot.phase} ${snapshot.step ?? ""}`.toLowerCase();
  const combat = step.includes("combat") && step.includes("damage");
  const first = lines(envelope.message)[0] ?? "";
  const damage = combat || /damage/i.test(first);
  const battlefield = snapshot.players.flatMap((p) => p.zones.battlefield);
  const mine = snapshot.players.find((p) => p.playerId === snapshot.viewerPlayerId)?.zones.battlefield ?? [];
  let attacker: ZoneCard | undefined;
  const rows = slots.map((slot) => {
    const name = splitName(slot.label);
    const card = battlefield.find((c) => c.card.name === name && (!combat || (c.blocking?.length ?? 0) > 0)) ?? battlefield.find((c) => c.card.name === name);
    if (combat && !attacker && card?.blocking?.length) attacker = mine.find((c) => card.blocking!.includes(c.instanceId));
    const player = card ? undefined : snapshot.players.find((p) => p.displayName === name);
    return { slot, name, card, player, symbol: !card && !player ? colorSymbol(name) : undefined };
  });
  const top = snapshot.xmage?.stack[0];
  const deathtouch = /deathtouch/i.test(attacker?.card.oracleText ?? top?.rulesText ?? "");
  const lethal = (card: ZoneCard | undefined) => {
    if (!damage || !card || !isCreatureCard(card)) return undefined;
    const toughness = Number(displayToughness(card));
    return Number.isFinite(toughness) ? lethalDamage(toughness, card.damage ?? 0, deathtouch) : undefined;
  };
  const initial = slots.map((s) => Math.min(Math.max(s.defaultValue ?? s.min, s.min), s.max));
  const [values, setValues] = useState<number[]>();
  const current = values ?? initial;
  const ref = useRef(current);
  ref.current = current;
  const total = current.reduce((a, b) => a + b, 0);
  const { totalMin, totalMax } = envelope;
  const valid = current.every((v, i) => v >= slots[i].min && v <= slots[i].max)
    && (totalMin === undefined || total >= totalMin) && (totalMax === undefined || total <= totalMax);
  const detail = totalMax !== undefined && totalMax === (totalMin ?? totalMax)
    ? (totalMax - total === 0 ? `All ${totalMax} given out` : totalMax - total > 0 ? `${totalMax - total} of ${totalMax} left to give` : `${total - totalMax} too many`)
    : `${total} given`;
  const move = (index: number, delta: number) => {
    const next = [...ref.current];
    // Never past the row's limits, nor more than the total to give.
    if (delta > 0 && totalMax !== undefined && next.reduce((a, b) => a + b, 0) >= totalMax) return false;
    const proposed = Math.min(Math.max(next[index] + delta, slots[index].min), slots[index].max);
    if (proposed === next[index]) return false;
    next[index] = proposed;
    ref.current = next;
    setValues(next);
    return true;
  };
  const cardHeight = Math.min(height * 0.42, 240);
  const width = cardHeight * 0.72;
  return (
    <Frame title={combat ? "Assign combat damage" : first || "Divide"} detail={detail} subject={combat ? { card: attacker } : { object: top }}
      snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={<>
        <button type="button" className="aplaque secondary" disabled={values === undefined || pending} onClick={() => setValues(undefined)}>Reset</button>
        {plaques(promptAnswers(snapshot, "choose_multi_amount"), sendAction, pending)}
        <button type="button" className="aplaque primary" disabled={!valid || pending} onClick={() => send({ type: "choose_multi_amount", amounts: current }, "Assign")}>Done</button>
      </>}>
      {rows.map((row, index) => {
        const value = current[index];
        const kill = lethal(row.card);
        const dead = kill !== undefined && value >= kill;
        return (
          <div key={row.slot.id} className="bsplit" style={{ width }} aria-label={`${row.name}: ${value}${dead ? ", lethal" : ""}`}>
            <div className="bface" style={{ width, height: cardHeight }}>
              {row.card ? <Printed name={row.card.card.name} card={row.card} width={width} inspect={inspect} />
                : row.player ? <Medallion player={row.player} viewer={row.player.playerId === snapshot.viewerPlayerId} diameter={width * 0.9} life={false} />
                  : row.symbol ? <ManaSymbol symbol={row.symbol} size={width * 0.6} />
                    : <AbilityCard name={row.name} kind="Target" text={row.slot.label} width={width} />}
              <span className={`bbadge ${dead ? "lethal" : ""} ${value === 0 && !dead ? "zero" : ""}`}>{value}</span>
              {dead && <span className="bskull" aria-hidden="true">☠</span>}
            </div>
            <span className="bname">{row.name}</span>
            <div className="bsteps">
              <RepeatButton className="blens" label={`One less to ${row.name}`} disabled={pending || value <= row.slot.min} step={() => move(index, -1)}>−</RepeatButton>
              <RepeatButton className="blens" label={`One more to ${row.name}`} step={() => move(index, 1)}
                disabled={pending || value >= row.slot.max || (totalMax !== undefined && total >= totalMax)}>+</RepeatButton>
            </div>
          </div>
        );
      })}
    </Frame>
  );
}

/** Choosing a pile (ArenaPileBrowser; Fact or Fiction): the piles fanned side by side in gold-rimmed wells; a click picks
 * one, the main plaque takes it. */
function PileBrowser({ snapshot, envelope, send, pending, height, inspect }: Props) {
  const [picked, setPicked] = useState<string>();
  const piles = envelope.piles!;
  const pile = piles.find((p) => p.id === picked);
  const width = 96 * Math.min(1.3, height / 440);
  const fan = (p: XmagePromptPile) => p.cards.map((card, index) => (
    <span key={card.instanceId} className="bfan" style={{ marginLeft: index === 0 ? 0 : -width * 0.45, rotate: `${(index - Math.floor(p.cards.length / 2)) * 4}deg` }}>
      <Printed name={card.card.name} card={card} width={width} inspect={inspect} />
    </span>
  ));
  return (
    <Frame title="Choose a pile" detail={clean(envelope.message)} subject={{ object: snapshot.xmage?.stack[0] }} snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={<button type="button" className="aplaque primary" disabled={!pile || pending || pileNumber(pile) === undefined}
        onClick={() => pile && send({ type: "choose_pile", pile: pileNumber(pile) }, pile.label)}>{pile ? `Choose ${pile.label}` : "Pick a pile"}</button>}>
      {piles.map((p) => (
        <button key={p.id} type="button" className={`bwell ${picked === p.id ? "on" : ""}`} disabled={pending} aria-pressed={picked === p.id}
          aria-label={`${p.label}: ${p.cards.map((c) => c.card.name).join(", ")}`} onClick={() => setPicked(p.id)}>
          <span className="blabel">{p.label.toUpperCase()} · {p.cards.length === 1 ? "1 CARD" : `${p.cards.length} CARDS`}</span>
          <span className="bfanrow">{p.cards.length > 0 ? fan(p) : <i className="bempty" style={{ width, height: width * 1.4 }}>Empty</i>}</span>
        </button>
      ))}
    </Frame>
  );
}

/**
 * Card choices the reference game's way (BoardCardChoiceView.arenaStage): a title naming the effect (Scry, Surveil,
 * Search your library…) over one line of instructions, the cards in the middle (scry and surveil in two wells, a click
 * moving a card across), a search over long lists, and Done. A card is picked first (it rises in a gold rim) and Done
 * answers; a multi-card choice is drafted here and delivered one native answer at a time (CardChoicePlan).
 */
function CardChoice({ snapshot, envelope, send, sendAction, pending, height, inspect, commitPlan }: Props) {
  const cards = envelope.cards ?? [];
  const listed = new Set(cards.map((c) => c.instanceId));
  const targets = (envelope.targets ?? []).filter((t) => !listed.has(t.id));
  const selectableIDs = cards.filter((c) => c.selectable !== false).map((c) => c.instanceId);
  const draftKind = commitPlan && CardChoicePlanRules.supportsDraft(envelope) ? CardChoicePlanRules.kind(envelope) : undefined;
  const chosen = Array.isArray(envelope.options?.chosenTargets) ? (envelope.options!.chosenTargets as string[]) : [];
  const [selectedID, setSelectedID] = useState<string>();
  const [draft, setDraft] = useState<string[]>(() => chosen.filter((id) => selectableIDs.includes(id)));
  const [topIDs, setTopIDs] = useState<string[]>(() => selectableIDs.filter((id) => !chosen.includes(id)));
  const [search, setSearch] = useState("");
  const text = envelope.message.toLowerCase();
  const zones = draftKind === "scry" ? "scry" : draftKind === "selection" && text.includes("surveil") ? "surveil"
    : draftKind === "selection" && text.includes("first pile") ? "piles" : undefined;
  const title = draftKind === "scry" ? "Scry" : draftKind === "topOrder" ? "Order the top of your library" : draftKind === "bottomOrder" ? "Order the bottom of your library"
    : text.includes("surveil") ? "Surveil" : text.includes("first pile") ? "Separate into two piles" : text.includes("discard") ? "Discard"
      : text.includes("search") || text.includes("from your library") ? "Search your library" : text.includes("graveyard") ? "Choose from a graveyard"
        : text.includes("exile") ? "Choose a card to exile" : draftKind === "selection" ? "Choose cards" : "Choose a card";
  // XMage's own words under the title only when they add to it (what to search for, how many); scry, surveil, piles and
  // ordering say nothing more, the wells and the order badges show it (arenaInstruction; Caleb's copy rule, 2026-10-22).
  const instruction = (() => {
    if (zones || draftKind === "topOrder" || draftKind === "bottomOrder") return undefined;
    const message = clean(CardChoicePlanRules.context(envelope));
    const words = message.replace(/^[. ]+|[. ]+$/g, "").toLowerCase();
    return words === "" || words === title.toLowerCase() ? undefined : message;
  })();
  const toggle = (id: string) => {
    if (pending || (!selectableIDs.includes(id) && !targets.some((t) => t.id === id))) return;
    if (draftKind) {
      if (draftKind === "topOrder" || draftKind === "bottomOrder") { setDraft((d) => CardChoicePlanRules.toggled(d, id)); return; }
      if (draft.includes(id)) { setDraft((d) => CardChoicePlanRules.toggled(d, id)); if (draftKind === "scry") setTopIDs((t) => [...t, id]); }
      else { setDraft((d) => CardChoicePlanRules.toggled(d, id)); setTopIDs((t) => t.filter((x) => x !== id)); }
      return;
    }
    setSelectedID((current) => (current === id ? undefined : id));
  };
  const query = search.trim().toLowerCase();
  const shown = cards.filter((c) => !query || [c.card.name, c.card.typeLine, c.card.oracleText ?? ""].some((v) => v.toLowerCase().includes(query)));
  const ordered = [...shown.filter((c) => c.selectable !== false), ...shown.filter((c) => c.selectable === false)];
  // The title starts under the opponent's medallion (50 points down), so that much more is reserved (arenaCardWidth).
  const width = Math.max(74, Math.min(150, (height - 192 - (cards.length > 6 ? 46 : 0) - (targets.length ? 56 : 0) - (zones ? 30 : 0)) / 1.4));
  const bounds = CardChoicePlanRules.selectionBounds(envelope.message);
  const countValid = bounds !== undefined && draft.length >= bounds[0] && draft.length <= bounds[1];
  const count = draftKind === "selection" && bounds ? (CardChoicePlanRules.isUnbounded(bounds) ? `${draft.length} chosen`
    : bounds[0] === bounds[1] ? `${draft.length} of ${bounds[1]}` : `${draft.length} · choose ${bounds[0]}–${bounds[1]}`) : undefined;
  const selected = selectedID && (cards.find((c) => c.instanceId === selectedID && c.selectable !== false)?.card.name ?? targets.find((t) => t.id === selectedID)?.label);
  const completion = (snapshot.legalActions ?? []).filter((a) => a.promptId === envelope.id && a.type === "answer_yes_no" && a.confirmed === false);
  const confirm = () => {
    if (draftKind) { commitPlan!(new CardChoicePlan(snapshot, envelope, draft, draftKind === "scry" ? topIDs : [])); return; }
    if (selectedID && selected) send({ type: (envelope.responseCommand?.type as "choose_target") ?? "choose_target", targetIds: [selectedID] }, `Choose ${selected}`);
  };
  const disabled = (!draftKind && !selected) || pending || (draftKind === "selection" && !countValid) ||
    ((draftKind === "topOrder" || draftKind === "bottomOrder") && draft.length !== selectableIDs.length);
  const card = (c: ZoneCard, w: number, number?: number) => {
    const picked = draft.includes(c.instanceId) || selectedID === c.instanceId;
    const marked = !zones && picked;
    const order = !zones && draftKind ? (draft.includes(c.instanceId) ? draft.indexOf(c.instanceId) + 1 : undefined) : number;
    return (
      <button key={c.instanceId} type="button" className={`bcard pick ${marked ? "picked" : ""} ${c.selectable === false ? "off" : ""}`} style={{ width: w }}
        disabled={pending} title={c.disabledReason} aria-pressed={picked} onClick={() => toggle(c.instanceId)}>
        <Printed name={c.card.name} card={c} width={w} inspect={inspect} />
        {order !== undefined ? <CountBadge count={order} size={28} /> : marked && !draftKind ? <span className="bcheck" aria-hidden="true">✓</span> : null}
      </button>
    );
  };
  const well = (label: string, wellIDs: string[], top: boolean, w: number) => (
    <div className="bwellzone" aria-label={label}>
      <b>{label.toUpperCase()}</b>
      <div className="bwellcards">
        {wellIDs.map((id) => {
          const c = cards.find((x) => x.instanceId === id);
          if (!c) return null;
          const index = wellIDs.indexOf(id);
          return (
            <div key={id} className="bwellcard">
              {card(c, w, zones === "scry" && wellIDs.length > 1 ? index + 1 : undefined)}
              {zones === "scry" && wellIDs.length > 1 && (
                <div className="bmove">
                  <button type="button" aria-label="Move earlier" disabled={index === 0 || pending} onClick={() => move(id, -1, top)}>‹</button>
                  <button type="button" aria-label="Move later" disabled={index === wellIDs.length - 1 || pending} onClick={() => move(id, 1, top)}>›</button>
                </div>
              )}
            </div>
          );
        })}
        {/* An empty well keeps its size; it says nothing (the card goes where you click it). */}
        {wellIDs.length === 0 && <i className="bempty" style={{ width: w, height: w * 1.4 + (zones === "scry" ? 30 : 0) }} />}
      </div>
    </div>
  );
  const move = (id: string, by: number, top: boolean) => {
    const update = (list: string[]) => {
      const i = list.indexOf(id);
      if (i < 0 || i + by < 0 || i + by >= list.length) return list;
      const next = [...list]; [next[i], next[i + by]] = [next[i + by], next[i]]; return next;
    };
    if (top) setTopIDs(update); else setDraft(update);
  };
  const wells = zones && (() => {
    const rest = selectableIDs.filter((id) => !draft.includes(id));
    const [left, right] = zones === "scry" ? [["Bottom", draft, false], ["Top", topIDs, true]] as const
      : zones === "surveil" ? [["Graveyard", draft, false], ["Library", rest, true]] as const : [["Pile 1", draft, false], ["Pile 2", rest, true]] as const;
    const slots = Math.max(1, left[1].length) + Math.max(1, right[1].length);
    const w = Math.max(64, Math.min(width, (900 - 14 - 40) / slots - 10));
    return <div className="bwells">{well(left[0], [...left[1]], left[2], w)}{well(right[0], [...right[1]], right[2], w)}</div>;
  })();
  return (
    <Frame title={title} detail={instruction} subject={{ object: snapshot.xmage?.stack[0] }} snapshot={snapshot} k={height / 440} inspect={inspect}
      above={cards.length > 6 && <input className="bsearch" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Name, type or rules text" aria-label="Search cards" />}
      below={<>
        {cards.length > 0 && shown.length === 0 && query && (
          <p className="bnomatch">No cards match your search. <button type="button" onClick={() => setSearch("")}>Clear search</button></p>
        )}
        {targets.length > 0 && (
          <div className="bgrid">{targets.map((target) => (
            <button key={target.id} type="button" className={`btile ${selectedID === target.id ? "picked" : ""}`} disabled={pending} aria-pressed={selectedID === target.id}
              onClick={() => toggle(target.id)}>{EngineDisplayText.label(target.label)}</button>
          ))}</div>
        )}
      </>}
      footer={<>
        {draftKind === "selection" && bounds && !zones && bounds[1] >= selectableIDs.length && draft.length < selectableIDs.length && selectableIDs.length > 1 && (
          <button type="button" className="aplaque secondary" onClick={() => setDraft(selectableIDs)}>Select all</button>
        )}
        {draftKind === "selection" && bounds && !zones && draft.length > 0 && <button type="button" className="aplaque secondary" onClick={() => setDraft([])}>Clear</button>}
        {!draftKind && completion.map((action) => (
          // XMage's "Done" here finishes without a card.
          <button key={action.id} type="button" className="aplaque secondary" disabled={pending} onClick={() => sendAction(action)}>
            {action.label.toLowerCase() === "done" ? "Choose none" : EngineDisplayText.label(action.label)}</button>
        ))}
        <button type="button" className="aplaque primary sub" disabled={disabled} onClick={confirm}>
          {draftKind || selected ? "Done" : targets.length === 0 ? "Choose a card" : "Choose one"}{count && <small>{count.toUpperCase()}</small>}
        </button>
      </>}>
      {wells ?? ordered.map((c) => card(c, width))}
    </Frame>
  );
}

/**
 * A zone opened from the table (ArenaZoneBrowser): graveyard, exile, the command zone side by side on the dimmed table,
 * an orange plaque under each card you can use (Cast, or the action's own name), Done to close.
 */
export function ZoneBrowser({ title, cards, snapshot, pending, sendAction, height, inspect, close, targetIDs, chooseTarget }: {
  title: string; cards: ZoneCard[]; snapshot: GameSnapshot; pending: boolean; sendAction: SendAction; height: number; inspect?: Inspect; close: () => void;
  /** Cards the open prompt can target: each gets Choose (ArenaZoneBrowser.runTargetAction). */
  targetIDs?: ReadonlySet<string>; chooseTarget?: (card: ZoneCard) => void;
}) {
  const actions = (card: ZoneCard) => (snapshot.legalActions ?? []).filter((a) => (a.cardInstanceId === card.instanceId || a.sourceInstanceId === card.instanceId) && a.type !== "make_mana");
  const targetable = (card: ZoneCard) => chooseTarget !== undefined && (targetIDs?.has(card.instanceId) ?? false);
  // Only what the table can't show: an empty zone, or that a card is wanted. No how-to lines (Caleb, 2026-10-22).
  const detail = cards.length === 0 ? (title.includes("Library") || title.includes("library") ? "Face down" : "No cards")
    : cards.some(targetable) ? "Choose a card" : undefined;
  const width = Math.min(220, height * 0.5) / 1.4;
  return (
    <Frame title={title} detail={detail} snapshot={snapshot} k={height / 440} inspect={inspect} onDismiss={close} back="Back to the zone"
      footer={<button type="button" className="aplaque primary" onClick={close}>Done</button>}>
      {cards.map((card) => {
        const list = actions(card);
        const target = targetable(card);
        return (
          <div key={card.instanceId} className={`bcard ${target ? "target" : list.length > 0 ? "usable" : ""}`} style={{ width }}>
            <Printed name={card.card.name} card={card} width={width} inspect={inspect} />
            {target && <button type="button" className="aplaque primary" disabled={pending} aria-label={`Choose ${card.card.name}`} onClick={() => chooseTarget!(card)}>Choose</button>}
            {list.slice(0, 3).map((action) => (
              <button key={action.id} type="button" className="aplaque primary" disabled={pending}
                onClick={() => {
                  // Casting a spell leaves the zone (GameplayAffordances.dismissesZone); other actions keep it open.
                  if (action.type === "cast_spell") close();
                  sendAction(action);
                }}>
                {list.length === 1 && action.type === "cast_spell" ? "Cast" : EngineDisplayText.label(action.label)}</button>
            ))}
          </div>
        );
      })}
    </Frame>
  );
}

const ZONE_WORDS: Record<string, string> = {
  battlefield: "On the battlefield", graveyard: "In the graveyard", exile: "In exile", hand: "In hand", library: "In the library",
};

/**
 * A player's commanders (the command zone as Arena's zone browser, opened from your medallion or a player card): each
 * commander large, partners side by side, its command-zone casts and next tax under it (iOS's wording), and under yours
 * the plaque that casts it, the actions the old medallion menu sent. An opponent's is to look at. Done closes it.
 */
export function CommanderBrowser({ player, snapshot, pending, sendAction, height, inspect, close }: {
  player: PlayerGameState; snapshot: GameSnapshot; pending: boolean; sendAction: SendAction; height: number; inspect?: Inspect; close: () => void;
}) {
  const mine = player.playerId === snapshot.viewerPlayerId;
  const entries = commanderEntries(player, snapshot);
  const title = mine ? "Command" : `${EngineDisplayText.label(player.displayName ?? "", "Opponent")} · Command`;
  const actions = (card: ZoneCard) => !mine ? [] : (snapshot.legalActions ?? []).filter((a) =>
    (a.cardInstanceId === card.instanceId || a.sourceInstanceId === card.instanceId) && a.type !== "make_mana");
  const usable = entries.flatMap((entry) => (entry.card && entry.zone === "command" ? actions(entry.card) : []));
  // One commander with one way to use it puts Cast beside Done; several keep their own buttons under each card.
  const single = entries.length === 1 && usable.length === 1 ? usable[0] : undefined;
  const use = (action: LegalAction) => { if (action.type === "cast_spell") close(); sendAction(action); };
  // The card fits what's left of the height: the title, the casts and tax, its buttons and the footer stay in view.
  const width = Math.max(110, Math.min(220, (height - (single || usable.length === 0 ? 250 : 292)) / 1.4));
  return (
    <Frame title={title} detail={entries.length === 0 ? "No cards" : undefined} snapshot={snapshot} k={height / 440} inspect={inspect} onDismiss={close}
      back="Back to the command zone" footer={<>
        {single && <button type="button" className="aplaque primary" disabled={pending} onClick={() => use(single)}>
          {single.type === "cast_spell" ? "Cast" : EngineDisplayText.label(single.label)}</button>}
        <button type="button" className={`aplaque ${single ? "secondary" : "primary"}`} onClick={close}>Done</button>
      </>}>
      {entries.map((entry) => {
        const list = entry.card && entry.zone === "command" && !single ? actions(entry.card) : [];
        const away = entry.zone !== undefined && entry.zone !== "command" ? ZONE_WORDS[entry.zone] : undefined;
        const counts = [entry.casts !== undefined ? `Command-zone casts: ${entry.casts}` : undefined, entry.tax !== undefined ? `Next tax: {${entry.tax}}` : undefined]
          .filter((line): line is string => line !== undefined);
        const lit = entry.card !== undefined && entry.zone === "command" && actions(entry.card).length > 0;
        return (
          <div key={entry.key} className={`bcard bcommander ${lit ? "usable" : ""} ${away ? "away" : ""}`} style={{ width }} data-id={`commander.${entry.name}`}>
            <Printed name={entry.card?.card.name ?? entry.name} card={entry.card} width={width} inspect={inspect} />
            {away && <span className="bwhere">{away}</span>}
            {counts.length > 0 && <span className="btax">{counts.map((line) => <span key={line}><RulesText text={line} /></span>)}</span>}
            {list.slice(0, 3).map((action) => (
              <button key={action.id} type="button" className="aplaque primary" disabled={pending} onClick={() => use(action)}>
                {list.length === 1 && action.type === "cast_spell" ? "Cast" : EngineDisplayText.label(action.label)}</button>
            ))}
          </div>
        );
      })}
    </Frame>
  );
}

/**
 * The stack (ArenaStackBrowser): its count, whether you are responding, each object in resolve order with its number
 * (Arena's count ovals), a gold rim and "RESOLVES NEXT" on the first, whose it is and what it targets; Stop skipping and
 * Resolve All when they apply, and Done.
 */
/**
 * A target question whose choices are on the stack (stackChoices; Gogo copying Zur's trigger) opens it to choose: its
 * message is the title, the choices glow, the rest dim, and a click chooses.
 */
export function StackBrowser({ snapshot, height, inspect, close, resolveAll, stopSkipping, choosable, choose, answers }: {
  snapshot: GameSnapshot; height: number; inspect?: Inspect; close: () => void; resolveAll?: () => void; stopSkipping?: () => void;
  choosable?: Set<string>; choose?: (id: string) => void; answers?: { id: string; title: string; action: () => void }[];
}) {
  const stack = snapshot.xmage?.stack ?? [];
  const choosing = choose !== undefined && (choosable?.size ?? 0) > 0;
  const title = choosing ? lines(snapshot.promptEnvelopeV2?.message ?? "")[0] ?? "Choose one" : "The Stack";
  const width = Math.min(height * 0.5, 230) * 0.72;
  const responding = (snapshot.legalActions ?? []).some((a) => ["pass_priority", "pass_until_response", "advance_phase"].includes(a.type));
  const owner = (controller?: string) => (controller === undefined ? undefined : controller === snapshot.viewerPlayerId ? "Yours"
    : `${snapshot.players.find((p) => p.playerId === controller)?.displayName ?? "Their"}’s`);
  return (
    <Frame title={title} snapshot={snapshot} k={height / 440} inspect={inspect} onDismiss={close} back="Back to the stack"
      heading={<>
        <h2 className={`stackhead ${choosing ? "choosing" : ""}`}>{title}{!choosing && <> <CountBadge count={stack.length} size={28} label={`${stack.length} on the stack`} /></>}</h2>
        <p className="stacksub">{stack.length > 1 ? "Resolves left to right" : "Resolves next"}
          <b className={`btag ${choosing || responding ? "ember" : ""}`}>{choosing ? "CHOOSE ONE" : responding ? "YOUR RESPONSE" : "WAITING"}</b></p>
      </>}
      footer={<>
        {stopSkipping && <button type="button" className="aplaque secondary" onClick={stopSkipping}>Stop skipping</button>}
        {resolveAll && !choosing && <button type="button" className="aplaque secondary" onClick={() => { close(); resolveAll(); }}>Resolve All</button>}
        {choosing && answers?.map((a) => <button key={a.id} type="button" className="aplaque secondary" onClick={a.action}>{a.title}</button>)}
        <button type="button" className={`aplaque ${choosing ? "secondary" : "primary"}`} onClick={close}>{choosing ? "View Battlefield" : "Done"}</button>
      </>}>
      {stack.map((item, index) => {
        const next = index === 0;
        const targets = stackTargetLabels(item.targetIds ?? [], snapshot);
        const whose = owner(item.controllerId) ?? item.sourceName ?? item.name;
        const choice = choosing && choosable!.has(item.id);
        return (
          <div key={item.id} className={`bitem ${next && !choosing ? "next" : ""} ${choice ? "choice" : choosing ? "dim" : ""}`}>
            <div className="bstackcard" role={choice ? "button" : undefined} tabIndex={choice ? 0 : undefined}
              aria-label={choice ? `Choose ${item.sourceName ?? item.name}` : undefined}
              onClickCapture={choice ? (event) => { event.stopPropagation(); event.preventDefault(); choose!(item.id); } : undefined}
              onKeyDown={choice ? (event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); choose!(item.id); } } : undefined}>
              <Subject object={item} snapshot={snapshot} width={width} inspect={inspect} />
              <CountBadge count={index + 1} size={30} />
            </div>
            <span className={`who ${next ? "next" : ""}`}>{next ? "RESOLVES NEXT" : whose.toUpperCase()}</span>
            {next && <span className="owner">{whose}</span>}
            {targets.length > 0 && <span className="tgt"><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="6.5" fill="none" stroke="currentColor" strokeWidth="1.8" /><path d="M10 1.5v5M10 13.5v5M1.5 10h5M13.5 10h5" stroke="currentColor" strokeWidth="1.8" /></svg>{targets.join(", ")}</span>}
          </div>
        );
      })}
    </Frame>
  );
}

/** StackTargetPresentation.labels: a player's name, a card's (a face-down one stays hidden), a stack object's, else unavailable. */
export function stackTargetLabels(ids: string[], snapshot: GameSnapshot): string[] {
  const cards = snapshot.players.flatMap((p) => [...p.zones.battlefield, ...p.zones.graveyard, ...p.zones.exile, ...p.zones.command, ...p.zones.hand]);
  return ids.map((id) => {
    const player = snapshot.players.find((p) => p.playerId === id);
    if (player) return id === snapshot.viewerPlayerId ? "You" : player.displayName ?? "Opponent";
    const card = cards.find((c) => c.instanceId === id);
    if (card) return card.card.name === "Face-down card" || (card.cardIcons ?? []).some((i) => i.iconType.toUpperCase() === "OTHER_FACEDOWN") ? "Hidden card" : card.card.name;
    const object = snapshot.xmage?.stack.find((o) => o.id === id || o.objectId === id);
    if (object) return object.sourceCard?.card.name ?? object.sourceName ?? object.name ?? "Unavailable target";
    return "Unavailable target";
  });
}

/**
 * The reference's number picker (ArenaAmountPill; MTG Arena's "Pay X = 10"): one capsule in the button corner, [−5] [−]
 * [answer] [+] [+5], Cancel under it, the board, caption and stack in view. Holding − or + keeps stepping; the arrow keys
 * step and Enter answers. X starts at the most your mana pays; anything else at its least.
 */
export function AmountPill({ snapshot, envelope, send, sendAction, pending, x, y }: Omit<Props, "height" | "inspect"> & { x: number; y: number }) {
  const isX = envelope.responseKind === "x_mana" || /\{X\}|value for x/i.test(envelope.message);
  const values = amountValues(envelope.amounts, envelope.minChoices, envelope.maxChoices);
  const initial = (() => {
    const cost = snapshot.xmage?.stack[0]?.sourceCard?.card.manaCost;
    const me = snapshot.players.find((p) => p.playerId === snapshot.viewerPlayerId);
    if (!isX || !cost || !me) return values[0];
    const sources = me.zones.battlefield.filter((c) => !c.tapped && (/\bland\b/i.test(c.card.typeLine) || /add \{|add one mana/i.test(c.card.oracleText ?? ""))).length;
    const pool = me.manaPool ? me.manaPool.W + me.manaPool.U + me.manaPool.B + me.manaPool.R + me.manaPool.G + me.manaPool.C : 0;
    const affordable = affordableX(cost, sources + pool);
    return affordable === undefined ? values[0] : clampAmount(values, affordable);
  })();
  const [value, setValue] = useState<number>();
  const current = value ?? initial;
  const ref = useRef(current);
  ref.current = current;
  const move = (places: number) => {
    const next = stepAmount(values, ref.current, places);
    if (next === ref.current) return false;
    ref.current = next;
    setValue(next);
    return true;
  };
  const submit = () => {
    const amount = ref.current;
    send(envelope.responseKind === "x_mana" ? { type: "play_x_mana", amount } : { type: "choose_amount", amount }, isX ? `X = ${amount}` : String(amount));
  };
  const cancel = promptAnswers(snapshot, "choose_amount", "play_x_mana")[0];
  const min = values[0];
  const max = values[values.length - 1];
  const live = useRef({ move, submit, pending });
  live.current = { move, submit, pending };
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (live.current.pending || (event.target as HTMLElement | null)?.closest("input, textarea")) return;
      const step = { ArrowUp: 1, ArrowRight: 1, ArrowDown: -1, ArrowLeft: -1, PageUp: 5, PageDown: -5 }[event.key];
      if (step !== undefined) { event.preventDefault(); live.current.move(step); }
      else if (event.key === "Enter") { event.preventDefault(); live.current.submit(); }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  const label = isX ? "Pay X" : "Choose";
  return (
    <div className="apill" style={{ left: x, top: y }} onClick={(event) => event.stopPropagation()}>
      <div className="plenses">
        {values.length > 6 && <RepeatButton className="plens five" repeats={false} label="Lower by 5" disabled={pending || current <= min} step={() => move(-5)}>−5</RepeatButton>}
        <RepeatButton className="plens" label="Lower by 1" disabled={pending || current <= min} step={() => move(-1)}>−</RepeatButton>
        <button type="button" className="pgo" disabled={pending} onClick={submit} aria-label={`${label} ${current}`}>
          <small>{label}</small><b>{isX ? `X = ${current}` : current}</b>
        </button>
        <RepeatButton className="plens" label="Raise by 1" disabled={pending || current >= max} step={() => move(1)}>+</RepeatButton>
        {values.length > 6 && <RepeatButton className="plens five" repeats={false} label="Raise by 5" disabled={pending || current >= max} step={() => move(5)}>+5</RepeatButton>}
      </div>
      {cancel && <button type="button" className="aplaque secondary" disabled={pending} onClick={() => sendAction(cancel)}>{EngineDisplayText.label(cancel.label)}</button>}
    </div>
  );
}
