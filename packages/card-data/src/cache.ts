import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { CardCacheMetadata } from "@magicmobile/shared";

export interface CachedCardVisual {
  name: string;
  smallImageUrl?: string;
  imageUrl?: string;
  largeImageUrl?: string;
  artCropUrl?: string;
  typeLine?: string;
  manaCost?: string;
  manaValue?: number;
  colors?: string[];
  colorIdentity?: string[];
  oracleText?: string;
  legalities?: {
    commander?: "legal" | "not_legal" | "banned" | "unknown";
  };
  isBasicLand?: boolean;
  artist?: string;
  copyright?: string;
}

export interface CachedCardImageManifestEntry {
  name: string;
  url: string;
  normalUrl?: string;
  inspectionUrl?: string;
}

export interface CachedSymbolManifestEntry {
  symbol: string;
  looseVariant?: string;
  english?: string;
  svgUrl: string;
  pngUrl?: string;
}

const defaultCacheDir = ".cache/scryfall";

export function getScryfallCacheDir(): string {
  return process.env.SCRYFALL_CACHE_DIR ?? defaultCacheDir;
}

export async function readScryfallCacheMetadata(cacheDir = getScryfallCacheDir()): Promise<CardCacheMetadata> {
  try {
    const raw = await readFile(join(cacheDir, "metadata.json"), "utf8");
    return JSON.parse(raw) as CardCacheMetadata;
  } catch {
    return {
      provider: "scryfall",
      status: "empty",
      cardCount: 0,
      imageCount: 0,
      missingImageCount: 0
    };
  }
}

export async function readCachedCardVisuals(
  names: string[],
  cacheDir = getScryfallCacheDir()
): Promise<Map<string, CachedCardVisual>> {
  const wanted = new Set(names.map(normalizeName));
  if (wanted.size === 0) return new Map();

  try {
    const raw = await readFile(join(cacheDir, "card-visuals.json"), "utf8");
    const cached = JSON.parse(raw) as CachedCardVisual[];
    const byName = new Map(cached.filter((card) => wanted.has(normalizeName(card.name))).map((card) => [card.name, card]));
    return byName;
  } catch {
    return new Map();
  }
}

export async function readCachedCardImageManifest(
  cacheDir = getScryfallCacheDir()
): Promise<CachedCardImageManifestEntry[]> {
  try {
    const raw = await readFile(join(cacheDir, "card-visuals.json"), "utf8");
    const cached = JSON.parse(raw) as CachedCardVisual[];
    return cached.flatMap((card) => {
      const url = card.smallImageUrl ?? card.imageUrl;
      if (!url) return [];
      const entry: CachedCardImageManifestEntry = { name: card.name, url };
      if (card.imageUrl) entry.normalUrl = card.imageUrl;
      const inspectionUrl = card.largeImageUrl ?? card.imageUrl;
      if (inspectionUrl) entry.inspectionUrl = inspectionUrl;
      return [entry];
    });
  } catch {
    return [];
  }
}

export async function readCachedSymbolManifest(
  cacheDir = getScryfallCacheDir()
): Promise<CachedSymbolManifestEntry[]> {
  try {
    const raw = await readFile(join(cacheDir, "symbols.json"), "utf8");
    return JSON.parse(raw) as CachedSymbolManifestEntry[];
  } catch {
    return [];
  }
}

export async function syncScryfallCache(cacheDir = getScryfallCacheDir()): Promise<CardCacheMetadata> {
  const headers = {
    Accept: "application/json",
    "User-Agent": "MagicMobile/0.1 card-cache-sync"
  };

  const bulkResponse = await fetch("https://api.scryfall.com/bulk-data/oracle-cards", { headers });
  if (!bulkResponse.ok) {
    throw new Error(`Failed to read Scryfall bulk metadata: ${bulkResponse.status}`);
  }

  const bulkMetadata = (await bulkResponse.json()) as { id?: string; updated_at?: string; download_uri?: string };
  if (!bulkMetadata.download_uri) {
    throw new Error("Scryfall bulk metadata did not include download_uri");
  }

  const [cardsResponse, symbolsResponse] = await Promise.all([
    fetch(bulkMetadata.download_uri, { headers }),
    fetch("https://api.scryfall.com/symbology", { headers })
  ]);
  if (!cardsResponse.ok) {
    throw new Error(`Failed to download Scryfall default cards: ${cardsResponse.status}`);
  }
  if (!symbolsResponse.ok) {
    throw new Error(`Failed to download Scryfall symbology: ${symbolsResponse.status}`);
  }

  const cards = (await cardsResponse.json()) as ScryfallBulkCard[];
  const symbolPayload = (await symbolsResponse.json()) as ScryfallSymbolResponse;
  const symbols = (symbolPayload.data ?? [])
    .filter((symbol) => symbol.svg_uri)
    .map((symbol) => ({
      symbol: symbol.symbol,
      looseVariant: symbol.loose_variant,
      english: symbol.english,
      svgUrl: symbol.svg_uri
    }));
  const visuals = cards.map((card) => {
    const imageUris = card.image_uris ?? card.card_faces?.find((face) => face.image_uris)?.image_uris;
    return {
      name: card.name,
      typeLine: card.type_line,
      manaCost: card.mana_cost,
      manaValue: card.cmc,
      colors: card.colors?.length ? card.colors : card.color_identity ?? [],
      colorIdentity: card.color_identity ?? [],
      oracleText: card.oracle_text,
      legalities: card.legalities ? { commander: card.legalities.commander } : undefined,
      isBasicLand: Boolean(card.type_line?.includes("Basic Land")),
      smallImageUrl: imageUris?.small ?? imageUris?.normal ?? imageUris?.border_crop,
      imageUrl: imageUris?.normal ?? imageUris?.border_crop,
      largeImageUrl: imageUris?.large ?? imageUris?.normal ?? imageUris?.border_crop,
      artCropUrl: imageUris?.art_crop,
      artist: card.artist,
      copyright: card.copyright ?? "™ & © Wizards of the Coast"
    };
  });

  const imageCount = visuals.filter((card) => card.imageUrl).length;
  const metadata: CardCacheMetadata = {
    provider: "scryfall",
    status: "ready",
    cardCount: visuals.length,
    imageCount,
    missingImageCount: visuals.length - imageCount,
    symbolCount: symbols.length,
    updatedAt: new Date().toISOString()
  };
  const bulkVersion = bulkMetadata.updated_at ?? bulkMetadata.id;
  if (bulkVersion) {
    metadata.bulkVersion = bulkVersion;
  }

  await mkdir(cacheDir, { recursive: true });
  await writeFile(join(cacheDir, "card-visuals.json"), JSON.stringify(visuals), "utf8");
  await writeFile(join(cacheDir, "symbols.json"), JSON.stringify(symbols), "utf8");
  await writeFile(join(cacheDir, "metadata.json"), JSON.stringify(metadata, null, 2), "utf8");

  return metadata;
}

function normalizeName(name: string): string {
  return name.trim().toLowerCase();
}

interface ScryfallBulkCard {
  name: string;
  type_line?: string;
  mana_cost?: string;
  oracle_text?: string;
  cmc?: number;
  colors?: string[];
  color_identity?: string[];
  image_uris?: ScryfallImageUris;
  card_faces?: Array<{ image_uris?: ScryfallImageUris }>;
  legalities?: {
    commander?: "legal" | "not_legal" | "banned" | "unknown";
  };
  artist?: string;
  copyright?: string;
}

interface ScryfallImageUris {
  small?: string;
  normal?: string;
  large?: string;
  border_crop?: string;
  art_crop?: string;
}

interface ScryfallSymbolResponse {
  data?: ScryfallSymbol[];
}

interface ScryfallSymbol {
  symbol: string;
  loose_variant?: string;
  english?: string;
  svg_uri?: string;
}
