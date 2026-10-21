/**
 * Arena browsers, the iOS Arena board's (ArenaBoardViews.swift, docs/ARENA_STYLE.md; Caleb, 2026-10-21: the phone's Arena
 * build is the baseline): no panel. The table dims, a serif title and one line sit at the top, the cards stand in the
 * middle, the answers sit under them as plaques, the card it's about stands on the right, and "View Battlefield" (top
 * right) steps the browser aside. A number is the reference's pill in the button corner instead (ArenaAmountPill), with
 * the board in view. They send exactly the commands the old prompt panel sent, so the engine never changes for a look.
 */
import { useEffect, useRef, useState } from "react";
import { EngineDisplayText } from "../../core/displayText";
import {
  displayToughness, type GameCommand, type GameSnapshot, isCreatureCard, type LegalAction, pileNumber, type PlayerGameState, promptKind,
  type PromptEnvelopeV2, type XmagePromptPile, type XmageStackObject, type ZoneCard,
} from "../../core/models";
import { cardImageURL } from "../cardArt";
import { AbilityCard, isStackAbility } from "./AbilityCard";
import { AVATAR } from "./avatars";
import { ManaSymbol, RulesText } from "./Symbols";

export type Send = (command: Omit<GameCommand, "gameId" | "playerId" | "promptId" | "messageId">, label: string) => void;
export type SendAction = (action: LegalAction) => void;
export type BrowserKind = "mulligan" | "question" | "amount" | "split" | "piles" | "abilities" | "modes" | "choices" | "cards" | "players";
/** A card under the pointer in a browser, to read it large: its name, and whether the zoom goes on the left (it sits right). */
export type Inspect = (zoom: { name: string; left: boolean } | undefined) => void;

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
 * The question in a few words, the reference's way ("Use Esper Sentinel's ability?"), with the whole of XMage's message
 * under it when it says more (ArenaQuestionStage.headline; Caleb, 2026-10-21: long questions filled the screen).
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
  if (stop >= 0 && stop < 70) return { title: `${text.slice(0, stop)}.`, detail: text };
  return { title: `${text.slice(0, 60).trim()}…`, detail: text };
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

const hover = (inspect: Inspect | undefined, name: string | undefined) => (inspect && name ? {
  onMouseEnter: (event: React.MouseEvent) => inspect({ name, left: event.clientX > window.innerWidth / 2 }),
  onMouseLeave: () => inspect(undefined),
} : {});

/** The printed card, at a width in board points. */
function Printed({ name, width, inspect, className = "" }: { name: string; width: number; inspect?: Inspect; className?: string }) {
  return <img className={`bprinted ${className}`} src={cardImageURL(name, "normal")} alt={name} crossOrigin="anonymous" draggable={false}
    style={{ width, height: width * 1.397 }} {...hover(inspect, name)} />;
}

/** What a question or browser is about: an ability as its ability card, a spell or card as itself. */
function Subject({ object, card, snapshot, width, inspect }: {
  object?: XmageStackObject; card?: ZoneCard; snapshot: GameSnapshot; width: number; inspect?: Inspect;
}) {
  if (object && (isStackAbility(object) || !object.sourceCard)) {
    const source = card ?? stackSource(object, snapshot);
    return (
      <div className="bsubject" {...hover(inspect, source?.card.name)}>
        <AbilityCard source={source} name={source ? undefined : object.sourceName ?? object.name} text={object.rulesText ?? object.name} width={width} />
      </div>
    );
  }
  const shown = object?.sourceCard ?? card;
  return shown ? <Printed name={shown.card.name} width={width} inspect={inspect} className="bsubject" /> : null;
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

/** The frame every browser shares (ArenaBrowserFrame): title and line, content, answers, the source card on the right. */
export function Frame({ title, detail, subject, snapshot, k, inspect, footer, column, back = "Back to the choice", onDismiss, children }: {
  title: string; detail?: string; subject?: Subjected; snapshot: GameSnapshot; k: number; inspect?: Inspect; footer?: React.ReactNode;
  column?: boolean; back?: string; onDismiss?: () => void; children: React.ReactNode;
}) {
  const shows = subject !== undefined && (subject.object !== undefined || subject.card !== undefined);
  return (
    <Veil back={back} onDismiss={onDismiss}>
      <div className="bbody" data-veil="" style={shows ? { paddingRight: 124 * k + 40 } : undefined}>
        <header data-veil=""><h2><RulesText text={title} /></h2>{detail && <p><RulesText text={detail} /></p>}</header>
        <div className={`bcontent ${column ? "column" : ""}`} data-veil="">{children}</div>
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
}

/** XMage's own answers to the prompt (Cancel, Done), less the ones a browser makes itself. */
const promptAnswers = (snapshot: GameSnapshot, ...except: string[]) =>
  (snapshot.legalActions ?? []).filter((a) => a.cardInstanceId === undefined && a.sourceInstanceId === undefined && !except.includes(a.type));
const plaques = (actions: LegalAction[], sendAction: SendAction, pending: boolean, style: "ember" | "leather" = "leather") => actions.map((action) => (
  <button key={action.id} type="button" className={`aplaque ${style}`} disabled={pending} onClick={() => sendAction(action)}>{EngineDisplayText.label(action.label)}</button>
));

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
function QuestionStage({ snapshot, envelope, send, sendAction, pending, height, inspect }: Props) {
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
              <button type="button" className="aplaque ember" disabled={pending} onClick={() => send({ type: "answer_yes_no", confirmed: true }, confirmation.yesLabel ?? "Yes")}>
                {confirmation.yesLabel ?? "Yes"}</button>
              <button type="button" className="aplaque leather" disabled={pending} onClick={() => send({ type: "answer_yes_no", confirmed: false }, confirmation.noLabel ?? "No")}>
                {confirmation.noLabel ?? "No"}</button>
            </>
          ) : (envelope.choices ?? []).map((choice) => (
            <button key={choice.id} type="button" className="aplaque leather" disabled={pending}
              onClick={() => send({ type: "resolve_choice", choiceIds: [choice.id] }, choice.label)}><RulesText text={EngineDisplayText.label(choice.label)} /></button>
          ))}
          {plaques(promptAnswers(snapshot, "answer_yes_no", "resolve_choice"), sendAction, pending)}
        </div>
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
  const firstLine = lines(envelope.message)[0];
  const detail = max > 1 ? `Click a mode to add it · up to ${max}${envelope.minChoices ? `, at least ${envelope.minChoices}` : ""}`
    : firstLine && !/^choose (a )?modes?\.?$/i.test(firstLine) ? firstLine : undefined;
  const width = Math.min(height * 0.52, 290) * 0.72;
  return (
    <Frame title={max > 1 ? "Choose modes" : "Choose a mode"} detail={detail} snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={plaques(promptAnswers(snapshot, "choose_mode"), sendAction, pending, "ember")}>
      {envelope.modes!.map((mode, index) => (
        <button key={mode.id} type="button" className="bpick" disabled={pending} aria-label={clean(mode.label)} {...hover(inspect, source?.card.name)}
          onClick={() => send({ type: "choose_mode", modeIds: [mode.id] }, mode.label)}>
          <AbilityCard source={source} name={source ? undefined : `Mode ${index + 1}`} kind={`Mode ${index + 1}`}
            text={clean(mode.label).replace(/^\d+\.\s*/, "")} width={width} />
        </button>
      ))}
    </Frame>
  );
}

/** Abilities and triggers as the reference's ability cards in a row; a click picks one (to order triggers, XMage asks for
 * the one that goes on the stack first, then the next). */
function AbilityBrowser({ snapshot, envelope, send, sendAction, pending, height, inspect }: Props) {
  const ordering = /trigger|goes to the stack first/i.test(envelope.message);
  const { title, line } = ordering
    ? { title: "Order your triggers", line: "Choose the one that goes on the stack first: it resolves last." }
    : heading(envelope, "Choose an ability");
  const width = Math.min(height * 0.5, 280) * 0.72;
  return (
    <Frame title={title} detail={line} snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={plaques(promptAnswers(snapshot, "choose_ability"), sendAction, pending)}>
      {envelope.abilities!.map((ability) => (
        <button key={ability.id} type="button" className="bpick" disabled={pending} {...hover(inspect, ability.sourceCard?.card.name ?? ability.sourceName)}
          onClick={() => send({ type: "choose_ability", abilityId: ability.id }, ability.label)}>
          <AbilityCard source={ability.sourceCard} name={ability.sourceName} text={ability.rulesText ?? ability.label} width={width} />
        </button>
      ))}
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
      footer={<>
        {options.some((o) => o.rememberID) && (
          <label className="bremember"><input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />Remember my choice for this game</label>
        )}
        {plaques(promptAnswers(snapshot, "resolve_choice"), sendAction, pending)}
      </>}>
      {options.length > 12 && !asCards && (
        <input className="bsearch" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search choices" aria-label="Search choices" />
      )}
      {asCards ? shown.map((option) => (
        <button key={option.id} type="button" className="bpick" disabled={pending} aria-label={clean(option.label)} {...hover(inspect, option.card?.card.name)}
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

/** A player's medallion, large, for the player and split browsers. */
function Medallion({ player, viewer, diameter, life = true }: { player?: PlayerGameState; viewer: boolean; diameter: number; life?: boolean }) {
  return (
    <span className="bmed" style={{ width: diameter, height: diameter }}>
      <span className="av">{viewer ? AVATAR.me : AVATAR.opp}</span>
      {player && life && <span className="hp" style={{ fontSize: diameter * 0.32 }}>{Math.max(0, player.life)}</span>}
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
        <button key={seat.id} type="button" className="bseat" disabled={pending} style={{ margin: `0 ${diameter * 0.17}px` }}
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
        <button type="button" className="aplaque leather" disabled={values === undefined || pending} onClick={() => setValues(undefined)}>Reset</button>
        {plaques(promptAnswers(snapshot, "choose_multi_amount"), sendAction, pending)}
        <button type="button" className="aplaque ember" disabled={!valid || pending} onClick={() => send({ type: "choose_multi_amount", amounts: current }, "Assign")}>Done</button>
      </>}>
      {rows.map((row, index) => {
        const value = current[index];
        const kill = lethal(row.card);
        const dead = kill !== undefined && value >= kill;
        return (
          <div key={row.slot.id} className="bsplit" style={{ width }} aria-label={`${row.name}: ${value}${dead ? ", lethal" : ""}`}>
            <div className="bface" style={{ width, height: cardHeight }}>
              {row.card ? <Printed name={row.card.card.name} width={width} inspect={inspect} />
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
      <Printed name={card.card.name} width={width} inspect={inspect} />
    </span>
  ));
  return (
    <Frame title="Choose a pile" detail={clean(envelope.message)} subject={{ object: snapshot.xmage?.stack[0] }} snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={<button type="button" className="aplaque ember" disabled={!pile || pending || pileNumber(pile) === undefined}
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

/** Cards to choose that aren't on the table (a graveyard, a search): the cards side by side, glowing; a click chooses. */
function CardChoice({ snapshot, envelope, send, sendAction, pending, height, inspect }: Props) {
  const cards = envelope.cards ?? [];
  const listed = new Set(cards.map((c) => c.instanceId));
  const others = (envelope.targets ?? []).filter((t) => !listed.has(t.id));
  const { title, line } = heading(envelope, "Choose a card");
  const width = Math.min(height * 0.46, 250) / 1.4;
  const zoneOf = (card: ZoneCard) => {
    for (const player of snapshot.players) {
      for (const [zone, list] of Object.entries(player.zones)) {
        if (Array.isArray(list) && list.some((c: ZoneCard) => c.instanceId === card.instanceId)) {
          const whose = player.playerId === snapshot.viewerPlayerId ? "Your" : `${player.displayName ?? "Their"}’s`;
          return `${whose} ${zone === "battlefield" ? "table" : zone}`;
        }
      }
    }
    return undefined;
  };
  return (
    <Frame title={title} detail={line} subject={{ object: snapshot.xmage?.stack[0] }} snapshot={snapshot} k={height / 440} inspect={inspect}
      footer={plaques(promptAnswers(snapshot, "choose_target"), sendAction, pending)}>
      {cards.map((card) => (
        <button key={card.instanceId} type="button" className="bcard target" disabled={pending || card.selectable === false} title={card.disabledReason}
          onClick={() => send({ type: "choose_target", targetIds: [card.instanceId] }, card.card.name)}>
          <Printed name={card.card.name} width={width} inspect={inspect} />
          <span className="bzone">{zoneOf(card) ?? ""}</span>
        </button>
      ))}
      {others.length > 0 && (
        <div className="bgrid">{others.map((target) => (
          <button key={target.id} type="button" className="btile" disabled={pending} onClick={() => send({ type: "choose_target", targetIds: [target.id] }, target.label)}>
            {EngineDisplayText.label(target.label)}</button>
        ))}</div>
      )}
    </Frame>
  );
}

/**
 * A zone opened from the table (ArenaZoneBrowser): graveyard, exile, the command zone side by side on the dimmed table,
 * an ember plaque under each card you can use (Cast, or the action's own name), Done to close.
 */
export function ZoneBrowser({ title, cards, snapshot, pending, sendAction, height, inspect, close }: {
  title: string; cards: ZoneCard[]; snapshot: GameSnapshot; pending: boolean; sendAction: SendAction; height: number; inspect?: Inspect; close: () => void;
}) {
  const actions = (card: ZoneCard) => (snapshot.legalActions ?? []).filter((a) => (a.cardInstanceId === card.instanceId || a.sourceInstanceId === card.instanceId) && a.type !== "make_mana");
  const usable = cards.some((c) => actions(c).length > 0);
  const detail = cards.length === 0 ? "Nothing here yet."
    : usable ? "Play a card from here, or point at one to read it."
      : cards.length === 1 ? "1 card. Point at it to read it." : `${cards.length} cards, newest last. Point at one to read it.`;
  const width = Math.min(height * 0.46, 250) / 1.4;
  return (
    <Frame title={title} detail={detail} snapshot={snapshot} k={height / 440} inspect={inspect} onDismiss={close} back="Back to the zone"
      footer={<button type="button" className="aplaque ember" onClick={close}>Done</button>}>
      {cards.map((card) => {
        const list = actions(card);
        return (
          <div key={card.instanceId} className={`bcard ${list.length > 0 ? "usable" : ""}`} style={{ width }}>
            <Printed name={card.card.name} width={width} inspect={inspect} />
            {list.slice(0, 3).map((action) => (
              <button key={action.id} type="button" className="aplaque ember" disabled={pending}
                onClick={() => { inspect?.(undefined); close(); sendAction(action); }}>
                {list.length === 1 && action.type === "cast_spell" ? "Cast" : EngineDisplayText.label(action.label)}</button>
            ))}
          </div>
        );
      })}
    </Frame>
  );
}

/** The whole stack (ArenaStackBrowser), from what resolves next: abilities as ability cards, who controls each, its targets. */
export function StackBrowser({ snapshot, height, inspect, close }: { snapshot: GameSnapshot; height: number; inspect?: Inspect; close: () => void }) {
  const stack = snapshot.xmage?.stack ?? [];
  const battlefield = snapshot.players.flatMap((p) => p.zones.battlefield);
  const nameOf = (id: string) => (id === snapshot.viewerPlayerId ? "you" : snapshot.players.find((p) => p.playerId === id)?.displayName ?? battlefield.find((c) => c.instanceId === id)?.card.name);
  const width = Math.min(height * 0.46, 250) * 0.72;
  return (
    <Frame title="The stack" detail={stack.length === 0 ? "The stack is empty." : "Left to right, from what resolves next."} snapshot={snapshot}
      k={height / 440} inspect={inspect} onDismiss={close} back="Back to the stack" footer={<button type="button" className="aplaque ember" onClick={close}>Done</button>}>
      {stack.map((item, index) => {
        const targets = (item.targetIds ?? []).map(nameOf).filter(Boolean);
        const controller = item.controllerId === snapshot.viewerPlayerId ? "Yours" : `${snapshot.players.find((p) => p.playerId === item.controllerId)?.displayName ?? "Their"}’s`;
        return (
          <div key={item.id} className={`bitem ${index === 0 ? "next" : ""}`}>
            <Subject object={item} snapshot={snapshot} width={width} inspect={inspect} />
            <span className="who">{controller}</span>
            {targets.length > 0 && <span className="tgt">Targets {targets.join(", ")}</span>}
          </div>
        );
      })}
    </Frame>
  );
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
      {cancel && <button type="button" className="aplaque leather" disabled={pending} onClick={() => sendAction(cancel)}>{EngineDisplayText.label(cancel.label)}</button>}
    </div>
  );
}
