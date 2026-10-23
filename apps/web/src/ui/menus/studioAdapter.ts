/**
 * What Deck Studio's screens ask of the deck logic in core/deckStudio: the card search with the filter line's coins and
 * colour (DeckStudioBinderCatalogue.cards), the quick check, the deck list by type, the mana curve and the plain text.
 */
import type { Catalogue, CatalogueCard } from "../../core/deckStudio/catalogue";
import type { DeckDraft } from "../../core/deckStudio/draft";
import { type CardGroup, cardGroups, manaCurve } from "../../core/deckStudio/analysis";
import { Preflight } from "../../core/deckStudio/preflight";
import { searchCatalogue } from "../../core/deckStudio/search";
import { decodeDeckLink, DeckLinkError, deckLinkSource } from "../../core/deckStudio/linkImport";
import { draftText, type TextAnnotation } from "../../core/deckStudio/textIO";
import type { StudioDeck } from "../../core/deckStudio/draft";

export interface CardFilters {
  query: string;
  /** "Creature", "Land" …; empty for any. */
  type: string;
  /** W, U, B, R, G, or C for colourless; empty for any. */
  color: string;
  /** Mana value coins 0–7 (7 is 7 or more); none lit shows every card. */
  mana: ReadonlySet<number>;
  withinIdentity: boolean;
}

/** BinderManaFilter.matches. */
const manaMatches = (value: number | undefined, mana: ReadonlySet<number>) =>
  mana.size === 0 || (value !== undefined && mana.has(Math.min(7, Math.max(0, Math.floor(value)))));

const colorMatches = (card: CatalogueCard, color: string) =>
  !color || (color === "C" ? (card.colors ?? []).length === 0 : (card.colors ?? []).includes(color));

const typeMatches = (card: CatalogueCard, type: string) => !type || (card.types ?? []).includes(type.toUpperCase());

/**
 * DeckStudioBinderCatalogue.cards: the catalogue search with the coins and colour applied. The coins can pick values
 * that are not next to each other (1 and 5), so the search asks for the whole span and keeps the chosen ones; at most
 * 120 sleeves show.
 */
export const searchCards = Object.assign((catalogue: Catalogue, filters: CardFilters, identity?: string[]): CatalogueCard[] => {
  const low = filters.mana.size > 0 ? Math.min(...filters.mana) : undefined;
  const high = filters.mana.size === 0 || filters.mana.has(7) ? undefined : Math.max(...filters.mana) + 0.99;
  const span = searchCatalogue(catalogue, { query: filters.query, type: filters.type, allowedIdentity: identity, minimumManaValue: low, maximumManaValue: high, limit: 2000 });
  return span.filter((card) => manaMatches(card.manaValue, filters.mana) && colorMatches(card, filters.color)).slice(0, 120);
}, {
  /** The deck shelf's filter: the same coins, colour, type and words over the deck's own cards. */
  matches(card: CatalogueCard, filters: CardFilters): boolean {
    const terms = filters.query.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const haystack = `${card.name} ${card.typeLine ?? ""} ${card.oracleText ?? ""}`.toLowerCase();
    return manaMatches(card.manaValue, filters.mana) && colorMatches(card, filters.color) && typeMatches(card, filters.type)
      && terms.every((term) => haystack.includes(term));
  },
});

export interface QuickCheck { issueCount: number; summary: string; lines: string[] }

/** DeckStudioPreflight: the chip's count, its one line, and a line per kind of issue. */
export function preflightOf(draft: DeckDraft, catalogue: Catalogue | undefined, canonicalName?: (name: string) => string | undefined): QuickCheck {
  const check = Preflight.of(draft, catalogue, canonicalName);
  return { issueCount: check.issueCount, summary: check.summary, lines: check.activeIssues.map((issue) => check.chipTitle(issue)) };
}

/** The deck column's groups by type (DeckStudioWorkspaceScreen.cardGroups). */
export const deckGroups = (draft: DeckDraft, catalogue: Catalogue | undefined): CardGroup[] => cardGroups(draft.rows, "Type", catalogue);

/** The builder's curve: the main deck's nonland cards by mana value, 0 to 7+. */
export const deckCurve = manaCurve;

/** The deck as Moxfield-style plain text, or undefined when it can't be written that way (TextExport). */
export function deckText(draft: DeckDraft): string | undefined {
  if (draft.rows.length === 0) return undefined;
  try { return draftText(draft); } catch { return undefined; }
}

/**
 * A public Moxfield or Archidekt deck through this site's own origin (the providers don't allow a browser on another
 * site to read their APIs; the dev server and Vercel forward /provider/… to the fixed endpoint). Unknown names are kept
 * for review.
 */
export async function fetchLinkedDeck(link: string, excludeSideboards: boolean, canonicalName: (name: string) => string | undefined):
  Promise<{ deck: StudioDeck; annotations: TextAnnotation[] }> {
  const source = deckLinkSource(link);
  const path = source.provider === "archidekt" ? source.endpoint.replace("https://archidekt.com/api/", "/provider/archidekt/")
    : source.endpoint.replace("https://api2.moxfield.com/", "/provider/moxfield/");
  let response: Response;
  try { response = await fetch(path, { headers: { Accept: "application/json" } }); }
  catch { throw new DeckLinkError("The deck site didn't answer. Check your connection, or paste the deck's text export."); }
  if (response.status === 404) throw new DeckLinkError("That deck wasn't found. Check that it is public.");
  if (!response.ok) throw new DeckLinkError(`The deck site refused this request (${response.status}). Paste the deck's text export instead.`);
  const deck = decodeDeckLink(source, await response.text(), { canonicalName, excludeSideboards, reviewOnly: true });
  return { deck, annotations: [] };
}
