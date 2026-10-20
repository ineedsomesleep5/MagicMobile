/**
 * Port of EngineDisplayText (OnDevicePromptAdapter.kt): plain-text presentation only. Never use
 * these results as engine IDs or answers. No HTML renderer, network request or hidden-card lookup.
 */
const newline = new RegExp("\\r\\n|[\\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]");
/** Swift `Character.isWhitespace`: the Unicode White_Space set, not only ASCII. */
const whitespace = new RegExp("[\\s\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]+");
const entity = /&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[A-Za-z]+);/g;
const named: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " ", ndash: "–", mdash: "—", hellip: "…", lsquo: "‘", rsquo: "’", times: "×",
};
const markup = /<!--[\s\S]*?(?:-->|$)|<\/?([A-Za-z][A-Za-z0-9:-]*)\b(?:[^<>"']|"[^"]*"|'[^']*')*>/g;
const blocks = new Set(["br", "p", "div", "li", "ul", "ol", "table", "tr", "td", "hr"]);
const suppressed = new Set(["script", "style", "iframe", "object", "svg", "math", "head", "template"]);
const attributes = /\s+([a-z][a-z0-9-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi;
const symbol = /^\{(?:[0-9]+|[WUBRGCXYZSTQE]|[WUBRGC2]\/[WUBRGCP])\}$/;

const decodeEntities = (source: string): string =>
  source.replace(entity, (match, token: string) => {
    let replacement: string | undefined = named[token];
    if (token.startsWith("#")) {
      const hex = token.toLowerCase().startsWith("#x");
      const digits = token.slice(hex ? 2 : 1);
      const number = hex ? Number.parseInt(digits, 16) : Number.parseInt(digits, 10);
      if (Number.isFinite(number) && number <= 0x10ffff && !(number >= 0xd800 && number <= 0xdfff)) {
        // Never introduce control or bidirectional-override characters.
        replacement = (number < 32 && ![9, 10, 13].includes(number)) || (number >= 127 && number <= 159) ||
          (number >= 0x202a && number <= 0x202e) || (number >= 0x2066 && number <= 0x2069) ? "" : String.fromCodePoint(number);
      }
    }
    return replacement ?? match;
  });

const imageSymbol = (tag: string): string => {
  // Only an explicit canonical symbol alt is supported. Never infer a label from src or a URL.
  const matches = [...tag.matchAll(attributes)].filter((m) => m[1].toLowerCase() === "alt");
  if (matches.length !== 1) return "";
  const value = (matches[0][2] ?? matches[0][3] ?? matches[0][4])?.toUpperCase();
  return value !== undefined && symbol.test(value) ? value : "";
};

const stripMarkup = (source: string): string => {
  let output = "";
  let cursor = 0;
  const hidden: string[] = [];
  for (const match of source.matchAll(markup)) {
    const index = match.index ?? 0;
    if (hidden.length === 0) output += source.slice(cursor, index);
    cursor = index + match[0].length;
    const tag = match[0];
    if (tag.startsWith("<!--")) continue;
    const name = (match[1] ?? "").toLowerCase();
    const closing = tag.startsWith("</");
    if (suppressed.has(name)) {
      if (closing) { if (hidden[hidden.length - 1] === name) hidden.pop(); }
      else if (!tag.endsWith("/>")) hidden.push(name);
      continue;
    }
    if (hidden.length > 0) continue;
    if (blocks.has(name)) output += "\n";
    else if (name === "img") output += imageSymbol(tag);
  }
  if (hidden.length === 0) output += source.slice(cursor);
  return output;
};

const knownPhases: Record<string, string> = {
  PRECOMBAT_MAIN: "Precombat main", POSTCOMBAT_MAIN: "Postcombat main", BEGIN_COMBAT: "Beginning of combat", END_COMBAT: "End of combat",
  DECLARE_ATTACKERS: "Declare attackers", DECLARE_BLOCKERS: "Declare blockers", FIRST_COMBAT_DAMAGE: "First-strike damage",
  COMBAT_DAMAGE: "Combat damage", END_TURN: "End step", CLEANUP: "Cleanup", UNTAP: "Untap", UPKEEP: "Upkeep", DRAW: "Draw",
  BEGINNING: "Beginning", COMBAT: "Combat", ENDING: "Ending",
};

export const EngineDisplayText = {
  text(source: string): string {
    let current = source;
    // Decode before parsing and reach a fixed point, including nested entities.
    for (;;) {
      const next = stripMarkup(decodeEntities(current)).split(newline)
        .map((line) => line.split(whitespace).filter((part) => part.length > 0).join(" "))
        .filter((line) => line.length > 0).join("\n");
      if (next === current) return next;
      current = next;
    }
  },
  label(source: string, fallback = ""): string {
    const value = EngineDisplayText.text(source).split(/\s+/).filter((part) => part.length > 0).join(" ");
    return value.length > 0 ? value : fallback;
  },
  phaseLabel(source: string): string {
    const value = EngineDisplayText.label(source);
    if (knownPhases[value]) return knownPhases[value];
    if (value.length === 0 || value !== value.toUpperCase() || !/^[\p{L}_\s]+$/u.test(value)) return value;
    const words = value.replace(/_/g, " ").toLowerCase();
    return words.charAt(0).toUpperCase() + words.slice(1);
  },
};
