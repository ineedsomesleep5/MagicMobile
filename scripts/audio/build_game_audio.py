#!/usr/bin/env python3
"""Render MagicMobile's sound effects and music into apps/ios/MagicMobile/Resources/Audio.

Every cue is a professional recording, trimmed, faded and loudness-matched here. No
synthesized layers (build 19 replaced them after play-testing). Sources and licenses are
listed in scripts/audio/SOURCES.md and in the app's Resources/Audio/CREDITS.txt:
  * Sonniss.com GDC Game Audio Bundles 2016-2020 (royalty-free, no attribution required).
    Files are fetched one by one from the official mirror listed on sonniss.com/gameaudiogdc.
  * Kenney.nl Casino Audio (CC0 1.0) for a few card-handling recordings.
  * Kevin MacLeod (incompetech.com), CC BY 4.0, for music and orchestral stingers.

Requires numpy and scipy (a scratch virtualenv is enough) plus macOS `afconvert`.
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

import numpy as np
from scipy.io import wavfile

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
    return sonniss("Magic_Spells_Impact_Air24", 0.0, 1.4, fade_out=0.5, stereo=True)


def r_page_flip():
    return sonniss("CATALOGUE_Page_Turn_9", 0.38, 0.78, fade_in=0.01, fade_out=0.08)


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


def r_creature_enter():
    plank = sonniss("Drop Soft - Single Plank, Drop 02", 0.0, 0.45, fade_out=0.1)
    body = sonniss("punch_general_body_impact_03", 0.0, 0.2, fade_out=0.06)
    return layer((kenney("casino-audio__card-place-1"), 0.0, -4), (plank, 0.01, 0), (body, 0.01, -7))


def r_token_create():
    plop = sonniss("Scatter Plops 04", 0.14, 0.26)
    sparkle = sonniss("collect_item_14", 0.0, 0.5, fade_out=0.2)
    return layer((plop, 0.0, 0), (sparkle, 0.02, -11))


def r_counter():
    return sonniss("Scatter Plops 04", 0.25, 0.36)


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
    "emote": (r_emote, -26, True),
    "card-draw-1": (lambda: r_card_draw(0), -25, False),
    "card-draw-2": (lambda: r_card_draw(1), -25, False),
    "card-draw-3": (lambda: r_card_draw(2), -25, False),
    "card-pickup": (r_card_pickup, -29, False),
    "card-play": (r_card_play, -23, False),
    "shuffle": (r_shuffle, -24, False),
    "land-drop": (r_land_drop, -22, False),
    "creature-enter": (r_creature_enter, -21, False),
    "token-create": (r_token_create, -25, False),
    "counter": (r_counter, -30, False),
    "ability": (r_ability, -27, True),
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
