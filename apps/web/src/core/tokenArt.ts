/**
 * Token artwork the way iOS finds it (NativeArtworkCatalogue.searchToken, NativeAssetStore.matchTokenArtwork): a Scryfall
 * search for the token's exact name, then the one printing whose name, type, rules, colours and printed P/T match what
 * the engine shows. A generic name never picks between different tokens. Checked by test/tokenArt.test.ts.
 */
import { EngineDisplayText } from "./displayText";
import { tokenArtworkName } from "./gameStats";
import type { TokenArtworkIdentity } from "./models";

export interface TokenArtwork {
  id: string; name: string; typeLine?: string; oracleText?: string; power?: string; toughness?: string; colors?: string[];
  face?: "back";
  /** Scryfall image URLs by size (normal, large, art_crop), cards.scryfall.io only. */
  images: Record<string, string>;
}

const COLORS = new Set(["W", "U", "B", "R", "G"]);
const validColors = (colors: string[] | undefined): colors is string[] =>
  colors !== undefined && colors.every((c) => COLORS.has(c)) && new Set(colors).size === colors.length;
const sameColors = (a: string[] | undefined, b: string[]) => { const set = new Set(a ?? []); return set.size === new Set(b).size && b.every((c) => set.has(c)); };

const artworkKey = (token: TokenArtwork) => `token:${token.id.toLowerCase()}${token.face === "back" ? ":back" : ""}`;
const byKey = (a: TokenArtwork, b: TokenArtwork) => (artworkKey(a) < artworkKey(b) ? -1 : artworkKey(a) > artworkKey(b) ? 1 : 0);

export function hasMatchingMetadata(token: TokenArtwork): boolean {
  const { name, typeLine, oracleText, colors, power, toughness } = token;
  if (!name || !typeLine || oracleText === undefined || !validColors(colors) || (power?.length ?? 0) > 32 || (toughness?.length ?? 0) > 32) return false;
  return typeLine.toLowerCase().includes("creature") ? !!power && !!toughness : true;
}

const normalizedText = (value: string) => EngineDisplayText.text(value).toLowerCase().split(/\s+/).filter(Boolean).join(" ");
const normalizedType = (value: string) => {
  const line = normalizedText(value).replace(/—/g, "-");
  return line.startsWith("token ") ? line.slice(6) : line;
};
const escape = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** XMage and Oracle word a token's self-reference differently ("this token", "this artifact", "Sacrifice Food Token:"). */
function normalizedRules(value: string, typeLine: string, name: string): string {
  let rules = normalizedText(value).replace(/this token/g, "this permanent");
  const kinds = normalizedType(typeLine).split(" - ")[0].split(" ");
  for (const kind of ["artifact", "creature", "enchantment", "land"]) {
    if (kinds.includes(kind)) rules = rules.split(`this ${kind}`).join("this permanent");
  }
  const selfName = normalizedText(tokenArtworkName(name));
  return rules.replace(new RegExp(`(?<![a-z0-9])sacrifice ${escape(selfName)}(?: token)?(?=\\s*:)`, "g"), "sacrifice this permanent");
}

export function sameTokenIdentity(a: TokenArtwork, b: TokenArtwork): boolean {
  return normalizedText(tokenArtworkName(a.name)) === normalizedText(tokenArtworkName(b.name)) &&
    normalizedType(a.typeLine ?? "") === normalizedType(b.typeLine ?? "") &&
    normalizedRules(a.oracleText ?? "", a.typeLine ?? "", a.name) === normalizedRules(b.oracleText ?? "", b.typeLine ?? "", b.name) &&
    a.power === b.power && a.toughness === b.toughness && sameColors(a.colors, b.colors ?? []);
}

/**
 * The printing for a token on the table: every visible detail must match; among equivalent printings the first by key.
 * Counters and buffs change P/T, so a different printed P/T is allowed only when every match prints the same one.
 */
export function matchTokenArtwork(candidates: TokenArtwork[], identity: TokenArtworkIdentity): TokenArtwork | undefined {
  const { name, typeLine, oracleText, power, toughness, colors } = identity;
  if (!validColors(colors) || !typeLine) return undefined;
  const key = normalizedText(tokenArtworkName(name));
  const type = normalizedType(typeLine);
  const rules = normalizedRules(oracleText, typeLine, name);
  const matches = candidates.filter((token) => hasMatchingMetadata(token) && normalizedText(tokenArtworkName(token.name)) === key &&
    normalizedType(token.typeLine ?? "") === type && normalizedRules(token.oracleText ?? "", token.typeLine ?? "", token.name) === rules &&
    sameColors(token.colors, colors));
  const exact = matches.filter((token) => token.power === power && token.toughness === toughness).sort(byKey);
  if (exact.length > 0) return exact[0];
  const first = matches[0];
  if (!first || !matches.every((token) => token.power === first.power && token.toughness === first.toughness)) return undefined;
  return [...matches].sort(byKey)[0];
}

/** A name safe to put in an exact-name search. */
export const safeTokenSearchName = (name: string) =>
  name.length > 0 && new TextEncoder().encode(name).length <= 120 && !name.includes("\"") && !name.includes("\\") && !/[\u0000-\u001f\u007f-\u009f]/.test(name);

/** The search iOS sends for one token: its exact name among tokens. */
export const tokenSearchQuery = (name: string) => `!"${tokenArtworkName(name)}" t:token`;

type Row = Record<string, unknown>;
const text = (row: Row | undefined, key: string) => (typeof row?.[key] === "string" ? (row[key] as string) : undefined);
const list = (row: Row | undefined, key: string) => (Array.isArray(row?.[key]) ? (row![key] as unknown[]).filter((c): c is string => typeof c === "string") : undefined);
function images(uris: unknown): Record<string, string> {
  const found: Record<string, string> = {};
  if (!uris || typeof uris !== "object") return found;
  for (const [size, url] of Object.entries(uris as Record<string, unknown>)) {
    if (typeof url !== "string") continue;
    try { if (new URL(url).hostname === "cards.scryfall.io") found[size] = url; } catch { /* not a URL */ }
  }
  return found;
}

/** Token faces from one page of a Scryfall search (NativeArtworkCatalogue.accept): a double-faced token gives both. */
export function tokensFromSearch(rows: Row[]): TokenArtwork[] {
  const tokens: TokenArtwork[] = [];
  for (const row of rows) {
    const layout = text(row, "layout");
    const id = text(row, "id");
    if (!id || (layout !== "token" && layout !== "double_faced_token")) continue;
    const faces = Array.isArray(row.card_faces) ? (row.card_faces as Row[]) : [];
    const face = faces[0];
    const doubleFaced = layout === "double_faced_token";
    const pick = (key: string) => (doubleFaced ? text(face, key) : undefined) ?? text(row, key) ?? text(face, key);
    tokens.push({
      id, name: (doubleFaced ? text(face, "name") : undefined) ?? text(row, "name") ?? "", typeLine: pick("type_line"), oracleText: pick("oracle_text"),
      power: pick("power"), toughness: pick("toughness"), colors: (doubleFaced ? list(face, "colors") : undefined) ?? list(row, "colors") ?? list(face, "colors"),
      images: images(row.image_uris ?? face?.image_uris),
    });
    const back = faces[1];
    if (doubleFaced && back) {
      tokens.push({ id, name: text(back, "name") ?? "", typeLine: text(back, "type_line"), oracleText: text(back, "oracle_text"), power: text(back, "power"),
        toughness: text(back, "toughness"), colors: list(back, "colors"), face: "back", images: images(back.image_uris) });
    }
  }
  return tokens;
}

/** The image for a matched token, or an equivalent printing's when it has none of that size. */
export function tokenImage(candidates: TokenArtwork[], match: TokenArtwork, size: string): string | undefined {
  return match.images[size] ?? candidates.find((token) => sameTokenIdentity(token, match) && token.images[size])?.images[size];
}
