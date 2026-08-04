import { createHmac } from "node:crypto";
import type { GameSnapshot } from "@magicmobile/shared";
import { createSupabaseRequestContext, type SupabaseRequestContext } from "./supabase/request";

export class GameSessionError extends Error {
  constructor(message: string, readonly status: 401 | 403 | 503) {
    super(message);
    this.name = "GameSessionError";
  }
}

export async function requireGameSession(request: Request, gameId: string): Promise<SupabaseRequestContext> {
  const context = await createSupabaseRequestContext(request);
  if (context.mode === "development") return context;
  const { data, error } = await context.client!
    .from("game_sessions")
    .select("id")
    .eq("owner_id", context.userId)
    .eq("game_id", gameId)
    .maybeSingle();
  if (error) throw new GameSessionError("Game session authorization is unavailable.", 503);
  if (!data) throw new GameSessionError("This game does not belong to your account.", 403);
  return context;
}

export async function saveGameSession(context: SupabaseRequestContext, snapshot: GameSnapshot): Promise<void> {
  if (context.mode === "development") return;
  const { error } = await context.client!.from("game_sessions").insert({
    owner_id: context.userId,
    game_id: snapshot.id,
    status: "active",
    revision: 1,
    snapshot
  });
  if (error) throw new GameSessionError("The game started, but its recovery session could not be saved.", 503);
}

export function createSocketToken(context: SupabaseRequestContext, gameId: string): string | undefined {
  const secret = process.env.XMAGE_SOCKET_TOKEN_SECRET?.trim();
  if (!secret) {
    if (process.env.NODE_ENV === "production") throw new GameSessionError("Live game authorization is not configured.", 503);
    return undefined;
  }
  const payload = Buffer.from(JSON.stringify({
    sub: context.userId,
    gameId,
    exp: Math.floor(Date.now() / 1000) + 5 * 60
  })).toString("base64url");
  const signature = createHmac("sha256", secret).update(payload).digest("base64url");
  return `${payload}.${signature}`;
}

export function gameSessionErrorResponse(error: unknown): Response | undefined {
  if (error && typeof error === "object" && "status" in error && typeof error.status === "number") {
    return Response.json({ error: error instanceof Error ? error.message : "Game session unavailable." }, { status: error.status });
  }
  return undefined;
}
