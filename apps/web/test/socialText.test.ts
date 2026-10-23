/** The social screens' words and small rules (FriendsView, FriendConversationView, PublicProfileView, the leaderboard). */
import { describe, expect, it } from "vitest";
import type { MessageConversation, PlayerFriend, PlayerSearchResult, RankedLeaderboardEntry } from "../src/core/account";
import {
  conversationLabel, friendLabel, friendStatus, leaderboardLabel, messagePreview, onlineText, placeMoves, podiumOrder, QUICK_REPLIES, relationTag,
  relativeTime, searchHint, searchResultLabel, searchResultLine, startsNewDay, usernameDraft, withRelation,
} from "../src/core/socialText";
import { RankPosition } from "../src/core/rankLadder";

const now = Date.UTC(2026, 9, 23, 12, 0, 0);
const friend = (extra: Partial<PlayerFriend> = {}): PlayerFriend =>
  ({ id: "00000000-0000-4000-8000-000000000001", username: "Mara", relation: "friend", online: false, ...extra });
const result = (extra: Partial<PlayerSearchResult> = {}): PlayerSearchResult => ({ username: "Mara", visibility: "public", relation: "none", ...extra });
const entry = (extra: Partial<RankedLeaderboardEntry> = {}): RankedLeaderboardEntry =>
  ({ position: 1, username: "Mara", points: 0, wins: 3, losses: 1, online: false, you: false, ...extra });
const message = (id: number, body: string, fromMe: boolean) => ({ id, body, sentAt: now, fromMe, read: false });

describe("social text", () => {
  it("keeps only letters, digits and underscores in a name, at most 20", () => {
    expect(usernameDraft("Ma ra-é_9!")).toBe("Mara_9");
    expect(usernameDraft("a".repeat(25))).toBe("a".repeat(20));
  });

  it("says when a friend was last seen, like Swift's named relative dates", () => {
    expect(relativeTime(now - 5 * 60_000, now, "en-US")).toBe("5 minutes ago");
    expect(relativeTime(now - 86_400_000, now, "en-US")).toBe("yesterday");
    expect(relativeTime(now - 3 * 86_400_000, now, "en-US")).toBe("3 days ago");
    expect(relativeTime(now, now, "en-US")).toBe("now");
  });

  it("gives each friend one status line: hosting, online, last seen or offline", () => {
    expect(friendStatus(friend({ online: true, hostingCode: "ABCD23", hostingOpenSeats: 1 }), now)).toBe("Hosting · 1 seat");
    expect(friendStatus(friend({ online: true, hostingCode: "ABCD23", hostingOpenSeats: 3 }), now)).toBe("Hosting · 3 seats");
    expect(friendStatus(friend({ online: false, hostingCode: "ABCD23", hostingOpenSeats: 3 }), now)).toBe("Offline");
    expect(friendStatus(friend({ online: true }), now)).toBe("Online");
    expect(friendStatus(friend({ lastSeenAt: now - 2 * 3_600_000 }), now, "en-US")).toBe("Last seen 2 hours ago");
    expect(friendLabel(friend({ online: true }), RankPosition.atStep(9), now)).toBe(`Mara, ${RankPosition.title(RankPosition.atStep(9))}, Online`);
  });

  it("hints under the search field until the text can be searched", () => {
    expect(searchHint("")).toBeUndefined();
    expect(searchHint("M")).toBe("Keep typing: two letters at least.");
    expect(searchHint("Ma ra")).toBe("Player names have letters, numbers and underscores only.");
    expect(searchHint("Ma")).toBeUndefined();
  });

  it("describes a found player and changes their relation in place", () => {
    expect(searchResultLine(result({ favoriteCommander: "Edgar Markov" }))).toBe("Edgar Markov");
    expect(searchResultLine(result())).toBe("No games to show yet");
    expect(searchResultLine(result({ visibility: "private" }))).toBe("Profile hidden");
    expect(searchResultLabel(result({ relation: "friend", online: true }), now)).toBe("Mara, unranked, friend, online");
    expect(searchResultLabel(result({ relation: "incoming" }), now)).toBe("Mara, unranked, wants to be your friend");
    expect(withRelation(result({ relation: "friend", online: true }), "outgoing")).toEqual(result({ relation: "outgoing" }));
  });

  it("previews conversations with strong language masked in theirs", () => {
    const theirs: MessageConversation = { username: "Mara", unread: 2, last: message(4, "oh shit", false) };
    const mine: MessageConversation = { username: "Mara", unread: 0, last: message(5, "gg", true) };
    expect(messagePreview(undefined)).toBe("Say hello");
    expect(messagePreview(theirs)).toBe("oh s***");
    expect(messagePreview(mine)).toBe("You: gg");
    expect(conversationLabel("Mara", theirs)).toBe("Mara, 2 unread, oh s***");
    expect(conversationLabel("Mara", undefined)).toBe("Mara, no messages yet");
    expect(QUICK_REPLIES).toEqual(["Want to play?", "Hello!", "Good game!", "Well played!", "Thanks!"]);
  });

  it("starts a new day heading between messages on different days", () => {
    const day = new Date(2026, 9, 23, 9).getTime();
    expect(startsNewDay(day + 3_600_000, day)).toBe(false);
    expect(startsNewDay(new Date(2026, 9, 24, 0, 5).getTime(), day)).toBe(true);
  });

  it("tags a public profile by relation", () => {
    expect(relationTag({ relation: "self", visibility: "public" })).toBe("YOU");
    expect(relationTag({ relation: "incoming", visibility: "public" })).toBe("WANTS TO BE FRIENDS");
    expect(relationTag({ relation: "none", visibility: "friends" })).toBe("FRIENDS ONLY");
    expect(relationTag({ relation: "none", visibility: "public" })).toBe("PUBLIC PROFILE");
  });

  it("orders the podium and counts places moved", () => {
    expect(podiumOrder([1, 2, 3])).toEqual([2, 1, 3]);
    expect(podiumOrder([1, 2])).toEqual([2, 1]);
    expect(podiumOrder([1])).toEqual([1]);
    const { positions, moves } = placeMoves({ Mara: 3, Ivo: 1, Gone: 2 }, [entry({ username: "Mara", position: 1 }), entry({ username: "Ivo", position: 2 }), entry({ username: "New", position: 3 })]);
    expect(positions).toEqual({ Mara: 1, Ivo: 2, New: 3 });
    expect(moves).toEqual({ Mara: 2, Ivo: -1 });
    expect(onlineText(1)).toBe("1 player online");
    expect(onlineText(4)).toBe("4 players online");
    expect(leaderboardLabel(entry({ title: "Giant Slayer", online: true, you: true }))).toBe("Number 1, Mara, Bronze IV, Giant Slayer, online, 3 wins, 1 losses, you");
  });
});
