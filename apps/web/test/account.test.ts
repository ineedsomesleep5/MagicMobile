/**
 * PlayerAccount and its wire types against a fake server (never the network). The rules and parsing follow
 * parity/chat-cases.json and parity/profile-cases.json (iOS TableChatTests and ProfileAnalyticsTests, Android's tests),
 * plus the cases of iOS FriendMessagesTests and RankedStandingTests.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  adoptStanding, type FriendMessage, FriendMessageRules, GameUploader, type MessageConversation, PlayerAccount, PlayerAccountRules,
  PlayerFriend, PlayerSearchResult, PlayerSearchRules, PublicProfile, RankedLeaderboard, rankedAITicket, rankedRecord, RankedStanding,
  SearchCancelled,
} from "../src/core/account";
import type { J } from "../src/core/json";
import { type MatchRecord, PlayerRecordStore } from "../src/core/playerRecord";
import { RankPosition, type RankState } from "../src/core/rankLadder";
import { SupabaseLite } from "../src/core/supabaseLite";

const root = join(__dirname, "..", "..", "..");
const parity = (name: string) => JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity", name), "utf8"));
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const chat: any = parity("chat-cases.json");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const profile: any = parity("profile-cases.json");

const OCTOBER = 1_791_000_000_000; // October 2026
const BASE = SupabaseLite.baseURL;

type Reply = { status: number; body?: J };
const ok = (body: J = null): Reply => ({ status: 200, body });
const fail = (message: string, status = 400): Reply => ({ status, body: { code: "P0001", message } });
const missing = (): Reply => ({ status: 404, body: { code: "PGRST202", message: "Could not find the function in the schema cache" } });
/** Lets the fake server's replies and the account's follow-up calls run. */
const settle = async () => { for (let i = 0; i < 20; i += 1) await new Promise((resolve) => setTimeout(resolve, 0)); };
const tokens = (access: string): Reply => ({ status: 200, body: { access_token: access, refresh_token: `r-${access}`, expires_in: 3600 } });

interface Call { path: string; body: Record<string, J>; bearer?: string }

/** A signed-in browser talking to a fake Supabase: `rpcs` answers by function name, `auth` answers auth/v1 calls. */
function harness(rpcs: Record<string, (params: Record<string, J>) => Reply>, auth: (path: string, body: Record<string, J>) => Reply = () => ({ status: 500 })) {
  const calls: Call[] = [];
  const map = new Map([["mm.web.session", JSON.stringify({ accessToken: "A0", refreshToken: "r0", expiresAt: OCTOBER + 3_600_000 })]]);
  const store = { get: (k: string) => map.get(k) ?? null, set: (k: string, v: string) => { map.set(k, v); }, remove: (k: string) => { map.delete(k); } };
  const fetch = async (url: string, init: RequestInit) => {
    const path = url.replace(BASE, "");
    const body = typeof init.body === "string" ? JSON.parse(init.body) : {};
    const bearer = (init.headers as Record<string, string>).Authorization;
    calls.push({ path, body, ...(bearer ? { bearer } : {}) });
    const fn = /^\/rest\/v1\/rpc\/(\w+)$/.exec(path)?.[1];
    const reply = fn ? (rpcs[fn]?.(body) ?? missing()) : auth(path, body);
    return new Response(reply.body === undefined ? "" : JSON.stringify(reply.body), { status: reply.status });
  };
  const scheduled: { ms: number; run: () => void; cancelled: boolean }[] = [];
  const schedule = (run: () => void, ms: number) => { const item = { ms, run, cancelled: false }; scheduled.push(item); return () => { item.cancelled = true; }; };
  const api = new SupabaseLite({ store, fetch, now: () => OCTOBER });
  const account = new PlayerAccount({ api, now: () => OCTOBER, schedule });
  const rpcCalls = (fn: string) => calls.filter((c) => c.path === `/rest/v1/rpc/${fn}`);
  return { account, api, calls, rpcCalls, scheduled, store: map };
}

const friendsJSON: J = [
  { id: "0B105EE9-8D80-4E09-B177-6D85B6782C65", username: "Host", relation: "friend", online: true, last_seen_at: "2026-09-28T04:23:48.401014+00:00", platform: "ios", hosting_code: "abc234", hosting_open_seats: 1 },
  { id: "8F11874A-78CA-4BFF-871B-92A3B135862B", username: "Full", relation: "friend", online: true, last_seen_at: null, platform: "android", hosting_code: "ABC234", hosting_open_seats: 0 },
  { id: "8F11874A-78CA-4BFF-871B-92A3B135862C", username: "Asker", relation: "incoming", online: false, last_seen_at: null, platform: null, hosting_code: null, hosting_open_seats: null },
];

const profileServer = (extra: Record<string, (params: Record<string, J>) => Reply> = {}) => ({
  mm_profile: () => ok({ id: "u1", username: "Caleb_22", visibility: "friends" }),
  mm_friends: () => ok(friendsJSON),
  mm_blocked: () => ok([{ username: "Rude" }]),
  mm_message_unread: () => ok(2),
  mm_friend_ranks: () => ok([{ username: "Host", season: "2026-10", rank_step: 9, pips: 2, title: null }, { username: "Full", season: "2026-09", rank_step: 3, pips: 0 }]),
  ...extra,
});

describe("PlayerAccountRules", () => {
  it("validates usernames, messages and request results as chat-cases.json says", () => {
    for (const item of chat.usernames) expect(PlayerAccountRules.isValidUsername(item.name), item.name).toBe(item.valid);
    for (const [code, message] of Object.entries(chat.messages)) expect(PlayerAccountRules.message(code), code).toBe(message);
    for (const item of chat.requestResults) expect(PlayerAccountRules.requestResult(item.result, item.username)).toBe(item.text);
  });

  it("has every message iOS has, word for word", () => {
    const messages: Record<string, string> = {
      username_taken: "That name is taken. Try another.",
      invalid_username: "Use 3–20 letters, numbers or underscores.",
      not_found: "No player has that name.",
      self: "That's you.",
      no_username: "Choose your name first.",
      too_many_requests: "You have too many friend requests waiting.",
      too_many_reports: "You've sent a lot of reports. Try again later.",
      not_friends: "You can only message friends.",
      invalid_message: "Write something first (500 characters at most).",
      too_many_messages: "You're sending messages fast. Wait a moment and try again.",
      anonymous_provider_disabled: "Profiles aren't available right now. You can still play.",
      anonymous_disabled: "Profiles aren't available right now. You can still play.",
      feature_unavailable: "That part of the profile server isn't ready yet. Try again after the next update.",
      invalid_visibility: "Choose Public, Friends only or Private.",
      too_many_games: "You've played a lot of games. Your game history catches up later.",
      offline: "You're offline. Profiles and friends come back when you reconnect.",
      provider_disabled: "Signing in isn't switched on yet. Try again after the next update.",
      manual_linking_disabled: "Signing in isn't switched on yet. Try again after the next update.",
      validation_failed: "Signing in isn't switched on yet. Try again after the next update.",
      sign_in_cancelled: "Sign-in cancelled.",
      error: "Something went wrong. Try again.",
      identity_already_exists: "Something went wrong. Try again.",
    };
    for (const [code, message] of Object.entries(messages)) expect(PlayerAccountRules.message(code), code).toBe(message);
  });

  it("validates usernames by ASCII letters, digits and underscores, 3–20 long", () => {
    expect(["abc", "A_1", "a".repeat(20), "___"].map(PlayerAccountRules.isValidUsername)).toEqual([true, true, true, true]);
    expect(["ab", "a".repeat(21), "a b", "émile", "émile", "名前です", "a-b", "a.b", "abc\n", "  abc"].map(PlayerAccountRules.isValidUsername))
      .toEqual(Array(10).fill(false));
  });

  it("normalizes search prefixes as profile-cases.json says", () => {
    for (const item of profile.searchPrefixes) expect(PlayerSearchRules.normalized(item.text) ?? null, `'${item.text}'`).toBe(item.normalized);
  });
});

describe("wire parsing", () => {
  it("decodes friend rows; only online friends with seats are joinable", () => {
    const rows = PlayerFriend.decodeList(friendsJSON);
    expect(rows.map(PlayerFriend.joinableCode)).toEqual(["ABC234", undefined, undefined]);
    expect(rows.map(PlayerFriend.isFriend)).toEqual([true, true, false]);
    expect(rows[0].lastSeenAt).toBe(Date.parse("2026-09-28T04:23:48.401Z"));
    expect(PlayerFriend.withRelation(rows[0], "outgoing")).toMatchObject({ relation: "outgoing", online: false });
    expect(() => PlayerFriend.decodeList([{ id: "nope", username: "x", relation: "friend", online: true }])).toThrow();
  });

  it("parses public profiles as profile-cases.json says", () => {
    for (const item of profile.publicProfiles) {
      const name = item.name;
      const p = PublicProfile.parse(item.json, Date.parse("2026-10-07T12:00:00Z"));
      const e = item.expect;
      expect(p.username, name).toBe(e.username);
      expect(p.restricted, name).toBe(e.restricted);
      expect(p.visibility, name).toBe(e.visibility);
      expect(p.relation, name).toBe(e.relation);
      expect(p.online ?? null, name).toBe(e.online);
      expect(PublicProfile.isFriend(p), name).toBe(e.isFriend);
      expect(p.rank?.step ?? null, name).toBe(e.rankStep);
      expect(p.summary.games, name).toBe(e.games);
      expect(p.summary.weeks.length, name).toBe(e.weeks);
      expect(p.games.length, name).toBe(e.gameCount);
      if (p.restricted) continue;
      expect(p.title, name).toBe(e.title);
      expect(p.favoriteCommander, name).toBe(e.favoriteCommander);
      expect(p.rank?.pips, name).toBe(e.rankPips);
      expect(p.rank?.peakStep, name).toBe(e.rankPeak);
      expect([p.summary.wins, p.summary.losses, p.summary.currentStreak, p.summary.bestStreak], name).toEqual([e.wins, e.losses, e.currentStreak, e.bestStreak]);
      expect(p.summary.averageTurns, name).toBeCloseTo(e.averageTurns, 9);
      expect(p.summary.weeks.map((w) => w.games), name).toEqual(e.weekGames);
      expect(p.summary.rankPoints.map((r) => r.points), name).toEqual(e.rankPoints);
      expect(p.summary.colors.map((c) => c.id), name).toEqual(e.colors);
      expect(p.summary.commanders.map((c) => c.id), name).toEqual(e.commanders);
      const first = p.games[0];
      expect(first.opponents.map((o) => o.name), name).toEqual(e.firstGameOpponents);
      expect(first.opponents.map((o) => o.hidden), name).toEqual(e.firstGameHidden);
      expect(first.opponents.map((o) => !o.isAI), name).toEqual(e.firstGameHuman);
      expect(p.games[1].deckName, name).toBe(e.secondGameDeck);
      expect(p.games[1].turns, name).toBeUndefined();
      expect(first.date, name).toBe(Date.parse("2026-10-06T10:00:00Z"));
    }
    expect(() => PublicProfile.parse({ restricted: true })).toThrow();
  });

  it("parses search results as profile-cases.json says", () => {
    const results = PlayerSearchResult.parse(profile.searchResults.json);
    const expected = profile.searchResults.expect;
    expect(results.length).toBe(expected.length);
    results.forEach((r, i) => {
      expect(r.username).toBe(expected[i].username);
      expect(r.visibility).toBe(expected[i].visibility);
      expect(r.relation).toBe(expected[i].relation);
      expect(r.online ?? null).toBe(expected[i].online);
      expect(r.rankStep ?? null).toBe(expected[i].rankStep);
    });
  });

  it("parses the message shapes, sanitizes, masks and merges (FriendMessagesTests)", () => {
    const conversations = FriendMessageRules.parseConversations([
      { username: "Aria_Blade", unread: 2, last: { id: 6, body: "Want to play?", sentAt: "2026-10-17T19:16:34.123456+00:00", fromMe: false, read: false } },
      { username: "ManaFiend", unread: 0, last: { id: 4, body: "Well played!", sentAt: "2026-10-16T08:00:00+00:00", fromMe: true, read: true } },
    ]);
    expect(conversations.map((c) => c.username)).toEqual(["Aria_Blade", "ManaFiend"]);
    expect(conversations[0].unread).toBe(2);
    expect(conversations[0].last.fromMe).toBe(false);
    const thread = FriendMessageRules.parseThread({ username: "Aria_Blade", hasMore: true, messages: [{ id: 5, body: "hi", sentAt: "2026-10-17T19:15:00+00:00", fromMe: true, read: true }] });
    expect(thread.hasMore).toBe(true);
    expect(thread.messages[0].id).toBe(5);
    expect(FriendMessageRules.parseMessage({ id: 9, body: "ok", sentAt: "2026-10-17T19:20:00.5+00:00", fromMe: true, read: false }).sentAt)
      .toBe(Date.parse("2026-10-17T19:20:00.500Z"));

    expect(FriendMessageRules.sanitize("   \n\t ")).toBeUndefined();
    expect(FriendMessageRules.sanitize("  up  for\na game?  ")).toBe("up for a game?");
    expect(FriendMessageRules.sanitize("x".repeat(600))?.length).toBe(FriendMessageRules.maxScalars);
    const theirs: FriendMessage = { id: 2, body: "well shit", sentAt: 1_000_000, fromMe: false, read: false };
    const mine: FriendMessage = { id: 1, body: "well shit", sentAt: 1_000_000, fromMe: true, read: true };
    expect(FriendMessageRules.shown(theirs)).toBe("well s***");
    expect(FriendMessageRules.shown(mine)).toBe("well shit");
    const merged = FriendMessageRules.merged([theirs, mine], [{ ...theirs, read: true }, { id: 3, body: "new", sentAt: 1_000_000, fromMe: false, read: false }]);
    expect(merged.map((m) => m.id)).toEqual([1, 2, 3]);
    expect(merged[1].read).toBe(true);
  });

  it("orders friends by last message, then quiet friends A–Z", () => {
    const at = (id: number): FriendMessage => ({ id, body: "x", sentAt: 1_000_000, fromMe: false, read: true });
    const conversations: MessageConversation[] = [
      { username: "Old", unread: 0, last: at(3) }, { username: "New", unread: 1, last: at(8) }, { username: "Gone", unread: 0, last: at(9) },
    ];
    const rows = FriendMessageRules.ordered(["zed", "Old", "New", "amy"], conversations);
    expect(rows.map((r) => r.name)).toEqual(["New", "Old", "amy", "zed"]);
    expect(rows[2].conversation).toBeUndefined();
  });

  it("parses the leaderboard and pins your row off the list", () => {
    const board = RankedLeaderboard.parse(JSON.parse(`{"season":"2026-10","scope":"everyone","total":3,"online":1,"entries":[{"position":1,"username":"Dahlia_Rose","title":"Mythic Legend","commander":"Ayula, Queen Among Bears","points":87,"step":20,"pips":7,"peakStep":20,"wins":28,"losses":11,"online":true,"you":false},{"position":2,"username":"ManaFiend","title":null,"commander":null,"points":71,"step":17,"pips":3,"peakStep":17,"wins":25,"losses":10,"online":false,"you":false}],"me":{"position":3,"username":"CalebM","title":"Contender","commander":"Edgar Markov","points":42,"step":10,"pips":2,"peakStep":11,"wins":14,"losses":9,"online":true,"you":true}}`));
    expect(board.entries.map((e) => e.username)).toEqual(["Dahlia_Rose", "ManaFiend"]);
    expect(RankedLeaderboard.rank(board.entries[0]).tier).toBe("mythic");
    expect(board.entries[1].title).toBeUndefined();
    expect(RankedLeaderboard.pinnedMe(board)?.username).toBe("CalebM");
    const empty = RankedLeaderboard.parse({ season: "2026-10", scope: "friends", total: 0, online: 0, entries: [], me: null });
    expect(empty.entries).toEqual([]);
    expect(RankedLeaderboard.pinnedMe(empty)).toBeUndefined();
  });

  it("parses the seeded ranked AI ticket", () => {
    const id = "0B105EE9-8D80-4E09-B177-6D85B6782C65";
    expect(rankedAITicket({ id, seed: "-4123456789012345678", aiSkill: 1 })).toEqual({ id, seed: -4123456789012345678n });
    expect(rankedAITicket({ id, seed: 4.5 })).toBeUndefined();
    expect(rankedAITicket(id)).toBeUndefined();
    expect(rankedAITicket({ id, seed: "9223372036854775808" })).toBeUndefined();
  });
});

describe("the server's ranked standing", () => {
  const standing = (o: { season?: string; points: number; peak?: number; wins?: number; losses?: number; unsettled?: number; history?: J; seeded?: boolean }) =>
    RankedStanding.parse({
      seeded: o.seeded ?? true, unsettled: o.unsettled ?? 0, season: o.season ?? "2026-10", points: o.points, peakPoints: o.peak ?? o.points,
      wins: o.wins ?? 0, losses: o.losses ?? 0, draws: 0, winStreak: 2, history: o.history ?? [], settlement: "counted", change: { outcome: "win" },
    });
  const played = (): RankState => ({
    season: "2026-10", position: RankPosition.fromPoints(2), peak: RankPosition.fromPoints(2), wins: 1, losses: 0, draws: 0, winStreak: 1, history: [],
  });

  it("parses the standing", () => {
    const value = standing({ points: 9, peak: 12, wins: 5, losses: 2, history: [{ season: "2026-09", finalPoints: 30, peakPoints: 33, wins: 9, losses: 4 }] });
    expect(value.points).toBe(9);
    expect(value.history?.[0].finalPoints).toBe(30);
    expect(value.settlement).toBe("counted");
    expect(() => RankedStanding.parse({ seeded: true })).toThrow();
  });

  it("adopts the server's standing", () => {
    const next = adoptStanding(played(), standing({ points: 9, peak: 12, wins: 5, losses: 2 }))!;
    expect(next.position).toEqual({ tier: "bronze", division: 2, pips: 1 });
    expect(next.peak).toEqual({ tier: "bronze", division: 1, pips: 0 });
    expect([next.wins, next.losses, next.winStreak]).toEqual([5, 2, 2]);
  });

  it("keeps its own count while a result is on its way", () => {
    expect(adoptStanding(played(), standing({ points: 0, unsettled: 1 }))).toBeUndefined();
    expect(adoptStanding(played(), standing({ points: 1 }), 1)).toBeUndefined();
  });

  it("rolls over to a newer season with its history, and never takes an older one", () => {
    const next = adoptStanding(played(), standing({ season: "2026-11", points: 4, history: [{ season: "2026-10", finalPoints: 20, peakPoints: 22, wins: 9, losses: 4 }] }))!;
    expect(next.season).toBe("2026-11");
    expect(next.position).toEqual(RankPosition.fromPoints(4));
    expect(next.history[0]).toMatchObject({ season: "2026-10", final: RankPosition.fromPoints(20), wins: 9 });
    expect(adoptStanding(next, standing({ season: "2026-09", points: 60 }))).toBeUndefined();
  });

  it("syncs: seeds an unseeded server from this browser, then adopts through the adapter", async () => {
    const values = new Map<string, string>();
    const store = new PlayerRecordStore({ get: (k) => values.get(k), set: (k, v) => { values.set(k, v); } }, () => OCTOBER);
    store.record({ mode: "ranked", outcome: "win", opponents: [{ name: "AI 1", isAI: true }], deckID: "d", deckName: "D", colors: ["R"], deckBracket: 2, turns: 9 });
    const h = harness(profileServer({
      mm_ranked_standing: () => ok({ seeded: false, unsettled: 0, season: "2026-10", points: 0, peakPoints: 0, wins: 0, losses: 0, draws: 0, winStreak: 0 }),
      mm_ranked_seed: (p) => ok({ seeded: true, unsettled: 0, season: "2026-10", points: p.p_points as number, peakPoints: p.p_peak_points as number, wins: 7, losses: 0, draws: 0, winStreak: 1 }),
    }));
    await h.account.start();
    let adopted: RankState | undefined;
    await h.account.syncRank(rankedRecord(store, (rank) => { adopted = rank; }));
    expect(h.rpcCalls("mm_ranked_seed")[0].body).toEqual({ p_points: RankPosition.points(store.rank.position), p_peak_points: RankPosition.points(store.rank.peak), p_wins: 1, p_losses: 0 });
    expect(adopted?.wins).toBe(7);
  });

  it("sends pending ranked AI results with their ticket; an unknown ticket is dropped", async () => {
    const h = harness(profileServer({
      mm_ranked_ai_result2: () => ok({ seeded: true, unsettled: 0, season: "2026-10", points: 5, peakPoints: 5, wins: 2, losses: 0, draws: 0, winStreak: 2 }),
      mm_ranked_ai_result: () => fail("not_found"),
      mm_ranked_standing: () => ok({ seeded: true, unsettled: 0, season: "2026-10", points: 5, peakPoints: 5, wins: 2, losses: 0, draws: 0, winStreak: 2 }),
    }));
    await h.account.start();
    const pending = [
      { ticket: "T1", outcome: "win" as const, date: OCTOBER, seeded: true, recordFile: "g1.json" },
      { ticket: "T2", outcome: "loss" as const, date: OCTOBER },
    ];
    const resolved: string[] = [], adopted: number[] = [];
    await h.account.syncRank({
      rank: played(), pendingRankedResults: pending, resolvePendingRankedResult: (t) => { resolved.push(t); },
      gameRecord: (name) => ({ name }), adopt: (s) => { adopted.push(s.points); },
    });
    expect(h.rpcCalls("mm_ranked_ai_result2")[0].body).toEqual({ p_game: "T1", p_result: "win", p_record: { name: "g1.json" } });
    expect(h.rpcCalls("mm_ranked_ai_result")[0].body).toEqual({ p_game: "T2", p_result: "loss" });
    expect(resolved).toEqual(["T1", "T2"]);
    expect(adopted).toEqual([5, 5]);
  });
});

describe("PlayerAccount", () => {
  it("starts: loads the profile, identities, friends, blocked, unread and this season's friend ranks", async () => {
    const h = harness(profileServer(), (path) => (path === "/auth/v1/user" ? ok(chat.linkedIdentities.user) : { status: 500 }));
    let heard = 0;
    h.account.subscribe(() => { heard += 1; });
    await h.account.start();
    const s = h.account.state;
    expect(s.phase).toBe("ready");
    expect(s.username).toBe("Caleb_22");
    expect([s.visibility, s.visibilityKnown]).toEqual(["friends", true]);
    expect(s.linkedIdentities.map((i) => i.provider)).toEqual(["google", "apple"]);
    expect(s.friends.map((f) => f.username)).toEqual(["Host", "Full", "Asker"]);
    expect([s.incomingCount, s.onlineFriendCount]).toEqual([1, 2]);
    expect(s.blocked).toEqual(["Rude"]);
    expect(s.unreadMessages).toBe(2);
    expect(s.friendRanks).toEqual({ Host: RankPosition.published(9, 2) });
    expect(heard).toBeGreaterThan(0);
    expect(h.account.version).toBe(heard);
    expect(h.calls.every((c) => c.bearer === "Bearer A0")).toBe(true);
  });

  it("is unavailable, with the notice, when the server refuses", async () => {
    const h = harness({ mm_profile: () => ({ status: 422, body: { code: 422, error_code: "anonymous_provider_disabled" } }) });
    await h.account.start();
    expect(h.account.state.phase).toBe("unavailable");
    expect(h.account.state.notice).toBe("Profiles aren't available right now. You can still play.");
  });

  it("claims a name: invalid ones never reach the server, a taken one says so", async () => {
    const h = harness(profileServer({ mm_claim_username: (p) => (p.p_username === "Taken" ? fail("username_taken") : ok()), mm_heartbeat: () => ok() }));
    await h.account.start();
    expect(await h.account.claim("a b")).toBe(false);
    expect(h.account.state.notice).toBe("Use 3–20 letters, numbers or underscores.");
    expect(await h.account.claim("Taken")).toBe(false);
    expect(h.account.state.notice).toBe("That name is taken. Try another.");
    expect(await h.account.claim("  New_Name ")).toBe(true);
    expect(h.account.state.username).toBe("New_Name");
    expect(h.account.state.notice).toBeUndefined();
    expect(h.rpcCalls("mm_claim_username").map((c) => c.body.p_username)).toEqual(["Taken", "New_Name"]);
    expect(h.rpcCalls("mm_heartbeat")[0].body).toEqual({ p_platform: null, p_hosting_code: null, p_open_seats: null });
  });

  it("signs in by linking; identity_already_exists falls back to a plain sign-in and switches profile", async () => {
    const idCalls: Record<string, J>[] = [];
    const h = harness(profileServer({ mm_profile: () => ok({ username: "Elsewhere", visibility: "public" }) }), (path, body) => {
      if (path === "/auth/v1/token?grant_type=id_token") {
        idCalls.push(body);
        return body.link_identity === true ? { status: 422, body: { code: 422, error_code: "identity_already_exists", msg: "Identity is already linked to another user" } } : tokens("G1");
      }
      if (path === "/auth/v1/user") return ok({ identities: [{ provider: "google", identity_data: { email: "p@gmail.com" } }] });
      return { status: 500 };
    });
    await h.account.signIn("google", "id.jwt", "raw");
    expect(idCalls).toEqual([
      { provider: "google", id_token: "id.jwt", nonce: "raw", link_identity: true },
      { provider: "google", id_token: "id.jwt", nonce: "raw" },
    ]);
    const s = h.account.state;
    expect([s.phase, s.username, s.isSigningIn, s.notice]).toEqual(["ready", "Elsewhere", false, undefined]);
    expect(s.linkedIdentities).toEqual([{ provider: "google", email: "p@gmail.com" }]);
    expect(h.rpcCalls("mm_profile")[0].bearer).toBe("Bearer G1");
    expect(JSON.parse(h.store.get("mm.web.session")!).accessToken).toBe("G1");
  });

  it("a refused sign-in leaves a notice and the profile as it was", async () => {
    const h = harness(profileServer(), (path) => (path.includes("id_token") ? { status: 400, body: { error_code: "provider_disabled" } } : { status: 500 }));
    await h.account.start();
    await h.account.signIn("apple", "t", undefined);
    expect(h.account.state.notice).toBe("Signing in isn't switched on yet. Try again after the next update.");
    expect(h.account.state.username).toBe("Caleb_22");
    expect(h.account.state.isSigningIn).toBe(false);
  });

  it("signs out to a fresh anonymous profile", async () => {
    const h = harness(profileServer(), (path) => (path === "/auth/v1/signup" ? tokens("N1") : { status: 500 }));
    await h.account.start();
    await h.account.signOut();
    expect(h.calls.some((c) => c.path === "/auth/v1/signup")).toBe(true);
    expect(h.rpcCalls("mm_profile").at(-1)?.bearer).toBe("Bearer N1");
  });

  it("friends: request, respond, remove, block and report", async () => {
    const h = harness(profileServer({
      mm_friend_request: (p) => (p.p_username === "Ghost" ? fail("not_found") : ok("accepted")),
      mm_respond_friend: () => ok(), mm_remove_friend: () => ok(), mm_block: () => ok(), mm_unblock: () => ok(), mm_report: () => ok(),
    }));
    await h.account.start();
    await h.account.addFriend("  Bebo ");
    expect(h.account.state.notice).toBe("You and Bebo are now friends.");
    await h.account.addFriend("Ghost");
    expect(h.account.state.notice).toBe("No player has that name.");
    const asker = h.account.state.friends[2];
    await h.account.respond(asker, true);
    expect(h.rpcCalls("mm_respond_friend")[0].body).toEqual({ p_requester: asker.id, p_accept: true });
    expect(h.account.state.notice).toBeUndefined();
    await h.account.remove(asker);
    expect(h.rpcCalls("mm_remove_friend")[0].body).toEqual({ p_other: asker.id });
    await h.account.block("Rude");
    await h.account.unblock("Rude");
    expect(h.rpcCalls("mm_unblock")[0].body).toEqual({ p_username: "Rude" });
    const before = h.rpcCalls("mm_friends").length;
    await h.account.report("Rude", undefined, "chat");
    expect(h.rpcCalls("mm_report")[0].body).toEqual({ p_username: "Rude", p_message: null, p_context: "chat" });
    expect(h.rpcCalls("mm_friends").length).toBe(before);
    expect(h.account.state.notice).toBe("Thanks. Rude was reported.");
  });

  it("presence: a heartbeat now and every 45 seconds while in the foreground, hosting sent at once", async () => {
    const h = harness(profileServer({ mm_heartbeat: () => ok() }));
    let after = 0;
    h.account.afterRefresh = () => { after += 1; };
    h.account.setForeground(true);
    await settle();
    expect(h.account.state.phase).toBe("ready");
    expect(h.rpcCalls("mm_heartbeat")).toHaveLength(1);
    expect(after).toBe(1);
    expect(h.scheduled.map((s) => s.ms)).toEqual([PlayerAccount.heartbeatInterval]);
    expect(PlayerAccount.heartbeatInterval).toBe(45_000);
    h.scheduled[0].run();
    await settle();
    expect(h.rpcCalls("mm_heartbeat")).toHaveLength(2);
    h.account.setHosting({ code: "ABC234", openSeats: 2 });
    await settle();
    expect(h.rpcCalls("mm_heartbeat").at(-1)?.body).toEqual({ p_platform: null, p_hosting_code: "ABC234", p_open_seats: 2 });
    h.account.setForeground(false);
    expect(h.scheduled.map((s) => s.ms)).toEqual([45_000, 45_000]);
    expect(h.scheduled[1].cancelled).toBe(true);
  });

  it("messages: conversations, a thread that updates the badge, sending, and a server without messages", async () => {
    let unread = 3;
    const h = harness(profileServer({
      mm_message_unread: () => ok(unread),
      mm_message_conversations: () => ok([{ username: "Host", unread: 1, last: { id: 6, body: "hi", sentAt: "2026-10-17T19:16:34+00:00", fromMe: false, read: false } }]),
      mm_message_thread: () => { unread = 0; return ok({ username: "Host", hasMore: false, messages: [] }); },
      mm_message_send: (p) => (p.p_username === "Stranger" ? fail("not_friends") : ok({ id: 7, body: p.p_body, sentAt: "2026-10-17T19:17:00+00:00", fromMe: true, read: false })),
    }));
    await h.account.start();
    expect((await h.account.conversations())?.[0].unread).toBe(1);
    await h.account.thread("Host");
    expect(h.rpcCalls("mm_message_thread")[0].body).toEqual({ p_username: "Host", p_before: null, p_limit: 50 });
    expect(h.account.state.unreadMessages).toBe(0);
    await h.account.thread("Host", 6);
    expect(h.rpcCalls("mm_message_thread")[1].body.p_before).toBe(6);
    expect(await h.account.sendMessage("Host", "   ")).toBeUndefined();
    expect((await h.account.sendMessage("Host", " gg  wp "))?.body).toBe("gg wp");
    expect(await h.account.sendMessage("Stranger", "hi")).toBeUndefined();
    expect(h.account.state.notice).toBe("You can only message friends.");

    const bare = harness(profileServer({ mm_message_unread: missing }));
    await bare.account.start();
    await bare.account.refreshUnread();
    expect(bare.account.state.messagesAvailable).toBe(false);
    expect(await bare.account.conversations()).toBeUndefined();
  });

  it("profiles: a card, a public profile, not found and a server without them", async () => {
    const h = harness(profileServer({
      mm_profile_card: () => ok({ username: "Host", season: "2026-10", rankStep: 9, pips: 2, peakStep: 9, wins: 3, losses: 1, title: null, favoriteCommander: "Krenko" }),
      mm_public_profile: (p) => (p.p_username === "DaAlpha" ? ok(profile.publicProfiles[0].json) : fail("not_found")),
      mm_set_visibility: () => ok("private"),
    }));
    await h.account.start();
    expect(await h.account.profileCard("Host")).toMatchObject({ username: "Host", rankStep: 9, favoriteCommander: "Krenko" });
    const found = await h.account.publicProfile("DaAlpha");
    expect(found.kind === "profile" && found.profile.username).toBe("DaAlpha");
    expect(await h.account.publicProfile("Nobody")).toEqual({ kind: "notFound" });
    expect(await h.account.setVisibility("private")).toBe(true);
    expect([h.account.state.visibility, h.account.state.visibilityKnown]).toEqual(["private", true]);

    const old = harness(profileServer());
    await old.account.start();
    expect(await old.account.publicProfile("DaAlpha")).toEqual({ kind: "unavailable" });
    expect(old.account.state.profilesAvailable).toBe(false);
    expect(await old.account.setVisibility("friends")).toBe(false);
    expect(old.account.state.visibilityKnown).toBe(false);
    expect(old.account.state.notice).toBe(PlayerAccountRules.message("feature_unavailable"));

    const idle = harness(profileServer());
    expect(await idle.account.publicProfile("DaAlpha")).toEqual({ kind: "failed", message: PlayerAccountRules.message("offline") });
  });

  it("search: short prefixes stay local, a newer search cancels an older one", async () => {
    const h = harness(profileServer({ mm_search_players: () => ok(profile.searchResults.json) }));
    await h.account.start();
    expect(await h.account.search("d")).toEqual([]);
    expect(h.rpcCalls("mm_search_players")).toHaveLength(0);
    expect((await h.account.search(" Da ")).map((r) => r.username)).toEqual(["DaFriend", "DaFriendsOnly", "Da_x"]);
    expect(h.rpcCalls("mm_search_players")[0].body).toEqual({ p_prefix: "Da" });
    const older = h.account.search("Da_");
    const newer = h.account.search("Da_x");
    await expect(older).rejects.toBeInstanceOf(SearchCancelled);
    expect(await newer).toHaveLength(3);
  });

  it("leaderboard and ranked publishing need a profile name", async () => {
    const h = harness(profileServer({
      mm_ranked_leaderboard: () => ok({ season: "2026-10", scope: "friends", total: 0, online: 0, entries: [], me: null }),
      mm_ranked_publish: () => ok(),
    }));
    expect(await h.account.rankedLeaderboard("everyone")).toBeUndefined();
    await h.account.start();
    expect((await h.account.rankedLeaderboard("friends", 10))?.scope).toBe("friends");
    expect(h.rpcCalls("mm_ranked_leaderboard")[0].body).toEqual({ p_scope: "friends", p_limit: 10 });
    const rank: RankState = { season: "2026-10", position: RankPosition.published(9, 2), peak: RankPosition.published(10, 0), wins: 5, losses: 2, draws: 0, winStreak: 1, history: [] };
    await h.account.publishRank(rank, "firstWin", undefined);
    expect(h.rpcCalls("mm_ranked_publish")[0].body).toEqual({
      p_season: "2026-10", p_rank_step: 9, p_pips: 2, p_peak_step: 10, p_wins: 5, p_losses: 2, p_title: "Rising Star", p_favorite_commander: null,
    });
  });

  it("records a game with the server's limits and maps its refusals", async () => {
    let reply: Reply = ok(true);
    const h = harness(profileServer({ mm_record_game: () => reply }));
    const match: MatchRecord = {
      id: "0B105EE9-8D80-4E09-B177-6D85B6782C65", date: Date.parse("2026-10-17T19:16:34.123Z"), mode: "ranked",
      opponents: [{ name: "n".repeat(70), isAI: true }, { name: "B", commander: "Edgar", isAI: false }, { name: "C", isAI: true }, { name: "D", isAI: true }],
      deckID: "d", deckName: "x".repeat(90), commander: "Krenko, Mob Boss", colors: ["R"], deckBracket: 2, outcome: "win", turns: 1200,
      rankChange: { outcome: "win", before: RankPosition.fromPoints(4), after: RankPosition.fromPoints(6), bonuses: [] },
    };
    expect(await h.account.recordGame(match)).toBe("unavailable");
    await h.account.start();
    expect(await h.account.recordGame(match)).toBe("sent");
    const body = h.rpcCalls("mm_record_game")[0].body;
    expect(body).toMatchObject({
      p_client_id: match.id, p_played_at: "2026-10-17T19:16:34.123Z", p_mode: "ranked", p_result: "win", p_deck_name: "x".repeat(80),
      p_commanders: ["Krenko, Mob Boss"], p_colors: ["R"], p_turns: 1000, p_rank_points: 6,
    });
    expect(body.p_opponents).toEqual([{ name: "n".repeat(60), commander: null, ai: true }, { name: "B", commander: "Edgar", ai: false }, { name: "C", commander: null, ai: true }]);
    reply = fail("invalid_game");
    expect(await h.account.recordGame(match)).toBe("rejected");
    reply = fail("no_username");
    expect(await h.account.recordGame(match)).toBe("unavailable");
    reply = fail("too_many_games");
    expect(await h.account.recordGame(match)).toBe("retryLater");
  });

  it("deletes the account and forgets the session", async () => {
    const h = harness(profileServer({ mm_delete_account: () => ok() }));
    await h.account.start();
    expect(await h.account.deleteAccount()).toBe(true);
    expect(h.account.state).toMatchObject({ phase: "idle", friends: [], blocked: [] });
    expect(h.account.state.username).toBeUndefined();
    expect(h.store.has("mm.web.session")).toBe(false);
  });
});

describe("GameUploader", () => {
  const match = (id: string): MatchRecord => ({ id, date: OCTOBER, mode: "quick", opponents: [], deckID: "d", deckName: "D", colors: [], deckBracket: 2, outcome: "win", turns: 5 });

  it("sends the oldest first, stops at the first retry and remembers what the server confirmed", async () => {
    const values = new Map<string, string>();
    const store = { get: (k: string) => values.get(k), set: (k: string, v: string) => { values.set(k, v); } };
    const uploader = new GameUploader(store);
    const matches = ["m4", "m3", "m2", "m1"].map(match); // newest first
    const sent: string[] = [];
    const confirmed = await uploader.flush(matches, async (m) => { sent.push(m.id); return m.id === "m3" ? "retryLater" : m.id === "m2" ? "rejected" : "sent"; });
    expect(sent).toEqual(["m1", "m2", "m3"]);
    expect(confirmed).toBe(1);
    expect(new GameUploader(store).pending(matches).map((m) => m.id)).toEqual(["m3", "m4"]);
  });
});
