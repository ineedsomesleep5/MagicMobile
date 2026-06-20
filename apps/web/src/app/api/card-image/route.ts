import { NextResponse } from "next/server";

const allowedHosts = new Set(["cards.scryfall.io", "img.scryfall.com"]);

export async function GET(request: Request) {
  const url = new URL(request.url).searchParams.get("url");
  if (!url) {
    return NextResponse.json({ error: "Missing card image URL." }, { status: 400 });
  }

  let imageUrl: URL;
  try {
    imageUrl = new URL(url);
  } catch {
    return NextResponse.json({ error: "Invalid card image URL." }, { status: 400 });
  }

  if (imageUrl.protocol !== "https:" || !allowedHosts.has(imageUrl.hostname)) {
    return NextResponse.json({ error: "Unsupported card image host." }, { status: 400 });
  }

  const response = await fetch(imageUrl, {
    headers: {
      Accept: "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
      "User-Agent": "MagicMobile/0.1 development"
    },
    next: { revalidate: 60 * 60 * 24 * 7 }
  });

  if (!response.ok || !response.body) {
    return NextResponse.json({ error: "Card image unavailable." }, { status: 502 });
  }

  return new Response(response.body, {
    headers: {
      "Cache-Control": "public, max-age=604800, stale-while-revalidate=604800",
      "Content-Type": response.headers.get("content-type") ?? "image/jpeg"
    }
  });
}
