#!/usr/bin/env python3
"""Games-per-tier for the ranked ladder options in docs/cloud/ladder-options.md.

Each run plays one season at a fixed win rate (no draws, no underdog decks: the player queues at their tier's
bracket) and records the game on which each tier is first reached. The ladder is the shared one: five tiers of four
divisions of four pips (points = step * 4 + pips; tier t starts at 16 t; Mythic at 80).

    python3 scripts/ranked/simulate_ladder.py              # the tables in ladder-options.md
    python3 scripts/ranked/simulate_ladder.py --runs 2000  # quicker

Seeded, so the same command prints the same numbers.
"""

import argparse
import random
import statistics

TIERS = ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Mythic"]
MYTHIC = 80
CAP = 3000  # games per run; a tier not reached by then counts as not reached


def tier_of(points):
    return min(points // 16, 5)


class Today:
    """The ladder as shipped: +1/-1, +1 for a third straight win below Gold, only Bronze IV is a floor."""

    name = "Today"

    def __init__(self, climb_bonus=1):
        self.points, self.streak = 0, 0

    def play(self, win):
        tier = tier_of(self.points)
        if win:
            self.streak += 1
            delta = 1 + (1 if tier < 2 and self.streak >= 3 else 0)
        else:
            self.streak, delta = 0, -1
        self.points = max(self.points + delta, self.floor())

    def floor(self):
        return 0


class FloorsA(Today):
    """Option A: today's steps and streak, but a loss never takes you below division IV of the tier you are in
    (Diamond IV at most, so Mythic can fall back to Diamond). You can't fall out of a tier, so this is also the
    start of the highest tier reached this season."""

    name = "A: tier floors"

    def floor(self):
        return min(tier_of(self.points), 4) * 16


class ArenaB(FloorsA):
    """Option B: Arena's Bo1 steps per tier and A's floors; no streak bonus."""

    name = "B: Arena steps + floors"
    # (win, loss) per tier: Bronze, Silver, Gold, Platinum, Diamond, Mythic
    STEPS = [(2, 0), (2, -1), (2, -1), (1, -1), (1, -1), (1, -1)]

    def play(self, win):
        up, down = self.STEPS[tier_of(self.points)]
        self.points = max(self.points + (up if win else down), self.floor())


class HearthstoneC:
    """Option C: everyone restarts at Bronze IV; wins count the climb bonus (1 + last season's best tier,
    one less each new tier reached, never below 1), doubled from the third straight win below Diamond;
    losses -1; a loss never takes you out of the tier you are in, Mythic included."""

    name = "C: Hearthstone reset + climb bonus"

    def __init__(self, climb_bonus=1):
        self.points, self.streak, self.bonus = 0, 0, climb_bonus

    def play(self, win):
        tier = tier_of(self.points)
        if win:
            self.streak += 1
            delta = self.bonus * (2 if tier < 4 and self.streak >= 3 else 1)
        else:
            self.streak, delta = 0, -1
        after = max(self.points + delta, tier * 16)
        self.bonus = max(1, self.bonus - (tier_of(after) - tier))
        self.points = after


def season(ladder, rate, rng, start_points=0, target=None):
    """Games until each tier is first reached (index = tier), None if never within CAP."""
    ladder.points = start_points
    reached = [None] * 6
    for t in range(tier_of(start_points) + 1):
        reached[t] = 0
    for game in range(1, CAP + 1):
        ladder.play(rng.random() < rate)
        t = tier_of(ladder.points)
        for k in range(t + 1):
            if reached[k] is None:
                reached[k] = game
        if reached[5] is not None or (target is not None and reached[target] is not None):
            break
    return reached


def summarize(results, tier):
    games = [r[tier] for r in results if r[tier] is not None]
    share = len(games) / len(results)
    if share < 0.5:
        return f"not reached (only {share:.0%})"
    median = statistics.median(games) if share == 1 else sorted(games + [CAP + 1] * (len(results) - len(games)))[len(results) // 2]
    within100 = sum(1 for g in games if g <= 100) / len(results)
    return f"{median:.0f} ({within100:.0%} by game 100)"


def per_tier(results, tier):
    """Median games spent in tier-1 before reaching tier (runs that reached it)."""
    spans = [r[tier] - r[tier - 1] for r in results if r[tier] is not None and r[tier - 1] is not None]
    if len(spans) < len(results) / 2:
        return "—"
    return f"{statistics.median(spans):.0f}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=20000)
    parser.add_argument("--seed", type=int, default=20261015)
    args = parser.parse_args()

    for rate in (0.5, 0.6):
        print(f"\n### Fresh player at a {rate:.0%} win rate (median games from Bronze IV; share reaching it by game 100)\n")
        print("| Ladder | " + " | ".join(TIERS[1:]) + " |")
        print("|---|" + "---|" * 5)
        rows_per_tier = []
        for cls in (Today, FloorsA, ArenaB, HearthstoneC):
            rng = random.Random(args.seed)
            results = [season(cls(), rate, rng) for _ in range(args.runs)]
            print(f"| {cls.name} | " + " | ".join(summarize(results, t) for t in range(1, 6)) + " |")
            rows_per_tier.append((cls.name, [per_tier(results, t) for t in range(1, 6)]))
        print(f"\nMedian games spent in each tier at {rate:.0%} (Bronze, Silver, Gold, Platinum, Diamond):\n")
        print("| Ladder | " + " | ".join(TIERS[:5]) + " |")
        print("|---|" + "---|" * 5)
        for name, spans in rows_per_tier:
            print(f"| {name} | " + " | ".join(spans) + " |")

    print("\n### Returning player whose last season ended at Diamond IV: median games back to Diamond IV\n")
    print("| Ladder | Starts at | 50% | 60% |")
    print("|---|---|---|---|")
    for cls, start, bonus, label in ((Today, 48, 1, "Platinum IV"), (FloorsA, 48, 1, "Platinum IV"),
                                     (ArenaB, 48, 1, "Platinum IV"), (HearthstoneC, 0, 5, "Bronze IV, climb bonus 5")):
        cells = []
        for rate in (0.5, 0.6):
            rng = random.Random(args.seed)
            results = [season(cls(climb_bonus=bonus), rate, rng, start_points=start, target=4) for _ in range(args.runs)]
            cells.append(summarize(results, 4))
        print(f"| {cls.name} | {label} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
