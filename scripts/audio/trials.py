#!/usr/bin/env python3
"""Audition candidates for cues being reworked, rendered next to the shipped sound, before any is wired in.

Each candidate runs through the same 60 Hz high-pass and loudness match as build_game_audio.py, and is written as
WAV (to send) and in the app's own format. Same sources and virtualenv as build_game_audio.py (scripts/audio/SOURCES.md).

  ~/.venvs/mm-audio/bin/python scripts/audio/trials.py --sonniss build_output/audio-sources/sonniss-wav \\
      --kenney build_output/audio-sources/kenney-wav --shipped apps/ios/MagicMobile/Resources/Audio \\
      --out build_output/audio-trials/round-2

Round 2 (2026-10-19, Caleb: opening and closing Deck Studio, pressing Play Commander):
- `book-open` / `book-close`: the spell book film (Resources/Grimoire, 1.43 s; the sound starts 0.2 s before the
  film plays, while its view fades in). Today opening plays ui-open twice plus page-flip, and closing a page-flip.
- `menu-play`: Play Commander. Today a 1.4 s airy magic impact.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(__file__))
import build_game_audio as game  # noqa: E402
from build_game_audio import kenney, layer, slowed, sonniss, tavern_room  # noqa: E402
from gamedsp import SR, highpass, loudness, lowpass, match_loudness  # noqa: E402
from sfx_synth import synth  # noqa: E402

BOOK_DB = -26.0   # between a page turn (-28) and a confirm (-26): the book is a 1.4 s moment of its own
PLAY_DB = -20.0   # menu-play's level today


def sparkle() -> np.ndarray:
    """The glints that drift off the opening pages: a soft, high bell chord, low in the mix."""
    bell = np.asarray(synth.chime([1568.0, 2349.3, 3136.0], dur=0.9, tau=0.32), dtype=np.float32)
    return lowpass(bell / (np.abs(bell).max() + 1e-9), 6500)


def book_open(with_sparkle: bool) -> np.ndarray:
    clasp = slowed(kenney("rpg-audio__metalClick", 0.05, 0.20, fade_out=0.04), -2)
    hinge = slowed(kenney("rpg-audio__creak3", 0.04, 0.34, fade_out=0.08), -3)
    cover = sonniss("PM_BA_BOOK_0_29 Book, Open, Paper", 0.10, 1.30, fade_in=0.01, fade_out=0.25)
    pages = sonniss("PM_BA_BOOK_2_6 Book, Paper, Page Turn", 0.10, 0.75, fade_in=0.01, fade_out=0.15)
    parts = [(clasp, 0.30, -8.0), (hinge, 0.36, -14.0), (cover, 0.24, 0.0), (pages, 0.70, -7.0)]
    if with_sparkle:
        parts.append((sparkle(), 0.55, -24.0))
    return tavern_room(layer(*parts))


def book_close() -> np.ndarray:
    pages = sonniss("PM_BA_BOOK_2_6 Book, Paper, Page Turn", 0.10, 0.70, fade_in=0.01, fade_out=0.12)
    cover = sonniss("shut_small_book_002", 0.0, 0.29, fade_out=0.06)
    table = slowed(kenney("rpg-audio__bookPlace2", 0.0, 0.30, fade_out=0.08), -3)
    clasp = slowed(kenney("rpg-audio__metalLatch", 0.02, 0.26, fade_out=0.05), -2)
    return tavern_room(layer((pages, 0.52, -6.0), (cover, 1.12, 0.0), (table, 1.19, -6.0), (clasp, 1.40, -9.0)))


def wide(x: np.ndarray) -> np.ndarray:
    return x if x.ndim == 2 else np.stack([x, x], axis=1)


def play_torch() -> np.ndarray:
    """A torch catching: a fire ignition with a soft wooden knock underneath for weight."""
    fire = sonniss("Designed Fire - Impacts - Large, ignition 03", 0.0, 1.4, fade_out=0.5, stereo=True)
    knock = wide(slowed(kenney("rpg-audio__bookPlace2", 0.0, 0.30, fade_out=0.08), -5))
    return layer((fire, 0.0, 0.0), (knock, 0.0, -8.0))


def play_steel() -> np.ndarray:
    """A blade drawn, with fire catching behind it."""
    shing = sonniss("Knife_Sword_Shing_Fienup_001", 0.05, 1.30, fade_out=0.45, stereo=True)
    fire = sonniss("Designed Fire - Impacts - Large, ignition 03", 0.0, 1.3, fade_out=0.5, stereo=True)
    return layer((shing, 0.0, 0.0), (fire, 0.08, -9.0))


def play_bellows() -> np.ndarray:
    """The smithy's bellows breathing on the coals: a warm flare."""
    return sonniss("MEDIEVAL, Smithy - 24 - Bellows - Fire, oven accent", 0.05, 1.4, fade_out=0.5, stereo=True)


def shipped(path: str) -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "x.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEF32@44100", path, wav], check=True)
        _, x = wavfile.read(wav)
    return x.astype(np.float32)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sonniss", required=True)
    parser.add_argument("--kenney", required=True)
    parser.add_argument("--shipped", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    game.SONNISS, game.KENNEY = args.sonniss, args.kenney
    os.makedirs(args.out, exist_ok=True)
    takes = {
        "book-open-A-book": (lambda: book_open(False), BOOK_DB, False),
        "book-open-B-book-sparkle": (lambda: book_open(True), BOOK_DB, False),
        "book-close-A": (book_close, BOOK_DB, False),
        "play-commander-A-torch": (play_torch, PLAY_DB, True),
        "play-commander-B-steel": (play_steel, PLAY_DB, True),
        "play-commander-C-bellows": (play_bellows, PLAY_DB, True),
    }
    for name in ("ui-open.m4a", "page-flip.m4a", "menu-play.m4a"):
        x = shipped(os.path.join(args.shipped, name))
        wavfile.write(os.path.join(args.out, "before-" + name.replace(".m4a", ".wav")), SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    for name, (recipe, target, stereo) in takes.items():
        y = match_loudness(highpass(recipe(), 60, order=2), target, -1.0)
        if y.ndim == 2 and not stereo:
            y = y.mean(axis=1)
        wavfile.write(os.path.join(args.out, name + ".wav"), SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
        info = game.write(name, y, args.out, stereo)
        print(f"{name:26s} {info['seconds']:.2f} s  loudness {loudness(y):6.1f} dB  peak {info['peak_db']:5.1f} dB")


if __name__ == "__main__":
    main()
