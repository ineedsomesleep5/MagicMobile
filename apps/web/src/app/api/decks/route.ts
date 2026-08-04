import { NextResponse } from "next/server";
import { createDeckRepository } from "@/lib/decks/repository";
import { deckErrorResponse, readJsonBody } from "@/lib/decks/http";
import { parseCreateDeckInput } from "@/lib/decks/validation";
import { createSupabaseRequestContext } from "@/lib/supabase/request";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const repository = createDeckRepository(await createSupabaseRequestContext(request));
    return NextResponse.json({ decks: await repository.list() });
  } catch (error) {
    return deckErrorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    const repository = createDeckRepository(await createSupabaseRequestContext(request));
    const deck = await repository.create(parseCreateDeckInput(await readJsonBody(request)));
    return NextResponse.json({ deck }, { status: 201 });
  } catch (error) {
    return deckErrorResponse(error);
  }
}
