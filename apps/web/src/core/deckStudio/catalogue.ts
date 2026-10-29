/**
 * Deck Studio's card catalogue (NativeDeckMetadataCatalogue.swift): selected-printing metadata, not live Oracle updates,
 * Commander legality or mana production. scripts/prepare_data.py writes it as public/generated/catalogue.json.
 */
import { appConfig } from "../appConfig";
import { cardNameCandidates, isFrontOf } from "../deckResolver";
import { EngineDisplayText } from "../displayText";

/** NativeDeckMetadataCatalogue.Card. A missing field means unavailable; an empty colour list is known colorless. */
export interface CatalogueCard {
  name: string;
  typeLine?: string;
  /** Upper-case card types ("CREATURE", "LAND"); unset when any type is one this build does not know. */
  types?: string[];
  oracleText?: string;
  manaValue?: number;
  manaCost?: string;
  colors?: string[];
  colorIdentity?: string[];
  /** Sets present in the pinned registry, not a promise that each printing is selectable. */
  setCodes: string[];
  /** Curated role keys from Scryfall's oracle tags ("ramp", "cardFlow" …); empty is no tag, not a claim. */
  roles: string[];
}

/** The compact wire form: [name, typeLine, types, oracleText, manaValue, manaCost, colors, colorIdentity, setCodes, roles?]. */
type Row = [string, ...(string | number | null)[]];
interface Wire { schema: number; catalogueHash: string; aliases: Record<string, string>; cards: Row[] }

const knownTypes = new Set(["ARTIFACT", "BATTLE", "CONSPIRACY", "CREATURE", "DUNGEON", "ENCHANTMENT", "INSTANT", "LAND", "PHENOMENON",
  "PLANE", "PLANESWALKER", "SCHEME", "SORCERY", "KINDRED", "VANGUARD"]);
const knownRoles = new Set(["ramp", "cardFlow", "interaction", "boardWipe", "protection", "graveyardHate", "recursion", "tutor"]);

class CatalogueError extends Error {}

/** Resolves only reverse faces attested by the bundled aliases (NativeDeckCanonicalNames.reverseFaces). */
export function reverseFaces(aliases: ReadonlyMap<string, string>, exactNames: ReadonlySet<string>): Map<string, string> {
  const candidates = new Map<string, Set<string>>();
  for (const [combined, front] of aliases) {
    if (!combined.startsWith(`${front} // `)) continue;
    const back = combined.slice(front.length + 4);
    if (back.length === 0 || exactNames.has(back)) continue;
    if (!candidates.has(back)) candidates.set(back, new Set());
    candidates.get(back)!.add(front);
  }
  const result = new Map<string, string>();
  for (const [back, fronts] of candidates) if (fronts.size === 1) result.set(back, [...fronts][0]);
  return result;
}

/** Swift `<` on names: code-unit order, which matches it for the catalogue's names. */
export const byName = (a: { name: string }, b: { name: string }) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);

export class Catalogue {
  /** Every card, sorted by name. */
  readonly all: readonly CatalogueCard[];
  readonly catalogueHash: string;
  private readonly index = new Map<string, CatalogueCard>();
  private readonly aliases = new Map<string, string>();
  private readonly reverse: Map<string, string>;
  /** Front faces with an attested back (double-faced cards). */
  private fronts?: Set<string>;

  constructor(cards: CatalogueCard[], aliases: Record<string, string>, catalogueHash = "") {
    this.all = [...cards].sort(byName);
    for (const card of this.all) this.index.set(card.name, card);
    if (this.index.size !== cards.length) throw new CatalogueError("Invalid local metadata catalogue.");
    for (const [alias, target] of Object.entries(aliases)) if (!this.index.has(alias)) this.aliases.set(alias, target);
    this.reverse = reverseFaces(this.aliases, new Set(this.index.keys()));
    this.catalogueHash = catalogueHash;
  }

  /** The exact name, a combined double-faced name, or an attested reverse face (`card(named:)`). */
  card(name: string): CatalogueCard | undefined {
    for (const candidate of cardNameCandidates(name)) {
      const card = this.index.get(candidate) ?? this.lookup(this.aliases.get(candidate)) ?? this.lookup(this.reverse.get(candidate));
      if (!card) continue;
      // A double-faced card's front never stands in for a different back (isFrontOf).
      if (isFrontOf(candidate, name) && (this.fronts ??= new Set(this.aliases.values())).has(card.name)) continue;
      return card;
    }
    // A fix the server sent for a name a deck site spells its own way (appConfig).
    const fixes = appConfig.current.nameFixes;
    for (const candidate of cardNameCandidates(name)) {
      const fixed = fixes[candidate] === undefined ? undefined : this.index.get(fixes[candidate]);
      if (fixed) return fixed;
    }
    return undefined;
  }

  /** The catalogue's own name for a card, like DeckResolver.canonicalName. */
  canonicalName(name: string): string | undefined { return this.card(name)?.name; }

  /** Every reverse face and the front face it belongs to. */
  get reverseFaceFronts(): ReadonlyMap<string, string> { return this.reverse; }

  private lookup(name: string | undefined) { return name === undefined ? undefined : this.index.get(name); }

  /** Decodes catalogue.json, checking it as the iOS decoder does. Rules text is cleaned with EngineDisplayText. */
  static fromJSON(raw: unknown): Catalogue {
    const wire = raw as Wire;
    if (typeof wire !== "object" || wire === null || wire.schema !== 1 || !Array.isArray(wire.cards) || wire.cards.length === 0
      || typeof wire.aliases !== "object" || wire.aliases === null) throw new CatalogueError("Invalid local metadata catalogue.");
    const text = (value: unknown) => (typeof value === "string" ? value : undefined);
    const list = (value: unknown) => (typeof value === "string" ? (value.length === 0 ? [] : value.split(" ")) : undefined);
    const colours = (value: unknown) => {
      if (typeof value !== "string") return undefined;
      const letters = [...value];
      if (letters.length > 5 || new Set(letters).size !== letters.length || letters.some((c) => !"WUBRG".includes(c))) {
        throw new CatalogueError("Invalid metadata colors; expected unique WUBRG symbols.");
      }
      return letters;
    };
    const cards = wire.cards.map((row): CatalogueCard => {
      const [name, typeLine, typesRaw, oracle, manaValue, manaCost, colors, identity, sets, roles] = row;
      if (typeof name !== "string" || name.length === 0) throw new CatalogueError("Invalid local metadata catalogue.");
      let types = list(typesRaw);
      // Unknown future types must not silently become nonlands in statistics or search.
      if (types && !types.every((type) => knownTypes.has(type))) types = undefined;
      const roleKeys = list(roles) ?? [];
      if (!roleKeys.every((role) => knownRoles.has(role))) throw new CatalogueError("Invalid metadata roles; expected unique known role keys.");
      if (manaValue !== null && manaValue !== undefined && (typeof manaValue !== "number" || !Number.isFinite(manaValue) || manaValue < 0)) {
        throw new CatalogueError("Invalid printed mana value.");
      }
      const oracleText = text(oracle);
      return {
        name, typeLine: types ? text(typeLine) : undefined, types, oracleText: oracleText === undefined ? undefined : EngineDisplayText.text(oracleText),
        manaValue: typeof manaValue === "number" ? manaValue : undefined, manaCost: text(manaCost), colors: colours(colors),
        colorIdentity: colours(identity), setCodes: list(sets) ?? [], roles: roleKeys,
      };
    });
    return new Catalogue(cards, wire.aliases, typeof wire.catalogueHash === "string" ? wire.catalogueHash : "");
  }
}

let loading: Promise<Catalogue> | undefined;

/** The app's catalogue, fetched and decoded once; a failed load is forgotten so the next call tries again. */
export function loadCatalogue(): Promise<Catalogue> {
  loading ??= fetch("/generated/catalogue.json")
    .then((response) => {
      if (!response.ok) throw new CatalogueError("Missing bundled card metadata.");
      return response.json();
    })
    .then(Catalogue.fromJSON)
    .catch((error: unknown) => { loading = undefined; throw error; });
  return loading;
}
