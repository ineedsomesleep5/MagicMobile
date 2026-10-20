/** Table chat, quick chat and join links: ports of TableChat.kt, TableLinks.kt and GameEmotes.kt (parity/chat-cases.json). */
import { codePointCount } from "./json";

const blank = /^[\p{Cc}\p{Zs}\p{Zl}\p{Zp}]$/u;

export const TableChatText = {
  /** Unicode code points in one message. */
  MAX_CODE_POINTS: 200,

  /**
   * One line of chat: control characters, tabs and line breaks become spaces, runs of spaces
   * collapse, and the result is trimmed and capped. Nothing left: nothing is sent.
   */
  sanitize(raw: string, limit = 200): string | undefined {
    let out = "";
    let pendingSpace = false;
    for (const ch of raw) {
      if (blank.test(ch)) pendingSpace = out.length > 0;
      else {
        if (pendingSpace) { out += " "; pendingSpace = false; }
        out += ch;
      }
    }
    const capped = codePointCount(out) > limit ? [...out].slice(0, limit).join("") : out;
    const trimmed = capped.endsWith(" ") ? capped.slice(0, -1) : capped;
    return trimmed.length > 0 ? trimmed : undefined;
  },

  codePoints: codePointCount,
};

/**
 * Masks strong language in received chat, keeping each word's first letter ("s***"). Only whole
 * words of ASCII letters are checked, so card names such as Cockatrice are left alone.
 */
export const TableChatFilter = {
  words: new Set([
    "ass", "asshole", "bastard", "bitch", "bollocks", "chink", "cock", "cunt", "dick", "dickhead", "fag", "faggot", "fuck", "kike",
    "motherfucker", "nigga", "nigger", "prick", "pussy", "retard", "shit", "slut", "spic", "twat", "wanker", "whore",
  ]),
  stems: ["bitch", "cunt", "fagg", "fuck", "motherf", "nigg", "retard", "shit", "slut", "twat", "wank", "whore"],
  suffixes: ["s", "es", "ed", "er", "ers", "ing", "y"],

  isBlocked(word: string): boolean {
    const lower = word.toLowerCase();
    if (TableChatFilter.words.has(lower) || TableChatFilter.stems.some((stem) => lower.startsWith(stem))) return true;
    return TableChatFilter.suffixes.some((suffix) => lower.endsWith(suffix) && TableChatFilter.words.has(lower.slice(0, -suffix.length)));
  },

  filtered(text: string): string {
    return text.replace(/[A-Za-z]+/g, (word) => (TableChatFilter.isBlocked(word) ? word[0] + "*".repeat(word.length - 1) : word));
  },
};

/** Join links for a cross-play table (TableJoinLink). */
export const TableJoinLink = {
  HOST: "magicmobile-downloads.vercel.app",
  SCHEME: "magicmobile",
  /** The relay's table-code alphabet (no 0/O, 1/I). */
  ALPHABET: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",

  url: (code: string) => {
    const normalized = TableJoinLink.normalized(code);
    return normalized === undefined ? undefined : `https://${TableJoinLink.HOST}/join/${normalized}`;
  },

  normalized(raw: string): string | undefined {
    const code = raw.toUpperCase();
    return code.length === 6 && [...code].every((ch) => TableJoinLink.ALPHABET.includes(ch)) ? code : undefined;
  },

  /** The table code in a join link, or undefined for any other link. */
  code(link: string): string | undefined {
    const match = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)([^?#]*)/.exec(link);
    if (!match) return undefined;
    const scheme = match[1].toLowerCase();
    const host = match[2].toLowerCase();
    const parts = match[3].split("/").filter((part) => part.length > 0);
    if (scheme === TableJoinLink.SCHEME && host === "join" && parts.length === 1) return TableJoinLink.normalized(parts[0]);
    if (scheme === "https" && host === TableJoinLink.HOST && parts.length === 2 && parts[0] === "join") return TableJoinLink.normalized(parts[1]);
    return undefined;
  },
};

/** Quick chat's fixed lines (GameEmote): never free text. */
export const GameEmotes = [
  { raw: "hello", text: "Hello!" }, { raw: "wellPlayed", text: "Well played!" }, { raw: "thanks", text: "Thanks!" },
  { raw: "oops", text: "Oops!" }, { raw: "wow", text: "Wow!" }, { raw: "goodGame", text: "Good game!" },
] as const;
export type GameEmote = (typeof GameEmotes)[number];
export const gameEmote = (raw: string | undefined): GameEmote | undefined => GameEmotes.find((e) => e.raw === raw);
