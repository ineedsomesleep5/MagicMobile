/**
 * The builder's local catalogue searches (DeckStudioCatalogueSearch.swift, NativeDeckMetadataCatalogue.search and
 * ranked; Android DeckMetadata.kt and DeckStudioBuilderSearch): Add cards with its search syntax and filters, Quick Add
 * name suggestions and the commander-first picker.
 */
import { byName, type Catalogue, type CatalogueCard } from "./catalogue";

const wubrg = ["W", "U", "B", "R", "G"];

/**
 * DeckStudioSearchSyntax, a small Scryfall-style subset: `t:creature`, `o:draw`, `mv<=3`, `mv>=2`, `mv=3`, `id:wu`
 * (identity within W and U; `id:c` is colorless). Values may be quoted: `t:"legendary creature"`. Every term must match.
 * Anything else, including a term still being typed, stays as name or rules text.
 */
export interface SearchSyntax {
  text: string;
  types: string[];
  oracle: string[];
  minimumManaValue?: number;
  maximumManaValue?: number;
  /** Allowed identity letters; undefined is no identity term. */
  identity?: Set<string>;
  setCode: string;
}

export const SearchSyntax = {
  hasFilters: (syntax: SearchSyntax) => syntax.types.length > 0 || syntax.oracle.length > 0 || syntax.minimumManaValue !== undefined
    || syntax.maximumManaValue !== undefined || syntax.identity !== undefined,

  plain: (text: string): SearchSyntax => ({ text, types: [], oracle: [], setCode: "" }),

  parse(query: string): SearchSyntax {
    const text: string[] = [];
    const result = SearchSyntax.plain("");
    for (const token of tokens(query)) {
      const lower = token.toLowerCase();
      const value = (prefix: string) => {
        if (!lower.startsWith(prefix)) return undefined;
        const rest = token.slice(prefix.length).replace(/^["\t\p{Zs}]+|["\t\p{Zs}]+$/gu, "");
        return rest.length === 0 ? undefined : rest;
      };
      // A term still being typed filters nothing yet.
      if (["t:", "o:", "id:", "mv<=", "mv>=", "mv="].some((prefix) => lower.startsWith(prefix) && value(prefix) === undefined)) continue;
      const type = value("t:");
      if (type !== undefined) { result.types.push(type); continue; }
      const rules = value("o:");
      if (rules !== undefined) { result.oracle.push(rules); continue; }
      const identity = value("id:");
      if (identity !== undefined) {
        const letters = new Set([...identity.toUpperCase()]);
        if ([...letters].every((letter) => [...wubrg, "C"].includes(letter)) && !(letters.has("C") && letters.size > 1)) {
          result.identity = new Set(wubrg.filter((color) => (result.identity ?? new Set(wubrg)).has(color) && letters.has(color)));
          continue;
        }
      }
      // Plain decimals only ("3", "2.5", ".5"): no exponents, signs or hex.
      const decimal = (prefix: string) => {
        const raw = value(prefix);
        if (raw === undefined || !/^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$/.test(raw)) return undefined;
        const number = Number(raw);
        return Number.isFinite(number) && number >= 0 ? number : undefined;
      };
      const atMost = decimal("mv<=");
      if (atMost !== undefined) { result.maximumManaValue = Math.min(result.maximumManaValue ?? atMost, atMost); continue; }
      const atLeast = decimal("mv>=");
      if (atLeast !== undefined) { result.minimumManaValue = Math.max(result.minimumManaValue ?? atLeast, atLeast); continue; }
      const exactly = decimal("mv=");
      if (exactly !== undefined) {
        result.minimumManaValue = Math.max(result.minimumManaValue ?? exactly, exactly);
        result.maximumManaValue = Math.min(result.maximumManaValue ?? exactly, exactly);
        continue;
      }
      text.push(token);
    }
    result.text = text.join(" ");
    return result;
  },
};

/** Whitespace-separated tokens; double quotes keep spaces inside a token. */
function tokens(query: string): string[] {
  const result: string[] = [];
  let current = "";
  let quoted = false;
  for (const character of query) {
    if (character === "\"") { quoted = !quoted; current += character; }
    else if (/\s/u.test(character) && !quoted) { if (current.length > 0) { result.push(current); current = ""; } }
    else current += character;
  }
  if (current.length > 0) result.push(current);
  return result;
}

/** Case-insensitive, like `range(of:options: .caseInsensitive)`. */
const containsIgnoringCase = (text: string | undefined, query: string) => text !== undefined && text.toLowerCase().includes(query.toLowerCase());
/** Case- and diacritic-insensitive, like Swift's `.diacriticInsensitive` search. */
const fold = (text: string) => (/^[\x00-\x7f]*$/.test(text) ? text.toLowerCase() : text.normalize("NFD").replace(/\p{M}+/gu, "").toLowerCase());

/** NativeDeckMetadataCatalogue.ranked: exact name, then prefix, then contained, then rules-text matches; names within each. */
export function ranked(cards: readonly CatalogueCard[], query: string): CatalogueCard[] {
  const trimmed = query.trim();
  if (trimmed.length === 0) return [...cards].sort(byName);
  const needle = trimmed.toLowerCase();
  return cards.map((card) => {
    const index = card.name.toLowerCase().indexOf(needle);
    return { card, rank: index < 0 ? 3 : index === 0 ? (needle.length === card.name.length ? 0 : 1) : 2 };
  }).sort((a, b) => (a.rank === b.rank ? byName(a.card, b.card) : a.rank - b.rank)).map((scored) => scored.card);
}

/** NativeDeckMetadataCatalogue.SearchFilter. `colors` and `colorIdentity` are exact sets; unknown metadata never matches. */
export interface SearchFilter {
  query?: string;
  type?: string;
  setCode?: string;
  colors?: ReadonlySet<string>;
  colorIdentity?: ReadonlySet<string>;
  minimumManaValue?: number;
  maximumManaValue?: number;
}

const sameSet = (values: string[] | undefined, wanted: ReadonlySet<string>) =>
  values !== undefined && new Set(values).size === wanted.size && values.every((value) => wanted.has(value));
const sameSetCode = (card: CatalogueCard, code: string) => card.setCodes.some((value) => value.toLowerCase() === code.toLowerCase());

/** NativeDeckMetadataCatalogue.search: the plain name-or-rules search. Without a query it keeps name order. */
export function plainSearch(catalogue: Catalogue, filter: SearchFilter = {}, limit = 40): CatalogueCard[] {
  if (limit <= 0) return [];
  const query = (filter.query ?? "").trim();
  const cap = Math.min(limit, 2000);
  const matches: CatalogueCard[] = [];
  for (const card of catalogue.all) {
    if ((query.length === 0 || containsIgnoringCase(card.name, query) || containsIgnoringCase(card.oracleText, query))
      && (!filter.type || containsIgnoringCase(card.typeLine, filter.type))
      && (!filter.setCode || sameSetCode(card, filter.setCode))
      && (filter.colors === undefined || sameSet(card.colors, filter.colors))
      && (filter.colorIdentity === undefined || sameSet(card.colorIdentity, filter.colorIdentity))
      && (filter.minimumManaValue === undefined || (card.manaValue !== undefined && card.manaValue >= filter.minimumManaValue))
      && (filter.maximumManaValue === undefined || (card.manaValue !== undefined && card.manaValue <= filter.maximumManaValue))) {
      matches.push(card);
      if (query.length === 0 && matches.length >= cap) break;
    }
  }
  return query.length === 0 ? matches : ranked(matches, query).slice(0, cap);
}

/** The Add cards sheet: its search field plus the Type, mana value, set and "Within commander color identity" filters. */
export interface SearchQuery {
  query: string;
  /** A type line word, as the Type picker gives it ("Creature"); empty is all types. */
  type?: string;
  /** The commander's identity when "Within commander color identity" is on. */
  allowedIdentity?: readonly string[];
  setCode?: string;
  minimumManaValue?: number;
  maximumManaValue?: number;
  /** 80 on the phones. */
  limit?: number;
}

/**
 * DeckStudioCatalogueSearch.cards. Search syntax filters apply before the cap together with the sheet's own filters;
 * without filter terms this is the plain name or rules-text search over each exact identity bucket, so off-color cards
 * cannot hide later matches.
 */
export function searchCatalogue(catalogue: Catalogue, search: SearchQuery): CatalogueCard[] {
  const { type = "", allowedIdentity, setCode = "", minimumManaValue: lower, maximumManaValue: upper, limit = 80 } = search;
  const valid = (value: number | undefined) => value === undefined || (Number.isFinite(value) && value >= 0);
  if (limit <= 0 || !valid(lower) || !valid(upper) || (lower !== undefined && upper !== undefined && lower > upper)) return [];
  const cap = Math.min(limit, 2000);
  const syntax = SearchSyntax.parse(search.query);
  if (SearchSyntax.hasFilters(syntax)) {
    if (allowedIdentity && !allowedIdentity.every((color) => wubrg.includes(color))) return [];
    if (type.length > 0) syntax.types.push(type);
    syntax.setCode = setCode;
    const lowers = [syntax.minimumManaValue, lower].filter((value): value is number => value !== undefined);
    const uppers = [syntax.maximumManaValue, upper].filter((value): value is number => value !== undefined);
    syntax.minimumManaValue = lowers.length > 0 ? Math.max(...lowers) : undefined;
    syntax.maximumManaValue = uppers.length > 0 ? Math.min(...uppers) : undefined;
    if (allowedIdentity) syntax.identity = new Set(wubrg.filter((color) => (syntax.identity ?? new Set(wubrg)).has(color) && allowedIdentity.includes(color)));
    return scan(catalogue, syntax, false, cap);
  }
  const filter: SearchFilter = { query: syntax.text, type, setCode, minimumManaValue: lower, maximumManaValue: upper };
  if (!allowedIdentity) return plainSearch(catalogue, filter, cap);
  const identity = [...new Set(allowedIdentity)].sort();
  if (identity.length > 5 || !identity.every((color) => wubrg.includes(color))) return [];
  const results: CatalogueCard[] = [];
  for (let mask = 0; mask < 1 << identity.length; mask += 1) {
    const bucket = new Set(identity.filter((_, index) => (mask & (1 << index)) !== 0));
    results.push(...plainSearch(catalogue, { ...filter, colorIdentity: bucket }, cap));
  }
  return ranked(results, syntax.text).slice(0, cap);
}

/** Quick Add autocomplete: names only, exact and prefix matches first. */
export function nameSuggestions(catalogue: Catalogue, query: string, limit = 5): CatalogueCard[] {
  const text = query.trim();
  if (text.length === 0 || limit <= 0) return [];
  return scan(catalogue, SearchSyntax.plain(text), true, Math.min(limit, 2000));
}

/** Legendary creatures and cards whose text says they can be your commander. Partner and background pairings are left to XMage. */
export const isCommanderCandidate = (card: CatalogueCard) =>
  (card.types?.includes("CREATURE") === true && containsIgnoringCase(card.typeLine, "Legendary"))
  || containsIgnoringCase(card.oracleText, "can be your commander");

/** The commander-first picker. Plain words match the name; the search syntax also applies. */
export function commanderSearch(catalogue: Catalogue, query: string, limit = 80): CatalogueCard[] {
  if (limit <= 0) return [];
  return scan(catalogue, SearchSyntax.parse(query), true, Math.min(limit, 2000), isCommanderCandidate);
}

function scan(catalogue: Catalogue, syntax: SearchSyntax, nameOnly: boolean, limit: number,
  extra: (card: CatalogueCard) => boolean = () => true): CatalogueCard[] {
  const matcher = (query: string) => {
    const folded = fold(query);
    return (text: string | undefined) => text !== undefined && (containsIgnoringCase(text, query) || fold(text).includes(folded));
  };
  const name = matcher(syntax.text);
  const types = syntax.types.map(matcher);
  const oracle = syntax.oracle.map(matcher);
  const identity = syntax.identity;
  const matches = catalogue.all.filter((card) =>
    (syntax.text.length === 0 || name(card.name) || (!nameOnly && name(card.oracleText)))
    && types.every((test) => test(card.typeLine)) && oracle.every((test) => test(card.oracleText))
    && (syntax.setCode.length === 0 || sameSetCode(card, syntax.setCode))
    && (identity === undefined || (card.colorIdentity !== undefined && card.colorIdentity.every((color) => identity.has(color))))
    && (syntax.minimumManaValue === undefined || (card.manaValue !== undefined && card.manaValue >= syntax.minimumManaValue))
    && (syntax.maximumManaValue === undefined || (card.manaValue !== undefined && card.manaValue <= syntax.maximumManaValue))
    && extra(card));
  return ranked(matches, syntax.text).slice(0, limit);
}
