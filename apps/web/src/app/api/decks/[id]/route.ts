import { NextResponse } from "next/server";
import { createDeckRepository } from "@/lib/decks/repository";
import { deckErrorResponse, readJsonBody } from "@/lib/decks/http";
import { parseUpdateDeckInput } from "@/lib/decks/validation";
import { createSupabaseRequestContext } from "@/lib/supabase/request";

export const dynamic = "force-dynamic";

interface DeckRouteContext {
  params: Promise<{ id: string }>;
}

export async function GET(request: Request, context: DeckRouteContext) {
  try {
    const { id } = await context.params;
    const repository = createDeckRepository(await createSupabaseRequestContext(request));
    return NextResponse.json({ deck: await repository.get(id) });
  } catch (error) {
    return deckErrorResponse(error);
  }
}

export async function PUT(request: Request, context: DeckRouteContext) {
  try {
    const { id } = await context.params;
    const repository = createDeckRepository(await createSupabaseRequestContext(request));
    const deck = await repository.update(id, parseUpdateDeckInput(await readJsonBody(request)));
    return NextResponse.json({ deck });
  } catch (error) {
    return deckErrorResponse(error);
  }
}

export async function DELETE(request: Request, context: DeckRouteContext) {
  try {
    const { id } = await context.params;
    const repository = createDeckRepository(await createSupabaseRequestContext(request));
    await repository.delete(id);
    return new NextResponse(null, { status: 204 });
  } catch (error) {
    return deckErrorResponse(error);
  }
}
