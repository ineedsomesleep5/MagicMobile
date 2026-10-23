/** Google sign-in in the browser: the auth URL, the redirect, nonces (SignInNonce on iOS) and the pending request. */
import { describe, expect, it } from "vitest";
import {
  beginGoogleSignIn, buildGoogleAuthURL, finishGoogleSignIn, GOOGLE_AUTH_ENDPOINT, GOOGLE_PENDING_KEY, GOOGLE_WEB_CLIENT_ID, isGoogleRedirect,
  makeNonce, parseGoogleRedirect, sha256Hex,
} from "../src/core/googleSignIn";

const memoryStore = () => {
  const map = new Map<string, string>();
  return { map, get: (k: string) => map.get(k) ?? null, set: (k: string, v: string) => { map.set(k, v); }, remove: (k: string) => { map.delete(k); } };
};

describe("Google sign-in", () => {
  it("uses the project's Web client", () => {
    expect(GOOGLE_WEB_CLIENT_ID).toBe("917754280625-metef3mern8f53ro92guud6n1qgmu3fp.apps.googleusercontent.com");
  });

  it("hashes like SignInNonce.hashed: lowercase hex SHA-256 of the UTF-8", async () => {
    expect(await sha256Hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    expect(await sha256Hex("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    expect(await sha256Hex("é")).toBe("4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c");
  });

  it("makes nonces like SignInNonce.make: 32 random bytes as base64, letters and digits only", () => {
    expect(makeNonce((bytes) => bytes.fill(0))).toBe("A".repeat(43));
    // 0xfb 0xff 0xbf encodes as "+/+/" in base64: the symbols go.
    expect(makeNonce((bytes) => bytes.forEach((_, i) => { bytes[i] = [0xfb, 0xff, 0xbf][i % 3]; }))).toMatch(/^[A-Za-z0-9]*$/);
    const a = makeNonce(), b = makeNonce();
    expect(a).toMatch(/^[A-Za-z0-9]{30,44}$/);
    expect(a).not.toBe(b);
  });

  it("builds the implicit-flow URL for an ID token", () => {
    const url = new URL(buildGoogleAuthURL({ clientId: GOOGLE_WEB_CLIENT_ID, redirectUri: "https://magicmobile-web.vercel.app/", nonceHashed: "abc123", state: "s1" }));
    expect(`${url.origin}${url.pathname}`).toBe(GOOGLE_AUTH_ENDPOINT);
    expect(GOOGLE_AUTH_ENDPOINT).toBe("https://accounts.google.com/o/oauth2/v2/auth");
    expect(Object.fromEntries(url.searchParams)).toEqual({
      client_id: GOOGLE_WEB_CLIENT_ID, redirect_uri: "https://magicmobile-web.vercel.app/", response_type: "id_token",
      scope: "openid email profile", nonce: "abc123", state: "s1", prompt: "select_account",
    });
  });

  it("parses Google's redirect", () => {
    expect(parseGoogleRedirect("#state=s1&id_token=eyJ.a.b&authuser=0&prompt=consent")).toEqual({ idToken: "eyJ.a.b", state: "s1" });
    expect(parseGoogleRedirect("id_token=t")).toEqual({ idToken: "t", state: "" });
    expect(parseGoogleRedirect("#error=access_denied&state=s1")).toEqual({ error: "sign_in_cancelled" });
    expect(parseGoogleRedirect("#error=invalid_request&error_subtype=x")).toEqual({ error: "invalid_request" });
    expect(parseGoogleRedirect("")).toEqual({ error: "sign_in_cancelled" });
    expect(parseGoogleRedirect("#id_token=")).toEqual({ error: "sign_in_cancelled" });
    expect(isGoogleRedirect("#state=s&id_token=t")).toBe(true);
    expect(isGoogleRedirect("#error=access_denied")).toBe(true);
    expect(isGoogleRedirect("#/profile")).toBe(false);
  });

  it("keeps the raw nonce across the redirect and checks the state", async () => {
    const store = memoryStore();
    const url = new URL(await beginGoogleSignIn(store, "https://example.test/"));
    const pending = JSON.parse(store.map.get(GOOGLE_PENDING_KEY)!);
    expect(url.searchParams.get("nonce")).toBe(await sha256Hex(pending.nonce));
    expect(url.searchParams.get("state")).toBe(pending.state);
    expect(url.searchParams.get("client_id")).toBe(GOOGLE_WEB_CLIENT_ID);

    expect(finishGoogleSignIn(store, `#id_token=tok&state=${pending.state}`)).toEqual({ idToken: "tok", nonce: pending.nonce });
    expect(store.map.has(GOOGLE_PENDING_KEY)).toBe(false);
    // Used once: the same reply again, or a reply for another request, is refused.
    expect(finishGoogleSignIn(store, `#id_token=tok&state=${pending.state}`)).toEqual({ error: "error" });
    await beginGoogleSignIn(store, "https://example.test/");
    expect(finishGoogleSignIn(store, "#id_token=tok&state=forged")).toEqual({ error: "error" });
    await beginGoogleSignIn(store, "https://example.test/");
    expect(finishGoogleSignIn(store, "#error=access_denied")).toEqual({ error: "sign_in_cancelled" });
  });
});
