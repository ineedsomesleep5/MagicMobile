import { NextResponse } from "next/server";
import sharp from "sharp";

const allowedHosts = new Set(["svgs.scryfall.io", "assets.scryfall.com"]);

export async function GET(request: Request) {
  const searchParams = new URL(request.url).searchParams;
  const url = searchParams.get("url");

  if (!url) {
    return NextResponse.json({ error: "Missing symbol image URL." }, { status: 400 });
  }

  let symbolUrl: URL;
  try {
    symbolUrl = new URL(url);
  } catch {
    return NextResponse.json({ error: "Invalid symbol image URL." }, { status: 400 });
  }

  if (symbolUrl.protocol !== "https:" || !allowedHosts.has(symbolUrl.hostname)) {
    return NextResponse.json({ error: "Unsupported symbol image host." }, { status: 400 });
  }

  const response = await fetch(symbolUrl, {
    headers: {
      Accept: "image/svg+xml,*/*",
      "User-Agent": "MagicMobile/0.1 symbol-cache"
    },
    next: { revalidate: 60 * 60 * 24 * 30 }
  });

  if (!response.ok) {
    return NextResponse.json({ error: "Symbol image unavailable." }, { status: 502 });
  }

  const svg = Buffer.from(await response.arrayBuffer());
  const png = await sharp(svg, { density: 192 })
    .resize(96, 96, { fit: "contain" })
    .png()
    .toBuffer();

  return new Response(new Uint8Array(png), {
    headers: {
      "Cache-Control": "public, max-age=2592000, stale-while-revalidate=2592000",
      "Content-Type": "image/png"
    }
  });
}
