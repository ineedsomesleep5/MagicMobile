"""Unit tests for the AI calibration orchestrator (scheduling, resume and statistics; no engine)."""
import collections
import csv
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import ai_calibration as calibration  # noqa: E402

DECKS = ["d1", "d2", "d3", "d4"]


class ScheduleTests(unittest.TestCase):
    def test_blocks_cancel_deck_and_seat(self):
        rows = calibration.schedule(1, 6, DECKS, 48, 7, "phone")
        pairs = collections.Counter(frozenset((r["deck_a"], r["deck_b"])) for r in rows)
        self.assertEqual(len(pairs), 6)
        self.assertEqual(set(pairs.values()), {8})
        for pair in pairs:
            games = [r for r in rows if frozenset((r["deck_a"], r["deck_b"])) == pair]
            # Each deck plays skill A equally often, half the time going first.
            self.assertEqual(collections.Counter((r["deck_a"], r["a_first"]) for r in games).most_common()[-1][1], 2)

    def test_seeds_repeat_and_differ(self):
        first = calibration.schedule(2, 4, DECKS, 8, 11, "phone")
        self.assertEqual(first, calibration.schedule(2, 4, DECKS, 8, 11, "phone"))
        self.assertEqual(len({r["game_seed"] for r in first}), 8)
        self.assertNotEqual(first[0]["game_seed"], calibration.schedule(2, 4, DECKS, 8, 12, "phone")[0]["game_seed"])
        self.assertTrue(all(0 <= r["game_seed"] < 2 ** 63 for r in first))

    def test_against_plays_each_deck_with_each_reference(self):
        rows = calibration.schedule(3, 3, ["x1", "x2"], 24, 5, "phone", against=["r1", "r2", "x1"])
        pairs = collections.Counter(frozenset((r["deck_a"], r["deck_b"])) for r in rows)
        # x1 never meets itself; x2 meets x1 as a reference.
        self.assertEqual(set(pairs), {frozenset(p) for p in [("x1", "r1"), ("x1", "r2"), ("x2", "r1"), ("x2", "r2"), ("x2", "x1")]})
        self.assertFalse(any({"r1", "r2"} == {r["deck_a"], r["deck_b"]} for r in rows))
        for pair in pairs:
            games = [r for r in rows if frozenset((r["deck_a"], r["deck_b"])) == pair]
            self.assertEqual(len({(r["deck_a"], r["a_first"]) for r in games[:4]}), 4)

    def test_overrides_reach_rows(self):
        rows = calibration.schedule(3, 4, DECKS, 4, 1, "phone", {"mistake_a": "10"})
        self.assertTrue(all(r["mistake_a"] == "10" and r["depth_b"] == "" for r in rows))


class ResumeTests(unittest.TestCase):
    def test_harness_failures_are_replayed(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "pairing.csv"
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, calibration.FIELDS)
                writer.writeheader()
                for game, end in enumerate(("ended", "jvm-exit", "turn-limit", "engine-stopped")):
                    writer.writerow({"game": game, "end": end, "winner": "A"})
            self.assertEqual(calibration.done_games(path), {0, 2})
            with path.open() as stream:
                self.assertEqual([r["game"] for r in csv.DictReader(stream)], ["0", "2"])


class StatisticsTests(unittest.TestCase):
    def test_wilson(self):
        low, high = calibration.wilson(40, 80)
        self.assertAlmostEqual(low, 0.393, places=3)
        self.assertAlmostEqual(high, 0.607, places=3)
        self.assertEqual(calibration.wilson(0, 0), (0.0, 1.0))

    def test_deck_summary_counts_both_seats(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "round.csv"
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, calibration.FIELDS)
                writer.writeheader()
                writer.writerow({"deck_a": "x", "deck_b": "y", "winner": "A"})
                writer.writerow({"deck_a": "y", "deck_b": "x", "winner": "A"})
                writer.writerow({"deck_a": "x", "deck_b": "y", "winner": "draw"})
            table = calibration.summarize_decks([path])
            self.assertIn("| x | 3 | 1 | 1 | 1 | 50%", table)
            self.assertIn("| y | 3 | 1 | 1 | 1 | 50%", table)
            # x won in seat A once of one decided game there; lost its one decided game in seat B.
            self.assertRegex(table, r"\| x \|.*\| 1/1 \| 0/1 \|")

    def test_focus_deck_reported_apart(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "skill1-vs-skill6-phone.csv"
            rows = [("x", "strong", "B"), ("strong", "x", "A"), ("x", "y", "A"), ("y", "x", "B"), ("strong", "x", "draw")]
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, calibration.FIELDS)
                writer.writeheader()
                for game, (deck_a, deck_b, winner) in enumerate(rows):
                    writer.writerow({"game": game, "budget": "phone", "skill_a": 1, "skill_b": 6, "deck_a": deck_a,
                                     "deck_b": deck_b, "first": "A", "winner": winner, "turns": 10, "seconds": 1})
            text = calibration.summarize([path], "strong")
            sections = text.split("\n\n")
            self.assertIn("| skill 1 vs skill 6 | phone | 5 | 2 | 2 | 1 | 50%", text)
            # Without the strong deck: games 2 and 3 only.
            self.assertIn("Without strong games:", text)
            self.assertIn("| skill 1 vs skill 6 | phone | 2 | 1 | 1 | 0 | 50%", text)
            # Its games: A won with it 1 of 1 decided, B won with it 1 of 1; deck 100%, A 50%.
            self.assertIn("| skill 1 vs skill 6 | 3 | 1/1 | 1/1 | 100% (34–100) | 50% (9–91) |", text)
            self.assertIn("Deck balance: uneven", sections[-1] + text)
            self.assertIn("strong A 2, B 1", text)

    def test_balanced_schedule_reports_even(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "pairing.csv"
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, calibration.FIELDS)
                writer.writeheader()
                for row in calibration.schedule(2, 6, DECKS, 24, 3, "phone"):
                    writer.writerow({**{k: row[k] for k in ("game", "budget", "skill_a", "skill_b", "deck_a", "deck_b")},
                                     "first": "A", "winner": "A", "turns": 5, "seconds": 1})
            self.assertIn("each skill played each deck equally often", calibration.summarize([path], None))


if __name__ == "__main__":
    unittest.main()
