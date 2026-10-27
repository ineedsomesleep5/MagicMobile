// Voice chat at online tables (docs/VOICE_CHAT.md): an Agora token for one seat in one game's channel.
// The channel is "mm-" + the game's epoch, a UUID only that table's players receive, so knowing the channel is the table
// membership check. The App Certificate is the Supabase secret AGORA_APP_CERTIFICATE (Caleb sets it; it never ships in an
// app). Without it the apps hide voice chat (voice_not_configured).
import pkg from "npm:agora-token@2.0.5";

const { RtcTokenBuilder, RtcRole } = pkg;
const APP_ID = Deno.env.get("AGORA_APP_ID") ?? "94122c528828478f81b6321f902bf808";
const LIFETIME_SECONDS = 4 * 60 * 60;
const CHANNEL = /^mm-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ACCOUNT = /^player[1-9]$/;
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

/** The signed-in player's id from the JWT the gateway already verified (verify_jwt); anonymous profiles count. */
function playerID(request: Request): string | undefined {
  const token = request.headers.get("Authorization")?.replace(/^Bearer /, "");
  const payload = token?.split(".")[1];
  if (!payload) return undefined;
  try {
    const claims = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    return claims.role === "authenticated" && typeof claims.sub === "string" ? claims.sub : undefined;
  } catch {
    return undefined;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (request.method !== "POST") return reply(405, { code: "method_not_allowed" });
  if (!playerID(request)) return reply(401, { code: "not_signed_in" });
  let body: { channel?: unknown; account?: unknown };
  try { body = await request.json(); } catch { return reply(400, { code: "bad_request" }); }
  const channel = typeof body.channel === "string" ? body.channel : "";
  const account = typeof body.account === "string" ? body.account : "";
  if (!CHANNEL.test(channel) || !ACCOUNT.test(account)) return reply(400, { code: "bad_request" });
  const certificate = Deno.env.get("AGORA_APP_CERTIFICATE");
  if (!certificate) return reply(503, { code: "voice_not_configured" });
  const token = RtcTokenBuilder.buildTokenWithUserAccount(APP_ID, certificate, channel, account, RtcRole.PUBLISHER,
    LIFETIME_SECONDS, LIFETIME_SECONDS);
  return reply(200, { appId: APP_ID, token, expiresIn: LIFETIME_SECONDS });
});
