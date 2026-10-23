/** profile-cases.json's summaries (iOS ProfileAnalyticsTests, Android ProfileAnalyticsTest.kt), plus the web's helpers. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { MatchRecord, PlayMode } from "../src/core/playerRecord";
import { percent, portraitChoices, ProfileGame, type ProfileRankPoint, ProfileSummary, rankChartRange } from "../src/core/profileSummary";
import { type RankOutcome, RankPosition } from "../src/core/rankLadder";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/profile-cases.json"), "utf8"));
const at = (text: string) => Date.parse(text);

function record(date: string, outcome: RankOutcome, options: { after?: number; deckID?: string; commander?: string; colors?: string[]; turns?: number; mode?: PlayMode } = {}): MatchRecord {
  const { after } = options;
  return {
    id: `${date}-${outcome}`, date: at(date), mode: options.mode ?? (after === undefined ? "quick" : "ranked"), opponents: [{ name: "Foe", isAI: true }],
    deckID: options.deckID ?? "d", deckName: options.deckID ?? "Deck", commander: options.commander ?? "Krenko, Mob Boss", colors: options.colors ?? ["R"],
    deckBracket: 2, outcome, turns: options.turns ?? 7,
    ...(after !== undefined ? { rankChange: { outcome, before: RankPosition.fromPoints(Math.max(0, after - 1)), after: RankPosition.fromPoints(after), bonuses: [] } } : {}),
  };
}

describe("profile summary", () => {
  it("summarises as profile-cases.json says", () => {
    expect(cases.summaries.length).toBeGreaterThan(0);
    for (const item of cases.summaries) {
      const points: ProfileRankPoint[] = [];
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const games: ProfileGame[] = item.games.map((row: any) => {
        if (typeof row.rankAfter === "number") points.unshift({ date: at(row.at), points: row.rankAfter });
        return {
          id: row.id, date: at(row.at), mode: row.mode, outcome: row.result, deckName: "", commanders: row.commanders ?? [], colors: row.colors ?? [],
          opponents: [], ...(row.turns > 0 ? { turns: row.turns } : {}),
        } satisfies ProfileGame;
      });
      const expected = item.expect;
      const summary = ProfileSummary.fromGames(games, at(item.now), points);
      expect(summary.games, item.name).toBe(expected.games);
      expect(summary.wins, item.name).toBe(expected.wins);
      expect(summary.losses, item.name).toBe(expected.losses);
      expect(summary.draws, item.name).toBe(expected.draws);
      expect(summary.currentStreak, item.name).toBe(expected.currentStreak);
      expect(summary.bestStreak, item.name).toBe(expected.bestStreak);
      if (expected.averageTurns == null) expect(summary.averageTurns, item.name).toBeUndefined();
      else expect(summary.averageTurns, item.name).toBeCloseTo(expected.averageTurns, 9);
      expect(summary.weeks.length, item.name).toBe(ProfileSummary.weekCount);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect(summary.weeks.map((w) => ({ start: ProfileSummary.dayText(w.start), games: w.games, wins: w.wins })), item.name).toEqual(expected.weeks);
      expect(summary.commanders, item.name).toEqual(expected.commanders ?? []);
      expect(summary.colors, item.name).toEqual(expected.colors ?? []);
      expect(summary.rankPoints.map((p) => p.points), item.name).toEqual(expected.rankPoints);
    }
  });

  it("follows the record's rank changes (testSummaryFromMatchRecordsFollowsTheRecordsRankChanges)", () => {
    const matches = [record("2026-10-06T10:00:00Z", "win", { after: 30 }), record("2026-10-05T10:00:00Z", "loss", { after: 29 }), record("2026-10-04T10:00:00Z", "win")];
    const summary = ProfileSummary.fromMatches(matches, at("2026-10-07T12:00:00Z"));
    expect(summary.rankPoints.map((p) => p.points)).toEqual([29, 30]);
    expect(summary.rankPoints.map((p) => p.date)).toEqual([at("2026-10-05T10:00:00Z"), at("2026-10-06T10:00:00Z")]);
    expect(summary.commanders.map((c) => c.id)).toEqual(["Krenko, Mob Boss"]);
    expect(summary.currentStreak).toBe(1);
    expect(ProfileGame.from(matches[0]).rankDelta).toBe(1);
    expect(ProfileGame.from(matches[2]).rankDelta).toBeUndefined();
    expect(ProfileSummary.position(summary.rankPoints[1])).toEqual(RankPosition.fromPoints(30));
  });

  it("counts each statistic", () => {
    const matches = [
      record("2026-10-06T10:00:00Z", "win", { turns: 9, commander: "Edgar Markov", colors: ["W", "B", "R"] }),
      record("2026-10-05T10:00:00Z", "draw", { turns: 0 }),
      record("2026-10-04T10:00:00Z", "loss", { turns: 5 }),
      record("2026-10-03T10:00:00Z", "win", { turns: 10 }),
    ];
    const summary = ProfileSummary.fromMatches(matches, at("2026-10-07T12:00:00Z"));
    expect([summary.games, summary.wins, summary.losses, summary.draws]).toEqual([4, 2, 1, 1]);
    expect(summary.averageTurns).toBeCloseTo(8, 9);
    expect(ProfileSummary.winRate(summary)).toBe(0.5);
    expect(summary.commanders).toEqual([{ id: "Krenko, Mob Boss", games: 3, wins: 1 }, { id: "Edgar Markov", games: 1, wins: 1 }]);
    expect(summary.colors).toEqual([{ id: "W", games: 1, wins: 1 }, { id: "B", games: 1, wins: 1 }, { id: "R", games: 4, wins: 2 }]);
    expect(ProfileSummary.shareWinRate(summary.colors[2])).toBe(0.5);
    expect(summary.rankPoints).toEqual([]);
  });

  it("reads streaks oldest first", () => {
    const outcomes: RankOutcome[] = ["win", "win", "loss", "win", "win", "win", "draw", "win"]; // oldest first
    const matches = outcomes.map((o, i) => record(`2026-10-0${i + 1}T10:00:00Z`, o)).reverse();
    const summary = ProfileSummary.fromMatches(matches, at("2026-10-09T12:00:00Z"));
    expect(summary.currentStreak).toBe(1);
    expect(summary.bestStreak).toBe(3);
    expect(ProfileSummary.fromMatches([record("2026-10-06T10:00:00Z", "loss")], at("2026-10-07T00:00:00Z")).currentStreak).toBe(0);
  });

  it("keeps eight Monday weeks in UTC relative to now", () => {
    // Sunday 23:59:59 UTC is still last week; Monday 00:00 starts this one.
    const now = at("2026-10-05T00:00:00Z");
    const weeks = ProfileSummary.emptyWeeks(now);
    expect(weeks.map((w) => ProfileSummary.dayText(w.start))).toEqual(
      ["2026-08-17", "2026-08-24", "2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05"]);
    expect(ProfileSummary.weekStart(at("2026-10-04T23:59:59Z"))).toBe(at("2026-09-28T00:00:00Z"));
    expect(ProfileSummary.weekStart(at("2026-10-11T23:59:59Z"))).toBe(at("2026-10-05T00:00:00Z"));
    const summary = ProfileSummary.fromMatches([
      record("2026-10-05T00:00:00Z", "win"), record("2026-10-04T23:59:59Z", "loss"), record("2026-08-16T23:00:00Z", "win"), record("2026-08-17T00:00:00Z", "win"),
    ], now);
    expect(summary.weeks.map((w) => [w.games, w.wins])).toEqual([[1, 1], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [1, 0], [1, 1]]);
    expect(summary.games).toBe(4);
  });

  it("narrows to a deck but keeps every ranked standing", () => {
    const matches = [
      record("2026-10-06T10:00:00Z", "win", { deckID: "a", after: 12 }),
      record("2026-10-05T10:00:00Z", "loss", { deckID: "b", after: 11 }),
      record("2026-10-04T10:00:00Z", "win", { deckID: "a" }),
    ];
    const summary = ProfileSummary.forDeck(matches, "a", at("2026-10-07T12:00:00Z"));
    expect([summary.games, summary.wins, summary.losses]).toEqual([2, 2, 0]);
    expect(summary.rankPoints.map((p) => p.points)).toEqual([11, 12]);
    expect(ProfileSummary.forDeck(matches, undefined, at("2026-10-07T12:00:00Z")).games).toBe(3);
  });

  it("describes a game as the card does", () => {
    const game = ProfileGame.from(record("2026-10-06T10:00:00Z", "win", { after: 12, turns: 0 }));
    expect(game.turns).toBeUndefined();
    expect([ProfileGame.opponentText(game), ProfileGame.modeText(game), ProfileGame.resultLetter(game), ProfileGame.resultName(game)])
      .toEqual(["Foe", "Ranked · AI", "W", "Won"]);
    const many: ProfileGame = { ...game, mode: "casual", outcome: "draw", opponents: [{ name: "A", isAI: false }, { name: "B", isAI: true, hidden: true }] };
    expect([ProfileGame.opponentText(many), ProfileGame.modeText(many), ProfileGame.resultLetter(many)]).toEqual(["2 opponents", "Custom", "D"]);
    expect(ProfileGame.opponentText({ ...game, opponents: [{ name: "X", isAI: false, hidden: true }] })).toBe("a player");
    expect(ProfileGame.opponentText({ ...game, opponents: [] })).toBe("Opponent");
    expect(ProfileGame.modeText({ ...game, opponents: [{ name: "X", isAI: false }] })).toBe("Ranked · Player");
  });

  it("rounds percentages and sizes the rank chart", () => {
    expect([percent(1, 3), percent(2, 3), percent(1, 2), percent(0, 0)]).toEqual([33, 67, 50, 0]);
    expect(rankChartRange([26, 25, 30])).toEqual({ low: 22, high: 33 });
    expect(rankChartRange([1])).toEqual({ low: 0, high: 10 });
  });

  it("offers portraits: played, then new deck commanders, keeping a deleted favourite", () => {
    const played = Array.from({ length: 14 }, (_, i) => `C${i}`);
    const choices = portraitChoices(played, ["C1", "", "Deck One", "Deck One", "C13"], "Gone");
    expect(choices.played).toEqual([...played.slice(0, 12), "Gone"]);
    expect(choices.decks).toEqual(["Deck One", "C13"]);
    expect(portraitChoices([], ["Deck One"], "Deck One")).toEqual({ played: [], decks: ["Deck One"] });
  });
});
