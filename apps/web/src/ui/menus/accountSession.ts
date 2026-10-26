/**
 * The page's one player account (iOS PlayerAccount.shared and its wiring in OnDeviceRootView): an anonymous Supabase
 * profile made on first use, kept in localStorage, joined to Google so the same profile opens on any phone or browser.
 * Finished games go up to the profile server, ranked AI results settle there with their game records, and the server's
 * standing replaces the browser's rank.
 *
 * Google sign-in leaves the page for Google and comes back with an ID token in the address's fragment: a cross-origin
 * isolated page (COOP same-origin) can't hear back from a pop-up. The token is then sent to Supabase as the phones send
 * theirs (`signIn`, with `link_identity` so this browser's profile is the one kept).
 */
import { useSyncExternalStore } from "react";
import { GameUploader, PlayerAccount, type PendingRankedResult, type RankedRecord, adoptStanding } from "../../core/account";
import { beginGoogleSignIn, finishGoogleSignIn, isGoogleRedirect } from "../../core/googleSignIn";
import { FriendChallengeCoordinator, RankedMatchmaker, SupabaseFriendChallenges, SupabaseRankedQueue } from "../../core/matchmaking";
import type { PlayerRecordStore } from "../../core/playerRecord";
import { type SessionStore, SupabaseLite } from "../../core/supabaseLite";
import { storage } from "../storage";

const sessionStore: SessionStore = {
  get: (key) => storage.get(key),
  set: (key, value) => storage.set(key, value),
  remove: (key) => { try { localStorage.removeItem(key); } catch { /* blocked storage */ } },
};

// A work or school filter may block supabase.co; then the site's own `/sb` route (a Vercel rewrite) reaches it.
export const account = new PlayerAccount({ api: new SupabaseLite({ store: sessionStore, fallbackBaseURL: `${location.origin}/sb` }) });
const uploader = new GameUploader(storage);
/** Challenges to and from friends, and the ranked queue, on the same profile (FriendChallengeCoordinator, RankedMatchmaker). */
export const challenges = new FriendChallengeCoordinator(new SupabaseFriendChallenges(account.api));
export const rankedQueue = new RankedMatchmaker(new SupabaseRankedQueue(account.api));
/** Redraws on a coordinator's or matchmaker's every change. */
export function useWatched(value: { subscribe(listener: () => void): () => void; version: number }) {
  useSyncExternalStore((listener) => value.subscribe(listener), () => value.version);
  return value;
}

export function useAccount(): PlayerAccount {
  useSyncExternalStore((listener) => account.subscribe(listener), () => account.version);
  return account;
}

/** Where Google sends the player back: this page's own address, without a path or fragment. */
const redirectURI = () => `${location.origin}/`;

export async function signInWithGoogle(): Promise<void> {
  location.assign(await beginGoogleSignIn(sessionStore, redirectURI()));
}

/** What a page load coming back from Google came to, for the message the menus show. */
export type GoogleReturn = { kind: "none" } | { kind: "signedIn"; username?: string } | { kind: "failed"; message: string };

/**
 * Back from Google: finishes the sign-in and clears the token from the address bar. Every outcome is reported (the
 * reason also goes to the console), so a sign-in never ends in a page that looks unchanged.
 */
export async function completeGoogleSignIn(): Promise<GoogleReturn> {
  if (!isGoogleRedirect(location.hash)) return { kind: "none" };
  const reply = finishGoogleSignIn(sessionStore, location.hash);
  history.replaceState(null, "", location.pathname + location.search);
  if ("error" in reply) {
    console.warn("Google sign-in did not finish:", reply.error);
    const message = reply.error === "sign_in_cancelled" ? "Google sign-in was cancelled."
      : reply.error === "error" ? "This browser lost track of the sign-in it started. Try again in this tab."
      : `Google refused the sign-in (${reply.error}). Try again.`;
    account.setNotice(message);
    return { kind: "failed", message };
  }
  await account.signIn("google", reply.idToken, reply.nonce);
  if (account.state.linkedIdentities.some((identity) => identity.provider === "google")) {
    return { kind: "signedIn", username: account.state.username };
  }
  const message = account.state.notice ?? "Google sign-in didn't finish. Try again.";
  console.warn("Google sign-in did not finish:", message);
  return { kind: "failed", message };
}

/** The browser's record as the account's RankedRecord: pending ranked results, their game records, the server's rank. */
export function rankedRecordOf(record: PlayerRecordStore, changed: () => void): RankedRecord {
  return {
    get rank() { return record.rank; },
    get pendingRankedResults(): readonly PendingRankedResult[] { return record.pendingRankedResults; },
    resolvePendingRankedResult: (ticket) => { record.resolvePendingRanked(ticket); changed(); },
    gameRecord: (name) => record.gameRecord(name) as ReturnType<RankedRecord["gameRecord"]>,
    settleRanked: (ticket, settlement, check, change, points) => { record.settleRanked(ticket, settlement, check, change, points); changed(); },
    adopt(standing) {
      const next = adoptStanding(record.rank, standing, record.pendingRankedResults.length);
      if (next) { record.adoptRank(next); changed(); }
    },
  };
}

/**
 * After each refresh of the profile (and when it first loads): ranked results and the server's standing, then the
 * finished games (OnDeviceRootView's afterRefresh). A ranked game goes up after its result counts there.
 */
export function connectRecord(record: PlayerRecordStore, changed: () => void) {
  const ranked = rankedRecordOf(record, changed);
  account.afterRefresh = async () => {
    await account.syncRank(ranked);
    await uploader.flush(record.matches.filter((m) => m.mode !== "ranked" || !record.pendingRankedResults.length), (match) => account.recordGame(match));
  };
  return {
    /** A finished game: ranked results settle on the server first, then the games go up. */
    async afterGame() { await account.afterRefresh?.(); },
    publish() { void account.publishRank(record.rank, record.title, record.shownCommander); },
  };
}
