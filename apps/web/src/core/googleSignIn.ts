/**
 * Google sign-in in the browser, without a popup or a Google SDK. The page is cross-origin isolated (COOP same-origin),
 * so a popup could never report back: the page itself goes to Google (OpenID Connect implicit flow, response_type
 * id_token) and Google sends it back with `#id_token=…&state=…`. The ID token then goes to Supabase with the raw nonce
 * (SupabaseLite.signInWithIdToken), as on iOS (AccountSignInCard.swift) and Android. docs/social/PROFILES.md.
 *
 * The redirect URI must be listed on the Web client in Google Cloud (project magicmobile, 917754280625).
 */
import type { SessionStore } from "./supabaseLite";

/** Google Cloud project "magicmobile"'s Web client (Android's server client ID). Client IDs are public. */
export const GOOGLE_WEB_CLIENT_ID = "917754280625-metef3mern8f53ro92guud6n1qgmu3fp.apps.googleusercontent.com";
export const GOOGLE_AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";
/** Where the pending sign-in's nonce and state wait across the redirect (sessionStorage in the app). */
export const GOOGLE_PENDING_KEY = "mm.web.googleSignIn";

const randomBytes = (count: number, random?: (bytes: Uint8Array) => void) => {
  const bytes = new Uint8Array(count);
  (random ?? ((b) => globalThis.crypto.getRandomValues(b)))(bytes);
  return bytes;
};

const base64 = (bytes: Uint8Array) => {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
};

/** SignInNonce.make: 32 random bytes in base64, letters and digits only. */
export function makeNonce(random?: (bytes: Uint8Array) => void): string {
  return base64(randomBytes(32, random)).replace(/[^A-Za-z0-9]/g, "");
}

/** Lowercase hex SHA-256 of the text's UTF-8 (SignInNonce.hashed). */
export async function sha256Hex(text: string): Promise<string> {
  const digest = await globalThis.crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export interface GoogleAuthRequest {
  clientId: string;
  redirectUri: string;
  /** sha256Hex of the raw nonce: Google puts it in the token, Supabase checks the raw value against it. */
  nonceHashed: string;
  /** Echoed back in the redirect, to tie it to this browser's request. */
  state: string;
}

/** Google's OpenID Connect implicit-flow URL for an ID token. */
export function buildGoogleAuthURL(request: GoogleAuthRequest): string {
  const query = new URLSearchParams({
    client_id: request.clientId, redirect_uri: request.redirectUri, response_type: "id_token", scope: "openid email profile",
    nonce: request.nonceHashed, state: request.state, prompt: "select_account",
  });
  return `${GOOGLE_AUTH_ENDPOINT}?${query.toString()}`;
}

export type GoogleRedirect = { idToken: string; state: string } | { error: string };

/**
 * Reads Google's redirect fragment (`location.hash`). A refused consent ("access_denied") or a reply without a token is
 * "sign_in_cancelled", like a closed sheet on iOS; any other Google error comes back as its code.
 */
export function parseGoogleRedirect(locationHash: string): GoogleRedirect {
  const params = new URLSearchParams(locationHash.replace(/^#/, ""));
  const error = params.get("error");
  if (error !== null) return { error: error === "access_denied" ? "sign_in_cancelled" : error };
  const idToken = params.get("id_token");
  if (idToken === null || idToken.length === 0) return { error: "sign_in_cancelled" };
  return { idToken, state: params.get("state") ?? "" };
}

/** Whether a fragment is Google's reply (so the page can finish signing in instead of routing on it). */
export const isGoogleRedirect = (locationHash: string) => /[#&](id_token|error)=/.test(locationHash.startsWith("#") ? locationHash : `#${locationHash}`);

/**
 * Starts a sign-in: keeps a fresh nonce and state in `store` for the page Google returns to, and returns the URL to go
 * to (`location.assign(url)`).
 */
export async function beginGoogleSignIn(store: SessionStore, redirectUri: string, options: { clientId?: string; random?: (bytes: Uint8Array) => void } = {}): Promise<string> {
  const nonce = makeNonce(options.random), state = makeNonce(options.random);
  store.set(GOOGLE_PENDING_KEY, JSON.stringify({ nonce, state }));
  return buildGoogleAuthURL({ clientId: options.clientId ?? GOOGLE_WEB_CLIENT_ID, redirectUri, nonceHashed: await sha256Hex(nonce), state });
}

/**
 * Finishes a sign-in from Google's redirect: the ID token and the raw nonce to hand to PlayerAccount.signIn, or an error
 * code for PlayerAccountRules.message. A reply whose state isn't this browser's pending one is refused ("error").
 */
export function finishGoogleSignIn(store: SessionStore, locationHash: string): { idToken: string; nonce: string } | { error: string } {
  const raw = store.get(GOOGLE_PENDING_KEY);
  store.remove(GOOGLE_PENDING_KEY);
  const reply = parseGoogleRedirect(locationHash);
  if ("error" in reply) return reply;
  let pending: unknown;
  try { pending = JSON.parse(raw ?? ""); } catch { pending = undefined; }
  const nonce = typeof pending === "object" && pending !== null ? (pending as Record<string, unknown>).nonce : undefined;
  const state = typeof pending === "object" && pending !== null ? (pending as Record<string, unknown>).state : undefined;
  if (typeof nonce !== "string" || typeof state !== "string" || state !== reply.state) return { error: "error" };
  return { idToken: reply.idToken, nonce };
}
