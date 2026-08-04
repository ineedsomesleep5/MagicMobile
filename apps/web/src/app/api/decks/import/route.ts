import { importDeck } from "@magicmobile/deck";
import { NextResponse } from "next/server";
import { deckErrorResponse, readDeckImportBody } from "@/lib/decks/http";
import { createDeckRepository } from "@/lib/decks/repository";
import { createSupabaseRequestContext } from "@/lib/supabase/request";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const repository = createDeckRepository(await createSupabaseRequestContext(request));
    const imported = await importDeck(await readDeckImportBody(request));
    const deck = await repository.create({
      name: imported.deck.name,
      entries: imported.deck.entries,
      ...(imported.deck.commander ? { commander: imported.deck.commander } : {}),
      rawList: imported.rawList,
      source: imported.source
    });
    return NextResponse.json({ deck }, { status: 201 });
  } catch (error) {
    return deckErrorResponse(error);
  }
}
