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


def play_steel_only() -> np.ndarray:
    """Round 3 (Caleb: B, but just the steel, no flame behind it): the blade drawn on its own. Its ring has died
    away by 0.75 s, so it ends there instead of carrying silence."""
    return sonniss("Knife_Sword_Shing_Fienup_001", 0.05, 0.90, fade_out=0.3, stereo=True)


def play_bellows() -> np.ndarray:
    """The smithy's bellows breathing on the coals: a warm flare."""
    return sonniss("MEDIEVAL, Smithy - 24 - Bellows - Fire, oven accent", 0.05, 1.4, fade_out=0.5, stereo=True)


# Round 4 (Caleb: should a card hitting the battlefield sound different for an artifact, enchantment, creature or
# token?). Today every permanent that isn't a land or token plays creature-enter (a plank drop with a body hit).
# Each starts on the landing, like creature-enter, so it lines up with the tile arriving.
ARRIVAL_DB = {"artifact": -22.0, "enchantment": -23.0, "planeswalker": -21.0, "token": -25.0}


def card_down(gain: float = 0.0) -> tuple:
    return (kenney("casino-audio__card-place-1", 0.14, 0.45, fade_out=0.1), 0.0, gain)


def enter_artifact() -> np.ndarray:
    """A heavy brass or iron thing set on the table: the card, then a plate-metal clang, a little lower."""
    clang = slowed(sonniss("Plate_Impact_Hard_02", 0.02, 0.55, fade_out=0.2), -2)
    return tavern_room(layer(card_down(-3.0), (clang, 0.01, -2.0)))


def enter_enchantment() -> np.ndarray:
    """The card settles and a soft glassy shimmer blooms off it."""
    shimmer = sonniss("MAGIC GENERIC Texture, Shimmer, Processed Glass, Reversed Layer, Disturbing, High", 1.25, 2.25,
                      fade_in=0.06, fade_out=0.45)
    return tavern_room(layer(card_down(0.0), (shimmer, 0.02, -7.0)))


def enter_planeswalker() -> np.ndarray:
    """Arrives with weight and presence: the card, a deep slowed metal resonance, a magic tail."""
    weight = slowed(kenney("rpg-audio__bookPlace2", 0.0, 0.30, fade_out=0.08), -4)
    resonance = slowed(sonniss("Plate_Impact_Hard_02", 0.02, 0.70, fade_out=0.35), -7)
    tail = sonniss("Magic_Spells_Impact_Creation20", 0.05, 1.20, fade_out=0.5)
    return tavern_room(layer(card_down(-2.0), (weight, 0.0, -4.0), (resonance, 0.01, -9.0), (tail, 0.03, -6.0)))


def enter_token() -> np.ndarray:
    """A quick card flick out of nowhere, with a few particle sparks as the motes gather."""
    flick = kenney("casino-audio__card-fan-1", 0.17, 0.45, fade_out=0.1)
    motes = sonniss("MAGIC ENERGY Texture, Complex, Particles, Zap, Sparks, Short-Circuit, High, Sweetener 03",
                    0.0, 0.5, fade_in=0.03, fade_out=0.25)
    return tavern_room(layer((flick, 0.0, 0.0), (lowpass(motes, 8000), 0.0, -11.0)))


# Round 5 (Caleb: round 4 and today's creature/token "don't really sound good at all"). Round 4 ran 0.75-1.4 s,
# stacked three or four layers with slowing and a room, and leaned on sci-fi textures ("processed glass, disturbing",
# "zap, short-circuit") and an armour clang. Now each is short (0.3-0.7 s), dry and simple: a warm wood knock for the
# card meeting the table plus one accent that says what it is, from Kenney Impact/Interface Sounds (CC0) and the
# Sonniss board-game pieces. Two takes each.
def ks(name: str, gain: float = 0.0, at: float = 0.0, end: float | None = None) -> tuple:
    pack = "interface-sounds" if name.split("_")[0] in {"glass", "drop", "pluck", "bong", "select"} else "impact-sounds"
    return (kenney(f"{pack}__{name}", 0.0, end, fade_out=0.04), at, gain)


ROUND5 = {
    # name: (layers, loudness target)
    "creature-A-heavy-knock": (lambda: [ks("impactWood_heavy_002"), ks("impactSoft_heavy_001", -6.0)], -21.0),
    "creature-B-board-piece": (lambda: [(sonniss("Placing Pieces on the Board 2", 0.0, 0.13), 0.0, 0.0),
                                        ks("impactSoft_heavy_003", -8.0, 0.005)], -21.0),
    "artifact-A-metal-clink": (lambda: [ks("impactWood_medium_003"), ks("impactMetal_light_000", -2.0, 0.005)], -22.0),
    "artifact-B-tin-clink": (lambda: [ks("impactWood_medium_000"), ks("impactTin_medium_001", -3.0, 0.005)], -22.0),
    "enchantment-A-glass-ring": (lambda: [ks("impactWood_light_001"), ks("impactGlass_medium_002", -3.0, 0.01)], -23.0),
    "enchantment-B-glass-chime": (lambda: [ks("impactWood_light_001"), ks("glass_001", -5.0, 0.01)], -23.0),
    "planeswalker-A-bell": (lambda: [ks("impactWood_heavy_002"), ks("impactBell_heavy_002", -6.0, 0.01)], -21.0),
    "planeswalker-B-thud-bell": (lambda: [ks("impactWood_heavy_000"), ks("impactSoft_heavy_002", -6.0),
                                          ks("impactBell_heavy_003", -9.0, 0.02)], -21.0),
    "token-A-tap-pop": (lambda: [ks("impactWood_light_000", -2.0), ks("drop_002", -4.0, 0.01)], -25.0),
    "token-B-pop-tick": (lambda: [ks("drop_004"), ks("glass_005", -10.0, 0.03)], -25.0),
}


# Round 6 (2026-10-19): what Arena and Hearthstone do (docs: sounds say what the card *is*). One card slam in three
# sizes by mana value, the five basic lands each sounding like their place (Caleb asked for a frog in the Swamp), and a
# short colour layer over the medium slam for permanents. Dry, short, recordings only.
FROG_AT = 38.62   # a single croak in Soundrangers' night swamp (bursts every ~0.5 s around 38-39 s)


def card_dealt() -> np.ndarray:
    return sonniss("games - Deck of cards dealt on to felt table surface 43", 0.42, 0.80, fade_in=0.004, fade_out=0.12)


def slam(size: str) -> list:
    parts = [(card_dealt(), 0.0, 0.0)]
    if size == "light":
        parts.append(ks("impactSoft_medium_001", -6.0))
    else:
        parts += [ks("impactWood_heavy_002", -3.0), ks("impactSoft_heavy_001", -6.0)]
    if size == "heavy":
        boom = lowpass(sonniss("Bluezone_BC0237_impact_017", 0.30, 0.95, fade_in=0.004, fade_out=0.3), 3000)
        parts.append((boom, 0.0, -8.0))
    return parts


def bed(name: str, at: float, length: float, lo: float | None = None, hi: float | None = None) -> np.ndarray:
    """A moment of an ambience, faded in quickly and out slowly, optionally band-limited."""
    x = sonniss(name, at, at + length, fade_in=0.04, fade_out=length * 0.55)
    if lo:
        x = highpass(x, lo)
    if hi:
        x = lowpass(x, hi)
    return x


def frog() -> np.ndarray:
    return bed("swamp_ambience_night_05_120_loop", FROG_AT, 0.85, lo=300, hi=3200)


ROUND6 = {
    "slam-1-light": (lambda: slam("light"), -23.0),
    "slam-2-medium": (lambda: slam("medium"), -22.0),
    "slam-3-heavy": (lambda: slam("heavy"), -21.0),
    "land-plains": (lambda: slam("light") + [
        (bed("Wind,Ext,Gust,Grasslands,Rustle,Buffeting", 56.4, 0.9, lo=150, hi=6000), 0.0, -4.0),
        (bed("Amb, Field, Birds, Wind, MS_01", 8.3, 0.7, lo=1500), 0.15, -12.0)], -22.0),
    "land-island": (lambda: slam("light") + [
        (bed("water_lapping_sea_waves_sandy_beach_03", 0.8, 1.0, lo=120), 0.0, -3.0),
        (sonniss("LIQUID HIT Lake, Branch, Splash, Lake, Seaweed in Water, Small, CU 04", 0.0, 0.5, fade_out=0.25), 0.02, -8.0)],
        -22.0),
    "land-swamp": (lambda: slam("light") + [
        (lowpass(sonniss("LIQUID HIT Lake, Branch, Splash, Lake, Seaweed in Water, Small, CU 04", 0.0, 0.45, fade_out=0.2),
                 2500), 0.0, -3.0),
        (sonniss("soil and dirt debris heavy 13", 0.03, 0.30, fade_out=0.12), 0.02, -12.0),
        (frog(), 0.18, -4.0)], -22.0),
    "land-mountain": (lambda: slam("light") + [
        (sonniss("rock impact medium 26", 0.08, 0.60, fade_out=0.25), 0.0, -2.0),
        (sonniss("rock tumble down debris long 06", 0.15, 0.85, fade_in=0.02, fade_out=0.35), 0.08, -11.0)], -22.0),
    "land-forest": (lambda: slam("light") + [
        (sonniss("leaves_pile_pick_up_04", 0.45, 0.95, fade_in=0.02, fade_out=0.25), 0.0, -6.0),
        (sonniss("tree_dead_tree_limb_impact_05", 0.20, 0.55, fade_out=0.15), 0.0, -10.0),
        (bed("NS01_007_Forest birds", 89.8, 0.9, lo=1500), 0.1, -9.0)], -22.0),
    "colour-white": (lambda: slam("medium") + [ks("impactBell_heavy_003", -9.0, 0.01),
        (bed("Wind,Ext,Gust,Grasslands,Rustle,Buffeting", 56.4, 0.5, lo=400, hi=6000), 0.0, -14.0)], -21.0),
    "colour-blue": (lambda: slam("medium") + [
        (sonniss("LIQUID HIT Lake, Branch, Splash, Lake, Seaweed in Water, Small, CU 04", 0.0, 0.55, fade_out=0.25), 0.0, -5.0)],
        -21.0),
    "colour-black": (lambda: slam("medium") + [
        (lowpass(sonniss("soil and dirt debris heavy 13", 0.03, 0.45, fade_out=0.2), 2500), 0.0, -7.0),
        (lowpass(sonniss("Bluezone_BC0237_impact_017", 0.30, 0.95, fade_out=0.35), 900), 0.0, -12.0)], -21.0),
    "colour-red": (lambda: slam("medium") + [
        (sonniss("sm-fire-firewood-small-03-DPAmono", 1.30, 1.95, fade_in=0.01, fade_out=0.3), 0.0, -5.0)], -21.0),
    "colour-green": (lambda: slam("medium") + [
        (sonniss("leaves_pile_pick_up_04", 0.45, 0.85, fade_in=0.02, fade_out=0.2), 0.0, -7.0),
        (bed("Amb, Field, Birds, Wind, MS_01", 8.3, 0.6, lo=1800), 0.05, -15.0)], -21.0),
    "colour-colourless": (lambda: slam("medium") + [ks("impactMetal_light_000", -4.0, 0.005)], -21.0),
}


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
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    game.SONNISS, game.KENNEY = args.sonniss, args.kenney
    os.makedirs(args.out, exist_ok=True)
    if args.only:
        wanted = set(args.only.split(","))
    takes = {
        "enter-artifact": (enter_artifact, ARRIVAL_DB["artifact"], False),
        "enter-enchantment": (enter_enchantment, ARRIVAL_DB["enchantment"], False),
        "enter-planeswalker": (enter_planeswalker, ARRIVAL_DB["planeswalker"], False),
        "enter-token-new": (enter_token, ARRIVAL_DB["token"], False),
        "play-commander-D-steel-only": (play_steel_only, PLAY_DB, True),
        "book-open-A-book": (lambda: book_open(False), BOOK_DB, False),
        "book-open-B-book-sparkle": (lambda: book_open(True), BOOK_DB, False),
        "book-close-A": (book_close, BOOK_DB, False),
        "play-commander-A-torch": (play_torch, PLAY_DB, True),
        "play-commander-B-steel": (play_steel, PLAY_DB, True),
        "play-commander-C-bellows": (play_bellows, PLAY_DB, True),
    }
    for name in ("ui-open.m4a", "page-flip.m4a", "menu-play.m4a", "creature-enter.caf", "token-create.m4a", "land-drop.m4a"):
        if not os.path.exists(os.path.join(args.shipped, name)):
            name = name.replace(".caf", ".m4a") if name.endswith(".caf") else name.replace(".m4a", ".caf")
        x = shipped(os.path.join(args.shipped, name))
        wavfile.write(os.path.join(args.out, "before-" + name.rsplit(".", 1)[0] + ".wav"), SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    for name, (layers, target) in {**ROUND5, **ROUND6}.items():
        takes[name] = ((lambda layers=layers: layer(*layers())), target, False)
    for name, (recipe, target, stereo) in takes.items():
        if args.only and name not in wanted:
            continue
        y = match_loudness(highpass(recipe(), 60, order=2), target, -1.0)
        # Sharp knocks hit the -1 dB ceiling before their loudness target; a fast limiter lets them reach it.
        limit = -6.0
        while loudness(y) < target - 0.5 and limit > -18.0:
            from pedalboard import Limiter
            y = match_loudness(Limiter(threshold_db=limit, release_ms=50)(y.astype(np.float32), SR), target, -1.0)
            limit -= 3.0
        if y.ndim == 2 and not stereo:
            y = y.mean(axis=1)
        wavfile.write(os.path.join(args.out, name + ".wav"), SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
        info = game.write(name, y, args.out, stereo)
        print(f"{name:26s} {info['seconds']:.2f} s  loudness {loudness(y):6.1f} dB  peak {info['peak_db']:5.1f} dB")


if __name__ == "__main__":
    main()
