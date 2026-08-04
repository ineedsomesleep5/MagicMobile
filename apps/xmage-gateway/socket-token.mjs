import { createHmac, timingSafeEqual } from "node:crypto";

export function signSocketToken(claims, secret) {
  if (!secret) throw new Error("XMAGE_SOCKET_TOKEN_SECRET is required to sign socket tokens.");
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const signature = createHmac("sha256", secret).update(payload).digest("base64url");
  return `${payload}.${signature}`;
}

export function verifySocketToken(token, gameId, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!secret) return { ok: true, claims: undefined };
  if (!token) return { ok: false, reason: "missing_token" };

  const [payload, signature, extra] = token.split(".");
  if (!payload || !signature || extra) return { ok: false, reason: "invalid_token" };

  const expected = createHmac("sha256", secret).update(payload).digest();
  let supplied;
  try {
    supplied = Buffer.from(signature, "base64url");
  } catch {
    return { ok: false, reason: "invalid_token" };
  }
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
    return { ok: false, reason: "invalid_signature" };
  }

  try {
    const claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    if (claims.gameId !== gameId) return { ok: false, reason: "wrong_game" };
    if (typeof claims.sub !== "string" || claims.sub.length === 0) return { ok: false, reason: "missing_subject" };
    if (!Number.isFinite(claims.exp) || claims.exp <= nowSeconds) return { ok: false, reason: "expired_token" };
    return { ok: true, claims };
  } catch {
    return { ok: false, reason: "invalid_payload" };
  }
}
