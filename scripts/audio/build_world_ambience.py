#!/usr/bin/env python3
"""Each Arena world's air, as one seamless loop in Resources/Audio/world-<slug>.caf.

Claude can't listen, so every world is checked in numbers: the level a phone's speaker can play (300 Hz to 8 kHz), the peak and
the step across the loop's seam. Caleb judges them in Sound Lab. The sources are the Sonniss files in scripts/audio/SOURCES.md,
converted as that file says.

  ~/.venvs/mm-audio/bin/python scripts/audio/build_world_ambience.py --sonniss <wav folder> --out apps/ios/MagicMobile/Resources/Audio
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

RATE = 44100
OUT_RATE = 32000
SEAM = 4.0  # Seconds the end of a loop fades into its start.


def read(folder, name):
    rate, data = wavfile.read(Path(folder) / name)
    assert rate == RATE, name
    data = data.astype(np.float32)
    return np.stack([data, data], axis=1) if data.ndim == 1 else data[:, :2]


def band(x, low=None, high=None, order=4):
    if low and high:
        sos = signal.butter(order, [low, high], "bandpass", fs=RATE, output="sos")
    elif low:
        sos = signal.butter(order, low, "highpass", fs=RATE, output="sos")
    else:
        sos = signal.butter(order, high, "lowpass", fs=RATE, output="sos")
    return signal.sosfiltfilt(sos, x, axis=0).astype(np.float32)


def heard(x):
    """Level in dB of what a phone's speaker can play."""
    return 20 * np.log10(np.sqrt(np.mean(band(x, 300, 8000) ** 2)) + 1e-9)


def steadiest(x, seconds):
    """The stretch with the least swing, so nothing in it jumps out on every pass."""
    block = RATE // 2
    level = np.sqrt(np.mean(x[: len(x) // block * block].reshape(-1, block, 2) ** 2, axis=(1, 2))) + 1e-9
    level = 20 * np.log10(level)
    span = int(seconds * 2)
    if len(level) <= span:
        return x
    start = min(range(len(level) - span), key=lambda i: level[i : i + span].std() + abs(level[i : i + span].mean() - np.median(level)) * 0.2)
    return x[start * block :]


def looped(x, seconds):
    length, fade = int(seconds * RATE), int(SEAM * RATE)
    assert len(x) >= length + fade, f"{len(x) / RATE:.1f}s is too short for {seconds}s"
    curve = np.linspace(0, 1, fade)[:, None].astype(np.float32)
    out = x[:length].copy()
    out[:fade] = x[:fade] * np.sqrt(curve) + x[length : length + fade] * np.sqrt(1 - curve)
    return out


def place(bed, clip, at, gain):
    """Lays a sound into the loop, wrapping past its end. Its own ends are faded, so it arrives and leaves softly."""
    fade = min(len(clip) // 4, int(0.25 * RATE))
    curve = np.ones(len(clip), dtype=np.float32)
    curve[:fade] = np.linspace(0, 1, fade)
    curve[-fade:] = np.linspace(1, 0, fade)
    index = (int(at * RATE) + np.arange(len(clip))) % len(bed)
    bed[index] += clip * curve[:, None] * gain


def crackles(x, count):
    """The loudest separate pops in a recording, each with its short ring."""
    envelope = np.abs(x).mean(axis=1)
    peaks, _ = signal.find_peaks(envelope, distance=int(0.5 * RATE), height=np.percentile(envelope, 99.5))
    strongest = peaks[np.argsort(envelope[peaks])[::-1][:count]]
    return [x[max(0, p - int(0.02 * RATE)) : p + int(0.4 * RATE)] for p in sorted(strongest)]


def volcano(folder):
    roar = steadiest(read(folder, "Lava Lava Windy.wav"), 50)
    # The recording is nearly all wind on the microphone: its lava lives above 200 Hz.
    bed = looped(band(roar, 200, 6000) * 14 + band(roar, 45, 200) * 0.4, 45)
    pops = crackles(band(read(folder, "Lava Lava Short Windy Crackles.wav"), 400, 7000), 7)
    rng = np.random.default_rng(11)
    spots = np.sort(rng.uniform(1, 44, 16))
    # A pop stands a little proud of the roar, and never startles.
    level = np.sqrt(np.mean(band(bed, 300, 8000) ** 2))
    for index, at in enumerate(spots):
        pop = pops[index % len(pops)]
        place(bed, pop / np.abs(pop).max(), at, level * rng.uniform(3, 6))
    return bed, -28


def utopia(folder):
    water = steadiest(read(folder, "FOUNTAIN Small, Splashes of Multiple Squirts on the Ground, Close.wav"), 50)
    # Close to the microphone it's all hiss: the far side of a plaza has lost its top.
    return looped(band(water, 220, 5200), 45), -31


def halloween(folder):
    texture = read(folder, "Bluezone_BC0255_ambience_texture_004.wav")
    # Nearly all of it is sub-bass, which a phone can't play and earbuds would make a weight on the head.
    return looped(band(texture, 280, 2400, order=6) * 14 + band(texture, 90, 280) * 0.28, 31), -29


def radio_night(folder):
    wind = steadiest(read(folder, "wind blowing mike v1.wav"), 37)
    bed = looped(band(wind, 170, 5000) * 3 + band(wind, 60, 170) * 0.3, 36)
    static = band(read(folder, "Bluezone_BC0266_radio_transmission_interference_noise_transmitter_008.wav"), 400, 3200)
    voices = band(read(folder, "Bluezone_BC0266_radio_transmission_radio_chatter_voice_interference_002_03.wav"), 400, 3000)
    level = np.sqrt(np.mean(band(bed, 300, 8000) ** 2))
    fit = lambda clip, db: clip * (level * 10 ** (db / 20) / (np.sqrt(np.mean(clip ** 2)) + 1e-9))
    place(bed, fit(static, -3), 7.5, 1)
    place(bed, fit(voices, -5), 17, 1)
    place(bed, fit(static, -5), 29, 1)
    return bed, -30


WORLDS = {"volcano": volcano, "utopia": utopia, "halloween": halloween, "radio-night": radio_night}


def finish(x, target):
    x = x * 10 ** ((target - heard(x)) / 20)
    # Only a stray peak meets this; the bed stays well under it.
    return np.tanh(x / 0.7) * 0.7


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sonniss", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    for slug, build in WORLDS.items():
        bed, target = build(args.sonniss)
        loop = finish(bed, target)
        step = np.abs(loop[0] - loop[-1]).mean()
        typical = np.abs(np.diff(loop, axis=0)).mean()
        small = signal.resample_poly(loop, OUT_RATE, RATE, axis=0)
        path = Path(args.out) / f"world-{slug}.caf"
        with tempfile.TemporaryDirectory() as scratch:
            wav = Path(scratch) / "loop.wav"
            wavfile.write(wav, OUT_RATE, (np.clip(small, -1, 1) * 32767).astype(np.int16))
            subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", "-c", "2", str(wav), str(path)], check=True)
        print(f"{slug:12s} {len(loop) / RATE:4.0f}s heard {heard(loop):6.1f} dB  all {20 * np.log10(np.sqrt(np.mean(loop ** 2))):6.1f} dB  "
              f"peak {np.abs(loop).max():.2f}  seam {step:.4f} vs {typical:.4f}  {path.stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
