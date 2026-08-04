import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "./config";

export interface SupabaseRequestContext {
  client: SupabaseClient | null;
  userId: string;
  mode: "supabase" | "development";
}

export class DeckAuthError extends Error {
  constructor(message: string, readonly status: 401 | 503) {
    super(message);
    this.name = "DeckAuthError";
  }
}

export const createSupabaseRequestContext = async (request: Request): Promise<SupabaseRequestContext> => {
  const config = getSupabasePublicConfig();
  if (!config) {
    if (process.env.NODE_ENV === "production") {
      throw new DeckAuthError("Cloud decks are not configured.", 503);
    }
    return { client: null, userId: "local-development-user", mode: "development" };
  }

  const authorization = request.headers.get("authorization");
  let bearerToken: string | undefined;
  let client: SupabaseClient;
  if (authorization?.startsWith("Bearer ")) {
    const token = authorization.slice("Bearer ".length).trim();
    if (!token) throw new DeckAuthError("Authentication is required.", 401);
    bearerToken = token;
    client = createClient(config.url, config.publishableKey, {
      auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } }
    });
  } else {
    const cookieStore = await cookies();
    client = createServerClient(config.url, config.publishableKey, {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (cookiesToSet) => {
          for (const cookie of cookiesToSet) {
            cookieStore.set(cookie.name, cookie.value, cookie.options);
          }
        }
      }
    });
  }

  const claimsResult = bearerToken
    ? await client.auth.getClaims(bearerToken)
    : await client.auth.getClaims();
  const { data, error } = claimsResult;
  const subject = typeof data?.claims?.sub === "string" ? data.claims.sub : "";
  if (error || !subject) throw new DeckAuthError("Authentication is required.", 401);
  return { client, userId: subject, mode: "supabase" };
};
