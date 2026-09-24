#!/usr/bin/env python3
"""Render MagicMobile's sound effects and music into apps/ios/MagicMobile/Resources/Audio.

Sources:
  * Recorded foley from Kenney.nl packs (CC0 1.0, public domain): Casino Audio,
    Interface Sounds, RPG Audio (https://kenney.nl/assets/<pack>). Pass the folder of
    decoded 44.1 kHz WAVs named "<pack>__<file>.wav" with --kenney.
  * Everything magical, musical or "big" (casts, bells, fanfares, music) is original
    synthesis in this file (see gamedsp.py).
  * The existing BoardFX impact recordings (Kenney Impact Sounds, CC0) are reused as layers.

Requires numpy and scipy (a scratch virtualenv is enough) plus macOS `afconvert`.
Usage (from the repo root):
  build_game_audio.py --kenney DIR --boardfx scripts/audio/sources/boardfx \
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
import zlib

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(__file__))
from gamedsp import *  # noqa: E402,F403
import gamedsp as g  # noqa: E402

KENNEY: str = ""
BOARDFX: str = ""


def kenney(name: str, gain_db: float = 0.0, trim: bool = True) -> np.ndarray:
    sr, x = wavfile.read(os.path.join(KENNEY, name + ".wav"))
    x = x.astype(np.float32) / 32768.0
    if x.ndim == 2:
        x = x.mean(axis=1)
    assert sr == SR, name
    if trim:
        x = trim_silence(x, -55, 0.02)
    x = normalize(x, -1.0 + gain_db)
    return fade(x, 0.001, 0.015)


def boardfx(name: str) -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "x.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1",
                        os.path.join(BOARDFX, name + ".m4a"), path], check=True)
        sr, x = wavfile.read(path)
    x = x.astype(np.float32) / 32768.0
    return fade(normalize(trim_silence(x, -55, 0.02), -1.0), 0.001, 0.015)


# ------------------------------------------------------------------ building blocks
def whoosh(seconds: float, f_from: float, f_to: float, rise: float = 0.5, color: str = "pink") -> np.ndarray:
    x = noise(seconds, color)
    x = sweep(x, "bandpass", f_from, f_to, q_width=0.9)
    return x * env_swell(seconds, seconds * rise, seconds * (1 - rise) + 0.01, 1.6)


def sparkle(notes: list[float], spacing: float = 0.045, decay: float = 0.28, seconds: float = 0.9) -> np.ndarray:
    parts = []
    for i, m in enumerate(notes):
        pan = ((i % 3) - 1) * 0.5
        bell = fm_bell(midi(m), seconds, ratio=3.5, index=1.2, decay=decay, brightness_decay=0.08)
        parts.append((stereo(bell * 0.6, pan), i * spacing))
    return mix(*parts)


def thud(freq: float = 70, seconds: float = 0.35, decay: float = 0.12) -> np.ndarray:
    return punch(lowpass(membrane(freq, seconds, drop=0.9, decay=decay, snap=0.35), 900), 4.0, 0.55)


def boom(seconds: float = 1.2, f0: float = 70, f1: float = 34) -> np.ndarray:
    t = times(seconds)
    body = sine(glide(f0, f1, seconds, 0.4), seconds) * np.exp(-t / (seconds * 0.35))
    crack = lowpass(noise(seconds, "brown"), 400) * np.exp(-t / 0.08) * 0.8
    return punch(saturate(body + crack, 1.4), 4.0, 0.5)


def brass_chord(notes: list[float], seconds: float, attack: float = 0.03, bright: float = 2600,
                vibrato: float = 0.004) -> np.ndarray:
    """Synth brass: detuned saws with a filter that blares open and settles."""
    t = times(seconds)
    voice = np.zeros(len(t), dtype=np.float32)
    for m in notes:
        for detune in (-0.0025, 0.0025):
            vib = 1 + vibrato * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
            voice += saw(midi(m) * (1 + detune) * vib, seconds, partials=24)
    voice /= len(notes) * 2
    # Blare: fast open then settle to ~60 % brightness.
    cutoff_env = 0.55 + 0.45 * np.exp(-t / 0.12)
    out = np.zeros_like(voice)
    block = 256
    zi = None
    for b in range(0, len(voice), block):
        f = 300 + bright * cutoff_env[min(b, len(t) - 1)] * min(1, (b / SR) / attack + 0.25)
        sos = g._sos("lowpass", f)
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        out[b : b + block], zi = g.signal.sosfilt(sos, voice[b : b + block], zi=zi)
    return saturate(out * env_adsr(seconds, attack, 0.15, 0.75, min(0.5, seconds * 0.4)), 1.3)


def string_pad(notes: list[float], seconds: float, cutoff: float = 1400, attack: float = 0.6) -> np.ndarray:
    t = times(seconds)
    voice = np.zeros(len(t), dtype=np.float32)
    for m in notes:
        for detune in (-0.004, 0.0, 0.004):
            vib = 1 + 0.003 * np.sin(2 * np.pi * (4.6 + detune * 200) * t)
            voice += saw(midi(m) * (1 + detune) * vib, seconds, partials=20)
    voice = lowpass(voice / (len(notes) * 3), cutoff, order=2)
    return voice * env_adsr(seconds, attack, 0.4, 0.85, min(1.2, seconds * 0.4))


def timpani(note: float = 43, seconds: float = 1.4) -> np.ndarray:
    t = times(seconds)
    f = midi(note)
    body = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.5 * t) + 0.3 * np.sin(2 * np.pi * f * 1.98 * t))
    body *= np.exp(-t / 0.55)
    hit = lowpass(noise(seconds), 2500) * np.exp(-t / 0.018) * 0.6
    return punch((body * 0.5 + hit).astype(np.float32), 3.0, 0.45)


def cymbal_swell(seconds: float, rise: float) -> np.ndarray:
    return highpass(noise(seconds), 5000) * env_swell(seconds, rise, seconds - rise + 0.01, 2.4) * 0.35


# ------------------------------------------------------------------ recipes
def r_ui_tap():
    return kenney("interface-sounds__select_002")


def r_ui_confirm():
    return reverb(kenney("interface-sounds__confirmation_002"), 0.12, 0.8)


def r_ui_back():
    return kenney("interface-sounds__back_002")


def r_ui_open():
    return mix(lowpass(kenney("interface-sounds__maximize_001"), 6000) * 0.6,
               stereo(whoosh(0.28, 500, 3200, 0.7) * 0.35, 0, 0.004))


def r_ui_close():
    return mix(lowpass(kenney("interface-sounds__minimize_001"), 6000) * 0.6,
               stereo(whoosh(0.26, 2800, 500, 0.3) * 0.3, 0, 0.004))


def r_ui_toggle():
    return kenney("interface-sounds__toggle_001")


def r_ui_tick():
    return kenney("interface-sounds__tick_004")


def r_ui_error():
    return lowpass(kenney("interface-sounds__error_006"), 5000)


def r_response_alert():
    tone = mix((fm_bell(midi(81), 0.9, ratio=2.0, index=0.8, decay=0.35) * 0.5, 0.0),
               (fm_bell(midi(88), 0.9, ratio=2.0, index=0.8, decay=0.4) * 0.45, 0.09))
    return reverb(tone, 0.25, 1.2)


def r_menu_play():
    gong = church_bell(midi(45), 2.4, decay=1.6) * 0.7
    swell = whoosh(0.9, 300, 4000, 0.85, "pink") * 0.25
    return reverb(mix(stereo(gong), stereo(swell, 0, 0.006), (sparkle([84, 88, 91, 96], 0.05), 0.35)), 0.35, 2.2)


def r_card_draw(variant: int):
    name = ["casino-audio__card-slide-1", "casino-audio__card-slide-3", "casino-audio__card-slide-8"][variant]
    return kenney(name)


def r_card_pickup():
    x = kenney("casino-audio__card-slide-4")
    return fade(x[: n_of(0.16)], 0.001, 0.06)


def r_card_play():
    return mix(kenney("casino-audio__card-shove-4") * 0.8, stereo(whoosh(0.35, 700, 3600, 0.6) * 0.3, 0, 0.005))


def r_hand_fan():
    return kenney("casino-audio__card-fan-1")


def r_shuffle():
    x = kenney("casino-audio__card-shuffle")
    return fade(x[: n_of(1.7)], 0.001, 0.25)


def r_card_place():
    return mix(kenney("casino-audio__card-place-1") * 0.85, thud(92, 0.3, 0.07) * 0.5)


def r_land_drop():
    debris = mix(*[(bandpass(noise(0.03), 1500, 5000) * np.exp(-times(0.03) / 0.006) * (0.3 - 0.05 * i), 0.05 + 0.028 * i)
                   for i in range(5)])
    return mix(kenney("casino-audio__card-place-3") * 0.7, thud(64, 0.5, 0.14), (debris, 0.0))


def r_creature_enter():
    return mix(kenney("casino-audio__card-place-1") * 0.7, thud(88, 0.35, 0.1) * 0.8,
               (lowpass(whoosh(0.45, 200, 900, 0.8, "brown"), 1200) * 0.35, 0.0))


def r_token_create():
    t = times(0.18)
    pop = sine(glide(520, 940, 0.18, 0.5), 0.18) * np.exp(-t / 0.05)
    return reverb(mix(stereo(pop * 0.7), (sparkle([88, 95], 0.05, 0.2, 0.5), 0.04)), 0.22, 1.0)


def r_mana_tap(variant: int):
    name = ["interface-sounds__glass_001", "interface-sounds__glass_003"][variant]
    ping = fm_bell(midi([86, 91][variant]), 0.6, ratio=2.0, index=0.6, decay=0.18) * 0.35
    return reverb(mix(kenney(name) * 0.75, ping), 0.2, 0.9)


def r_counter():
    t = times(0.14)
    blip = sine(glide(700, 1100, 0.14), 0.14) * np.exp(-t / 0.04) * 0.4
    return mix(kenney("interface-sounds__glass_005") * 0.6, blip)


def r_ability():
    return reverb(mix(sparkle([88, 93, 100], 0.04, 0.22, 0.6),
                      stereo(highpass(noise(0.5), 6000) * env_swell(0.5, 0.08, 0.4) * 0.12, 0, 0.004)), 0.28, 1.2)


def r_cast_white():
    bells = sparkle([84, 88, 91, 96], 0.07, 0.6, 1.6)
    air = stereo(highpass(noise(1.3, "pink"), 3500) * env_swell(1.3, 0.35, 0.9) * 0.18, 0, 0.008)
    halo = stereo(sine(midi(72), 1.4) * env_swell(1.4, 0.3, 1.0) * 0.2)
    return reverb(mix(bells, air, halo), 0.38, 2.4)


def r_cast_blue():
    t = times(1.2)
    f = glide(430, 700, 1.2, 0.6) * (1 + 0.012 * np.sin(2 * np.pi * 6 * t))
    tone = sine(f, 1.2) * env_swell(1.2, 0.45, 0.75) * 0.35
    water = sweep(noise(1.2, "pink"), "bandpass", 300, 2400, 0.8, curve=0.8) * env_swell(1.2, 0.5, 0.7) * 0.4
    plinks = sparkle([79, 86, 91], 0.12, 0.25, 0.9)
    return reverb(mix(stereo(tone), stereo(water, 0, 0.006), (plinks, 0.25)), 0.42, 2.6)


def r_cast_black():
    drone = string_pad([38, 45, 50], 1.3, cutoff=700, attack=0.5) * env_swell(1.3, 0.55, 0.75, 1.3)
    whisper = bandpass(noise(1.3), 900, 3200) * env_swell(1.3, 0.5, 0.8) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * times(1.3))) * 0.22
    sub = sine(glide(62, 44, 1.3), 1.3) * env_swell(1.3, 0.55, 0.75) * 0.45
    return reverb(mix(stereo(drone), stereo(whisper, 0.2, 0.01), stereo(sub)), 0.35, 2.2, damping=0.8)


def r_cast_red():
    seconds = 1.3
    t = times(seconds)
    density = env_swell(seconds, 0.55, 0.7)
    crackle = np.zeros(len(t), dtype=np.float32)
    idx = np.where(g.rng.random(len(t)) < 0.0035 * density)[0]
    for i in idx:
        amp = g.rng.uniform(0.3, 1.0)
        length = int(g.rng.uniform(40, 220))
        seg = g.rng.standard_normal(length) * np.exp(-np.arange(length) / (length / 4)) * amp
        crackle[i : i + length] += seg[: len(crackle) - i]
    crackle = bandpass(crackle, 1500, 7000) * 0.5
    roar = sweep(noise(seconds, "brown"), "lowpass", 200, 1300, curve=0.7) * env_swell(seconds, 0.55, 0.75) * 0.9
    return reverb(mix(stereo(crackle, 0.15, 0.004), stereo(roar), (stereo(boom(0.8, 90, 45) * 0.55), 0.45)), 0.28, 1.8)


def r_cast_green():
    notes = [67, 71, 74, 76, 79]  # G major pentatonic, rising
    harp = mix(*[(stereo(pluck(midi(m), 1.3, 0.9975, 0.6) * 0.45, ((i % 3) - 1) * 0.4), i * 0.075) for i, m in enumerate(notes)])
    knock = mix(stereo(membrane(210, 0.12, 0.3, 0.035, 0.5) * 0.4))
    leaves = stereo(bandpass(noise(1.0, "pink"), 1800, 6000) * env_swell(1.0, 0.3, 0.7) * 0.12, 0, 0.006)
    return reverb(mix(knock, harp, leaves), 0.35, 2.0)


def r_cast_colorless():
    clang = metal(560, 1.0, 0.35) * 0.6
    return reverb(mix(kenney("rpg-audio__metalClick") * 0.5, (stereo(clang), 0.01),
                      (sparkle([86, 93], 0.06, 0.3, 0.6) * 0.6, 0.05)), 0.3, 1.6)


def r_cast_multi():
    return mix(r_cast_white() * 0.65, (r_cast_blue() * 0.45, 0.05))


def r_spell_big():
    seconds = 2.4
    choir = formant(saw(midi(50), seconds, 30) + saw(midi(57), seconds, 30) + saw(midi(62), seconds, 30), "ah")
    choir = choir * env_swell(seconds, 0.7, 1.7, 1.4) * 0.9
    return reverb(mix(stereo(boom(1.6, 72, 32) * 0.9), stereo(choir, 0, 0.012), (cymbal_swell(0.9, 0.75), 0.0)),
                  0.45, 3.0)


def r_commander_cast():
    brass = brass_chord([48, 55, 60, 64, 67], 1.6, attack=0.04)
    return reverb(mix(stereo(timpani(36, 1.4)), stereo(brass * 0.8, 0, 0.008), (cymbal_swell(0.5, 0.45), 0.0)), 0.4, 2.8)


def r_attack():
    drum = punch(membrane(96, 0.5, drop=0.8, decay=0.16, snap=0.5), 4.0, 0.55)
    return mix(kenney("rpg-audio__drawKnife3") * 1.1, (stereo(drum * 0.55), 0.0),
               (stereo(whoosh(0.3, 900, 4000, 0.7) * 0.25, 0.1, 0.004), 0.05))


def r_block():
    clang = lowpass(kenney("rpg-audio__metalPot2"), 5500) * 0.7
    ring = metal(330, 0.9, 0.3) * 0.35
    return reverb(mix(clang, stereo(ring), stereo(thud(80, 0.3, 0.08) * 0.5)), 0.2, 1.3)


def r_strike():
    return mix(boardfx("fx-damage"), (kenney("rpg-audio__knifeSlice2") * 0.25, 0.0))


def r_player_hit():
    return mix(boardfx("fx-player-hit"), stereo(boom(0.7, 60, 38) * 0.6))


def r_death():
    seconds = 0.9
    dissolve = sweep(noise(seconds, "pink"), "bandpass", 3200, 300, 0.9) * env_exp(seconds, 0.02, 0.28) * 0.5
    grains = mix(*[(fm_bell(midi(96 - 3 * i), 0.25, 2.7, 1.0, 0.07) * 0.18, 0.04 + 0.05 * i) for i in range(5)])
    return reverb(mix(boardfx("fx-death") * 0.8, stereo(dissolve, 0, 0.006), (stereo(grains), 0.0)), 0.25, 1.5)


def r_exile():
    seconds = 1.1
    t = times(seconds)
    rise = sine(glide(700, 2400, seconds, 0.8) * (1 + 0.01 * np.sin(2 * np.pi * 7 * t)), seconds) * env_swell(seconds, 0.6, 0.5) * 0.3
    air = highpass(noise(seconds, "pink"), 2500) * env_swell(seconds, 0.6, 0.5) * 0.3
    return reverb(mix(stereo(rise), stereo(air, 0, 0.008)), 0.45, 2.4)


def r_life_gain():
    chime = mix(*[(fm_bell(midi(m), 1.2, 2.0, 0.7, 0.5) * 0.45, i * 0.08) for i, m in enumerate([72, 76, 79, 84])])
    return reverb(stereo(chime), 0.35, 2.0)


def r_life_loss():
    seconds = 0.7
    tone = lowpass(saw(glide(midi(57), midi(52), seconds, 0.7), seconds, 12), 900) * env_exp(seconds, 0.01, 0.25) * 0.6
    return reverb(stereo(tone), 0.2, 1.4)


def r_stack_resolve():
    x = whoosh(0.32, 2600, 450, 0.25) * 0.5
    drop = sine(glide(900, 450, 0.2), 0.2) * env_exp(0.2, 0.004, 0.05) * 0.2
    return reverb(stereo(mix(x, drop)), 0.18, 1.0)


def r_turn_you():
    bell = church_bell(midi(69), 2.6, decay=1.8)
    sub = sine(midi(45), 2.0) * env_exp(2.0, 0.01, 0.7) * 0.25
    return reverb(mix(stereo(bell), stereo(sub), (sparkle([93, 100], 0.07, 0.4, 0.8) * 0.35, 0.12)), 0.35, 2.6)


def r_turn_opponent():
    bell = church_bell(midi(62), 2.0, decay=1.3) * 0.8
    return reverb(stereo(lowpass(bell, 3000)), 0.35, 2.4, damping=0.8)


def r_game_start():
    roll = mix(*[(punch(lowpass(membrane(150 + 6 * i, 0.12, 0.3, 0.05, 0.6), 2000), 3.0, 0.5) * (0.25 + 0.03 * i), 0.035 * i)
                 for i in range(22)])
    stab = brass_chord([50, 57, 62, 66, 69], 1.8, attack=0.03)
    return reverb(mix(stereo(roll), (stereo(timpani(38, 1.6)), 0.78), (stereo(stab * 0.85, 0, 0.008), 0.78),
                      (cymbal_swell(0.9, 0.8), 0.0), (kenney("casino-audio__cards-pack-open-1") * 0.3, 0.0)), 0.4, 2.8)


def r_versus():
    rise = whoosh(0.55, 250, 5000, 0.9, "pink") * 0.55
    slam = mix(boom(1.4, 80, 32), metal(180, 1.2, 0.4) * 0.35, timpani(33, 1.4) * 0.7)
    return reverb(mix(stereo(rise, 0, 0.006), (stereo(slam), 0.5), (sparkle([88, 95, 100], 0.05, 0.5, 1.2) * 0.4, 0.55)),
                  0.4, 2.8)


def r_victory():
    # "da-da-da DAAAA": a triplet pickup into a held tonic, then IV and back to I.
    parts = []
    beat = 0.16
    for i in range(3):
        parts.append((stereo(brass_chord([55, 64, 67], 0.2, 0.015) * 0.7, -0.15), i * beat))
    parts.append((stereo(brass_chord([48, 60, 64, 67, 72], 1.1, 0.02), 0.0), 3 * beat))
    parts.append((stereo(brass_chord([53, 60, 65, 69, 72], 0.7, 0.03) * 0.9, 0.1), 3 * beat + 1.05))
    parts.append((stereo(brass_chord([48, 55, 60, 64, 67, 72], 2.2, 0.04), 0.0), 3 * beat + 1.7))
    parts.append((stereo(timpani(36, 1.2)), 3 * beat))
    parts.append((stereo(timpani(36, 1.8)), 3 * beat + 1.7))
    parts.append((cymbal_swell(1.8, 1.65), 0.2))
    parts.append((sparkle([84, 88, 91, 96, 100], 0.06, 0.7, 1.8) * 0.5, 3 * beat + 1.75))
    return reverb(mix(*parts), 0.42, 3.2)


def r_defeat():
    bell = church_bell(midi(45), 3.5, decay=2.4) * 0.55
    pad = mix((string_pad([45, 52, 57, 60], 1.6, 1000, 0.25), 0.0),
              (string_pad([41, 48, 53, 57], 1.4, 900, 0.25), 1.4),
              (string_pad([40, 47, 52, 56], 2.4, 800, 0.3), 2.6))
    return reverb(mix(stereo(bell), stereo(pad * 0.8, 0, 0.01)), 0.45, 3.2, damping=0.8)


def r_dice_roll():
    return mix(kenney("casino-audio__dice-shake-2") * 0.8, (kenney("casino-audio__dice-throw-1"), 1.05))


def r_dice_land():
    return mix(kenney("casino-audio__die-throw-2"), (sparkle([91, 96], 0.05, 0.3, 0.6) * 0.3, 0.12))


def r_page_flip():
    return kenney("rpg-audio__bookFlip1") * 0.8


# ------------------------------------------------------------------ music
def music_loop(chords: list[list[float]], bar: float, plucks_per_bar: int, seed: int, cutoff: float,
               pluck_level: float) -> np.ndarray:
    """Render the progression twice and keep the second pass: its opening already holds the
    reverb tail of the previous pass, so the file loops without a seam."""
    local = np.random.default_rng(seed)
    cycle = bar * len(chords)
    total = cycle * 2 + 1
    layers = []
    for rep in range(2):
        for i, chord in enumerate(chords):
            start = rep * cycle + i * bar
            # Voiced an octave up as well so a phone speaker carries the harmony.
            pad = string_pad([c for c in chord] + [chord[1] + 12, chord[2] + 12], bar + 1.2, cutoff, attack=bar * 0.35)
            layers.append((stereo(pad * 0.5, 0, 0.012), start))
            bass = punch(sine(midi(chord[0] - 12), bar + 1.0), 2.5, 0.4) * env_adsr(bar + 1.0, 1.0, 0.5, 0.8, 1.0) * 0.16
            layers.append((stereo(bass), start))
            steps = sorted(local.choice(8, size=plucks_per_bar, replace=False))
            for s in steps:
                note = local.choice(chord[1:]) + 12 * local.integers(0, 2)
                pl = pluck(midi(note), 2.2, 0.9982, 0.55) * pluck_level
                layers.append((stereo(pl, float(local.uniform(-0.6, 0.6))), start + s * bar / 8))
    full = reverb(mix(*layers, length=total), 0.5, 4.0, damping=0.7)
    loop = full[n_of(cycle) : n_of(cycle * 2)]
    return loop


def r_music_menu():
    # D minor – B♭ – F – C – D minor – B♭ – G minor – A: warm, hopeful, low energy.
    chords = [[50, 57, 62, 65], [46, 53, 58, 62], [53, 57, 60, 65], [48, 55, 60, 64],
              [50, 57, 62, 65], [46, 53, 58, 62], [43, 50, 55, 58], [45, 52, 57, 61]]
    return music_loop(chords, 8.0, 3, 11, 1700, 0.34)


def r_music_game():
    # A minor – F – C – G – A minor – F – D minor – E, sparser and darker under play.
    chords = [[45, 52, 57, 60], [41, 48, 53, 57], [48, 52, 55, 60], [43, 50, 55, 59],
              [45, 52, 57, 60], [41, 48, 53, 57], [38, 45, 50, 53], [40, 47, 52, 56]]
    return music_loop(chords, 8.0, 2, 29, 1300, 0.24)


# ------------------------------------------------------------------ catalogue
CUES: dict[str, tuple] = {
    # name: (recipe, loudness target dBFS, stereo?)
    "ui-tap": (r_ui_tap, -26, False),
    "ui-confirm": (r_ui_confirm, -22, True),
    "ui-back": (r_ui_back, -26, False),
    "ui-open": (r_ui_open, -26, True),
    "ui-close": (r_ui_close, -27, True),
    "ui-toggle": (r_ui_toggle, -26, False),
    "ui-tick": (r_ui_tick, -28, False),
    "ui-error": (r_ui_error, -24, False),
    "response-alert": (r_response_alert, -24, True),
    "menu-play": (r_menu_play, -18, True),
    "card-draw-1": (lambda: r_card_draw(0), -22, False),
    "card-draw-2": (lambda: r_card_draw(1), -22, False),
    "card-draw-3": (lambda: r_card_draw(2), -22, False),
    "card-pickup": (r_card_pickup, -26, False),
    "card-play": (r_card_play, -21, True),
    "hand-fan": (r_hand_fan, -25, False),
    "shuffle": (r_shuffle, -22, False),
    "card-place": (r_card_place, -20, False),
    "land-drop": (r_land_drop, -18, False),
    "creature-enter": (r_creature_enter, -19, False),
    "token-create": (r_token_create, -22, True),
    "mana-tap-1": (lambda: r_mana_tap(0), -25, True),
    "mana-tap-2": (lambda: r_mana_tap(1), -25, True),
    "counter": (r_counter, -25, False),
    "ability": (r_ability, -23, True),
    "cast-white": (r_cast_white, -20, True),
    "cast-blue": (r_cast_blue, -20, True),
    "cast-black": (r_cast_black, -19, True),
    "cast-red": (r_cast_red, -19, True),
    "cast-green": (r_cast_green, -20, True),
    "cast-colorless": (r_cast_colorless, -20, True),
    "cast-multi": (r_cast_multi, -20, True),
    "spell-big": (r_spell_big, -17, True),
    "commander-cast": (r_commander_cast, -16, True),
    "attack": (r_attack, -18, True),
    "block": (r_block, -19, True),
    "strike": (r_strike, -17, False),
    "player-hit": (r_player_hit, -15, True),
    "death": (r_death, -19, True),
    "exile": (r_exile, -21, True),
    "life-gain": (r_life_gain, -21, True),
    "life-loss": (r_life_loss, -21, True),
    "stack-resolve": (r_stack_resolve, -26, True),
    "turn-you": (r_turn_you, -18, True),
    "turn-opponent": (r_turn_opponent, -22, True),
    "game-start": (r_game_start, -16, True),
    "versus": (r_versus, -15, True),
    "victory": (r_victory, -14, True),
    "defeat": (r_defeat, -17, True),
    "dice-roll": (r_dice_roll, -20, False),
    "dice-land": (r_dice_land, -19, True),
    "page-flip": (r_page_flip, -25, False),
    "music-menu": (r_music_menu, -24, True),
    "music-game": (r_music_game, -27, True),
}


def write(name: str, x: np.ndarray, out_dir: str, want_stereo: bool) -> dict:
    if not want_stereo and x.ndim == 2:
        x = x.mean(axis=1)
    if want_stereo and x.ndim == 1:
        x = stereo(x)
    x = np.nan_to_num(x)
    music = name.startswith("music-")
    if not music:
        x = trim_silence(x, -62, 0.03)
        x = fade(x, 0.0015, min(0.12, len(x) / SR * 0.25))
    if float(np.max(np.abs(x))) > 0.95:
        x = normalize(x, -1.0)
    peak = float(np.max(np.abs(x)))
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, SR, pcm)
        short = len(x) / SR < 0.4 and not music
        if short:
            # Tiny UI sounds stay uncompressed: no codec priming, instant response.
            dest = os.path.join(out_dir, name + ".caf")
            subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", wav, dest], check=True)
        else:
            dest = os.path.join(out_dir, name + ".m4a")
            rate = "128000" if (want_stereo or music) else "96000"
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", rate, "-q", "127", wav, dest], check=True)
    return {"file": os.path.basename(dest), "seconds": round(len(x) / SR, 3), "peak_db": round(20 * np.log10(peak + 1e-9), 1),
            "loudness_db": round(float(loudness(x)), 1), "bytes": os.path.getsize(dest)}


def main() -> None:
    global KENNEY, BOARDFX
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kenney", required=True)
    parser.add_argument("--boardfx", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    KENNEY, BOARDFX = args.kenney, args.boardfx
    os.makedirs(args.out, exist_ok=True)
    only = set(filter(None, args.only.split(",")))
    report = {}
    for name, (recipe, target, want_stereo) in CUES.items():
        if only and name not in only:
            continue
        g.rng = np.random.default_rng(zlib.crc32(name.encode()))
        x = recipe()
        # Nothing below ~60 Hz survives a phone speaker; it would only eat headroom.
        x = highpass(x, 60, order=2)
        x = match_loudness(x, target, -1.0)
        for old in (name + ".m4a", name + ".caf"):
            path = os.path.join(args.out, old)
            if os.path.exists(path):
                os.remove(path)
        report[name] = write(name, x, args.out, want_stereo)
        print(f"{name:18s} {report[name]}")
    if not only:
        with open(os.path.join(os.path.dirname(__file__), "audio-manifest.json"), "w") as f:
            json.dump(report, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
