/** SupabaseLite against a fake fetch (never the network): sessions, refresh, one token fetch at a time, sign-in, errors. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { LinkedIdentity, type SessionStore, SupabaseFailure, SupabaseLite } from "../src/core/supabaseLite";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const chat: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/chat-cases.json"), "utf8"));

const BASE = SupabaseLite.baseURL;
const NOW = 1_791_000_000_000;

function memoryStore(initial: Record<string, string> = {}): SessionStore & { map: Map<string, string> } {
  const map = new Map(Object.entries(initial));
  return { map, get: (k) => map.get(k) ?? null, set: (k, v) => { map.set(k, v); }, remove: (k) => { map.delete(k); } };
}

interface Call { url: string; method: string; headers: Record<string, string>; body?: unknown }
type Reply = { status: number; body?: unknown } | Promise<{ status: number; body?: unknown }>;

function fakeFetch(handler: (call: Call) => Reply) {
  const calls: Call[] = [];
  const fetch = async (url: string, init: RequestInit): Promise<Response> => {
    const call: Call = {
      url, method: init.method ?? "GET", headers: { ...(init.headers as Record<string, string>) },
      ...(typeof init.body === "string" ? { body: JSON.parse(init.body) } : {}),
    };
    calls.push(call);
    const reply = await handler(call);
    const text = reply.body === undefined ? "" : typeof reply.body === "string" ? reply.body : JSON.stringify(reply.body);
    return new Response(reply.status === 204 ? null : text, { status: reply.status });
  };
  return { calls, fetch };
}

const tokens = (access: string, refresh = `r-${access}`, expiresIn = 3600) => ({ status: 200, body: { access_token: access, refresh_token: refresh, expires_in: expiresIn } });
const session = (expiresAt: number, access = "old") => JSON.stringify({ accessToken: access, refreshToken: "r-old", expiresAt });

describe("SupabaseLite", () => {
  it("signs up anonymously on first use, keeps the session and calls the function with the bearer", async () => {
    const store = memoryStore();
    const { calls, fetch } = fakeFetch((call) => (call.url.endsWith("/auth/v1/signup") ? tokens("A1") : { status: 200, body: { username: "Caleb_22" } }));
    const api = new SupabaseLite({ store, fetch, now: () => NOW });
    expect(await api.rpc("mm_profile")).toEqual({ username: "Caleb_22" });
    expect(calls.map((c) => `${c.method} ${c.url}`)).toEqual([`POST ${BASE}/auth/v1/signup`, `POST ${BASE}/rest/v1/rpc/mm_profile`]);
    expect(calls[0].body).toEqual({ data: {} });
    expect(calls[0].headers.apikey).toBe(SupabaseLite.publishableKey);
    expect(calls[0].headers.Authorization).toBeUndefined();
    expect(calls[1].headers).toMatchObject({ apikey: SupabaseLite.publishableKey, Authorization: "Bearer A1", "Content-Type": "application/json" });
    expect(calls[1].body).toEqual({});
    expect(JSON.parse(store.map.get("mm.web.session")!)).toEqual({ accessToken: "A1", refreshToken: "r-A1", expiresAt: NOW + 3_600_000 });

    // The next call (and a new client on the same store) reuses the session.
    await api.rpc("mm_friends");
    await new SupabaseLite({ store, fetch, now: () => NOW }).rpc("mm_blocked", { p_x: 1 });
    expect(calls.filter((c) => c.url.includes("/auth/"))).toHaveLength(1);
    expect(calls[3].body).toEqual({ p_x: 1 });
  });

  it("uses the publishable key and project URL iOS uses", () => {
    expect(SupabaseLite.baseURL).toBe("https://pbspondpyvrjcnvwhtim.supabase.co");
    expect(SupabaseLite.publishableKey).toBe("sb_publishable_V_i-mPM26P8fNLlKAYu2xg_4p-lPHYu");
    expect(SupabaseLite.sessionKey).toBe("mm.web.session");
  });

  it("refreshes a token within a minute of expiring", async () => {
    const store = memoryStore({ "mm.web.session": session(NOW + 59_000) });
    const { calls, fetch } = fakeFetch((call) => (call.url.includes("grant_type=refresh_token") ? tokens("A2") : { status: 204 }));
    const api = new SupabaseLite({ store, fetch, now: () => NOW });
    expect(await api.rpc("mm_heartbeat")).toBeNull();
    expect(calls[0].url).toBe(`${BASE}/auth/v1/token?grant_type=refresh_token`);
    expect(calls[0].body).toEqual({ refresh_token: "r-old" });
    expect(calls[1].headers.Authorization).toBe("Bearer A2");

    // More than a minute left: no refresh.
    const fresh = fakeFetch(() => ({ status: 200, body: 3 }));
    expect(await new SupabaseLite({ store: memoryStore({ "mm.web.session": session(NOW + 61_000) }), fetch: fresh.fetch, now: () => NOW }).rpc("mm_message_unread")).toBe(3);
    expect(fresh.calls.map((c) => c.url)).toEqual([`${BASE}/rest/v1/rpc/mm_message_unread`]);
    expect(fresh.calls[0].headers.Authorization).toBe("Bearer old");
  });

  it("forgets the session when a refresh is refused (4xx), and keeps it on a server error", async () => {
    const store = memoryStore({ "mm.web.session": session(NOW - 1) });
    const refused = fakeFetch(() => ({ status: 400, body: { error_code: "refresh_token_not_found", msg: "Invalid Refresh Token" } }));
    const api = new SupabaseLite({ store, fetch: refused.fetch, now: () => NOW });
    await expect(api.rpc("mm_profile")).rejects.toMatchObject({ code: "refresh_token_not_found" });
    expect(store.map.has("mm.web.session")).toBe(false);
    expect(api.hasSession).toBe(false);

    const kept = memoryStore({ "mm.web.session": session(NOW - 1) });
    const down = fakeFetch(() => ({ status: 503, body: "upstream" }));
    await expect(new SupabaseLite({ store: kept, fetch: down.fetch, now: () => NOW }).rpc("mm_profile")).rejects.toMatchObject({ code: "error" });
    expect(kept.map.has("mm.web.session")).toBe(true);
  });

  it("shares one token fetch between concurrent callers", async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const { calls, fetch } = fakeFetch(async (call) => {
      if (call.url.endsWith("/auth/v1/signup")) { await gate; return tokens("A1"); }
      return { status: 200, body: JSON.stringify(call.url.split("/").pop()) };
    });
    const api = new SupabaseLite({ store: memoryStore(), fetch, now: () => NOW });
    const results = Promise.all([api.rpc("mm_profile"), api.rpc("mm_friends"), api.accessToken()]);
    await Promise.resolve();
    release();
    expect(await results).toEqual(["mm_profile", "mm_friends", "A1"]);
    expect(calls.filter((c) => c.url.endsWith("/auth/v1/signup"))).toHaveLength(1);
  });

  it("marks the token expired after a 401, so the next call refreshes", async () => {
    let first = true;
    const { calls, fetch } = fakeFetch((call) => {
      if (call.url.includes("refresh_token")) return tokens("A2");
      if (first) { first = false; return { status: 401, body: "" }; }
      return { status: 200, body: true };
    });
    const api = new SupabaseLite({ store: memoryStore({ "mm.web.session": session(NOW + 600_000) }), fetch, now: () => NOW });
    await expect(api.rpc("mm_profile")).rejects.toMatchObject({ code: "not_signed_in" });
    expect(await api.rpc("mm_profile")).toBe(true);
    expect(calls.map((c) => c.url.replace(BASE, ""))).toEqual(["/rest/v1/rpc/mm_profile", "/auth/v1/token?grant_type=refresh_token", "/rest/v1/rpc/mm_profile"]);
  });

  it("maps server errors to codes", async () => {
    expect(SupabaseLite.errorCode(`{"code":"P0001","details":null,"hint":null,"message":"no_username"}`)).toBe("no_username");
    expect(SupabaseLite.errorCode(`{"code":422,"error_code":"anonymous_provider_disabled","msg":"Anonymous sign-ins are disabled"}`)).toBe("anonymous_provider_disabled");
    expect(SupabaseLite.errorCode(`{"code":"PGRST202","message":"Could not find the function public.mm_x"}`)).toBe("feature_unavailable");
    expect(SupabaseLite.errorCode(`{"code":"42883","message":"function public.mm_x() does not exist"}`)).toBe("feature_unavailable");
    expect(SupabaseLite.errorCode(`{"error_code":"identity_already_exists","message":"Identity is already linked"}`)).toBe("identity_already_exists");
    expect(SupabaseLite.errorCode("<html>")).toBeUndefined();
    expect(SupabaseLite.errorCode("[]")).toBeUndefined();
    expect(SupabaseLite.code(new SupabaseFailure("self"))).toBe("self");
    expect(SupabaseLite.code(new Error("boom"))).toBe("error");

    const signedIn = () => memoryStore({ "mm.web.session": session(NOW + 600_000) });
    const notFound = fakeFetch(() => ({ status: 404, body: "" }));
    await expect(new SupabaseLite({ store: signedIn(), fetch: notFound.fetch, now: () => NOW }).rpc("mm_x")).rejects.toMatchObject({ code: "feature_unavailable" });
    const taken = fakeFetch(() => ({ status: 400, body: { code: "23505", message: "username_taken" } }));
    await expect(new SupabaseLite({ store: signedIn(), fetch: taken.fetch, now: () => NOW }).rpc("mm_claim_username")).rejects.toMatchObject({ code: "username_taken" });
    const offline = new SupabaseLite({ store: signedIn(), fetch: async () => { throw new TypeError("Failed to fetch"); }, now: () => NOW });
    await expect(offline.rpc("mm_profile")).rejects.toMatchObject({ code: "offline" });
    await expect(new SupabaseLite({ store: memoryStore(), fetch: async () => { throw new TypeError("Failed to fetch"); }, now: () => NOW }).accessToken())
      .rejects.toBeInstanceOf(SupabaseFailure);
  });

  it("signs in with an ID token, linking with the current bearer", async () => {
    const store = memoryStore({ "mm.web.session": session(NOW + 600_000) });
    const { calls, fetch } = fakeFetch(() => tokens("G1", "rG1", 1800));
    const api = new SupabaseLite({ store, fetch, now: () => NOW });
    await api.signInWithIdToken("id.jwt", "google", "raw-nonce", true);
    expect(calls[0].url).toBe(`${BASE}/auth/v1/token?grant_type=id_token`);
    expect(calls[0].method).toBe("POST");
    expect(calls[0].headers).toMatchObject({ apikey: SupabaseLite.publishableKey, Authorization: "Bearer old" });
    expect(calls[0].body).toEqual({ provider: "google", id_token: "id.jwt", nonce: "raw-nonce", link_identity: true });
    expect(JSON.parse(store.map.get("mm.web.session")!)).toEqual({ accessToken: "G1", refreshToken: "rG1", expiresAt: NOW + 1_800_000 });

    await api.signInWithIdToken("id.jwt", "apple", undefined, false);
    expect(calls[1].headers.Authorization).toBeUndefined();
    expect(calls[1].body).toEqual({ provider: "apple", id_token: "id.jwt" });

    const linked = fakeFetch(() => ({ status: 422, body: { code: 422, error_code: "identity_already_exists", msg: "Identity is already linked to another user" } }));
    await expect(new SupabaseLite({ store, fetch: linked.fetch, now: () => NOW }).signInWithIdToken("t", "google", "n", true))
      .rejects.toMatchObject({ code: "identity_already_exists" });
  });

  it("reads linked identities from auth/v1/user without the anonymous one", async () => {
    const { calls, fetch } = fakeFetch(() => ({ status: 200, body: chat.linkedIdentities.user }));
    const api = new SupabaseLite({ store: memoryStore({ "mm.web.session": session(NOW + 600_000) }), fetch, now: () => NOW });
    const identities = await api.linkedIdentities();
    expect(calls[0]).toMatchObject({ url: `${BASE}/auth/v1/user`, method: "GET", headers: { apikey: SupabaseLite.publishableKey, Authorization: "Bearer old" } });
    expect(identities.map((i) => i.provider)).toEqual(chat.linkedIdentities.expected.map((e: { provider: string }) => e.provider));
  });

  it("parses linked identities as chat-cases.json says", () => {
    const parsed = LinkedIdentity.parse(chat.linkedIdentities.user);
    const expected: { provider: string; title: string; email?: string }[] = chat.linkedIdentities.expected;
    expect(parsed.map((i) => i.provider)).toEqual(expected.map((e) => e.provider));
    expect(parsed.map(LinkedIdentity.title)).toEqual(expected.map((e) => e.title));
    expect(parsed.map((i) => i.email)).toEqual(expected.map((e) => e.email));
    expect(LinkedIdentity.parse({ identities: [{ provider: "anonymous" }] })).toEqual([]);
    expect(LinkedIdentity.title({ provider: "github" })).toBe("Github");
  });

  it("forgets the session", async () => {
    const store = memoryStore({ "mm.web.session": session(NOW + 600_000) });
    const { calls, fetch } = fakeFetch((call) => (call.url.endsWith("signup") ? tokens("A9") : { status: 200, body: null }));
    const api = new SupabaseLite({ store, fetch, now: () => NOW });
    api.forgetSession();
    expect(store.map.size).toBe(0);
    await api.rpc("mm_profile");
    expect(calls[0].url).toBe(`${BASE}/auth/v1/signup`);
  });
});
