#!/usr/bin/env python3
"""Give a silent simulator recording of a design preview its soundtrack, from the app's own sound log.

`xcrun simctl io recordVideo` records no audio. Run the preview with MAGICMOBILE_LOG_SOUNDS=1 and capture its console
(`simctl launch --console-pty`): the app prints `MMSTEP <unix time> <step>` when a walkthrough advances and
`MMSOUND <unix time> <cue> <volume> <rate> <device time>` as each cue starts. This finds the frames where the
walkthrough's label changes (one per step), places every sound relative to its own step's label change (the recorder's
clock drifts by ~0.1 s over a minute, so one global offset is not enough), and muxes the bundled cue files at their
played volume and rate onto the video.

  ~/.venvs/mm-audio/bin/python scripts/audio/demo_soundtrack.py --video arrivals.mov --console console.log \\
      --audio apps/ios/MagicMobile/Resources/Audio --label-box 0.32,0.098,0.68,0.13 --out demo.mp4 \\
      [--start 1.5] [--rec-start <unix time the recorder was launched>]
"""
from __future__ import annotations

import argparse
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample

SR = 44100
LEAD = 0.1        # GameAudio.playTogether starts a group this long after it logs it
GROUP = 0.08      # cues logged closer than this were started together
RENDER = 1 / 30   # the label shows one frame after the step is logged


def label_changes(video: str, box: tuple[float, float, float, float]) -> list[float]:
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                            "-of", "csv=p=0", video], capture_output=True, text=True, check=True).stdout.strip()
    width, height = map(int, probe.split(","))
    x0, y0, x1, y1 = box
    crop = f"crop={int(width * (x1 - x0))}:{int(height * (y1 - y0))}:{int(width * x0)}:{int(height * y0)}"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vf", f"fps=30,{crop},scale=200:24,format=gray",
                          "-f", "rawvideo", "-"], capture_output=True, check=True).stdout
    frames = np.frombuffer(raw, np.uint8).reshape(-1, 24, 200).astype(np.float32)
    change = np.abs(np.diff(frames, axis=0)).mean(axis=(1, 2))
    threshold = np.median(change) + 6 * (np.median(np.abs(change - np.median(change))) + 0.2)
    events: list[int] = []
    for i in np.where(change > threshold)[0]:
        if not events or i - events[-1] > 8:
            events.append(int(i))
    return [(i + 1) / 30 for i in events]


def decode(path: str) -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "x.wav")
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEF32@44100", "-c", "2", path, wav], check=True)
        _, x = wavfile.read(wav)
    return x.astype(np.float32).reshape(-1, 2)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", required=True)
    parser.add_argument("--console", required=True)
    parser.add_argument("--audio", required=True, help="the app's Resources/Audio")
    parser.add_argument("--label-box", default="0.32,0.098,0.68,0.13", help="x0,y0,x1,y1 of the step label, 0-1")
    parser.add_argument("--start", type=float, default=0.0, help="trim the video's first seconds")
    parser.add_argument("--rec-start", type=float, default=None,
                        help="unix time the recorder was launched; its first frame comes 0-1.6 s later, which settles which "
                             "label change is the first step (steps ~3 s apart otherwise fit one step off as well)")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    lines = [line.split() for line in open(args.console) if line.startswith(("MMSTEP", "MMSOUND"))]
    steps = [float(parts[1]) for parts in lines if parts[0] == "MMSTEP"]
    sounds = [(float(p[1]), p[2], float(p[3]), float(p[4])) for p in lines if p[0] == "MMSOUND"]
    changes = label_changes(args.video, tuple(map(float, args.label_box.split(","))))
    # Pair each logged step with its label change. Other things cross the label too (the turn banner), so find the lag
    # that lines most steps up with a change, then give each step the change nearest that lag (or the lag itself).
    def matches(lag: float) -> int:
        return sum(any(abs(st - steps[0] - lag - c) < 0.12 for c in changes) for st in steps)
    if args.rec_start is not None:
        first = steps[0] - args.rec_start
        window = np.arange(-first, 1.6 - first, 0.01)
    else:
        window = np.arange(-8, 2, 0.01)
    lag = max(window, key=matches)
    anchors = []
    for st in steps:
        guess = st - steps[0] - lag
        near = min(changes, key=lambda c: abs(c - guess))
        anchors.append((st, (near if abs(near - guess) < 0.25 else guess) - RENDER))
    shift = matches(lag)
    last_step = [p for p in lines if p[0] == "MMSTEP"][-1]
    demo_end = anchors[-1][1] if last_step[2].strip() == "0" else None
    print(f"{len(steps)} steps, {shift} matched to label changes; demo ends at {demo_end}")

    def video_time(t: float) -> float:
        before = [a for a in anchors if a[0] <= t] or anchors[:1]
        log, seen = before[-1]
        return seen + (t - log)

    duration = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                                     args.video], capture_output=True, text=True, check=True).stdout)
    track = np.zeros((int((duration + 2) * SR), 2), dtype=np.float32)
    cache: dict[str, np.ndarray] = {}
    # Cues logged within GROUP of each other were one playTogether call: they all start LEAD after the first.
    starts: list[float] = []
    for i, (t, *_rest) in enumerate(sounds):
        if i > 0 and t - sounds[i - 1][0] < GROUP:
            starts.append(starts[-1])
        elif i + 1 < len(sounds) and sounds[i + 1][0] - t < GROUP:
            starts.append(t + LEAD)
        else:
            starts.append(t)
    for (t, cue, volume, rate), start in zip(sounds, starts):
        name = next((f for f in (cue + ".caf", cue + ".m4a", cue + "-1.caf", cue + "-1.m4a")
                     if os.path.exists(os.path.join(args.audio, f))), None)
        if name is None:
            print("missing", cue)
            continue
        x = cache.setdefault(name, decode(os.path.join(args.audio, name)))
        if abs(rate - 1) > 1e-3:
            x = resample(x, int(len(x) / rate), axis=0).astype(np.float32)
        at = int(video_time(start) * SR)
        if 0 <= at < len(track):
            end = min(len(track), at + len(x))
            track[at:end] += x[: end - at] * volume
        print(f"{video_time(start):6.2f}s  {cue:16s} vol {volume:.2f}")
    peak = float(np.abs(track).max())
    if peak > 0.98:
        track *= 0.98 / peak
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "track.wav")
        wavfile.write(wav, SR, (track * 32767).astype(np.int16))
        length = ["-t", f"{demo_end - args.start:.3f}"] if demo_end else []
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(args.start), "-i", args.video, "-ss", str(args.start), "-i", wav, *length,
                        "-vf", "fps=30,scale=600:-2:flags=lanczos", "-c:v", "libx264", "-preset", "slow", "-crf", "24",
                        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart",
                        args.out], check=True)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
