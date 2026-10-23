/**
 * Port of SupabaseLite (apps/ios/MagicMobile/PlayerAccount.swift; Android PlayerAccount.kt): the few Supabase Auth and
 * PostgREST calls the profile needs. The publishable key is public by design; every call runs as the signed-in player.
 *
 * The session is kept through an injected string store (the app passes localStorage under `mm.web.session`) as
 * `{"accessToken": "…", "refreshToken": "…", "expiresAt": <ms since 1970>}`. The first call without a session makes an
 * anonymous player (POST auth/v1/signup with `{"data": {}}`); later calls refresh it a minute before it expires. Only one
 * sign-up or refresh runs at a time: two calls at first load must not make two players.
 *
 * Server contract: docs/social/PROFILES.md and supabase/migrations/*.sql (the mm_* functions).
 */
import type { J } from "./json";

/** Where the session lives: localStorage in the app, a Map-backed object in tests. */
export interface SessionStore {
  get(key: string): string | null | undefined;
  set(key: string, value: string): void;
  remove(key: string): void;
}

export interface SupabaseSession { accessToken: string; refreshToken: string; expiresAt: number }

export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export interface SupabaseLiteOptions {
  store: SessionStore;
  /** Defaults to the global fetch. */
  fetch?: FetchLike;
  /** Milliseconds since 1970; defaults to Date.now. */
  now?: () => number;
  /** Defaults to SupabaseLite.sessionKey. */
  key?: string;
  /**
   * The same server through the page's own origin (the site rewrites `/sb/*` to it), for a network that blocks
   * supabase.co (a school or work filter). Used only after the direct address fails, and then kept for this browser.
   */
  fallbackBaseURL?: string;
}

/** A server error's code ("username_taken"), "offline", or "error". */
export class SupabaseFailure extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "SupabaseFailure";
  }
}

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);

const parseJSON = (text: string): unknown => {
  try { return JSON.parse(text); } catch { return undefined; }
};

export class SupabaseLite {
  static readonly baseURL = "https://pbspondpyvrjcnvwhtim.supabase.co";
  static readonly publishableKey = "sb_publishable_V_i-mPM26P8fNLlKAYu2xg_4p-lPHYu";
  static readonly sessionKey = "mm.web.session";
  /** A token this close to expiring is refreshed first. */
  static readonly refreshMargin = 60_000;

  private session?: SupabaseSession;
  private tokenFetch?: Promise<string>;
  private readonly store: SessionStore;
  private readonly fetcher: FetchLike;
  private readonly now: () => number;
  private readonly key: string;
  private readonly fallbackBaseURL?: string;
  /** Where requests go: the server, or the page's own origin once the server proved unreachable from here. */
  private base: string;
  static readonly routeKey = "mm.web.supabaseRoute";

  constructor(options: SupabaseLiteOptions) {
    this.store = options.store;
    this.fetcher = options.fetch ?? ((url, init) => globalThis.fetch(url, init));
    this.now = options.now ?? Date.now;
    this.key = options.key ?? SupabaseLite.sessionKey;
    this.fallbackBaseURL = options.fallbackBaseURL;
    let proxied = false;
    try { proxied = this.fallbackBaseURL !== undefined && this.store.get(SupabaseLite.routeKey) === "proxy"; } catch { /* storage blocked */ }
    this.base = proxied ? this.fallbackBaseURL! : SupabaseLite.baseURL;
    this.session = this.loadSession();
  }

  /** A server error's code ("username_taken"), "offline", or "error". */
  static code(error: unknown): string {
    return error instanceof SupabaseFailure ? error.code : "error";
  }

  /** PostgREST's {"message": "username_taken", ...} or Auth's {"error_code": ...}. */
  static errorCode(body: string): string | undefined {
    const parsed = parseJSON(body);
    if (!isRecord(parsed)) return undefined;
    // A function the server doesn't have yet (PostgREST PGRST202, or Postgres 42883): the feature isn't there.
    if (typeof parsed.code === "string" && ["PGRST202", "42883"].includes(parsed.code)) return "feature_unavailable";
    if (typeof parsed.error_code === "string") return parsed.error_code;
    return typeof parsed.message === "string" ? parsed.message : undefined;
  }

  /** Whether a session is kept (anonymous or signed in). */
  get hasSession(): boolean { return this.session !== undefined; }

  /** Calls rest/v1/rpc/<fn> as the player. Returns the parsed reply (null for an empty or non-JSON one). */
  async rpc(fn: string, params: Record<string, J> = {}): Promise<J> {
    const token = await this.accessToken();
    const { status, text } = await this.request(`rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: SupabaseLite.publishableKey, Authorization: `Bearer ${token}` },
      body: JSON.stringify(params),
    }, 15_000);
    if (status === 401 && this.session) this.session = { ...this.session, expiresAt: Number.NEGATIVE_INFINITY };
    if (status < 200 || status >= 300) {
      throw new SupabaseFailure(SupabaseLite.errorCode(text) ?? (status === 401 ? "not_signed_in" : status === 404 ? "feature_unavailable" : "error"));
    }
    const parsed = text.length === 0 ? null : parseJSON(text);
    return parsed === undefined ? null : (parsed as J);
  }

  /**
   * Google or Apple sign-in with an OpenID Connect ID token. With `link`, the identity joins the current (anonymous)
   * account so its profile, friends and rank stay; without it, this browser switches to the account that already has
   * that identity. `nonce` is the raw value whose SHA-256 the provider put in the token.
   */
  async signInWithIdToken(idToken: string, provider: string, nonce: string | undefined, link: boolean): Promise<void> {
    const headers: Record<string, string> = { "Content-Type": "application/json", apikey: SupabaseLite.publishableKey };
    const body: Record<string, J> = { provider, id_token: idToken };
    if (nonce !== undefined) body.nonce = nonce;
    if (link) {
      body.link_identity = true;
      headers.Authorization = `Bearer ${await this.accessToken()}`;
    }
    const { status, text } = await this.request("auth/v1/token?grant_type=id_token", { method: "POST", headers, body: JSON.stringify(body) }, 20_000);
    const json = parseJSON(text);
    if (status < 200 || status >= 300 || !isRecord(json) || typeof json.access_token !== "string" || typeof json.refresh_token !== "string") {
      throw new SupabaseFailure(SupabaseLite.errorCode(text) ?? "error");
    }
    this.keep(json.access_token, json.refresh_token, json.expires_in);
  }

  /** The account's identities from auth/v1/user (LinkedIdentity.parse reads them). */
  async user(): Promise<Record<string, unknown>> {
    const token = await this.accessToken();
    const { status, text } = await this.request("auth/v1/user", {
      method: "GET", headers: { apikey: SupabaseLite.publishableKey, Authorization: `Bearer ${token}` },
    }, 15_000);
    const json = parseJSON(text);
    if (status !== 200 || !isRecord(json)) throw new SupabaseFailure(SupabaseLite.errorCode(text) ?? "error");
    return json;
  }

  /** The sign-in methods on this account beyond its anonymous start ("google", "apple"), with their email. */
  async linkedIdentities(): Promise<LinkedIdentity[]> {
    return LinkedIdentity.parse(await this.user());
  }

  /** The signed-in user's id, from the access token's `sub` (deck sync keeps its record per profile). */
  async userID(): Promise<string | undefined> {
    const token = await this.accessToken();
    try {
      const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      const sub = (JSON.parse(atob(payload.padEnd(Math.ceil(payload.length / 4) * 4, "="))) as { sub?: unknown }).sub;
      return typeof sub === "string" ? sub : undefined;
    } catch { return undefined; }
  }

  forgetSession(): void {
    this.session = undefined;
    try { this.store.remove(this.key); } catch { /* storage blocked */ }
  }

  /** One sign-up or refresh at a time: two calls at first load must not make two players. */
  async accessToken(): Promise<string> {
    const current = this.session;
    if (current && current.expiresAt > this.now() + SupabaseLite.refreshMargin) return current.accessToken;
    if (!this.tokenFetch) {
      const running = this.fetchToken();
      this.tokenFetch = running;
      const clear = () => { if (this.tokenFetch === running) this.tokenFetch = undefined; };
      running.then(clear, clear);
    }
    return this.tokenFetch;
  }

  private async fetchToken(): Promise<string> {
    const refresh = this.session?.refreshToken;
    const path = refresh === undefined ? "auth/v1/signup" : "auth/v1/token?grant_type=refresh_token";
    // No email or password: Supabase makes an anonymous user.
    const body = refresh === undefined ? { data: {} } : { refresh_token: refresh };
    const { status, text } = await this.request(path, {
      method: "POST", headers: { "Content-Type": "application/json", apikey: SupabaseLite.publishableKey }, body: JSON.stringify(body),
    }, 15_000);
    const json = parseJSON(text);
    if (status < 200 || status >= 300 || !isRecord(json) || typeof json.access_token !== "string" || typeof json.refresh_token !== "string") {
      const code = SupabaseLite.errorCode(text) ?? "error";
      // A refresh token that no longer works (deleted account): start over as a new player.
      if (refresh !== undefined && status >= 400 && status < 500) this.forgetSession();
      throw new SupabaseFailure(code);
    }
    return this.keep(json.access_token, json.refresh_token, json.expires_in);
  }

  private keep(accessToken: string, refreshToken: string, expiresIn: unknown): string {
    const seconds = typeof expiresIn === "number" && Number.isFinite(expiresIn) ? expiresIn : 3600;
    this.session = { accessToken, refreshToken, expiresAt: this.now() + seconds * 1000 };
    try { this.store.set(this.key, JSON.stringify(this.session)); } catch { /* storage blocked: the session lasts this page */ }
    return accessToken;
  }

  /** A failed connection or a timeout is "offline", like URLError on iOS. */
  private async request(path: string, init: RequestInit, timeout: number): Promise<{ status: number; text: string }> {
    try {
      return await this.send(this.base, path, init, timeout);
    } catch (error) {
      // The server's own address unreachable (a filtered network): try the page's origin, and keep it if it answers.
      if (this.fallbackBaseURL === undefined || this.base === this.fallbackBaseURL) throw error;
      const answer = await this.send(this.fallbackBaseURL, path, init, timeout);
      this.base = this.fallbackBaseURL;
      try { this.store.set(SupabaseLite.routeKey, "proxy"); } catch { /* storage blocked */ }
      return answer;
    }
  }

  private async send(base: string, path: string, init: RequestInit, timeout: number): Promise<{ status: number; text: string }> {
    const controller = typeof AbortController === "function" ? new AbortController() : undefined;
    const timer = controller ? setTimeout(() => controller.abort(), timeout) : undefined;
    try {
      const response = await this.fetcher(`${base}/${path}`, { ...init, ...(controller ? { signal: controller.signal } : {}) });
      return { status: response.status, text: await response.text() };
    } catch {
      throw new SupabaseFailure("offline");
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  }

  private loadSession(): SupabaseSession | undefined {
    try {
      const parsed = parseJSON(this.store.get(this.key) ?? "");
      if (isRecord(parsed) && typeof parsed.accessToken === "string" && typeof parsed.refreshToken === "string" && typeof parsed.expiresAt === "number") {
        return { accessToken: parsed.accessToken, refreshToken: parsed.refreshToken, expiresAt: parsed.expiresAt };
      }
    } catch { /* storage blocked */ }
    return undefined;
  }
}

/** A sign-in method on the account (Google, Apple), from Auth's user record. */
export interface LinkedIdentity { provider: string; email?: string }

export const LinkedIdentity = {
  title: (identity: LinkedIdentity) =>
    identity.provider === "apple" ? "Apple" : identity.provider === "google" ? "Google"
      : identity.provider.split(/(\s+)/).map((word) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()).join(""),

  /** Auth's `identities`, without the anonymous one. An Apple email may be a private relay address. */
  parse(user: unknown): LinkedIdentity[] {
    const identities = isRecord(user) && Array.isArray(user.identities) ? user.identities : [];
    return identities.flatMap((identity): LinkedIdentity[] => {
      if (!isRecord(identity) || typeof identity.provider !== "string" || identity.provider === "anonymous") return [];
      const data = isRecord(identity.identity_data) ? identity.identity_data : undefined;
      const email = typeof data?.email === "string" ? data.email : typeof identity.email === "string" ? identity.email : undefined;
      return [{ provider: identity.provider, ...(email !== undefined ? { email } : {}) }];
    });
  },
} as const;
