/**
 * The words and small rules the social screens show (iOS FriendsView.swift, Ranked/FriendConversationView.swift,
 * Ranked/PublicProfileView.swift, Ranked/RankedHallViews.swift's leaderboard), kept free of React so they are tested on
 * their own (test/socialText.test.ts). Dates are milliseconds since 1970.
 */
import {
  FriendMessageRules, type MessageConversation, PlayerFriend, PlayerSearchResult, PlayerSearchRules, type PublicProfile, RankedLeaderboard,
  type RankedLeaderboardEntry,
} from "./account";
import { RankPosition, type RankTier } from "./rankLadder";
import { GameEmotes } from "./tableChat";

/** Each tier's metal (RankTier.tint), as "r,g,b". */
export const TIER_TINT: Record<RankTier, string> = {
  bronze: "204,128,69", silver: "204,212,224", gold: "255,204,92", platinum: "140,230,219", diamond: "128,191,255", mythic: "255,115,56",
};

/** The name field keeps letters, digits and underscores (ASCII only), at most 20. */
export const usernameDraft = (value: string) => [...value].filter((ch) => /^[A-Za-z0-9_]$/.test(ch)).slice(0, 20).join("");

/** Swift's `.relative(presentation: .named)`: "now", "5 minutes ago", "yesterday", "last week". */
export function relativeTime(then: number, now: number, locale?: string): string {
  const format = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
  const seconds = Math.round((then - now) / 1000);
  const units: [Intl.RelativeTimeFormatUnit, number][] = [["year", 31_536_000], ["month", 2_592_000], ["week", 604_800], ["day", 86_400], ["hour", 3600], ["minute", 60]];
  for (const [unit, size] of units) {
    const value = Math.trunc(seconds / size);
    if (value !== 0) return format.format(value, unit);
  }
  return format.format(seconds, "second");
}

/** A friend's line under their name: short enough to show whole beside the row's buttons. */
export function friendStatus(friend: PlayerFriend, now: number, locale?: string): string {
  if (PlayerFriend.joinableCode(friend) !== undefined) {
    const seats = friend.hostingOpenSeats ?? 1;
    return seats === 1 ? "Hosting · 1 seat" : `Hosting · ${seats} seats`;
  }
  if (friend.online) return "Online";
  if (friend.lastSeenAt === undefined) return "Offline";
  return `Last seen ${relativeTime(friend.lastSeenAt, now, locale)}`;
}

/** What a friend's row says to a screen reader. */
export const friendLabel = (friend: PlayerFriend, rank: RankPosition | undefined, now: number, locale?: string) =>
  `${friend.username}${rank ? `, ${RankPosition.title(rank)}` : ""}, ${friendStatus(friend, now, locale)}`;

/** The line under the search field while what's typed can't be searched yet; undefined once it can (or it's empty). */
export function searchHint(trimmed: string): string | undefined {
  if (trimmed === "" || PlayerSearchRules.normalized(trimmed) !== undefined) return undefined;
  return trimmed.length < PlayerSearchRules.minimumLength ? "Keep typing: two letters at least." : "Player names have letters, numbers and underscores only.";
}

/** The line under a found player's name. */
export const searchResultLine = (result: PlayerSearchResult) =>
  result.favoriteCommander ?? (result.visibility === "public" ? "No games to show yet" : "Profile hidden");

export function searchResultLabel(result: PlayerSearchResult, now: number = Date.now()): string {
  const position = PlayerSearchResult.position(result, now);
  const rank = position ? `, ${RankPosition.title(position)}` : ", unranked";
  const relation = result.relation === "friend" ? `, friend${result.online === true ? ", online" : ""}`
    : result.relation === "outgoing" ? ", request sent" : result.relation === "incoming" ? ", wants to be your friend" : "";
  return `${result.username}${rank}${relation}`;
}

/** A search result after the relation changed here; presence shows for friends only. */
export function withRelation(result: PlayerSearchResult, relation: string): PlayerSearchResult {
  const next: PlayerSearchResult = { ...result, relation };
  if (relation !== "friend") delete next.online;
  return next;
}

// MARK: Messages

/** The quick replies over the composer (FriendConversationView.quickReplies). */
export const QUICK_REPLIES: string[] = ["Want to play?", ...["hello", "goodGame", "wellPlayed", "thanks"].map((raw) => GameEmotes.find((e) => e.raw === raw)!.text)];

/** A conversation's line in the Messages list: the last message, yours after "You:". */
export function messagePreview(conversation: MessageConversation | undefined): string {
  if (!conversation) return "Say hello";
  const text = FriendMessageRules.shown(conversation.last);
  return conversation.last.fromMe ? `You: ${text}` : text;
}

export function conversationLabel(name: string, conversation: MessageConversation | undefined): string {
  if (!conversation) return `${name}, no messages yet`;
  const unread = conversation.unread > 0 ? `, ${conversation.unread} unread` : "";
  return `${name}${unread}, ${messagePreview(conversation)}`;
}

/** Whether two moments fall on different days here (a day heading goes between them). */
export function startsNewDay(message: number, previous: number): boolean {
  const a = new Date(message), b = new Date(previous);
  return a.getFullYear() !== b.getFullYear() || a.getMonth() !== b.getMonth() || a.getDate() !== b.getDate();
}

// MARK: Profiles

/** The tag beside a public profile's name. */
export function relationTag(profile: Pick<PublicProfile, "relation" | "visibility">): string {
  switch (profile.relation) {
    case "self": return "YOU";
    case "friend": return "FRIEND";
    case "outgoing": return "REQUESTED";
    case "incoming": return "WANTS TO BE FRIENDS";
    default: return profile.visibility === "public" ? "PUBLIC PROFILE" : "FRIENDS ONLY";
  }
}

// MARK: Leaderboard

/** The top three in podium order: second, first, third. */
export function podiumOrder<T>(top: readonly T[]): T[] {
  if (top.length === 3) return [top[1], top[0], top[2]];
  if (top.length === 2) return [top[1], top[0]];
  return [...top];
}

/** Places gained (positive) or lost since the last refresh, and the places to compare the next one with. */
export function placeMoves(last: Readonly<Record<string, number>>, entries: readonly RankedLeaderboardEntry[]):
  { positions: Record<string, number>; moves: Record<string, number> } {
  const positions: Record<string, number> = {};
  for (const entry of entries) if (!(entry.username in positions)) positions[entry.username] = entry.position;
  const moves: Record<string, number> = {};
  for (const [name, position] of Object.entries(positions)) {
    const before = last[name];
    if (before !== undefined && before !== position) moves[name] = before - position;
  }
  return { positions, moves };
}

export const onlineText = (count: number) => (count === 1 ? "1 player online" : `${count} players online`);

export function leaderboardLabel(entry: RankedLeaderboardEntry): string {
  const parts = [`Number ${entry.position}`, entry.username, RankPosition.title(RankedLeaderboard.rank(entry))];
  if (entry.title !== undefined) parts.push(entry.title);
  if (entry.online) parts.push("online");
  parts.push(`${entry.wins} wins, ${entry.losses} losses`);
  if (entry.you) parts.push("you");
  return parts.join(", ");
}
