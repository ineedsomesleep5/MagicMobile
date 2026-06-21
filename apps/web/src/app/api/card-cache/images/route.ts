import { readCachedCardImageManifest, readScryfallCacheMetadata } from "@magicmobile/card-data";

export async function GET(): Promise<Response> {
  const [metadata, images] = await Promise.all([
    readScryfallCacheMetadata(),
    readCachedCardImageManifest()
  ]);

  if (metadata.status !== "ready" && images.length === 0) {
    return Response.json(
      {
        error: "Card cache is empty. Run POST /api/card-cache before downloading images.",
        metadata,
        images
      },
      { status: 409 }
    );
  }

  return Response.json({ metadata, images });
}
