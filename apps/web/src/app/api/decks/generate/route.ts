import { generateBracketThreeCommanderDeck } from "@magicmobile/deck";

interface GenerateDeckRequest {
  bracket?: number;
  seed?: string;
  playerId?: string;
}

export async function POST(request: Request): Promise<Response> {
  const body = (await request.json()) as GenerateDeckRequest;
  if (body.bracket !== undefined && body.bracket !== 3) {
    return Response.json({ error: "Only bracket 3 Commander deck generation is available." }, { status: 400 });
  }

  return Response.json(
    generateBracketThreeCommanderDeck({
      ...(body.seed ? { seed: body.seed } : {}),
      ...(body.playerId ? { playerId: body.playerId } : {})
    })
  );
}
