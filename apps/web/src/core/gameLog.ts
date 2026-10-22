/**
 * The game log as the Arena board reads it (iOS GameLogPresentation.swift and ArenaLogLine in GameLogAndStyles.swift):
 * an engine message read without an HTML renderer into styled spans, with the card names the message already disclosed;
 * each line's kind and icon; and CombatLogReasons, one line of public combat context under damage and deaths.
 * Checked by test/gameLog.test.ts against the iOS goldens (text-cases.json) and combat-cases.json.
 */
import { BoardEventDiffer, type CombatKeyword, CombatKeywords, isInCombat } from "./boardEvents";
import { EngineDisplayText } from "./displayText";
import type { GameLogEntry, GameSnapshot } from "./models";

export type LogRole = "action" | "player" | "card";
/** Identity and label already disclosed by this log entry. Not lookup authorization. */
export interface CardReference { objectID: string; name: string }
export interface LogSpan { text: string; role: LogRole; bold: boolean; italic: boolean; card?: CardReference }

// Tokenize before decoding so encoded angle brackets remain literal text.
const TOKENS = /<!--[\s\S]*?(?:-->|$)|<\/?([A-Za-z][A-Za-z0-9:-]*)\b(?:[^<>"']|"[^"]*"|'[^']*')*>|&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);|<[Ff][Oo][Nn][Tt]\s+[^<>]*$/g;
const ATTRIBUTES = /\s+([a-z][a-z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Matches mage.util.GameLog's log palette, not arbitrary CSS or tooltip colors.
const CARD_COLORS = new Set(["#90ee90", "#ff6347", "#87cefa", "#696969", "#f0e68c", "#daa520", "#b0c4de"]);
const SUPPRESSED = new Set(["script", "style", "iframe", "object", "svg", "math", "head", "template"]);
const BLOCKS = new Set(["br", "p", "div", "li", "ul", "ol", "table", "tr", "td", "hr"]);
const REDACTED = new Set(["hidden card", "face-down card", "face down card", "card details unavailable"]);
// CharacterSet.whitespacesAndNewlines, less the separators text() would drop (VT, FF, NEL).
const WHITESPACE = new Set([9, 10, 13, 0x20, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000]);

/** The entity decoder's control policy, applied to literal input before tokenizing so controls cannot disguise markup. */
const withoutControls = (source: string) => [...source].filter((character) => {
  const value = character.codePointAt(0)!;
  return !((value < 32 && value !== 9 && value !== 10 && value !== 13) || (value >= 127 && value <= 159)
    || (value >= 0x202a && value <= 0x202e) || (value >= 0x2066 && value <= 0x2069));
}).join("");

function readAttributes(tag: string): Record<string, string> {
  const values: Record<string, string> = {};
  const duplicates = new Set<string>();
  for (const match of tag.matchAll(ATTRIBUTES)) {
    const key = match[1].toLowerCase();
    const value = match[2] ?? match[3] ?? match[4];
    if (value === undefined) continue;
    if (key in values) duplicates.add(key);
    values[key] = value;
  }
  for (const key of duplicates) delete values[key];
  return values;
}

/** Whitespace entities are kept as they are (text() would trim them); the rest go through the prompt decoder. */
function entity(token: string): string {
  if (token === "&nbsp;") return " ";
  if (token.startsWith("&#")) {
    const body = token.slice(2, -1);
    const hex = body[0] === "x" || body[0] === "X";
    const value = Number.parseInt(hex ? body.slice(1) : body, hex ? 16 : 10);
    if (value === 160) return " ";
    if (WHITESPACE.has(value) || (value >= 0x2000 && value <= 0x200a)) return String.fromCodePoint(value);
  }
  return EngineDisplayText.text(token);
}

/** Display-only interpretation of an authorized log message. Never queries cards or uses an HTML renderer. */
export class GameLogPresentation {
  readonly spans: LogSpan[];
  get plainText() { return this.spans.map((span) => span.text).join(""); }

  constructor(message: string) {
    const source = withoutControls(message);
    const result: LogSpan[] = [];
    type Style = { role: LogRole; bold: boolean; italic: boolean };
    let style: Style = { role: "action", bold: false, italic: false };
    const frames: { name: string; previous: Style; objectID?: string; start: number }[] = [];
    const hidden: string[] = [];
    let pendingCardID: string | undefined;
    let cursor = 0;
    let buffer = "";

    const append = (value: string) => {
      if (hidden.length > 0 || value.length === 0) return;
      let text = value;
      if (pendingCardID !== undefined) {
        // Only a UUID-matching suffix directly after a named card is metadata.
        text = text.replace(new RegExp(`^[ \\t]*\\[${pendingCardID}\\](?=[\\s.,;:!?()]|$)`, "i"), "");
        pendingCardID = undefined;
      }
      if (text.length > 0) result.push({ text, ...style });
    };

    for (const match of source.matchAll(TOKENS)) {
      buffer += source.slice(cursor, match.index);
      cursor = match.index! + match[0].length;
      const token = match[0];
      if (token.startsWith("&")) { buffer += entity(token); continue; }
      append(buffer);
      buffer = "";
      if (token.startsWith("<!--")) continue;
      // A truncated font opening tag must not expose its private attributes.
      if (match[1] === undefined) continue;
      const name = match[1].toLowerCase();
      const closing = token.startsWith("</");
      if (SUPPRESSED.has(name)) {
        if (closing) {
          // Closing an ancestor also closes its malformed or unclosed children.
          const index = hidden.lastIndexOf(name);
          if (index >= 0) hidden.splice(index);
        } else if (!token.endsWith("/>") || !["svg", "math"].includes(name)) {
          hidden.push(name);
        }
        continue;
      }
      if (hidden.length > 0) continue;
      if (BLOCKS.has(name)) { append("\n"); continue; }
      // The canonical mana alt only; no src or title lookup.
      if (name === "img") { append(EngineDisplayText.text(token)); continue; }
      if (name !== "font" && name !== "i" && name !== "b") continue;
      if (closing) {
        const index = frames.map((frame) => frame.name).lastIndexOf(name);
        if (index < 0) continue;
        const frame = frames[index];
        const label = result.slice(frame.start).map((span) => span.text).join("").trim();
        style = frame.previous;
        frames.splice(index);
        if (frame.objectID && label && /\p{L}/u.test(label) && !label.startsWith("[")) {
          pendingCardID = frame.objectID.slice(0, 3);
          if (!REDACTED.has(label.toLowerCase())) {
            for (let position = frame.start; position < result.length; position++) result[position].card ??= { objectID: frame.objectID, name: label };
          }
        }
      } else if (!token.endsWith("/>")) {
        const attrs = readAttributes(token);
        const id = attrs.object_id && UUID.test(attrs.object_id) ? attrs.object_id.toLowerCase() : undefined;
        frames.push({ name, previous: style, objectID: name === "font" ? id : undefined, start: result.length });
        if (name === "b") style = { ...style, bold: true };
        if (name === "i") style = { ...style, italic: true };
        if (name === "font") {
          const color = (attrs.color ?? "").toLowerCase();
          if (id !== undefined || CARD_COLORS.has(color)) style = { ...style, role: "card" };
          else if (color === "#20b2aa") style = { ...style, role: "player" };
        }
      }
    }
    append(buffer + source.slice(cursor));
    this.spans = result;
  }

  /** The distinct card references in order (a card's name split over spans counts once). */
  get references(): CardReference[] {
    const found: CardReference[] = [];
    for (const span of this.spans) {
      const last = found[found.length - 1];
      if (span.card && !(last && last.objectID === span.card.objectID && last.name === span.card.name)) found.push(span.card);
    }
    return found;
  }
}

export type LogIcon = "died" | "exile" | "steal" | "cast" | "combat" | "hurt" | "heal" | "draw" | "arrive" | "ability" | "dot";
export interface ArenaLogLine { kind: "turn" | "autoPass" | "event"; text: string; icon?: LogIcon; tint?: string }

const GOLD = "#ffd675", RED = "#ff7361", CYAN = "#80e6ff", GREEN = "#80e68c";

/** ArenaLogLine: a turn divider, smart pass's quiet line, or an event with an icon for what happened, from the public text. */
export function arenaLogLine(entry: GameLogEntry): ArenaLogLine {
  const text = new GameLogPresentation(entry.message).plainText;
  const lower = text.toLowerCase();
  if (text.startsWith("TURN ")) return { kind: "turn", text };
  if (entry.id.startsWith("local:auto-pass:") || text.startsWith("Auto-passed")) return { kind: "autoPass", text };
  const event = (icon: LogIcon, tint: string): ArenaLogLine => ({ kind: "event", text, icon, tint });
  if (lower.includes(" died") || lower.includes("destroy")) return event("died", RED);
  if (lower.includes("exile")) return event("exile", "#bfb3ff");
  if (lower.includes("gains control") || lower.includes("from graveyard onto the battlefield")) return event("steal", RED);
  if (lower.includes(" casts ")) return event("cast", GOLD);
  if (lower.includes(" attacks") || lower.includes("attacking") || lower.includes("blocks")) return event("combat", "#ff994d");
  if ((lower.includes("loses") && lower.includes("life")) || lower.includes("damage")) return event("hurt", RED);
  if (lower.includes("gains") && lower.includes("life")) return event("heal", GREEN);
  if (lower.includes("draws")) return event("draw", CYAN);
  if (lower.includes(" plays ") || lower.includes("onto the battlefield")) return event("arrive", GREEN);
  if (lower.includes("activates") || lower.includes("ability")) return event("ability", GOLD);
  return event("dot", "rgba(255,255,255,.35)");
}

/** Which combat damage the new log entries of one snapshot transition came from. */
export type DamageStep = "firstStrike" | "regular" | "combined" | "none";
export interface Fighter { name: string; keywords: ReadonlySet<CombatKeyword> }

/** Steps as XMage names them ("FIRST_COMBAT_DAMAGE") or normalized ("first-combat-damage"). */
export const normalizedStep = (step: string) => step.toLowerCase().replace(/_/g, "-");

export function damageStep(previousStep: string | undefined, currentStep: string): DamageStep {
  const previous = previousStep === undefined ? undefined : normalizedStep(previousStep);
  const step = normalizedStep(currentStep);
  const first = BoardEventDiffer.firstStrikeStep;
  const preDamage = BoardEventDiffer.preDamageSteps;
  if (step === first && previous !== first) return "firstStrike";
  if (previous === first && step !== first && !preDamage.has(step)) return "regular";
  if (previous !== undefined && preDamage.has(previous) && step !== first && !preDamage.has(step)) return "combined";
  return "none";
}

/**
 * One-line reasons for the combat damage and deaths the public log already shows, such as "Atarka, World Render has
 * double strike (first-strike damage)". Uses only public snapshot data: the combat keywords of creatures seen attacking
 * or blocking this turn, and the step. A reason is decided once, when its entry first appears, so a keyword that ends
 * later never rewrites it.
 */
export class CombatLogReasons {
  /** Log entry ID to its reason. */
  reasons = new Map<string, string>();
  private gameID?: string;
  private turn = 0;
  private previousStep?: string;
  /** Creatures seen attacking or blocking this turn, by lowercased instance ID. */
  private fighters = new Map<string, Fighter>();
  private seen = new Set<string>();

  observe(snapshot: GameSnapshot) {
    const step = normalizedStep(snapshot.step ?? snapshot.phase);
    const fresh = this.gameID !== snapshot.id;
    if (fresh) {
      this.reasons = new Map(); this.turn = 0; this.previousStep = undefined; this.fighters = new Map(); this.seen = new Set();
      this.gameID = snapshot.id;
    }
    if (snapshot.turn !== this.turn) { this.fighters = new Map(); this.turn = snapshot.turn; }
    for (const card of snapshot.players.flatMap((player) => player.zones.battlefield)) {
      if (isInCombat(card)) {
        this.fighters.set(card.instanceId.toLowerCase(), { name: card.card.name, keywords: new Set(CombatKeywords.of(card.cardIcons, card.card.oracleText)) });
      }
    }
    const transition = damageStep(fresh ? undefined : this.previousStep, step);
    const reasons = new Map(this.reasons);
    for (const entry of snapshot.log) {
      if (this.seen.has(entry.id)) continue;
      this.seen.add(entry.id);
      // Entries already in the log when a game is first seen have no known context.
      if (fresh) continue;
      const reason = CombatLogReasons.reason(entry.message, transition, this.fighters);
      if (reason) reasons.set(entry.id, reason);
    }
    const live = new Set(snapshot.log.map((entry) => entry.id));
    for (const id of this.seen) if (!live.has(id)) this.seen.delete(id);
    for (const id of reasons.keys()) if (!live.has(id)) reasons.delete(id);
    this.reasons = reasons;
    this.previousStep = step;
  }

  /**
   * The reason for one engine log message, or undefined. Reads XMage's own wording: "<source> deals N damage to
   * <target>", "<player> loses N life at combat from <source>" and "<creature> died".
   */
  static reason(message: string, step: DamageStep, fighters: ReadonlyMap<string, Fighter>): string | undefined {
    if (step === "none") return undefined;
    const presentation = new GameLogPresentation(message);
    const text = presentation.plainText.trim();
    const references = presentation.references;
    const fighter = (reference?: CardReference) => (reference ? fighters.get(reference.objectID.toLowerCase()) : undefined);
    if (text.endsWith(" died")) {
      const dead = references[0];
      const found = fighter(dead);
      if (step !== "firstStrike" || !dead || !found) return undefined;
      return CombatKeywords.strikesFirst(found.keywords)
        ? `${dead.name} dies to first-strike damage`
        : `${dead.name} dies to first-strike damage before dealing damage`;
    }
    const damage = / deals \d+ damage to /.test(text);
    const lifeLoss = / loses \d+ life at combat from /.test(text);
    if (!damage && !lifeLoss) return undefined;
    const source = damage ? references[0] : references[references.length - 1];
    const keywords = fighter(source)?.keywords;
    if (!source || !keywords) return undefined;
    if (keywords.has("doubleStrike")) {
      if (step === "firstStrike") return `${source.name} has double strike (first-strike damage)`;
      if (step === "regular") return `${source.name} has double strike (regular damage)`;
      return `${source.name} has double strike (first-strike and regular damage)`;
    }
    if (keywords.has("firstStrike") && step !== "regular") return `${source.name} has first strike (first-strike damage)`;
    if (keywords.has("deathtouch") && damage && references.length > 1) return `${source.name} has deathtouch (any damage is lethal)`;
    return undefined;
  }
}
