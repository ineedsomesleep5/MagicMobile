#!/usr/bin/env python3
"""Trial: a sound of its own for the steal (board FX `controlChanged`), which today borrows `card-pickup`.

The cue fires when the taker's brass chain hooks the card (stealHookFraction of a 1.5 s effect, see
BoardEventTimeline.swift), and the card lands 0.66 s later. So, from the hook:

  0.00 s  the hook bites: Kenney RPG `metalLatch`, slowed to a heavier brass clink
  0.09 s  the chain runs: grains of the RPG belt-buckle jingles, slowed down (lower) and softened, thinning out
  under   the card moving: a quiet air whoosh from claude-motion's generators (sfx_synth, MIT)
  0.66 s  it lands: Kenney Casino `card-place-1`

Pedalboard (Spotify, GPLv3 tool; nothing of it ships) warms, compresses and puts it in a small wooden room.
Then the same 60 Hz high-pass and loudness match as build_game_audio.py. Writes the trial and the current
`card-pickup` side by side, as WAV and as the app's own format, for Caleb to audition before anything is wired in.

  ~/.venvs/mm-audio/bin/python scripts/audio/trial_steal.py \\
      --kenney build_output/audio-sources/kenney-wav --out build_output/audio-trials/steal
"""
from __future__ import annotations

import argparse
import os
import random
import sys

import numpy as np
from fractions import Fraction

from pedalboard import Compressor, HighpassFilter, LowpassFilter, PeakFilter, Pedalboard, Reverb
from scipy.io import wavfile
from scipy.signal import resample_poly

sys.path.insert(0, os.path.dirname(__file__))
import build_game_audio as game  # noqa: E402
from gamedsp import SR, fade, highpass, loudness, match_loudness  # noqa: E402
from sfx_synth import synth  # noqa: E402

# Between a card pickup (-29) and exile (-24): a steal is a bigger moment than picking up a card.
TARGET_DB = -27.0
LAND_AT = 0.66


def shifted(x: np.ndarray, semitones: float) -> np.ndarray:
    """Tape-style: slowed down to lower the pitch (and lengthen it), which keeps foley natural. Pedalboard's
    PitchShift smeared these short grains into a faint ring around 4-6 kHz."""
    ratio = Fraction(2 ** (semitones / 12)).limit_denominator(200)
    return resample_poly(x, ratio.denominator, ratio.numerator).astype(np.float32)


def hook() -> np.ndarray:
    latch = game.kenney("rpg-audio__metalLatch", 0.03, 0.26, fade_out=0.05)
    return LowpassFilter(cutoff_frequency_hz=7000)(shifted(latch, -3), SR)


def chain(seed: int = 7) -> np.ndarray:
    """A run of links: short buckle grains, slower and quieter as the card nears its slot."""
    rng = random.Random(seed)
    grains = [game.kenney("rpg-audio__beltHandle1", 0.10, 0.17, fade_out=0.02),
              game.kenney("rpg-audio__beltHandle2", 0.18, 0.25, fade_out=0.02),
              game.kenney("rpg-audio__beltHandle2", 0.265, 0.33, fade_out=0.02)]
    parts, at = [], 0.09
    for i in range(7):
        g = shifted(grains[i % len(grains)], rng.uniform(-6.0, -3.5))
        parts.append((g, at, -3.0 - 1.0 * i))
        at += 0.065 + 0.008 * i
    return LowpassFilter(cutoff_frequency_hz=6000)(game.layer(*parts), SR)


def whoosh() -> np.ndarray:
    return np.asarray(synth.whoosh(0.62, 260, 1400, peak=0.55, q=0.9), dtype=np.float32)


def land() -> np.ndarray:
    return game.kenney("casino-audio__card-place-1", 0.14, 0.40, fade_out=0.08)


ROOM = Pedalboard([
    HighpassFilter(cutoff_frequency_hz=90),
    PeakFilter(cutoff_frequency_hz=260, gain_db=2.0, q=0.8),   # a little wood warmth
    LowpassFilter(cutoff_frequency_hz=9500),
    Compressor(threshold_db=-18, ratio=2.5, attack_ms=3, release_ms=80),
    Reverb(room_size=0.18, damping=0.6, wet_level=0.12, dry_level=0.9, width=0.0),
])


def r_steal(with_whoosh: bool = True) -> np.ndarray:
    parts = [(hook(), 0.0, 0.0), (chain(), 0.0, 0.0), (land(), LAND_AT, -6.0)]
    if with_whoosh:
        parts.append((whoosh(), 0.05, -22.0))
    x = game.layer(*parts)
    x = np.concatenate([x, np.zeros(int(0.25 * SR), dtype=np.float32)])   # room for the reverb tail
    return fade(ROOM(x, SR), 0.001, 0.12)


def finish(x: np.ndarray, target: float) -> np.ndarray:
    return match_loudness(highpass(x, 60, order=2), target, -1.0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kenney", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    game.KENNEY = args.kenney
    os.makedirs(args.out, exist_ok=True)
    takes = {
        "before-card-pickup": (game.r_card_pickup(), -29.0),
        "after-steal-chain": (r_steal(True), TARGET_DB),
        "after-steal-chain-dry": (r_steal(False), TARGET_DB),
    }
    for name, (x, target) in takes.items():
        y = finish(x, target)
        wavfile.write(os.path.join(args.out, name + ".wav"), SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
        info = game.write(name, y, args.out, False)
        print(f"{name:24s} {info['seconds']:.2f} s  loudness {loudness(y):6.1f} dB  peak {info['peak_db']:5.1f} dB  {info['file']}")


if __name__ == "__main__":
    main()
