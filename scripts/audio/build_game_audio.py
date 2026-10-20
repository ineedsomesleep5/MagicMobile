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
# Free clips found for Caleb's Sound Bin (build_output/audio-sources): pixabay-raw (Pixabay licence) and oga-raw
# (OpenGameArt CC0). Paths below are relative to it.
LIBRARY: str = ""


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


def library(rel: str, longest: float, start: float = 0.0, gentle: bool = False) -> np.ndarray:
    """A Sound Bin clip (mp3, ogg or wav) from just before its first strong onset, up to `longest` seconds or until it
    falls quiet, faded; the same cut Caleb auditioned (scripts/audio/round12.py). `gentle` (creature voices) keeps the
    quiet tail and fades over longer: Caleb found the voices cut off too fast."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "x.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(LIBRARY, rel), "-ac", "1", "-ar", str(SR),
                        "-f", "wav", wav], check=True)
        x = wavfile.read(wav)[1].astype(np.float32) / 32768.0
    x = x[n_of(start):] if start else x
    env = np.convolve(np.abs(x), np.ones(441) / 441, mode="same")
    first = max(0, int(np.argmax(env > env.max() * 0.08)) - n_of(0.01))
    seg = x[first:first + n_of(longest)].copy()
    loud = np.where(env[first:first + len(seg)] > env.max() * (0.012 if gentle else 0.03))[0]
    if len(loud):
        seg = seg[: loud[-1] + n_of(0.15 if gentle else 0.08)]
    n = len(seg)
    fi, fo = min(n_of(0.004), n // 4), (min(n_of(0.35), n // 2) if gentle else min(n_of(0.15), n // 3))
    seg[:fi] *= np.linspace(0, 1, fi)
    seg[n - fo:] *= np.linspace(1, 0, fo)
    return normalize(seg, -1.0)


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
    """Tape-style speed change: negative semitones slow it down, lower and longer; positive speed it up, higher and
    shorter. Keeps foley natural. Pedalboard's
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
def r_card_pickup():
    return kenney("casino-audio__card-slide-4", 0.0, 0.16, fade_out=0.06)


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

LAND_DB = -22


def reach(x: np.ndarray, target: float) -> np.ndarray:
    """Match loudness; sharp knocks hit the -1 dB ceiling first, so a fast limiter lets them reach the target (the same
    steps trials.py used for what Caleb auditioned)."""
    from pedalboard import Limiter
    y, limit = match_loudness(x, target, -1.0), -6.0
    while loudness(y) < target - 0.5 and limit > -18.0:
        y = match_loudness(Limiter(threshold_db=limit, release_ms=50)(y.astype(np.float32), SR), target, -1.0)
        limit -= 3.0
    return y


def r_land(kind: str):
    return lambda: layer(*slam_parts("light"), *LAND_LAYERS[kind]())


# One sound per kind of card (Caleb, 2026-10-19: water, fire and leaves only for lands; trials round 8, take A each).
# Hits keep their natural transients: limiting flattened the creature thock (round 8), so these only match loudness.
def pine() -> tuple:
    return (sonniss("PineBlock_8x22x100cm_FaceDropped100cmOntoMDF_BeyerdynamicTG137c_Medium", 6.77, 7.15, fade_out=0.12), 0.0, 0.0)


def beech(gain: float = 0.0) -> tuple:
    return (sonniss("BeechPlank_3x27x100cm_EndDropped30cmOntoMDF_SureSM57_Close", 3.26, 3.60, fade_out=0.12), 0.0, gain)


def deep_thud(gain: float) -> tuple:
    return (lowpass(sonniss("10 Hit Deep Thud", 0.08, 0.62, fade_out=0.3), 500), 0.0, gain)


def creature_parts(heavy: bool) -> list:
    """A pine block dropped flat (the thock), a deep thud and a little dust; big creatures add a drum hit."""
    dust = (sonniss("Rustles - Pile, Debris 22", 0.0, 0.25, fade_out=0.12), 0.01, -12.0 if heavy else -14.0)
    parts = [pine(), deep_thud(-5.0 if heavy else -6.0), dust]
    if heavy:
        parts.append((lowpass(sonniss("03 Hit Big Drum", 0.02, 0.9, fade_out=0.45), 900), 0.0, -5.0))
    return parts


# The targets round 8 asked for: match_loudness softly saturates past -1 dB, so these land at about -22.2 and -21.3,
# exactly the takes Caleb heard.
CREATURE_DB = {False: -21.0, True: -20.0}


def creature_sound(heavy: bool) -> np.ndarray:
    return match_loudness(highpass(layer(*creature_parts(heavy)), 60, order=2), CREATURE_DB[heavy], -1.0)


# Round 13 (Caleb): no wood knock under anything. A creature with a voice plays the voice alone; one without lands as
# a card placed on the table (a soft thud under it for big ones); artifacts, enchantments and planeswalkers play their
# own sound alone. creature_parts and creature_sound above stay for the trials scripts.
PX, OGA = "pixabay-raw", "oga-raw"


def card_placed():
    return library(f"{PX}/cards/oxidvideos-placing-playing-card-522514.mp3", 0.35)


def r_creature(heavy: bool):
    if not heavy:
        return card_placed
    return lambda: layer((card_placed(), 0.0, 0.0), (deep_thud(0.0)[0], 0.0, -12.0))


def r_arrive_artifact():
    return sonniss("IMPACT METAL Short Slam_03", 0.13, 0.65, fade_out=0.25)


def r_arrive_enchantment():
    return library(f"{PX}/enchantment/u_jt9vdte8nd-magic-church-bell-293423.mp3", 1.0)


def r_arrive_planeswalker():
    return layer(ks("impactBell_heavy_002", 0.0, 0.0),
                 (sonniss("Magic_Spells_Impact_Creation20", 0.06, 0.90, fade_out=0.4), 0.02, -6.0))


def r_cast_instant():
    return sonniss("Whoosh_Fast_02", 0.05, 0.75, fade_in=0.01, fade_out=0.3)


def r_cast_sorcery():
    return sonniss("Whooshes_135", 0.90, 2.10, fade_in=0.03, fade_out=0.5)


def r_cast_permanent():
    """A creature, artifact or other permanent spell going on the stack: a soft swipe; it lands with its own sound."""
    return sonniss("Whoosh,Organic,Fabric,Glove,Airy,Breathy,Punchy", 0.0, 0.46, fade_out=0.15)


# A creature type's voice, played alone when the creature arrives (Caleb, round 13: no knock under it). The apps map
# card subtypes to these slots in BoardFXArrivalSound; add a slot here, there and in GameSound to grow the list.
# Slots with several voices ship as numbered files and the apps pick one at random.
# Rounds 9-11 (Sonniss): human B (armour and a sword drawn), dragon B (a roar), the sliver hiss, the elf's singing bowl
# an octave up, the squirrel's chirp slowed three semitones.
SONNISS_VOICES = {
    # Round 14 (Caleb: a bit longer, not cut off so fast): each slice runs on into its natural tail.
    "human": lambda: layer((sonniss("LeatherArmor_Rustle_03", 0.22, 0.93, fade_in=0.01, fade_out=0.3), 0.0, 0.0),
                           (sonniss("Sword Scrapes Multiple, Battle, Metal, Slash, Draw", 0.12, 0.90, fade_in=0.01,
                                    fade_out=0.35), 0.06, 0.0)),
    "dragon": lambda: sonniss("Creature_Dragon_Roar_01", 0.04, 2.0, fade_in=0.01, fade_out=0.7),
    "elf": lambda: highpass(slowed(sonniss("SINGING_BOWL_Strike_Sustain_D_02", 3.40, 6.60, fade_out=1.6), 12.0), 600),
    "sliver": lambda: layer((sonniss("MR - Insect Creature Attack VO 02", 0.0, 0.88, fade_in=0.01, fade_out=0.3), 0.0, 0.0),
                            (sonniss("Bluezone_BC0263_creature_crab_organic_texture_carapace_crack_squishy_003", 0.0,
                                     0.45, fade_in=0.01, fade_out=0.2), 0.0, -4.0)),
    "squirrel": lambda: highpass(slowed(sonniss("Squirrel 2017 Lookout Hood Dawn Loud Squirrel 3", 7.76, 8.30,
                                                fade_in=0.01, fade_out=0.25), -3.0), 700),
}


def lib(rel: str, longest: float, start: float = 0.0):
    """A creature voice from the Sound Bin library, run on into its tail (round 14: up to 1.6x the auditioned cut)."""
    return lambda: library(rel, min(2.0, longest * 1.6), start, gentle=True)


# slot: its voices, in file order (creature-<slot>-<n> when there are several). Round 13 picks (the Sound Bin).
CREATURE_VOICES = {
    "human": [SONNISS_VOICES["human"]],
    "goblin": [lib(f"{PX}/goblin/applehillstudios-mad-goblin-laughter-1-543569.mp3", 0.8)],
    "elf": [SONNISS_VOICES["elf"]],
    "dragon": [SONNISS_VOICES["dragon"], lib(f"{PX}/dragon/freesound_community-dragon-growl-37570.mp3", 1.1),
               lib(f"{PX}/dragon/dragon-studio-epic-dragon-roar-364481.mp3", 1.1)],
    "sliver": [SONNISS_VOICES["sliver"]],
    "squirrel": [SONNISS_VOICES["squirrel"], lib(f"{PX}/chipmunk/freesound_community-046634_chipmunk-63290.mp3", 0.6),
                 lib(f"{PX}/squirrel/freesound_community-squirrel-89831.mp3", 0.6)],
    # Orc, Ogre, Troll; Giant uses the first two (Caleb: the large monster attack is not for giants)
    "orc": [lib(f"{PX}/orc/magiaz-ogre-387364.mp3", 0.9), lib(f"{OGA}/creatures1/grunt_01.ogg", 0.7),
            lib(f"{PX}/orc/daviddumaisaudio-large-monster-attack-195713.mp3", 0.8)],
    "bear": [lib(f"{PX}/beast/dragon-studio-beast-growl-sound-376873.mp3", 1.0)],
    "dinosaur": [lib(f"{PX}/beast/dragon-studio-dinosaur-growl-487679.mp3", 1.0)],
    "beast": [lib(f"{PX}/beast/dragon-studio-growl-of-the-beast-504021.mp3", 1.0)],
    "horror": [lib(f"{PX}/beast/dragon-studio-beast-growl-494304.mp3", 1.0),
               lib(f"{PX}/beast/dragon-studio-monster-growl-376892.mp3", 1.0),
               lib(f"{PX}/beast/the-vampires-monster-weretiger-yarik-roar-6-321637.mp3", 1.0)],
    "critter": [lib(f"{OGA}/creatures1/cute_01.ogg", 0.6)],
    # Round 14 (Caleb): a real rat for Rat and Mouse; the cute critter stays for Fox, Rabbit, Otter and the like
    "rat": [lib(f"{PX}/rat/u_3yocsblk00-rat-squeaking-sound-effecthd-570216.mp3", 0.75)],
    "eldrazi": [lib(f"{PX}/eldrazi/brvhrtz-creature-01-brvhrtz-232041.mp3", 1.19)],
    "faerie": [lib(f"{PX}/fairy/humordome-fairy-sparkle-451414.mp3", 0.9),
               lib(f"{PX}/fairy/freesound_community-fairy-flyby-2-106731.mp3", 0.9)],
    "angel": [lib(f"{PX}/angel/freesound_community-ahhhh-37191.mp3", 1.1)],
    "vampire": [lib(f"{PX}/vampire/alesiadavina-female-vampire-attack-hiss-sound-effect-dark-sfx-552124.mp3", 0.8)],
    "zombie": [lib(f"{PX}/zombie/dragon-studio-zombie-sound-2-357976.mp3", 1.0),
               lib(f"{PX}/zombie/freesound_community-zombie-groan-95051.mp3", 1.0)],
    "wolf": [lib(f"{PX}/wolf/dragon-studio-spooky-wolf-howl-410547.mp3", 1.2)],
    "cat": [lib(f"{PX}/cat/soundreality-cat-meow-fx-461188.mp3", 0.8), lib(f"{PX}/cat/dragon-studio-cute-cat-meow-472372.mp3", 0.8)],
    # The chirp comes 0.62 s into the recording (Caleb: it started too early and cut the chirp off)
    "bird": [lib(f"{PX}/bird/loswin23-bird-chirp-485390.mp3", 0.8, start=0.62)],
    "ooze": [lib(f"{OGA}/creatures1/burble_01.ogg", 0.7), lib(f"{OGA}/creatures2/slime_01.ogg", 0.7)],
    "wizard": [lib(f"{PX}/wizard/daviddumaisaudio-magical-spell-cast-190272.mp3", 1.0),
               lib(f"{PX}/wizard/universfield-spell-casting-229208.mp3", 1.0)],
    "insect": [lib(f"{OGA}/creatures1/bug_04.ogg", 0.6), lib(f"{PX}/insect/yodguard-giant-insect-footsteps-1-482548.mp3", 0.7)],
}
# Voices of big creatures sit a dB louder than small ones (the round 8 arrival levels).
BIG_VOICES = {"dragon", "orc", "bear", "dinosaur", "beast", "horror", "zombie", "wolf", "angel", "eldrazi"}
VOICE_DB = {False: -21.0, True: -20.0}


# Peaky voices meet the -1 dB ceiling first and land quieter than asked: these targets bring them to their level.
VOICE_TARGET = {"creature-insect-2": -15.5}


def voice_cues() -> dict:
    cues = {}
    for slot, voices in CREATURE_VOICES.items():
        for i, recipe in enumerate(voices, start=1):
            name = f"creature-{slot}" if len(voices) == 1 else f"creature-{slot}-{i}"
            cues[name] = (recipe, VOICE_TARGET.get(name, VOICE_DB[slot in BIG_VOICES]), False)
    return cues


ARRIVAL_CUES = {"land-plains", "land-island", "land-swamp", "land-mountain", "land-forest"}


def r_ability():
    return sonniss("Arcane_Spell_Doppler_Shift_03", 0.0, 0.35, fade_out=0.12, stereo=True)


# ------------------------------------------------------------------ spells by color
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
    # Round 13 (Caleb): a card taken off the pile, a card placed on the table, a riffle shuffle
    "card-draw": (lambda: library(f"{PX}/cards/oxidvideos-taking-playing-card-522520.mp3", 0.4), -25, False),
    "card-pickup": (r_card_pickup, -29, False),
    "card-play": (card_placed, -23, False),
    "shuffle": (lambda: library(f"{PX}/cards/freesound_community-card-shuffle-94662.mp3", 1.3), -24, False),
    "land-drop": (r_land_drop, -22, False),
    "counter": (r_counter, -30, False),
    "ability": (r_ability, -27, True),
    "steal": (r_steal, -27, False),
    # The target the Sound Bin used: a sharp card snap meets the -1 dB ceiling first and lands near -25, as Caleb heard
    "arrive-creature": (r_creature(False), -22.2, False),
    "arrive-creature-heavy": (r_creature(True), -22.2, False),
    "arrive-artifact": (r_arrive_artifact, -22, False),
    "arrive-enchantment": (r_arrive_enchantment, -23, False),
    "arrive-planeswalker": (r_arrive_planeswalker, -21.0, False),
    "cast-instant": (r_cast_instant, -22, False),
    "cast-sorcery": (r_cast_sorcery, -21, False),
    "cast-permanent": (r_cast_permanent, -25, False),
    **voice_cues(),
    "land-plains": (r_land("plains"), LAND_DB, False),
    "land-island": (r_land("island"), LAND_DB, False),
    "land-swamp": (r_land("swamp"), LAND_DB, False),
    "land-mountain": (r_land("mountain"), LAND_DB, False),
    "land-forest": (r_land("forest"), LAND_DB, False),
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
    parser.add_argument("--library", required=True, help="build_output/audio-sources (pixabay-raw, oga-raw)")
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    global LIBRARY
    SONNISS, KENNEY, MUSIC, LIBRARY = args.sonniss, args.kenney, args.music, args.library
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
    # A partial run (--only) updates its entries in the manifest; retired cues drop out either way.
    path = os.path.join(os.path.dirname(__file__), "audio-manifest.json")
    manifest = json.load(open(path)) if only and os.path.exists(path) else {}
    manifest.update(report)
    manifest = {k: v for k, v in manifest.items() if k in CUES or k in TRACKS}
    with open(path, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
