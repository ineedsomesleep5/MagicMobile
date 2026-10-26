/** ranked-cases.json's ladder, positions, tiers and seasons (iOS RankedParityTests, Android RankedParityTest.kt). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RankChange, RankLadder, RankPosition, RankState, RankTier, SeasonBadge } from "../src/core/rankLadder";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/ranked-cases.json"), "utf8"));
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const position = (row: any) => RankPosition.make(row.tier, row.division, row.pips);
const at = (tier: RankTier, division: number, pips: number) => ({ ...RankState.fresh("2026-10"), position: RankPosition.make(tier, division, pips) });

describe("rank ladder", () => {
  it("moves as ranked-cases.json says", () => {
    expect(cases.pipsPerDivision).toBe(RankPosition.pipsPerDivision);
    for (const item of cases.ladder) {
      const state = { ...RankState.fresh("2026-10"), position: position(item.before), peak: position(item.before), winStreak: item.streak };
      const result = RankLadder.apply(item.outcome, state, item.deckBracket);
      expect(result.state.position, item.name).toEqual(position(item.after));
      expect(result.state.winStreak, item.name).toBe(item.streakAfter);
      expect(RankChange.pipDelta(result.change), item.name).toBe(item.delta);
      expect(result.change.bonuses, item.name).toEqual(item.bonuses);
      expect(RankChange.kind(result.change), item.name).toBe(item.kind);
    }
  });

  it("positions and tiers", () => {
    for (const item of cases.positions) {
      const p = RankPosition.fromPoints(item.points);
      expect(RankPosition.step(p), JSON.stringify(item)).toBe(item.step);
      expect(RankPosition.title(p)).toBe(item.title);
      expect(p.pips).toBe(item.pips);
      expect(RankPosition.opponentBracket(p)).toBe(item.opponentBracket);
      expect(RankPosition.points(p)).toBe(item.points);
    }
    for (const item of cases.tiers) {
      expect(RankTier.opponentBrackets(item.tier)).toEqual(item.opponentBrackets);
      expect(RankTier.maxDeckBracket(item.tier)).toBe(item.maxDeckBracket);
      expect(RankTier.aiSkill(item.tier)).toBe(item.aiSkill);
    }
    expect(RankTier.preconOpponentsOnly("bronze")).toBe(true);
    expect(RankTier.preconOpponentsOnly("silver")).toBe(false);
  });

  it("seasons and rollover", () => {
    for (const item of cases.seasons) expect(RankLadder.season(item.millis)).toBe(item.season);
    for (const item of cases.seasonEnds) expect(RankLadder.seasonEnd(item.season)?.getTime()).toBe(item.millis);
    expect(RankLadder.seasonEnd("2026")).toBeUndefined();
    expect(RankLadder.seasonEnd("2026-09")?.toISOString()).toBe("2026-10-01T00:00:00.000Z");
    expect(RankLadder.seasonName("2026-10", "en-US")).toBe("October 2026");
    // Quarterly from November 2026: a season is named by its first month and spans three.
    expect(RankLadder.seasonName("2026-11", "en-US")).toBe("Nov 2026 – Jan 2027");
    expect(RankLadder.season(Date.UTC(2026, 11, 15))).toBe("2026-11");
    expect(RankLadder.seasonName("junk", "en-US")).toBe("junk");
    for (const item of cases.rollover) {
      const state = { ...RankState.fresh(item.season), position: position(item.position), peak: position(item.peak), wins: item.wins, losses: item.losses };
      const next = RankLadder.rollover(state, item.to);
      expect(next.position, item.name).toEqual(position(item.after));
      expect(next.history.length, item.name).toBe(item.history.length);
      next.history.forEach((record, index) => {
        const expected = item.history[index];
        expect(record.season, item.name).toBe(expected.season);
        expect(record.final, item.name).toEqual(position(expected.final));
        expect(record.peak, item.name).toEqual(position(expected.peak));
        expect([record.wins, record.losses], item.name).toEqual([expected.wins, expected.losses]);
      });
      if (item.to !== item.season) {
        expect(next.wins + next.losses, item.name).toBe(0);
        expect(next.peak, item.name).toEqual(next.position);
      }
    }
  });

  it("numbers seasons and earns their badges as ranked-cases.json says", () => {
    for (const item of cases.seasonNumbers) expect(RankLadder.seasonNumber(item.season), item.season).toBe(item.number ?? undefined);
    expect(RankLadder.seasonNumber("junk")).toBeUndefined();
    const { rank, expect: expected, best } = cases.seasonBadges;
    const peak = RankPosition.fromPoints(rank.peakPoints);
    const state: RankState = {
      ...RankState.fresh(rank.season), peak, wins: rank.played ? 1 : 0,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      history: rank.history.map((row: any) => ({ season: row.season, final: RankPosition.fromPoints(row.peakPoints), peak: RankPosition.fromPoints(row.peakPoints), wins: 1, losses: 0 })),
    };
    const badges = SeasonBadge.earned(state);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    expect(badges.map((b) => ({ season: b.season, tier: b.peak.tier, inProgress: b.inProgress, founder: SeasonBadge.founder(b) }))).toEqual(expected.map((e: any) =>
      ({ season: e.season, tier: e.tier, inProgress: e.inProgress, founder: e.founder })));
    expect(SeasonBadge.best(badges)?.season).toBe(best);
    // Nothing played this season: no badge in play; nothing finished: no best.
    expect(SeasonBadge.earned({ ...state, wins: 0 }).map((b) => b.season)).toEqual(["2026-10", "2026-09"]);
    expect(SeasonBadge.best(SeasonBadge.earned({ ...state, history: [] }))).toBeUndefined();
  });

  it("keeps at most 24 past seasons, newest first", () => {
    let state: RankState = { ...RankState.fresh("2024-01"), wins: 1 };
    for (let month = 2; month <= 30; month++) {
      const season = `${2024 + Math.floor((month - 1) / 12)}-${String(((month - 1) % 12) + 1).padStart(2, "0")}`;
      state = { ...RankLadder.rollover(state, season), wins: 1 };
    }
    expect(state.history.length).toBe(24);
    expect(state.history[0].season > state.history[23].season).toBe(true);
  });

  it("climbs across divisions and tiers to Mythic, and falls back no lower than the tier's floor", () => {
    let state = at("bronze", 4, 0);
    const titles: string[] = [];
    for (let i = 0; i < 100 && state.position.tier !== "mythic"; i++) {
      state = RankLadder.apply("win", state, 4).state;
      titles.push(RankPosition.title(state.position));
    }
    expect(titles.slice(0, 3)).toEqual(["Bronze IV", "Bronze III", "Bronze III"]);
    expect(titles).toContain("Silver IV");
    expect(titles.length).toBe(56); // 24 wins through Gold at two pips, 32 through Platinum and Diamond at one
    expect(state.position).toEqual({ tier: "mythic", division: 0, pips: 0 });
    expect(state.peak).toEqual(state.position);
    state = RankLadder.apply("win", state, 4).state;
    expect(RankPosition.title(state.position)).toBe("Mythic");
    expect(state.position.pips).toBe(1);
    for (let i = 0; i < 20; i++) state = RankLadder.apply("loss", state, 4).state;
    expect(state.position).toEqual({ tier: "diamond", division: 4, pips: 0 });
    expect(state.peak).toEqual({ tier: "mythic", division: 0, pips: 1 });
    expect(state.losses).toBe(20);
    const gold = RankLadder.apply("loss", at("gold", 3, 0), 3);
    expect(gold.state.position).toEqual({ tier: "gold", division: 4, pips: 3 });
    expect(RankChange.kind(gold.change)).toBe("divisionDown");
    expect(RankPosition.published(13, 1)).toEqual({ tier: "platinum", division: 3, pips: 1 });
    expect(RankPosition.make("silver", 9, 9)).toEqual({ tier: "silver", division: 4, pips: 3 });
  });
});
