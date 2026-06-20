import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { CardCacheMetadata } from "@magicmobile/shared";

export interface CachedCardVisual {
  name: string;
  imageUrl?: string;
  artCropUrl?: string;
  typeLine?: string;
  manaCost?: string;
  manaValue?: number;
  colors?: string[];
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

function normalizeName(name: string): string {
  return name.trim().toLowerCase();
}
