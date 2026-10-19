#!/usr/bin/env python3
"""Render MagicMobile's sound effects and music into apps/ios/MagicMobile/Resources/Audio.

Every cue is a professional recording, trimmed, faded and loudness-matched here. No
synthesized layers (build 19 replaced them after play-testing). Sources and licenses are
listed in scripts/audio/SOURCES.md and in the app's Resources/Audio/CREDITS.txt:
  * Sonniss.com GDC Game Audio Bundles 2016-2020 (royalty-free, no attribution required).
    Files are fetched one by one from the official mirror listed on sonniss.com/gameaudiogdc.
  * Kenney.nl Casino Audio and RPG Audio (CC0 1.0) for card handling, metal and books.
  * Kevin MacLeod (incompetech.com), CC BY 4.0, for music and orchestral stingers.

Requires numpy, scipy and pedalboard (a scratch virtualenv is enough, e.g. ~/.venvs/mm-audio) plus macOS
`afconvert`. Pedalboard is only a build tool here (EQ, compression, a small room); nothing of it ships.
Sources are 44.1 kHz float WAVs converted with `afconvert -f WAVE -d LEF32@44100`, named
after the original files. Usage (from the repo root):
  build_game_audio.py --sonniss DIR --kenney DIR --music DIR \
      --out apps/ios/MagicMobile/Resources/Audio [--only name,...]
The loudness report is written to scripts/audio/audio-manifest.json.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

from fractions import Fraction

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly

sys.path.insert(0, os.path.dirname(__file__))
from gamedsp import SR, fade, highpass, loudness, lowpass, match_loudness, n_of, normalize  # noqa: E402

SONNISS: str = ""
KENNEY: str = ""
MUSIC: str = ""


def load(directory: str, name: str, start: float = 0.0, end: float | None = None, fade_in: float = 0.002,
         fade_out: float = 0.03, stereo: bool = False) -> np.ndarray:
    """One slice of a source recording, faded at both ends so no cut clicks."""
    sr, x = wavfile.read(os.path.join(directory, name + ".wav"))
    assert sr == SR, name
    x = x.astype(np.float32)
    if x.ndim == 2 and not stereo:
        x = x.mean(axis=1)
    elif x.ndim == 1 and stereo:
        x = np.stack([x, x], axis=1)
    x = x[n_of(start): n_of(end) if end is not None else len(x)]
    return fade(normalize(x, -1.0), fade_in, fade_out)


def sonniss(name: str, start: float = 0.0, end: float | None = None, fade_in: float = 0.002,
            fade_out: float = 0.03, stereo: bool = False) -> np.ndarray:
    return load(SONNISS, name, start, end, fade_in, fade_out, stereo)


def kenney(name: str, start: float = 0.0, end: float | None = None, fade_out: float = 0.02) -> np.ndarray:
    return load(KENNEY, name, start, end, 0.001, fade_out)


def layer(*parts: tuple[np.ndarray, float, float]) -> np.ndarray:
    """(signal, start seconds, gain dB) layers of the same channel count."""
    end = max(n_of(at) + len(x) for x, at, _ in parts)
    shape = (end, 2) if parts[0][0].ndim == 2 else (end,)
    out = np.zeros(shape, dtype=np.float32)
    for x, at, gain in parts:
        s = n_of(at)
        out[s: s + len(x)] += x * 10 ** (gain / 20)
    return out


def slowed(x: np.ndarray, semitones: float) -> np.ndarray:
    """Tape-style: slowed down to lower the pitch (and lengthen it), which keeps foley natural. Pedalboard's
    PitchShift smears grains this short into a faint ring (docs/LESSONS.md)."""
    ratio = Fraction(2 ** (semitones / 12)).limit_denominator(200)
    return resample_poly(x, ratio.denominator, ratio.numerator, axis=0).astype(np.float32)


def tavern_room(x: np.ndarray, wet: float = 0.12, tail: float = 0.25) -> np.ndarray:
    """A little wood warmth, gentle compression and a small wooden room, for layered foley."""
    from pedalboard import Compressor, HighpassFilter, LowpassFilter, PeakFilter, Pedalboard, Reverb
    board = Pedalboard([
        HighpassFilter(cutoff_frequency_hz=90),
        PeakFilter(cutoff_frequency_hz=260, gain_db=2.0, q=0.8),
        LowpassFilter(cutoff_frequency_hz=9500),
        Compressor(threshold_db=-18, ratio=2.5, attack_ms=3, release_ms=80),
        Reverb(room_size=0.18, damping=0.6, wet_level=wet, dry_level=0.9, width=0.0),
    ])
    padded = np.concatenate([x, np.zeros((int(tail * SR),) + x.shape[1:], dtype=np.float32)])
    y = board(padded.T if padded.ndim == 2 else padded, SR)
    return fade((y.T if padded.ndim == 2 else y).astype(np.float32), 0.001, 0.12)


# ------------------------------------------------------------------ interface
def r_ui_tap():
    return sonniss("Bluezone_BC0268_switch_button_click_small_005", 0.0, 0.12)


def r_ui_confirm():
    # Two soft marimba notes: a warm wooden "yes".
    return sonniss("marimba_tone_007", 0.0, 0.42, fade_out=0.12)


def r_ui_back():
    return sonniss("UI_SoundPack11_Back_v1", 0.49, 0.75)


def r_ui_open():
    return sonniss("NOTEPAD_Page_Turn_4", 0.55, 1.05, fade_in=0.02, fade_out=0.12)


def r_ui_close():
    return sonniss("shut_small_book_002", 0.0, 0.2)


def r_ui_toggle():
    return sonniss("Scatter Plops 04", 0.14, 0.25)


def r_ui_tick():
    return sonniss("UI_Mechanical_Move_40", 0.0, 0.1)


def r_ui_error():
    return sonniss("owl_notification_005", 0.0, 0.3, fade_out=0.05)


def r_response_alert():
    # Balafon, an octave up: "your decision".
    return sonniss("BALAFON - NOTIF OCT UP", 0.22, 1.2, fade_out=0.3, stereo=True)


def r_menu_play():
    """Play Commander (and the other "go" buttons: Ranked, Quick Match, a combo loop): a blade drawn. Caleb picked it
    without the fire behind it (trials.py round 3), 2026-10-19; until then an airy magic impact."""
    return sonniss("Knife_Sword_Shing_Fienup_001", 0.05, 0.90, fade_out=0.3, stereo=True)


def r_page_flip():
    return sonniss("CATALOGUE_Page_Turn_9", 0.38, 0.78, fade_in=0.01, fade_out=0.08)


def r_book_open():
    """Deck Studio's spell book opening (Resources/Grimoire film, 1.43 s; the cue starts 0.2 s before the film plays):
    the clasp clicks, the cover creaks as it lifts, the book opens and its pages riffle as the parchment fills the
    screen. Caleb picked it (trials.py round 2, take A), 2026-10-19."""
    clasp = slowed(kenney("rpg-audio__metalClick", 0.05, 0.20, fade_out=0.04), -2)
    hinge = slowed(kenney("rpg-audio__creak3", 0.04, 0.34, fade_out=0.08), -3)
    cover = sonniss("PM_BA_BOOK_0_29 Book, Open, Paper", 0.10, 1.30, fade_in=0.01, fade_out=0.25)
    pages = sonniss("PM_BA_BOOK_2_6 Book, Paper, Page Turn", 0.10, 0.75, fade_in=0.01, fade_out=0.15)
    return tavern_room(layer((clasp, 0.30, -8.0), (hinge, 0.36, -14.0), (cover, 0.24, 0.0), (pages, 0.70, -7.0)))


def r_book_close():
    """The book closing again on the same film timing: the pages riffle shut, the cover lands on the table, the
    clasp latches."""
    pages = sonniss("PM_BA_BOOK_2_6 Book, Paper, Page Turn", 0.10, 0.70, fade_in=0.01, fade_out=0.12)
    cover = sonniss("shut_small_book_002", 0.0, 0.29, fade_out=0.06)
    table = slowed(kenney("rpg-audio__bookPlace2", 0.0, 0.30, fade_out=0.08), -3)
    clasp = slowed(kenney("rpg-audio__metalLatch", 0.02, 0.26, fade_out=0.05), -2)
    return tavern_room(layer((pages, 0.52, -6.0), (cover, 1.12, 0.0), (table, 1.19, -6.0), (clasp, 1.40, -9.0)))


def r_emote():
    return sonniss("User Interface Notification Bubbles 04", 0.0, 0.34, fade_out=0.1, stereo=True)


# ------------------------------------------------------------------ cards
def r_card_draw(variant: int):
    if variant == 2:
        return sonniss("Gathering a pile of small cards 05", 2.59, 3.1, fade_in=0.01, fade_out=0.12)
    return kenney(["casino-audio__card-slide-1", "casino-audio__card-slide-3"][variant])


def r_card_pickup():
    return kenney("casino-audio__card-slide-4", 0.0, 0.16, fade_out=0.06)


def r_card_play():
    tap = sonniss("games - Deck of cards handled, shuffled and tapped onto table 1", 1.46, 1.66, fade_out=0.06)
    return layer((kenney("casino-audio__card-shove-4"), 0.0, -2), (tap, 0.04, -4))


def r_shuffle():
    return sonniss("games - Deck of cards handled, shuffled and tapped onto table 1", 0.18, 1.8, fade_out=0.2)


# ------------------------------------------------------------------ board
def r_land_drop():
    piece = sonniss("Placing Pieces on the Board 2", 0.0, 0.13)
    plank = lowpass(sonniss("Drop Soft - Single Plank, Drop 02", 0.0, 0.3, fade_out=0.08), 5000)
    return layer((kenney("casino-audio__card-place-3"), 0.0, -3), (piece, 0.0, -2), (plank, 0.01, -8))


def r_counter():
    return sonniss("Scatter Plops 04", 0.25, 0.36)


def r_steal():
    """The board's steal (BoardFX controlChanged), from the moment the taker's chain hooks the card: the hook
    bites (a latch, slowed to a heavier brass clink), the chain's links run as the card is dragged (belt-buckle
    grains, slowed and thinning out), and the card lands 0.66 s later. Caleb picked it dry, 2026-10-19."""
    from pedalboard import LowpassFilter
    hook = LowpassFilter(cutoff_frequency_hz=7000)(slowed(kenney("rpg-audio__metalLatch", 0.03, 0.26, fade_out=0.05), -3), SR)
    grains = [kenney("rpg-audio__beltHandle1", 0.10, 0.17, fade_out=0.02),
              kenney("rpg-audio__beltHandle2", 0.18, 0.25, fade_out=0.02),
              kenney("rpg-audio__beltHandle2", 0.265, 0.33, fade_out=0.02)]
    shifts = [-5.1904, -5.6229, -4.3727, -5.8189, -4.6603, -5.0858, -5.855]   # the trial Caleb heard
    links, at = [], 0.09
    for i, shift in enumerate(shifts):
        links.append((slowed(grains[i % len(grains)], shift), at, -3.0 - 1.0 * i))
        at += 0.065 + 0.008 * i
    land = kenney("casino-audio__card-place-1", 0.14, 0.40, fade_out=0.08)
    chain = LowpassFilter(cutoff_frequency_hz=6000)(layer(*links), SR)
    return tavern_room(layer((hook, 0.0, 0.0), (chain, 0.0, 0.0), (land, 0.66, -6.0)))


# ------------------------------------------------------------------ cards arriving (Caleb picked round 6, 2026-10-19)
# Like Arena and Hearthstone, an arrival says what the card is: a card slam sized by mana value, the basic lands each
# sounding like their place, and a short colour layer that the apps play over the slam (one per colour, up to two).
FROG_AT = 38.62   # a single croak in Soundrangers' night swamp (bursts every ~0.5 s around 38-39 s)


def ks(name: str, gain: float = 0.0, at: float = 0.0, end: float | None = None) -> tuple:
    """A Kenney Impact or Interface Sounds take as a (signal, start, gain dB) layer."""
    pack = "interface-sounds" if name.split("_")[0] in {"glass", "drop", "pluck", "bong", "select"} else "impact-sounds"
    return (kenney(f"{pack}__{name}", 0.0, end, fade_out=0.04), at, gain)


def card_dealt() -> np.ndarray:
    return sonniss("games - Deck of cards dealt on to felt table surface 43", 0.42, 0.80, fade_in=0.004, fade_out=0.12)


def slam_parts(size: str) -> list:
    """A card dealt onto felt with a thud under it; medium adds a wood knock, heavy a low boom."""
    parts = [(card_dealt(), 0.0, 0.0)]
    if size == "light":
        parts.append(ks("impactSoft_medium_001", -6.0))
    else:
        parts += [ks("impactWood_heavy_002", -3.0), ks("impactSoft_heavy_001", -6.0)]
    if size == "heavy":
        parts.append((lowpass(sonniss("Bluezone_BC0237_impact_017", 0.30, 0.95, fade_in=0.004, fade_out=0.3), 3000), 0.0, -8.0))
    return parts


def bed(name: str, at: float, length: float, lo: float | None = None, hi: float | None = None) -> np.ndarray:
    """A moment of an ambience, faded in quickly and out slowly, optionally band-limited."""
    x = sonniss(name, at, at + length, fade_in=0.04, fade_out=length * 0.55)
    if lo:
        x = highpass(x, lo)
    if hi:
        x = lowpass(x, hi)
    return x


def splash(end: float = 0.5, fade_out: float = 0.25) -> np.ndarray:
    return sonniss("LIQUID HIT Lake, Branch, Splash, Lake, Seaweed in Water, Small, CU 04", 0.0, end, fade_out=fade_out)


LAND_LAYERS = {
    "plains": lambda: [(bed("Wind,Ext,Gust,Grasslands,Rustle,Buffeting", 56.4, 0.9, lo=150, hi=6000), 0.0, -4.0),
                       (bed("Amb, Field, Birds, Wind, MS_01", 8.3, 0.7, lo=1500), 0.15, -12.0)],
    "island": lambda: [(bed("water_lapping_sea_waves_sandy_beach_03", 0.8, 1.0, lo=120), 0.0, -3.0), (splash(), 0.02, -8.0)],
    "swamp": lambda: [(lowpass(splash(0.45, 0.2), 2500), 0.0, -3.0),
                      (sonniss("soil and dirt debris heavy 13", 0.03, 0.30, fade_out=0.12), 0.02, -12.0),
                      (bed("swamp_ambience_night_05_120_loop", FROG_AT, 0.85, lo=300, hi=3200), 0.18, -4.0)],
    "mountain": lambda: [(sonniss("rock impact medium 26", 0.08, 0.60, fade_out=0.25), 0.0, -2.0),
                         (sonniss("rock tumble down debris long 06", 0.15, 0.85, fade_in=0.02, fade_out=0.35), 0.08, -11.0)],
    "forest": lambda: [(sonniss("leaves_pile_pick_up_04", 0.45, 0.95, fade_in=0.02, fade_out=0.25), 0.0, -6.0),
                       (sonniss("tree_dead_tree_limb_impact_05", 0.20, 0.55, fade_out=0.15), 0.0, -10.0),
                       (bed("NS01_007_Forest birds", 89.8, 0.9, lo=1500), 0.1, -9.0)],
}

COLOUR_LAYERS = {
    "white": lambda: [ks("impactBell_heavy_003", -9.0, 0.01),
                      (bed("Wind,Ext,Gust,Grasslands,Rustle,Buffeting", 56.4, 0.5, lo=400, hi=6000), 0.0, -14.0)],
    "blue": lambda: [(splash(0.55), 0.0, -5.0)],
    "black": lambda: [(lowpass(sonniss("soil and dirt debris heavy 13", 0.03, 0.45, fade_out=0.2), 2500), 0.0, -7.0),
                      (lowpass(sonniss("Bluezone_BC0237_impact_017", 0.30, 0.95, fade_out=0.35), 900), 0.0, -12.0)],
    "red": lambda: [(sonniss("sm-fire-firewood-small-03-DPAmono", 1.30, 1.95, fade_in=0.01, fade_out=0.3), 0.0, -5.0)],
    "green": lambda: [(sonniss("leaves_pile_pick_up_04", 0.45, 0.85, fade_in=0.02, fade_out=0.2), 0.0, -7.0),
                      (bed("Amb, Field, Birds, Wind, MS_01", 8.3, 0.6, lo=1800), 0.05, -15.0)],
    "colorless": lambda: [ks("impactMetal_light_000", -4.0, 0.005)],
}
SLAM_DB = {"light": -23.0, "medium": -22.0, "heavy": -21.0}


def reach(x: np.ndarray, target: float) -> np.ndarray:
    """Match loudness; sharp knocks hit the -1 dB ceiling first, so a fast limiter lets them reach the target (the same
    steps trials.py used for what Caleb auditioned)."""
    from pedalboard import Limiter
    y, limit = match_loudness(x, target, -1.0), -6.0
    while loudness(y) < target - 0.5 and limit > -18.0:
        y = match_loudness(Limiter(threshold_db=limit, release_ms=50)(y.astype(np.float32), SR), target, -1.0)
        limit -= 3.0
    return y


def r_slam(size: str):
    return lambda: layer(*slam_parts(size))


def r_land(kind: str):
    return lambda: layer(*slam_parts("light"), *LAND_LAYERS[kind]())


def r_colour_layer(colour: str):
    """The colour layer alone, which the apps play over the slam. Caleb auditioned slam + layer levelled together as one
    mix at -21 dB; here the layer gets the level at which the shipped medium slam plus this layer is that loud again.
    Already levelled: CUES gives it no loudness target."""
    def recipe() -> np.ndarray:
        slam = reach(highpass(layer(*slam_parts("medium")), 60, order=2), SLAM_DB["medium"])
        texture = highpass(layer(*COLOUR_LAYERS[colour]()), 60, order=2)
        n = max(len(slam), len(texture))

        def together(gain: float) -> float:
            mix = np.zeros(n, dtype=np.float32)
            mix[:len(slam)] += slam
            mix[:len(texture)] += texture * gain
            return loudness(mix)

        lo, hi = 0.0, 4.0
        for _ in range(40):   # loudness grows with the layer's gain
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if together(mid) < -21.0 else (lo, mid)
        return texture * lo
    return recipe


ARRIVAL_CUES = {"slam-light", "slam-medium", "slam-heavy", "land-plains", "land-island", "land-swamp", "land-mountain",
                "land-forest"}


def r_ability():
    return sonniss("Arcane_Spell_Doppler_Shift_03", 0.0, 0.35, fade_out=0.12, stereo=True)


# ------------------------------------------------------------------ spells by color
def r_cast_white():
    return sonniss("Ice_Spell_Ice_Spell_Buff_Positive_02", 0.0, 0.85, fade_out=0.3, stereo=True)


def r_cast_blue():
    return sonniss("Magic_Spells_CastShort_Water_General07", 0.1, 1.6, fade_in=0.04, fade_out=0.5, stereo=True)


def r_cast_black():
    return sonniss("Dark_Spell_Life_Tap_03", 0.05, 1.5, fade_out=0.5, stereo=True)


def r_cast_red():
    return sonniss("Fire_Spell_Dragon_Trap_03", 0.3, 1.7, fade_in=0.03, fade_out=0.5, stereo=True)


def r_cast_green():
    return sonniss("MAGIC AIR Large Whoosh, Swirl, Wind Gust, Foliage 01", 0.3, 1.7, fade_in=0.05, fade_out=0.4,
                   stereo=True)


def r_cast_colorless():
    return sonniss("Magic_Spells_Impact_Creation20", 0.0, 1.1, fade_out=0.35, stereo=True)


def r_cast_multi():
    return sonniss("Magic_Transformation03", 0.15, 1.8, fade_in=0.05, fade_out=0.5, stereo=True)


def r_spell_big():
    return sonniss("Magic_Explosion_Short19", 0.0, 0.95, fade_out=0.3, stereo=True)


def r_commander_cast():
    swell = sonniss("Magic_Transformation03", 0.1, 2.2, fade_in=0.05, fade_out=0.6, stereo=True)
    hit = sonniss("Magic_Explosion_Short19", 0.0, 0.95, fade_out=0.3, stereo=True)
    return layer((swell, 0.0, 0), (hit, 0.42, -4))


# ------------------------------------------------------------------ combat and life
def r_attack(variant: int):
    start, end = [(0.09, 0.4), (0.58, 0.84), (1.08, 1.36)][variant]
    return sonniss("Fast Action Swish_HW 05", start, end, fade_out=0.06)


def r_block():
    return sonniss("Weapon_Impact_Parry_01", 0.08, 0.62, fade_out=0.15, stereo=True)


def r_strike():
    return sonniss("punch_general_body_impact_03", 0.0, 0.2, fade_out=0.06)


def r_player_hit():
    punch = sonniss("punch_heavy_huge_distorted_01", 0.0, 0.4, fade_out=0.1, stereo=True)
    crunch = sonniss("Bluezone_BC0237_impact_017", 0.0, 0.6, fade_out=0.25, stereo=True)
    return layer((punch, 0.0, 0), (crunch, 0.0, -7))


def r_death():
    return lowpass(sonniss("Misc_Glass_Crystal_Shatter", 0.0, 0.7, fade_out=0.3, stereo=True), 9000)


def r_exile():
    return sonniss("Whoosh,Sound Design,Logo,Airy to Shiver,Uncertain,Low", 0.9, 2.6, fade_in=0.1, fade_out=0.35,
                   stereo=True)


def r_life_gain():
    return sonniss("collect_item_14", 0.0, 0.9, fade_out=0.35, stereo=True)


def r_life_loss():
    return sonniss("Magic_Spells_CastShort_Push14", 0.03, 0.9, fade_out=0.3, stereo=True)


# ------------------------------------------------------------------ big moments
def r_turn_you():
    return sonniss("Impact,Sound Design,Hit,Chime,Resonant Hit,Chime Accent,Tinkle,Fast", 0.0, 2.0,
                   fade_out=0.8, stereo=True)


def music(name: str, start: float, end: float, fade_in: float, fade_out: float) -> np.ndarray:
    return load(MUSIC, name, start, end, fade_in, fade_out, stereo=True)


def r_versus():
    return music("Danse Macabre - Big Hit 1", 0.45, 3.2, 0.005, 0.8)


def r_victory():
    return music("Discovery Hit", 4.4, 11.6, 0.15, 1.2)


def r_defeat():
    return music("Greta Sting", 1.0, 9.8, 0.3, 1.8)


def r_dice_roll():
    return sonniss("DICE on Hard Wood, Throw and Roll , Standard, 2 Two Dice, v1", 0.0, 0.7, fade_out=0.1)


def r_dice_land():
    return sonniss("Backgammon Piece 21", 0.0, 0.2)


# ------------------------------------------------------------------ catalogue
CUES: dict[str, tuple] = {
    # name: (recipe, loudness target dBFS (phone weighted), stereo?)
    "ui-tap": (r_ui_tap, -31, False),
    "ui-confirm": (r_ui_confirm, -26, False),
    "ui-back": (r_ui_back, -31, False),
    "ui-open": (r_ui_open, -31, False),
    "ui-close": (r_ui_close, -32, False),
    "ui-toggle": (r_ui_toggle, -30, False),
    "ui-tick": (r_ui_tick, -33, False),
    "ui-error": (r_ui_error, -28, False),
    "response-alert": (r_response_alert, -25, True),
    "menu-play": (r_menu_play, -20, True),
    "page-flip": (r_page_flip, -28, False),
    "book-open": (r_book_open, -26, False),
    "book-close": (r_book_close, -26, False),
    "emote": (r_emote, -26, True),
    "card-draw-1": (lambda: r_card_draw(0), -25, False),
    "card-draw-2": (lambda: r_card_draw(1), -25, False),
    "card-draw-3": (lambda: r_card_draw(2), -25, False),
    "card-pickup": (r_card_pickup, -29, False),
    "card-play": (r_card_play, -23, False),
    "shuffle": (r_shuffle, -24, False),
    "land-drop": (r_land_drop, -22, False),
    "counter": (r_counter, -30, False),
    "ability": (r_ability, -27, True),
    "steal": (r_steal, -27, False),
    "slam-light": (r_slam("light"), SLAM_DB["light"], False),
    "slam-medium": (r_slam("medium"), SLAM_DB["medium"], False),
    "slam-heavy": (r_slam("heavy"), SLAM_DB["heavy"], False),
    "land-plains": (r_land("plains"), -22, False),
    "land-island": (r_land("island"), -22, False),
    "land-swamp": (r_land("swamp"), -22, False),
    "land-mountain": (r_land("mountain"), -22, False),
    "land-forest": (r_land("forest"), -22, False),
    "layer-white": (r_colour_layer("white"), None, False),
    "layer-blue": (r_colour_layer("blue"), None, False),
    "layer-black": (r_colour_layer("black"), None, False),
    "layer-red": (r_colour_layer("red"), None, False),
    "layer-green": (r_colour_layer("green"), None, False),
    "layer-colorless": (r_colour_layer("colorless"), None, False),
    "cast-white": (r_cast_white, -22, True),
    "cast-blue": (r_cast_blue, -22, True),
    "cast-black": (r_cast_black, -22, True),
    "cast-red": (r_cast_red, -22, True),
    "cast-green": (r_cast_green, -22, True),
    "cast-colorless": (r_cast_colorless, -22, True),
    "cast-multi": (r_cast_multi, -22, True),
    "spell-big": (r_spell_big, -21, True),
    "commander-cast": (r_commander_cast, -19, True),
    "attack-1": (lambda: r_attack(0), -22, False),
    "attack-2": (lambda: r_attack(1), -22, False),
    "attack-3": (lambda: r_attack(2), -22, False),
    "block": (r_block, -21, True),
    "strike": (r_strike, -21, False),
    "player-hit": (r_player_hit, -18, True),
    "death": (r_death, -24, True),
    "exile": (r_exile, -24, True),
    "life-gain": (r_life_gain, -25, True),
    "life-loss": (r_life_loss, -24, True),
    "turn-you": (r_turn_you, -21, True),
    "versus": (r_versus, -18, True),
    "victory": (r_victory, -17, True),
    "defeat": (r_defeat, -19, True),
    "dice-roll": (r_dice_roll, -24, False),
    "dice-land": (r_dice_land, -25, False),
}

# Kevin MacLeod tracks, played whole as a crossfading playlist per scene.
TRACKS: dict[str, str] = {
    "music-menu-1": "Midnight Tale",
    "music-menu-2": "Industrious Ferret",
    "music-menu-3": "Village Consort",
    "music-menu-4": "Thatched Villagers",
    "music-game-1": "Teller of the Tales",
    "music-game-2": "Lord of the Land",
    "music-game-3": "Suonatore di Liuto",
    "music-game-4": "Pippin the Hunchback",
}
MUSIC_RMS_DB = -21.0


def write(name: str, x: np.ndarray, out_dir: str, want_stereo: bool, is_music: bool = False) -> dict:
    if x.ndim == 2 and not want_stereo:
        x = x.mean(axis=1)
    peak = float(np.max(np.abs(x)))
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, SR, pcm)
        if len(x) / SR < 0.4 and not is_music:
            # Tiny sounds stay uncompressed: no codec priming, instant response.
            dest = os.path.join(out_dir, name + ".caf")
            subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", wav, dest], check=True)
        elif is_music:
            # HE-AAC keeps a whole track near 1 MB; iPhone decodes it in hardware.
            dest = os.path.join(out_dir, name + ".m4a")
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aach", "-b", "48000", wav, dest], check=True)
        else:
            dest = os.path.join(out_dir, name + ".m4a")
            rate = "128000" if want_stereo else "96000"
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", rate, "-q", "127", wav, dest], check=True)
    return {"file": os.path.basename(dest), "seconds": round(len(x) / SR, 3), "peak_db": round(20 * np.log10(peak + 1e-9), 1),
            "loudness_db": round(float(loudness(x)), 1), "bytes": os.path.getsize(dest)}


def render_track(title: str) -> np.ndarray:
    """A whole track at one playlist level, gently faded in and out."""
    sr, x = wavfile.read(os.path.join(MUSIC, title + ".wav"))
    assert sr == SR, title
    x = x.astype(np.float32)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)
    y = x * 10 ** ((MUSIC_RMS_DB - rms) / 20)
    limit = 10 ** (-1 / 20)
    if np.max(np.abs(y)) > limit:
        y = limit * np.tanh(y / limit)
    return fade(y.astype(np.float32), 0.5, 2.0)


def main() -> None:
    global SONNISS, KENNEY, MUSIC
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sonniss", required=True)
    parser.add_argument("--kenney", required=True)
    parser.add_argument("--music", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    SONNISS, KENNEY, MUSIC = args.sonniss, args.kenney, args.music
    os.makedirs(args.out, exist_ok=True)
    only = set(filter(None, args.only.split(",")))
    report = {}

    def replace(name: str) -> None:
        for old in (name + ".m4a", name + ".caf"):
            path = os.path.join(args.out, old)
            if os.path.exists(path):
                os.remove(path)

    for name, (recipe, target, want_stereo) in CUES.items():
        if only and name not in only:
            continue
        x = recipe()
        # Nothing below ~60 Hz survives a phone speaker; it would only eat headroom.
        x = highpass(x, 60, order=2)
        if name in ARRIVAL_CUES:
            x = reach(x, target)
        elif target is not None:   # colour layers arrive already levelled against the slam they sit on
            x = match_loudness(x, target, -1.0)
        replace(name)
        report[name] = write(name, x, args.out, want_stereo)
        print(f"{name:18s} {report[name]}")
    for name, title in TRACKS.items():
        if only and name not in only:
            continue
        replace(name)
        report[name] = write(name, render_track(title), args.out, True, is_music=True)
        report[name]["title"] = title
        print(f"{name:18s} {report[name]}")
    if not only:
        with open(os.path.join(os.path.dirname(__file__), "audio-manifest.json"), "w") as f:
            json.dump(report, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
