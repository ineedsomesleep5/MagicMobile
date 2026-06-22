import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const cacheDir = process.env.SCRYFALL_CACHE_DIR ?? ".cache/scryfall";
const bulkEndpoint = "https://api.scryfall.com/bulk-data/oracle-cards";

const headers = {
  Accept: "application/json",
  "User-Agent": "MagicMobile/0.1 card-cache-sync"
};

const bulkResponse = await fetch(bulkEndpoint, { headers });
if (!bulkResponse.ok) {
  throw new Error(`Failed to read Scryfall bulk metadata: ${bulkResponse.status}`);
}

const bulkMetadata = await bulkResponse.json();
if (!bulkMetadata.download_uri) {
  throw new Error("Scryfall bulk metadata did not include download_uri");
}

console.log(`Downloading Scryfall default cards from ${bulkMetadata.download_uri}`);
const cardsResponse = await fetch(bulkMetadata.download_uri, { headers });
if (!cardsResponse.ok) {
  throw new Error(`Failed to download Scryfall default cards: ${cardsResponse.status}`);
}

const cards = await cardsResponse.json();
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
    artCropUrl: imageUris?.art_crop,
    artist: card.artist,
    copyright: card.copyright ?? "™ & © Wizards of the Coast"
  };
});

const imageCount = visuals.filter((card) => card.imageUrl).length;
const metadata = {
  provider: "scryfall",
  status: "ready",
  bulkVersion: bulkMetadata.updated_at ?? bulkMetadata.id,
  cardCount: visuals.length,
  imageCount,
  missingImageCount: visuals.length - imageCount,
  updatedAt: new Date().toISOString()
};

await mkdir(cacheDir, { recursive: true });
await writeFile(join(cacheDir, "card-visuals.json"), JSON.stringify(visuals), "utf8");
await writeFile(join(cacheDir, "metadata.json"), JSON.stringify(metadata, null, 2), "utf8");

console.log(`Cached ${metadata.cardCount} Scryfall cards (${metadata.imageCount} images) in ${cacheDir}`);
