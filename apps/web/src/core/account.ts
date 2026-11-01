/**
 * Port of PlayerAccount.swift (Android PlayerAccount.kt) and the server parts it uses from apps/ios/MagicMobile/Ranked/
 * (FriendMessages.swift, RankLadder.swift's RankedStanding and RankedLeaderboard, PlayerRecord.swift's adopt,
 * GameUploader.swift, ProfileAnalytics.swift's PublicProfile and player search). Checked by test/account.test.ts against
 * parity/chat-cases.json and parity/profile-cases.json, as iOS and Android are.
 *
 * The player's instant profile: an anonymous Supabase account made on first use, a unique username used at every table,
 * friends with presence, messages between friends, and the ranked standing the server keeps. Games never depend on it:
 * offline, the web keeps the typed name and plays as before.
 *
 * PlayerAccount is framework-free (like GameTable): `state` is replaced on every change, `version` counts changes and
 * `subscribe(listener)` hears them, so React reads it with useSyncExternalStore.
 */
import { appConfig } from "./appConfig";
import { arr, bool, get, int, isObject, isUuid, type J, type JObject, str } from "./json";
import { parseMyGames } from "./remoteGames";
import { Achievement, type KeyValueStore, type MatchRecord, type PlayerRecordStore, type PlayMode } from "./playerRecord";
import { ProfileGame, ProfileSummary } from "./profileSummary";
import { RankLadder, type RankOutcome, RankPosition, type RankState, type SeasonBadge, type SeasonRecord, type ServerRankChange } from "./rankLadder";
import { SupabaseFailure, SupabaseLite, type LinkedIdentity } from "./supabaseLite";
import { TableChatFilter, TableChatText, TableJoinLink } from "./tableChat";

// MARK: Rules

const usernamePattern = /^[A-Za-z0-9_]+$/;
/** Swift's `trimmingCharacters(in: .whitespaces)`: spaces and tabs, not line breaks. */
const trimSpaces = (text: string) => text.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");

/** The rules shared with iOS and Android (parity/chat-cases.json checks all three). */
export const PlayerAccountRules = {
  /** 3–20 letters, digits or underscores; unique ignoring case on the server. */
  isValidUsername: (name: string) => name.length >= 3 && name.length <= 20 && usernamePattern.test(name),

  /** What the player reads for a server error code (the mm_* functions raise these). */
  message(code: string): string {
    switch (code) {
      case "username_taken": return "That name is taken. Try another.";
      case "invalid_username": return "Use 3–20 letters, numbers or underscores.";
      case "not_found": return "No player has that name.";
      case "self": return "That's you.";
      case "no_username": return "Choose your name first.";
      case "too_many_requests": return "You have too many friend requests waiting.";
      case "too_many_reports": return "You've sent a lot of reports. Try again later.";
      case "not_friends": return "You can only message friends.";
      case "invalid_message": return "Write something first (500 characters at most).";
      case "too_many_messages": return "You're sending messages fast. Wait a moment and try again.";
      case "anonymous_provider_disabled": case "anonymous_disabled": return "Profiles aren't available right now. You can still play.";
      case "feature_unavailable": return "That part of the profile server isn't ready yet. Try again after the next update.";
      case "invalid_visibility": return "Choose Public, Friends only or Private.";
      case "too_many_games": return "You've played a lot of games. Your game history catches up later.";
      case "offline": return "You're offline. Profiles and friends come back when you reconnect.";
      case "provider_disabled": case "manual_linking_disabled": case "validation_failed":
        return "Signing in isn't switched on yet. Try again after the next update.";
      case "sign_in_cancelled": return "Sign-in cancelled.";
      default: return "Something went wrong. Try again.";
    }
  },

  /** A friend request's result, as the player reads it. */
  requestResult(result: string, username: string): string {
    switch (result) {
      case "accepted": return `You and ${username} are now friends.`;
      case "already_friends": return `You're already friends with ${username}.`;
      default: return `Friend request sent to ${username}.`;
    }
  },
} as const;

/** What the search field sends: at least two letters, digits or underscores (the server returns nothing otherwise). */
export const PlayerSearchRules = {
  minimumLength: 2,
  maximumLength: 20,
  normalized(text: string): string | undefined {
    const trimmed = trimSpaces(text);
    return trimmed.length >= PlayerSearchRules.minimumLength && trimmed.length <= PlayerSearchRules.maximumLength && usernamePattern.test(trimmed)
      ? trimmed : undefined;
  },
} as const;

/** Who may open a player's profile. Public by default; the server enforces it (mm_public_profile). */
export type ProfileVisibility = "public" | "friends" | "private";
export const ProfileVisibility = {
  all: ["public", "friends", "private"] as ProfileVisibility[],
  parse: (raw: unknown): ProfileVisibility | undefined => (ProfileVisibility.all.includes(raw as ProfileVisibility) ? (raw as ProfileVisibility) : undefined),
  title: (v: ProfileVisibility) => ({ public: "Public", friends: "Friends only", private: "Private" })[v],
  /** What the choice means, in a line. */
  detail: (v: ProfileVisibility) => ({
    public: "Any player can open your profile, with your rank and recent games.",
    friends: "Only your friends can open your profile.",
    private: "Nobody but you can open your profile. Friends still see when you're online.",
  })[v],
} as const;

// MARK: Wire parsing

const malformed = () => new Error("malformed");
/** NSNumber's intValue: any JSON number, truncated. */
const num = (value: J | undefined): number | undefined => (typeof value === "number" ? Math.trunc(value) : undefined);
const optional = <T>(value: J | undefined, read: (value: J | undefined) => T | undefined): T | undefined => {
  if (value === undefined || value === null) return undefined;
  const result = read(value);
  if (result === undefined) throw malformed();
  return result;
};
const required = <T>(value: J | undefined, read: (value: J | undefined) => T | undefined): T => {
  const result = read(value);
  if (result === undefined) throw malformed();
  return result;
};
const strings = (value: J | undefined): string[] | undefined => {
  const list = arr(value);
  return list && list.every((item) => typeof item === "string") ? (list as string[]) : undefined;
};

/** PostgREST timestamps: "2026-10-05T12:30:00+00:00", with or without fractions, as milliseconds since 1970. */
export function parseTimestamp(text: string): number | undefined {
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})$/i.exec(text);
  if (!match) return undefined;
  const millis = match[2] === undefined ? "" : `.${match[2].slice(0, 3).padEnd(3, "0")}`;
  const zone = match[3].toUpperCase() === "Z" ? "Z" : match[3].includes(":") ? match[3] : `${match[3].slice(0, 3)}:${match[3].slice(3)}`;
  const value = Date.parse(`${match[1]}${millis}${zone}`);
  return Number.isNaN(value) ? undefined : value;
}
const timestamp = (value: J | undefined) => (typeof value === "string" ? parseTimestamp(value) : undefined);

/** "2026-10-05" as that day's 00:00 UTC. */
const day = (text: string): number | undefined => {
  const parts = text.split("-").filter((piece) => /^[+-]?\d+$/.test(piece)).map(Number);
  return parts.length === 3 ? Date.UTC(parts[0], parts[1] - 1, parts[2]) : undefined;
};

// MARK: Friends

/** One row of mm_friends(): a friend, or a request either way. */
export interface PlayerFriend {
  id: string;
  username: string;
  /** friend, incoming or outgoing. */
  relation: string;
  online: boolean;
  lastSeenAt?: number;
  platform?: string;
  hostingCode?: string;
  hostingOpenSeats?: number;
}

export const PlayerFriend = {
  isFriend: (f: PlayerFriend) => f.relation === "friend",
  isIncoming: (f: PlayerFriend) => f.relation === "incoming",
  isOutgoing: (f: PlayerFriend) => f.relation === "outgoing",
  withRelation: (f: PlayerFriend, relation: string): PlayerFriend => ({ ...f, relation, online: relation === "friend" ? f.online : false }),
  /** A table this online friend is hosting with a seat still open. */
  joinableCode(f: PlayerFriend): string | undefined {
    if (f.relation !== "friend" || !f.online || f.hostingCode === undefined || (f.hostingOpenSeats ?? 0) <= 0) return undefined;
    return TableJoinLink.normalized(f.hostingCode);
  },
  /** Throws on a malformed row, like the Swift decoder. */
  decodeList(json: J): PlayerFriend[] {
    return required(json, arr).map((row) => {
      const hostingOpenSeats = optional(get(row, "hosting_open_seats"), int);
      const lastSeenAt = optional(get(row, "last_seen_at"), timestamp);
      const platform = optional(get(row, "platform"), str);
      const hostingCode = optional(get(row, "hosting_code"), str);
      return {
        id: required(get(row, "id"), (v) => (isUuid(v) ? v : undefined)),
        username: required(get(row, "username"), str), relation: required(get(row, "relation"), str), online: required(get(row, "online"), bool),
        ...(lastSeenAt !== undefined ? { lastSeenAt } : {}), ...(platform !== undefined ? { platform } : {}),
        ...(hostingCode !== undefined ? { hostingCode } : {}), ...(hostingOpenSeats !== undefined ? { hostingOpenSeats } : {}),
      };
    });
  },
} as const;

/** Another player's public ranked card (mm_profile_card). */
export interface PlayerProfileCard {
  username: string;
  season?: string;
  rankStep?: number;
  pips?: number;
  peakStep?: number;
  wins?: number;
  losses?: number;
  title?: string;
  favoriteCommander?: string;
}

export const PlayerProfileCard = {
  parse(json: J): PlayerProfileCard {
    const card: PlayerProfileCard = { username: required(get(json, "username"), str) };
    for (const key of ["season", "title", "favoriteCommander"] as const) { const v = optional(get(json, key), str); if (v !== undefined) card[key] = v; }
    for (const key of ["rankStep", "pips", "peakStep", "wins", "losses"] as const) { const v = optional(get(json, key), int); if (v !== undefined) card[key] = v; }
    return card;
  },
  /** This season's place, or undefined when unranked or from an earlier season. */
  position: (card: PlayerProfileCard, now: number = Date.now()) =>
    card.rankStep !== undefined && card.season === RankLadder.season(now) ? RankPosition.published(card.rankStep, card.pips ?? 0) : undefined,
} as const;

// MARK: Public profiles and search

export interface PublicProfileRank { season: string; step: number; pips: number; peakStep: number; wins: number; losses: number }

/** Another player's profile, as mm_public_profile returns it. */
export interface PublicProfile {
  username: string;
  /** Set when the viewer may not open it: private, or friends-only for a stranger. */
  restricted: boolean;
  visibility: ProfileVisibility;
  /** self, friend, outgoing, incoming or none. */
  relation: string;
  online?: boolean;
  title?: string;
  favoriteCommander?: string;
  rank?: PublicProfileRank;
  summary: ProfileSummary;
  games: ProfileGame[];
  /** Finished seasons at their peak, newest first (mm_public_profile `seasons`). */
  seasons: SeasonBadge[];
  /** Best first (mm_public_profile `awards`). */
  awards: Award[];
}

export const PublicProfile = {
  isSelf: (p: PublicProfile) => p.relation === "self",
  isFriend: (p: PublicProfile) => p.relation === "friend",
  /** This season's place, or undefined when it is from an earlier season. */
  rankPosition: (rank: PublicProfileRank, now: number = Date.now()) =>
    rank.season === RankLadder.season(now) ? RankPosition.published(rank.step, rank.pips) : undefined,

  /** Reads the server's JSON. Missing parts come out empty rather than failing the screen. `now` fixes empty weeks. */
  parse(root: J, now: number = Date.now()): PublicProfile {
    const username = str(get(root, "username"));
    if (!isObject(root) || username === undefined) throw malformed();
    const visibility = ProfileVisibility.parse(root.visibility) ?? "public";
    const relation = str(root.relation) ?? "none";
    if (root.restricted === true) {
      return { username, restricted: true, visibility, relation, summary: ProfileSummary.fromGames([], now), games: [], seasons: [], awards: [] };
    }
    let rank: PublicProfileRank | undefined;
    const r = root.rank;
    const season = str(get(r, "season")), step = num(get(r, "step"));
    if (isObject(r) && season !== undefined && step !== undefined) {
      rank = { season, step, pips: num(r.pips) ?? 0, peakStep: num(r.peakStep) ?? step, wins: num(r.wins) ?? 0, losses: num(r.losses) ?? 0 };
    }
    const rows = (value: J | undefined): JObject[] => (arr(value) ?? []).filter(isObject);
    const shares = (list: JObject[], key: string) => list.flatMap((row) => {
      const id = str(row[key]);
      return id === undefined ? [] : [{ id, games: num(row.games) ?? 0, wins: num(row.wins) ?? 0 }];
    });
    const weeks = rows(root.weekly).flatMap((row) => {
      const start = typeof row.week === "string" ? day(row.week) : undefined;
      return start === undefined ? [] : [{ start, games: num(row.games) ?? 0, wins: num(row.wins) ?? 0 }];
    });
    const rankPoints = rows(root.rankHistory).flatMap((row) => {
      const date = timestamp(row.at), points = num(row.points);
      return date === undefined || points === undefined ? [] : [{ date, points }];
    });
    const stats = isObject(root.stats) ? root.stats : {};
    const averageTurns = typeof stats.avgTurns === "number" ? stats.avgTurns : undefined;
    const summary: ProfileSummary = {
      games: num(stats.games) ?? 0, wins: num(stats.wins) ?? 0, losses: num(stats.losses) ?? 0, draws: num(stats.draws) ?? 0,
      currentStreak: num(stats.currentStreak) ?? 0, bestStreak: num(stats.bestStreak) ?? 0,
      ...(averageTurns !== undefined ? { averageTurns } : {}),
      weeks: weeks.length === 0 ? ProfileSummary.emptyWeeks(now) : weeks,
      commanders: shares(rows(root.commanders), "name"), colors: shares(rows(root.colors), "color"), rankPoints,
    };
    const games = rows(root.games).flatMap((row): ProfileGame[] => {
      const id = str(row.id), date = timestamp(row.playedAt);
      const mode = (["quick", "ranked", "casual"] as PlayMode[]).find((m) => m === row.mode);
      const outcome = (["win", "loss", "draw"] as RankOutcome[]).find((o) => o === row.result);
      if (id === undefined || date === undefined || mode === undefined || outcome === undefined) return [];
      const opponents = rows(row.opponents).flatMap((item) => {
        const name = str(item.name);
        if (name === undefined) return [];
        const commander = str(item.commander);
        return [{ name, ...(commander !== undefined ? { commander } : {}), isAI: bool(item.ai) ?? true, hidden: bool(item.hidden) ?? false }];
      });
      const turns = num(row.turns);
      return [{
        id, date, mode, outcome, deckName: str(row.deckName) ?? "", commanders: strings(row.commanders) ?? [], colors: strings(row.colors) ?? [],
        opponents, ...(turns !== undefined ? { turns } : {}),
      }];
    });
    const seasons = rows(root.seasons).flatMap((row): SeasonBadge[] => {
      const season = str(row.season), peak = num(row.peakPoints);
      return season === undefined || peak === undefined ? [] : [{ season, peak: RankPosition.fromPoints(peak), inProgress: false }];
    });
    const online = bool(root.online), title = str(root.title), favoriteCommander = str(root.favoriteCommander);
    return {
      username, restricted: false, visibility, relation,
      ...(online !== undefined ? { online } : {}), ...(title !== undefined ? { title } : {}),
      ...(favoriteCommander !== undefined ? { favoriteCommander } : {}), ...(rank ? { rank } : {}), summary, games, seasons, awards: Award.parse(root.awards),
    };
  },
} as const;

/**
 * An award on a profile (mm_my_awards, mm_public_profile `awards`; Caleb, 2026-10-30): a medal that lives on the server,
 * art included, so a new one needs no deploy (docs/SERVER_CONTROLS.md). iOS's AwardViews.swift and Android's Award match it.
 */
export interface Award {
  id: string;
  name: string;
  detail: string;
  /** The medal's art; without it, or if it can't load, a star medal in `tint`. */
  imageUrl?: string;
  /** "#RRGGBB". */
  tint: string;
  /** 1 plain, 2 a soft glow, 3 a strong glow and a gold ring. */
  rarity: number;
  note?: string;
  awardedAt?: number;
  /** A trophy, which stands on the Trophies shelf rather than among the awards. */
  shelf: boolean;
  /** False until the player's app has shown it, which it does with a ceremony. */
  seen: boolean;
}

export const Award = {
  gold: "#FFCC5C",
  /** The rows from the server; one without an id or a name is skipped. */
  parse(value: J | undefined): Award[] {
    return (arr(value) ?? []).filter(isObject).flatMap((row): Award[] => {
      const id = str(row.id), name = str(row.name);
      if (!id || !name) return [];
      const imageUrl = str(row.imageUrl), tint = str(row.tint), note = str(row.note), at = Date.parse(str(row.awardedAt) ?? "");
      return [{
        id, name, detail: str(row.description) ?? "", tint: tint && /^#[0-9a-f]{6}$/i.test(tint) ? tint : Award.gold,
        rarity: Math.min(Math.max(num(row.rarity) ?? 1, 1), 3), shelf: bool(row.shelf) ?? false, seen: bool(row.seen) ?? true,
        ...(imageUrl?.startsWith("https://") ? { imageUrl } : {}), ...(note ? { note } : {}), ...(Number.isNaN(at) ? {} : { awardedAt: at }),
      }];
    });
  },
  /** The award's note and the day it was earned. */
  caption: (award: Award) => [award.note, award.awardedAt === undefined ? undefined
    : new Date(award.awardedAt).toLocaleDateString(undefined, { dateStyle: "medium" })].filter(Boolean).join(" · "),
} as const;

/** What opening another player's profile came to. */
export type PublicProfileResult =
  | { kind: "profile"; profile: PublicProfile }
  /** No such player, or one that blocked you (or whom you blocked): the server says the same for both. */
  | { kind: "notFound" }
  /** The server doesn't have public profiles yet. */
  | { kind: "unavailable" }
  | { kind: "failed"; message: string };

/** A player found by typing the start of a name (mm_search_players). */
export interface PlayerSearchResult {
  username: string;
  favoriteCommander?: string;
  season?: string;
  rankStep?: number;
  pips?: number;
  visibility: ProfileVisibility;
  /** friend, outgoing, incoming or none. */
  relation: string;
  online?: boolean;
}

export const PlayerSearchResult = {
  position: (r: PlayerSearchResult, now: number = Date.now()) =>
    r.rankStep !== undefined && r.season === RankLadder.season(now) ? RankPosition.published(r.rankStep, r.pips ?? 0) : undefined,
  parse(json: J): PlayerSearchResult[] {
    return required(json, arr).filter(isObject).flatMap((row): PlayerSearchResult[] => {
      const username = str(row.username);
      if (username === undefined) return [];
      const favoriteCommander = str(row.favorite_commander), season = str(row.season), rankStep = num(row.rank_step), pips = num(row.pips);
      const online = bool(row.online);
      return [{
        username, ...(favoriteCommander !== undefined ? { favoriteCommander } : {}), ...(season !== undefined ? { season } : {}),
        ...(rankStep !== undefined ? { rankStep } : {}), ...(pips !== undefined ? { pips } : {}),
        visibility: ProfileVisibility.parse(row.visibility) ?? "public", relation: str(row.relation) ?? "none",
        ...(online !== undefined ? { online } : {}),
      }];
    });
  },
} as const;

// MARK: Messages between friends

/** One message in a conversation. */
export interface FriendMessage { id: number; body: string; sentAt: number; fromMe: boolean; read: boolean }
/** A conversation with a friend: the last message and how many of theirs are unread. */
export interface MessageConversation { username: string; unread: number; last: FriendMessage }
/** A page of one conversation, oldest first. */
export interface MessageThread { username: string; messages: FriendMessage[]; hasMore: boolean }

const parseMessage = (json: J | undefined): FriendMessage => ({
  id: required(get(json, "id"), int), body: required(get(json, "body"), str), sentAt: required(get(json, "sentAt"), timestamp),
  fromMe: required(get(json, "fromMe"), bool), read: required(get(json, "read"), bool),
});

export const FriendMessageRules = {
  /** Unicode scalars in one message (the server allows 500 characters). */
  maxScalars: 500,
  /** How often an open conversation asks for new messages. */
  pollSeconds: 5,

  /** What gets sent: one tidy line, or nothing. */
  sanitize: (raw: string) => TableChatText.sanitize(raw, FriendMessageRules.maxScalars),
  /** A friend's message as shown: strong language masked, like table chat. Your own show as typed. */
  shown: (message: FriendMessage) => (message.fromMe ? message.body : TableChatFilter.filtered(message.body)),

  /** A newer page merged into what's on screen: one copy of each message, oldest first. */
  merged(existing: readonly FriendMessage[], page: readonly FriendMessage[]): FriendMessage[] {
    const byID = new Map<number, FriendMessage>();
    for (const message of [...existing, ...page]) byID.set(message.id, message);
    return [...byID.values()].sort((a, b) => a.id - b.id);
  },

  /**
   * Friends ordered for the Messages tab: conversations by their last message (newest first), then friends you haven't
   * written to yet, alphabetically.
   */
  ordered(friends: readonly string[], conversations: readonly MessageConversation[]): { name: string; conversation?: MessageConversation }[] {
    const byName = new Map<string, MessageConversation>();
    for (const c of conversations) if (!byName.has(c.username)) byName.set(c.username, c);
    const talked = conversations.filter((c) => friends.includes(c.username)).sort((a, b) => b.last.id - a.last.id)
      .map((c) => ({ name: c.username, conversation: c }));
    const quiet = friends.filter((name) => !byName.has(name))
      .sort((a, b) => { const x = a.toLowerCase(), y = b.toLowerCase(); return x < y ? -1 : x > y ? 1 : 0; })
      .map((name) => ({ name }));
    return [...talked, ...quiet];
  },

  parseMessage: (json: J): FriendMessage => parseMessage(json),
  parseConversations: (json: J): MessageConversation[] => required(json, arr).map((row) => ({
    username: required(get(row, "username"), str), unread: required(get(row, "unread"), int), last: parseMessage(get(row, "last")),
  })),
  parseThread: (json: J): MessageThread => ({
    username: required(get(json, "username"), str), messages: required(get(json, "messages"), arr).map(parseMessage),
    hasMore: required(get(json, "hasMore"), bool),
  }),
} as const;

// MARK: Ranked standing on the server

export interface RankedSeason { season: string; finalPoints: number; peakPoints: number; wins: number; losses: number }

/**
 * The ladder as the server keeps it (mm_ranked_standing). Once the player has a profile the server decides rank: the
 * browser shows its own result at once, then takes this.
 */
export interface RankedStanding {
  /** False only for a new server standing that has never counted a result: the browser may seed it once. */
  seeded: boolean;
  /** Matches this player reported that the other side hasn't yet. */
  unsettled: number;
  season: string;
  points: number;
  peakPoints: number;
  wins: number;
  losses: number;
  draws: number;
  winStreak: number;
  /** Placement matches still to play; absent from a server before placements. */
  placementLeft?: number;
  history?: RankedSeason[];
  /** How the result just sent counted (mm_ranked_ai_result): counted, too_soon, capped, unverified or abandoned. */
  settlement?: string;
  /** The server's move on the ladder for that result (absent when it didn't count, or was already settled). */
  change?: ServerRankChange;
  /** Why a win settled unverified: too_short, too_fast, no_record, … */
  check?: string;
}

export const RankedStanding = {
  parse(json: J): RankedStanding {
    const n = (key: string) => required(get(json, key), int);
    const history = optional(get(json, "history"), arr)?.map((row) => ({
      season: required(get(row, "season"), str), finalPoints: required(get(row, "finalPoints"), int),
      peakPoints: required(get(row, "peakPoints"), int), wins: required(get(row, "wins"), int), losses: required(get(row, "losses"), int),
    }));
    const settlement = optional(get(json, "settlement"), str);
    const check = optional(get(json, "check"), str);
    // A change without its points (an older server's) is left out rather than losing the standing with it.
    const moved = get(json, "change");
    const pointsBefore = int(get(moved, "pointsBefore")), pointsAfter = int(get(moved, "pointsAfter")), bonuses = strings(get(moved, "bonuses"));
    const movedLeft = int(get(moved, "placementLeft")), placementLeft = optional(get(json, "placementLeft"), int);
    const change: ServerRankChange | undefined = pointsBefore !== undefined && pointsAfter !== undefined
      ? { pointsBefore, pointsAfter, ...(bonuses ? { bonuses } : {}), ...(movedLeft !== undefined ? { placementLeft: movedLeft } : {}) } : undefined;
    return {
      seeded: required(get(json, "seeded"), bool), unsettled: n("unsettled"), season: required(get(json, "season"), str), points: n("points"),
      peakPoints: n("peakPoints"), wins: n("wins"), losses: n("losses"), draws: n("draws"), winStreak: n("winStreak"),
      ...(placementLeft !== undefined ? { placementLeft } : {}),
      ...(history ? { history } : {}), ...(settlement !== undefined ? { settlement } : {}),
      ...(change ? { change } : {}), ...(check !== undefined ? { check } : {}),
    };
  },
} as const;

const positionsEqual = RankPosition.equal;
const rankEqual = (a: RankState, b: RankState) =>
  a.season === b.season && positionsEqual(a.position, b.position) && positionsEqual(a.peak, b.peak) && a.wins === b.wins &&
  a.losses === b.losses && a.draws === b.draws && a.winStreak === b.winStreak && a.placementGames === b.placementGames &&
  a.history.length === b.history.length &&
  a.history.every((s, i) => {
    const t = b.history[i];
    return s.season === t.season && positionsEqual(s.final, t.final) && positionsEqual(s.peak, t.peak) && s.wins === t.wins && s.losses === t.losses;
  });

/**
 * PlayerRecordStore.adopt: the server's standing applied to the browser's rank, or undefined when nothing changes. Kept
 * back while a result is still on its way (a friend match the other side hasn't reported, or an AI result not sent yet),
 * so a pip just earned never flickers away. An older season from the server never replaces a newer one here.
 */
export function adoptStanding(rank: RankState, standing: RankedStanding, pendingResults = 0): RankState | undefined {
  if (standing.unsettled !== 0 || pendingResults > 0 || standing.season < rank.season) return undefined;
  const base = standing.season === rank.season ? rank : RankLadder.rollover(rank, standing.season);
  const position = RankPosition.fromPoints(standing.points);
  let history: SeasonRecord[] = [...base.history];
  // The server's past seasons replace the browser's for the same month.
  for (const record of standing.history ?? []) {
    const season: SeasonRecord = {
      season: record.season, final: RankPosition.fromPoints(record.finalPoints), peak: RankPosition.fromPoints(record.peakPoints),
      wins: record.wins, losses: record.losses,
    };
    const index = history.findIndex((s) => s.season === record.season);
    if (index >= 0) history[index] = season; else history.push(season);
  }
  history = history.sort((a, b) => (a.season > b.season ? -1 : a.season < b.season ? 1 : 0)).slice(0, 24);
  const next: RankState = {
    ...base, position, peak: RankPosition.max(RankPosition.fromPoints(standing.peakPoints), position),
    wins: standing.wins, losses: standing.losses, draws: standing.draws, winStreak: standing.winStreak, history,
    ...(standing.placementLeft !== undefined ? { placementGames: standing.placementLeft } : {}),
  };
  return rankEqual(next, rank) ? undefined : next;
}

/** A ranked game against the AI whose result the server hasn't confirmed yet (mm_ranked_ai_result). */
export interface PendingRankedResult {
  ticket: string;
  outcome: RankOutcome;
  date: number;
  /** The ticket carried a server seed (mm_ranked_ai_start2): the result goes with the game record. */
  seeded?: boolean;
  /** The game record's name, when the engine kept one. */
  recordFile?: string;
}

/** What syncRank reads and changes: the iOS PlayerRecordStore's server parts. */
export interface RankedRecord {
  readonly rank: RankState;
  /** Finished ranked AI games still to send, oldest first. */
  readonly pendingRankedResults: readonly PendingRankedResult[];
  /** The server answered for this ticket (or never will). */
  resolvePendingRankedResult(ticket: string): void;
  gameRecord(name: string): J | undefined;
  /** The server's word on a sent result: how it counted and its own move on the ladder (PlayerRecordStore.settleRanked). */
  settleRanked?(ticket: string, settlement: string | undefined, check: string | undefined, change: ServerRankChange | undefined, points?: number): void;
  /** Takes the server's standing (see adoptStanding). */
  adopt(standing: RankedStanding): void;
}

/**
 * The web's PlayerRecordStore as a RankedRecord. The web record keeps no AI tickets yet, so nothing is pending; the
 * store has no setter for its rank, so `onAdopt` receives the adopted rank to keep (until it does, nothing is kept).
 */
export function rankedRecord(store: PlayerRecordStore, onAdopt?: (rank: RankState) => void): RankedRecord {
  return {
    get rank() { return store.rank; },
    pendingRankedResults: [],
    resolvePendingRankedResult: () => {},
    gameRecord: () => undefined,
    adopt(standing) {
      const next = adoptStanding(store.rank, standing, 0);
      if (next) onAdopt?.(next);
    },
  };
}

export type RankedLeaderboardScope = "everyone" | "friends";

export interface RankedLeaderboardEntry {
  position: number;
  username: string;
  title?: string;
  commander?: string;
  points: number;
  wins: number;
  losses: number;
  online: boolean;
  you: boolean;
  /** Straight wins right now; absent from a server before 2026-10-27. */
  streak?: number;
}

/**
 * The season leaderboard from the server's standings (mm_ranked_leaderboard): everyone or friends, private profiles and
 * blocked players already left out by the server, plus the caller's own row.
 */
export interface RankedLeaderboard {
  season: string;
  scope: string;
  total: number;
  online: number;
  entries: RankedLeaderboardEntry[];
  me?: RankedLeaderboardEntry;
  /** Last season's top three (the champions); absent from a server before 2026-10-27. */
  champions?: { season: string; entries: RankedLeaderboardEntry[] };
}

const parseEntry = (row: J | undefined): RankedLeaderboardEntry => {
  const title = optional(get(row, "title"), str), commander = optional(get(row, "commander"), str);
  const streak = optional(get(row, "streak"), int);
  return {
    position: required(get(row, "position"), int), username: required(get(row, "username"), str),
    ...(title !== undefined ? { title } : {}), ...(commander !== undefined ? { commander } : {}),
    points: required(get(row, "points"), int), wins: required(get(row, "wins"), int), losses: required(get(row, "losses"), int),
    online: required(get(row, "online"), bool), you: required(get(row, "you"), bool),
    ...(streak !== undefined ? { streak } : {}),
  };
};

/** A champion's row: its step and pips instead of points, never online. */
const parseChampion = (row: J | undefined): RankedLeaderboardEntry => {
  const commander = optional(get(row, "commander"), str);
  return {
    position: required(get(row, "position"), int), username: required(get(row, "username"), str), ...(commander !== undefined ? { commander } : {}),
    points: RankPosition.points(RankPosition.published(required(get(row, "step"), int), required(get(row, "pips"), int))),
    wins: required(get(row, "wins"), int), losses: required(get(row, "losses"), int), online: false, you: required(get(row, "you"), bool),
  };
};

export const RankedLeaderboard = {
  scopes: ["everyone", "friends"] as RankedLeaderboardScope[],
  parse(json: J): RankedLeaderboard {
    const me = get(json, "me"), champions = get(json, "champions");
    return {
      season: required(get(json, "season"), str), scope: required(get(json, "scope"), str), total: required(get(json, "total"), int),
      online: required(get(json, "online"), int), entries: required(get(json, "entries"), arr).map(parseEntry),
      ...(me !== undefined && me !== null ? { me: parseEntry(me) } : {}),
      ...(champions !== undefined && champions !== null
        ? { champions: { season: required(get(champions, "season"), str), entries: required(get(champions, "entries"), arr).map(parseChampion) } } : {}),
    };
  },
  rank: (entry: RankedLeaderboardEntry) => RankPosition.fromPoints(entry.points),
  /** The caller's row is pinned at the foot when it isn't among the shown entries. */
  pinnedMe: (board: RankedLeaderboard) =>
    board.me && !board.entries.some((e) => e.username === board.me!.username) ? board.me : undefined,
} as const;

/**
 * The server's ticket for a ranked AI game and the seed the engine plays it with (mm_ranked_ai_start2). `ai` is the AI the
 * server tuned for this game (ranked_ai_tuning): its skill, deliberate-mistake chance and the AI deck's Power target.
 * Absent from servers before that tuning, when the tier's bundled values apply.
 */
export interface RankedAITicket { id: string; seed: bigint; ai?: { skill: number; mistakePercent: number; power: number } }

/**
 * `{"id": uuid, "seed": "<64-bit decimal>", "aiSkill": 3, "aiMistakePercent": 8, "aiPower": 5.63}` (the seed is text:
 * JSON numbers lose precision past 2^53). The AI fields count only together and in the engine's ranges.
 */
export function rankedAITicket(json: J): RankedAITicket | undefined {
  const id = get(json, "id"), seed = get(json, "seed");
  if (!isUuid(id) || typeof seed !== "string" || !/^[+-]?\d+$/.test(seed)) return undefined;
  const value = BigInt(seed);
  if (value < -(2n ** 63n) || value >= 2n ** 63n) return undefined;
  const skill = get(json, "aiSkill"), mistakePercent = get(json, "aiMistakePercent"), power = get(json, "aiPower");
  const tuned = Number.isInteger(skill) && (skill as number) >= 1 && (skill as number) <= 10
    && Number.isInteger(mistakePercent) && (mistakePercent as number) >= 0 && (mistakePercent as number) <= 100
    && typeof power === "number" && Number.isFinite(power);
  return { id, seed: value, ...(tuned ? { ai: { skill: skill as number, mistakePercent: mistakePercent as number, power: power as number } } : {}) };
}

// MARK: Ranked queue and friend challenges (types only: the services are ported with their screens)

/** One ranked queue ticket as the server reports it (mm_ranked_*). */
export interface RankedTicket {
  ticket?: string;
  status: string;
  matchId?: string;
  /** "host" opens the relay table, "guest" joins it. */
  role?: string;
  tableCode?: string;
  opponent?: string;
  opponentStep?: number;
}

/** The server calls ranked play makes. */
export interface RankedQueueService {
  enqueue(protocol: string, rankStep: number, deckBracket: number): Promise<RankedTicket>;
  poll(ticket: string): Promise<RankedTicket>;
  cancel(ticket: string): Promise<RankedTicket>;
  setTable(match: string, code: string): Promise<void>;
  report(match: string, outcome: RankOutcome): Promise<void>;
}

/** A friend challenge as the server reports it (mm_challenge_*). */
export interface FriendChallenge {
  id: string;
  /** "quick" or "ranked". */
  mode: string;
  /** pending, accepted, declined, cancelled or expired. */
  status: string;
  role?: string;
  challenger?: string;
  challenged?: string;
  challengerStep?: number;
  /** The relay identity the challenger's table needs. */
  protocol?: string;
  /** Only after accepting, for the friend. */
  tableCode?: string;
  /** The ranked match both sides report to (ranked challenges only). */
  matchId?: string;
}

export interface FriendChallengeService {
  send(username: string, mode: PlayMode, protocol: string, rankStep: number, tableCode: string): Promise<FriendChallenge>;
  incoming(): Promise<FriendChallenge[]>;
  status(id: string): Promise<FriendChallenge>;
  accept(id: string, protocol: string, rankStep: number): Promise<FriendChallenge>;
  decline(id: string): Promise<void>;
  cancel(id: string): Promise<FriendChallenge>;
}

// MARK: Game uploads

/** What sending a finished game to the profile server came to. */
export type GameUploadResult =
  /** Stored, or already there. */
  | "sent"
  /** Offline, rate limited or not signed in: try again later. */
  | "retryLater"
  /** The server refused this game for good; sending it again would fail the same way. */
  | "rejected"
  /** The server doesn't record games yet, or there is no profile name: nothing to retry now. */
  | "unavailable";

/**
 * Sends this browser's finished games to the profile server (mm_record_game). The browser's record is the source of
 * truth: a game counts as sent once the server confirmed it, and any recent game not yet confirmed is tried again
 * whenever the page is open and online. Sending never blocks play and never throws.
 */
export class GameUploader {
  /** The newest games considered each time: older ones stay in the browser. */
  static readonly window = 60;
  /** At most this many go in one pass (the server allows 100 an hour). */
  static readonly perPass = 40;
  static readonly keep = 400;
  static readonly key = "mm.web.uploadedGames";

  private sent: string[] = [];
  private running = false;

  constructor(private readonly store?: KeyValueStore, private readonly key = GameUploader.key) {
    try {
      const parsed: unknown = JSON.parse(store?.get(key) ?? "[]");
      if (Array.isArray(parsed)) this.sent = parsed.filter((id): id is string => typeof id === "string");
    } catch { /* a malformed list only means a few games are sent again */ }
  }

  /** The recent games the server hasn't confirmed, oldest first. `matches` is newest first, like the record. */
  pending(matches: readonly MatchRecord[]): MatchRecord[] {
    const confirmed = new Set(this.sent);
    return matches.slice(0, GameUploader.window).filter((match) => !confirmed.has(match.id)).reverse();
  }

  /**
   * Sends what is pending, oldest first, and stops at the first game that could not be sent for now. Returns how many
   * the server confirmed. A pass already running makes this one a no-op.
   */
  async flush(matches: readonly MatchRecord[], send: (match: MatchRecord) => Promise<GameUploadResult>): Promise<number> {
    if (this.running) return 0;
    this.running = true;
    let confirmed = 0;
    try {
      for (const match of this.pending(matches).slice(0, GameUploader.perPass)) {
        const result = await send(match);
        if (result === "sent") { this.sent.push(match.id); confirmed += 1; }
        else if (result === "rejected") this.sent.push(match.id);
        else break;
      }
    } finally {
      this.save();
      this.running = false;
    }
    return confirmed;
  }

  private save() {
    if (this.sent.length > GameUploader.keep) this.sent.splice(0, this.sent.length - GameUploader.keep);
    // A failed save only means a few games are sent again; the server stores each once.
    try { this.store?.set(this.key, JSON.stringify(this.sent)); } catch { /* storage blocked */ }
  }
}

// MARK: The account

export type AccountPhase = "idle" | "loading" | "ready" | "unavailable";

export interface Hosting { code: string; openSeats: number }

export interface AccountState {
  phase: AccountPhase;
  username?: string;
  friends: PlayerFriend[];
  /** This player's awards, best first (mm_my_awards). */
  awards: Award[];
  /** The Trophies shelf's server rows (mm_trophies): every trophy, with `awardedAt` on the ones this player holds. */
  trophies: Award[];
  blocked: string[];
  /** Friends' ranked standings by username (mm_friend_ranks), for their badges. */
  friendRanks: Record<string, RankPosition>;
  /** Who may open this player's profile (mm_profile). `visibilityKnown` is false on a server that predates the setting. */
  visibility: ProfileVisibility;
  visibilityKnown: boolean;
  /** False once the server has said it has no player search / public profiles yet: the screens fall back gently. */
  searchAvailable: boolean;
  profilesAvailable: boolean;
  /** Unread messages from friends: the badge on the Friends button. */
  unreadMessages: number;
  /** False on a server without friend messages yet. */
  messagesAvailable: boolean;
  notice?: string;
  /** Google or Apple sign-ins on this account; empty while the profile lives only in this browser (anonymous). */
  linkedIdentities: LinkedIdentity[];
  isSigningIn: boolean;
  /** The table this player hosts while it still has open seats (shared with friends). */
  hosting?: Hosting;
  /** Derived from `friends`. */
  incomingCount: number;
  onlineFriendCount: number;
}

const initialState = (): AccountState => ({
  phase: "idle", friends: [], awards: [], trophies: [], blocked: [], friendRanks: {}, visibility: "public", visibilityKnown: false, searchAvailable: true,
  profilesAvailable: true, unreadMessages: 0, messagesAvailable: true, linkedIdentities: [], isSigningIn: false, incomingCount: 0,
  onlineFriendCount: 0,
});

/** A search that a newer one replaced (typing in the search field), not a failure. */
export class SearchCancelled extends Error {
  constructor() { super("cancelled"); this.name = "SearchCancelled"; }
}

export interface PlayerAccountOptions {
  api: SupabaseLite;
  /** Milliseconds since 1970; defaults to Date.now. */
  now?: () => number;
  /**
   * mm_heartbeat's p_platform. The server accepts only "ios", "android" or null (anything else raises invalid_platform),
   * so the web sends null.
   */
  platform?: "ios" | "android" | null;
  /** Runs `run` after `ms` and returns its cancel; defaults to setTimeout. */
  schedule?: (run: () => void, ms: number) => () => void;
}

const prefix = (text: string, count: number) => [...text].slice(0, count).join("");
const code = (error: unknown) => SupabaseLite.code(error);

export class PlayerAccount {
  /** Presence while the page is open: once now, then every 45 seconds, with friends refreshed. */
  static readonly heartbeatInterval = 45_000;
  /** How long a ranked AI game waits for its server ticket. */
  static readonly rankedAITimeout = 4_000;

  state: AccountState = initialState();
  version = 0;
  /** Runs after each refresh while the page is open: the web sends games that could not be sent before. */
  afterRefresh?: () => Promise<void> | void;

  readonly api: SupabaseLite;
  private readonly now: () => number;
  private readonly platform: "ios" | "android" | null;
  private readonly schedule: (run: () => void, ms: number) => () => void;
  private listeners = new Set<() => void>();
  private foregroundRun = 0;
  private cancelBeat?: () => void;
  private starting?: Promise<void>;
  private searchRun = 0;

  constructor(options: PlayerAccountOptions) {
    this.api = options.api;
    this.now = options.now ?? Date.now;
    this.platform = options.platform ?? null;
    this.schedule = options.schedule ?? ((run, ms) => { const timer = setTimeout(run, ms); return () => clearTimeout(timer); });
  }

  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  private changed() { this.version += 1; this.listeners.forEach((listener) => listener()); }
  private set(patch: Partial<AccountState>) {
    const next = { ...this.state, ...patch };
    for (const key of Object.keys(patch) as (keyof AccountState)[]) if (patch[key] === undefined) delete (next as Partial<AccountState>)[key];
    next.incomingCount = next.friends.filter(PlayerFriend.isIncoming).length;
    next.onlineFriendCount = next.friends.filter((f) => PlayerFriend.isFriend(f) && f.online).length;
    this.state = next;
    this.changed();
  }
  private fail(error: unknown) { this.set({ notice: PlayerAccountRules.message(code(error)) }); }
  private get hasName() { return this.state.phase === "ready" && this.state.username !== undefined; }

  setNotice(notice: string | undefined) { this.set({ notice }); }

  /**
   * Signs in (making the anonymous account on first use) and loads the profile. Safe to call often: a call while one is
   * loading waits for it, so the first heartbeat and rank sync see the profile's name.
   */
  start(): Promise<void> {
    if (this.starting) return this.starting;
    const running = this.load();
    this.starting = running;
    void running.finally(() => { if (this.starting === running) this.starting = undefined; });
    return running;
  }

  private async load(): Promise<void> {
    this.set({ phase: "loading" });
    try {
      const profile = await this.api.rpc("mm_profile");
      const visibility = ProfileVisibility.parse(get(profile, "visibility"));
      this.set({ username: str(get(profile, "username")), ...(visibility ? { visibility, visibilityKnown: true } : {}), phase: "ready" });
      try { this.set({ linkedIdentities: await this.api.linkedIdentities() }); } catch { /* keeps what it had */ }
      await this.refresh();
    } catch (error) {
      this.set({ phase: "unavailable", notice: PlayerAccountRules.message(code(error)) });
    }
  }

  async claim(name: string): Promise<boolean> {
    const trimmed = trimSpaces(name);
    if (!PlayerAccountRules.isValidUsername(trimmed)) { this.set({ notice: PlayerAccountRules.message("invalid_username") }); return false; }
    try {
      await this.api.rpc("mm_claim_username", { p_username: trimmed });
      this.set({ username: trimmed, notice: undefined });
      await this.heartbeat();
      return true;
    } catch (error) {
      this.fail(error);
      return false;
    }
  }

  /**
   * Keeps the profile with a Google or Apple account. The first time, the sign-in joins this browser's account, so its
   * name, friends and rank stay. If that account already has a profile (another device), this browser switches to it.
   */
  async signIn(provider: string, idToken: string, nonce: string | undefined): Promise<void> {
    if (this.state.isSigningIn) return;
    this.set({ isSigningIn: true });
    try {
      try {
        await this.api.signInWithIdToken(idToken, provider, nonce, true);
      } catch (error) {
        if (code(error) !== "identity_already_exists") throw error;
        await this.api.signInWithIdToken(idToken, provider, nonce, false);
      }
      // A load that began before the sign-in may still hold the old profile: let it end, then load the signed-in one.
      await this.starting?.catch(() => undefined);
      this.set({ phase: "idle" });
      await this.start();
      this.set({ notice: undefined });
    } catch (error) {
      this.fail(error);
    } finally {
      this.set({ isSigningIn: false });
    }
  }

  /** Signs out of Google or Apple here. The profile stays on the account; this browser starts a fresh one. */
  async signOut(): Promise<void> {
    this.api.forgetSession();
    this.set({
      username: undefined, friends: [], awards: [], trophies: [], blocked: [], friendRanks: {}, linkedIdentities: [], unreadMessages: 0, visibility: "public",
      visibilityKnown: false, phase: "idle",
    });
    await this.start();
  }

  async refresh(): Promise<void> {
    if (this.state.phase !== "ready") return;
    try {
      const friends = PlayerFriend.decodeList(await this.api.rpc("mm_friends"));
      this.set({ friends });
      const rows = arr(await this.api.rpc("mm_blocked")) ?? [];
      this.set({ blocked: rows.flatMap((row) => { const name = str(get(row, "username")); return name === undefined ? [] : [name]; }) });
    } catch (error) {
      this.fail(error);
    }
    // Messages are extra too: a server without them leaves the badge off.
    try {
      const count = int(await this.api.rpc("mm_message_unread"));
      if (count !== undefined) this.set({ unreadMessages: count });
    } catch { /* no badge */ }
    // Ranks are extra: a server without them leaves the badges off.
    try {
      const rows = arr(await this.api.rpc("mm_friend_ranks"));
      if (rows) {
        const season = RankLadder.season(this.now());
        const friendRanks: Record<string, RankPosition> = {};
        for (const row of rows) {
          const name = str(get(row, "username")), step = int(get(row, "rank_step")), pips = int(get(row, "pips"));
          if (name === undefined || step === undefined || pips === undefined || get(row, "season") !== season || name in friendRanks) continue;
          friendRanks[name] = RankPosition.published(step, pips);
        }
        this.set({ friendRanks });
      }
    } catch { /* no badges */ }
  }

  /** The code of the table this player hosts while it still has open seats; a change is sent at once. */
  setHosting(hosting: Hosting | undefined) {
    const old = this.state.hosting;
    if (old?.code === hosting?.code && old?.openSeats === hosting?.openSeats) return;
    this.set({ hosting });
    void this.heartbeat();
  }

  /** Presence while the page is open: once now, then every 45 seconds, with friends refreshed. */
  setForeground(active: boolean) {
    this.foregroundRun += 1;
    this.cancelBeat?.();
    this.cancelBeat = undefined;
    if (!active) return;
    const run = this.foregroundRun;
    const beat = async () => {
      if (run !== this.foregroundRun) return;
      await this.heartbeat();
      await this.refresh();
      await this.afterRefresh?.();
      if (run === this.foregroundRun) this.cancelBeat = this.schedule(() => { void beat(); }, PlayerAccount.heartbeatInterval);
    };
    void (async () => {
      if (this.state.phase !== "ready") await this.start();
      await beat();
    })();
  }

  async heartbeat(): Promise<void> {
    if (!this.hasName) return;
    const hosting = this.state.hosting;
    try {
      await this.api.rpc("mm_heartbeat", {
        p_platform: this.platform, p_hosting_code: hosting?.code ?? null, p_open_seats: hosting?.openSeats ?? null,
      });
    } catch { /* presence is best effort */ }
  }

  /**
   * Starts a ranked game against the AI on the server, so its result counts there. Undefined offline or without a
   * profile name: that game then counts in this browser only. Waits at most `timeout`, since the game waits for it.
   */
  async startRankedAIGame(deckBracket: number, timeout = PlayerAccount.rankedAITimeout): Promise<RankedAITicket | undefined> {
    if (!this.hasName) return undefined;
    let cancel: (() => void) | undefined;
    const timer = new Promise<undefined>((resolve) => { cancel = this.schedule(() => resolve(undefined), timeout); });
    const ticket = this.api.rpc("mm_ranked_ai_start2", { p_deck_bracket: deckBracket }).then(rankedAITicket, () => undefined);
    try { return await Promise.race([ticket, timer]); } finally { cancel?.(); }
  }

  /**
   * Sends finished ranked AI games, then takes the server's standing (seeding it once from this browser when the server
   * has none yet). Quiet on failure: the browser's own count stands until the next try.
   */
  async syncRank(record: RankedRecord): Promise<void> {
    if (!this.hasName) return;
    for (const pending of [...record.pendingRankedResults]) {
      try {
        let data: J;
        if (pending.seeded === true) {
          // The game record backs the result; without one a win settles as unverified.
          const game = pending.recordFile !== undefined ? record.gameRecord(pending.recordFile) : undefined;
          data = await this.api.rpc("mm_ranked_ai_result2", { p_game: pending.ticket, p_result: pending.outcome, p_record: game ?? null });
        } else {
          data = await this.api.rpc("mm_ranked_ai_result", { p_game: pending.ticket, p_result: pending.outcome });
        }
        record.resolvePendingRankedResult(pending.ticket);
        let standing: RankedStanding | undefined;
        try { standing = RankedStanding.parse(data); } catch { /* an older server answers without the standing */ }
        if (standing) {
          record.settleRanked?.(pending.ticket, standing.settlement, standing.check, standing.change, standing.points);
          record.adopt(standing);
        }
      } catch (error) {
        // A ticket the server doesn't know never will be; anything else waits for the next sync.
        if (code(error) === "not_found") record.resolvePendingRankedResult(pending.ticket);
      }
    }
    let standing: RankedStanding;
    try { standing = RankedStanding.parse(await this.api.rpc("mm_ranked_standing")); } catch { return; }
    const local = record.rank;
    if (!standing.seeded && (RankPosition.compare(local.position, RankPosition.start) > 0 || local.wins + local.losses > 0)) {
      try {
        standing = RankedStanding.parse(await this.api.rpc("mm_ranked_seed", {
          p_points: RankPosition.points(local.position), p_peak_points: RankPosition.points(local.peak), p_wins: local.wins, p_losses: local.losses,
        }));
      } catch { /* adopts the unseeded standing */ }
    }
    record.adopt(standing);
  }

  /**
   * Shares the title and favourite commander with friends. The server keeps the rank itself and ignores the rank numbers
   * sent here (they stay for older servers). Quiet on failure. (iOS also takes the stats, which it never sends.)
   */
  async publishRank(rank: RankState, title: Achievement | undefined, commander: string | undefined): Promise<void> {
    if (!this.hasName) return;
    try {
      await this.api.rpc("mm_ranked_publish", {
        p_season: rank.season, p_rank_step: RankPosition.step(rank.position), p_pips: rank.position.pips,
        p_peak_step: RankPosition.step(rank.peak), p_wins: rank.wins, p_losses: rank.losses,
        p_title: title !== undefined ? Achievement.title(title) : null, p_favorite_commander: commander ?? null,
      });
    } catch { /* the next change publishes again */ }
  }

  // MARK: Messages between friends

  /** Just the unread count (checked more often during a game). */
  async refreshUnread(): Promise<void> {
    if (!this.hasName || !this.state.messagesAvailable) return;
    try {
      const count = int(await this.api.rpc("mm_message_unread"));
      if (count !== undefined) this.set({ unreadMessages: count });
    } catch (error) {
      if (code(error) === "feature_unavailable") this.set({ messagesAvailable: false });
    }
  }

  /** Conversations with friends, newest first; undefined offline or on a server without messages. */
  async conversations(): Promise<MessageConversation[] | undefined> {
    if (!this.hasName) return undefined;
    try {
      const list = FriendMessageRules.parseConversations(await this.api.rpc("mm_message_conversations"));
      this.set({ messagesAvailable: true });
      return list;
    } catch (error) {
      if (code(error) === "feature_unavailable") this.set({ messagesAvailable: false });
      return undefined;
    }
  }

  /** A page of a conversation (the newest, or the messages before `before`). Reading the newest marks theirs read. Throws. */
  async thread(name: string, before?: number): Promise<MessageThread> {
    const thread = FriendMessageRules.parseThread(await this.api.rpc("mm_message_thread", { p_username: name, p_before: before ?? null, p_limit: 50 }));
    if (before === undefined) {
      try {
        const count = int(await this.api.rpc("mm_message_unread"));
        if (count !== undefined) this.set({ unreadMessages: count });
      } catch { /* the badge catches up later */ }
    }
    return thread;
  }

  /** Sends a message to a friend; undefined (with a notice) when it couldn't be sent. */
  async sendMessage(name: string, raw: string): Promise<FriendMessage | undefined> {
    const body = FriendMessageRules.sanitize(raw);
    if (body === undefined) return undefined;
    try {
      return FriendMessageRules.parseMessage(await this.api.rpc("mm_message_send", { p_username: name, p_body: body }));
    } catch (error) {
      this.fail(error);
      return undefined;
    }
  }

  // MARK: Profiles and the ladder

  /** The season leaderboard (mm_ranked_leaderboard), or undefined offline or without a profile name. */
  async rankedLeaderboard(scope: RankedLeaderboardScope, limit = 50): Promise<RankedLeaderboard | undefined> {
    if (!this.hasName) return undefined;
    try { return RankedLeaderboard.parse(await this.api.rpc("mm_ranked_leaderboard", { p_scope: scope, p_limit: limit })); } catch { return undefined; }
  }

  /** Your games from every device (mm_my_games), newest first; undefined when they can't be read now. */
  async myGames(): Promise<MatchRecord[] | undefined> {
    if (!this.hasName) return undefined;
    try { return parseMyGames(await this.api.rpc("mm_my_games", { p_limit: 300 })); } catch { return undefined; }
  }

  /** Another player's ranked card, or undefined when they have none (or can't be seen). */
  async profileCard(username: string): Promise<PlayerProfileCard | undefined> {
    if (this.state.phase !== "ready") return undefined;
    try { return PlayerProfileCard.parse(await this.api.rpc("mm_profile_card", { p_username: username })); } catch { return undefined; }
  }

  /**
   * Players whose name starts with `text` (at least two letters; the server returns nothing for less). Throws
   * SearchCancelled when a newer search replaced this one.
   */
  async search(text: string): Promise<PlayerSearchResult[]> {
    const run = ++this.searchRun;
    const normalized = PlayerSearchRules.normalized(text);
    if (this.state.phase !== "ready" || normalized === undefined) return [];
    try {
      const results = PlayerSearchResult.parse(await this.api.rpc("mm_search_players", { p_prefix: normalized }));
      if (run !== this.searchRun) throw new SearchCancelled();
      this.set({ searchAvailable: true });
      return results;
    } catch (error) {
      if (error instanceof SearchCancelled || run !== this.searchRun) throw new SearchCancelled();
      if (code(error) === "feature_unavailable") this.set({ searchAvailable: false });
      throw error;
    }
  }

  /** Another player's profile (or your own, as others see it). */
  async publicProfile(name: string): Promise<PublicProfileResult> {
    if (this.state.phase !== "ready") return { kind: "failed", message: PlayerAccountRules.message("offline") };
    try {
      const profile = PublicProfile.parse(await this.api.rpc("mm_public_profile", { p_username: name }), this.now());
      this.set({ profilesAvailable: true });
      return { kind: "profile", profile };
    } catch (error) {
      const failure = code(error);
      if (failure === "feature_unavailable") { this.set({ profilesAvailable: false }); return { kind: "unavailable" }; }
      if (failure === "not_found") return { kind: "notFound" };
      return { kind: "failed", message: PlayerAccountRules.message(failure) };
    }
  }

  /** Who may open this player's profile. Quiet about a server that doesn't have the setting yet. */
  async setVisibility(next: ProfileVisibility): Promise<boolean> {
    if (!this.hasName) return false;
    try {
      await this.api.rpc("mm_set_visibility", { p_visibility: next });
      this.set({ visibility: next, visibilityKnown: true, notice: undefined });
      return true;
    } catch (error) {
      const failure = code(error);
      this.set({ ...(failure === "feature_unavailable" ? { visibilityKnown: false } : {}), notice: PlayerAccountRules.message(failure) });
      return false;
    }
  }

  /** Sends one finished game. Never throws: the caller keeps what could not be sent and tries again later. */
  /** The server's settings for the web (mm_app_config): the menu's notice, name fixes and switches. Best effort. */
  async refreshAppConfig(): Promise<void> {
    if (this.state.phase !== "ready") return;
    try { appConfig.store(await this.api.rpc("mm_app_config", { p_platform: "web", p_build: 0 })); } catch { /* the last copy stays */ }
  }

  /** Quiet about a server without awards or trophies: the profile just shows none, and the built-in coins. */
  async refreshAwards(): Promise<void> {
    if (this.state.phase !== "ready") return;
    try {
      this.set({ awards: Award.parse(await this.api.rpc("mm_my_awards")) });
      this.set({ trophies: Award.parse(await this.api.rpc("mm_trophies")) });
    } catch { /* keeps what it had */ }
  }

  /** Its ceremony has played, here and on the player's other devices. */
  markAwardSeen(award: Award): void {
    this.set({ awards: this.state.awards.map((a) => (a.id === award.id ? { ...a, seen: true } : a)) });
    void this.api.rpc("mm_awards_seen", { p_ids: [award.id] }).catch(() => undefined);
  }

  /** A voice chat token for one seat of one game (the agora-token function; VoiceRoom). */
  async voiceToken(channel: string, account: string): Promise<{ appId: string; token: string }> {
    const reply = await this.api.invoke("agora-token", { channel, account });
    const appId = str(get(reply, "appId")), token = str(get(reply, "token"));
    if (!appId || !token) throw new SupabaseFailure("error");
    return { appId, token };
  }

  async recordGame(match: MatchRecord): Promise<GameUploadResult> {
    if (!this.hasName) return "unavailable";
    const params: Record<string, J> = {
      p_client_id: match.id, p_played_at: new Date(match.date).toISOString(), p_mode: match.mode, p_result: match.outcome,
      p_deck_name: prefix(match.deckName, 80), p_commanders: match.commander !== undefined ? [prefix(match.commander, 160)] : [],
      p_colors: match.colors,
      p_opponents: match.opponents.slice(0, 3).map((o) => ({
        name: prefix(o.name, 60), commander: o.commander !== undefined ? prefix(o.commander, 160) : null, ai: o.isAI,
      })),
    };
    if (match.turns > 0) params.p_turns = Math.min(1000, match.turns);
    if (match.durationSeconds !== undefined && match.durationSeconds > 0) params.p_duration_seconds = Math.min(86_400, Math.round(match.durationSeconds));
    if (match.rankChange) params.p_rank_points = RankPosition.points(match.rankChange.after);
    try {
      await this.api.rpc("mm_record_game", params);
      return "sent";
    } catch (error) {
      switch (code(error)) {
        case "feature_unavailable": case "no_username": return "unavailable";
        case "invalid_game": return "rejected";
        default: return "retryLater";
      }
    }
  }

  // MARK: Friends

  async addFriend(name: string): Promise<void> {
    const trimmed = trimSpaces(name);
    if (trimmed.length === 0) return;
    try {
      const result = str(await this.api.rpc("mm_friend_request", { p_username: trimmed })) ?? "requested";
      this.set({ notice: PlayerAccountRules.requestResult(result, trimmed) });
      await this.refresh();
    } catch (error) {
      this.fail(error);
    }
  }

  respond(friend: PlayerFriend, accept: boolean) { return this.perform("mm_respond_friend", { p_requester: friend.id, p_accept: accept }); }
  remove(friend: PlayerFriend) { return this.perform("mm_remove_friend", { p_other: friend.id }); }
  block(name: string) { return this.perform("mm_block", { p_username: name }); }
  unblock(name: string) { return this.perform("mm_unblock", { p_username: name }); }

  /** Reports another player's chat message or name to the developer. */
  async report(name: string, message: string | undefined, context: string): Promise<void> {
    await this.perform("mm_report", { p_username: name, p_message: message ?? null, p_context: context }, false);
    if (this.state.notice === undefined) this.set({ notice: `Thanks. ${name} was reported.` });
  }

  /** Deletes the account and everything tied to it; a new one is made the next time. */
  async deleteAccount(): Promise<boolean> {
    try {
      await this.api.rpc("mm_delete_account");
      this.api.forgetSession();
      this.set({ username: undefined, friends: [], awards: [], trophies: [], blocked: [], hosting: undefined, phase: "idle" });
      return true;
    } catch (error) {
      this.fail(error);
      return false;
    }
  }

  private async perform(fn: string, params: Record<string, J>, refreshAfter = true): Promise<void> {
    try {
      await this.api.rpc(fn, params);
      this.set({ notice: undefined });
      if (refreshAfter) await this.refresh();
    } catch (error) {
      this.fail(error);
    }
  }
}
