import { readCachedSymbolManifest, readScryfallCacheMetadata } from "@magicmobile/card-data";

export async function GET(request: Request): Promise<Response> {
  const [metadata, symbols] = await Promise.all([
    readScryfallCacheMetadata(),
    readCachedSymbolManifest()
  ]);

  if (metadata.status !== "ready" && symbols.length === 0) {
    return Response.json(
      {
        error: "Card cache is empty. Run POST /api/card-cache before downloading symbols.",
        metadata,
        symbols
      },
      { status: 409 }
    );
  }

  const origin = publicOrigin(request);
  return Response.json({
    metadata,
    symbols: symbols.map((symbol) => ({
      ...symbol,
      pngUrl: `${origin}/api/symbol-image?url=${encodeURIComponent(symbol.svgUrl)}`
    }))
  });
}

function publicOrigin(request: Request): string {
  const configuredOrigin = process.env.PUBLIC_APP_URL ?? process.env.NEXT_PUBLIC_APP_URL;
  if (configuredOrigin) {
    return configuredOrigin.replace(/\/$/, "");
  }

  const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
  if (host && !host.startsWith("0.0.0.0")) {
    const proto = request.headers.get("x-forwarded-proto") ?? "https";
    return `${proto}://${host}`;
  }

  return new URL(request.url).origin;
}
