"""Small offline DSP kit for MagicMobile's sound design (numpy + scipy).

Everything here renders float32 arrays at 44.1 kHz. Mono signals are 1-D; stereo
signals are shaped (n, 2). Nothing runs in the app: the build script renders files.
"""
from __future__ import annotations

import numpy as np
from scipy import signal

SR = 44100
rng = np.random.default_rng(20260924)


# ---------------------------------------------------------------- basics
def n_of(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def times(seconds: float) -> np.ndarray:
    return np.arange(n_of(seconds)) / SR


def midi(note: float) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


def silence(seconds: float) -> np.ndarray:
    return np.zeros(n_of(seconds), dtype=np.float32)


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if len(x) >= n:
        return x[:n]
    shape = (n - len(x),) + x.shape[1:]
    return np.concatenate([x, np.zeros(shape, dtype=x.dtype)])


def mix(*parts: tuple[np.ndarray, float] | np.ndarray, length: float | None = None) -> np.ndarray:
    """Mix mono or stereo parts. A part may be (signal, start_seconds)."""
    items = [(p, 0.0) if isinstance(p, np.ndarray) else p for p in parts]
    stereo = any(sig.ndim == 2 for sig, _ in items)
    end = max(n_of(start) + len(sig) for sig, start in items)
    if length is not None:
        end = n_of(length)
    out = np.zeros((end, 2) if stereo else end, dtype=np.float32)
    for sig, start in items:
        if stereo and sig.ndim == 1:
            sig = np.stack([sig, sig], axis=1)
        s = n_of(start) if start > 0 else 0
        if s >= end:
            continue
        seg = sig[: end - s]
        out[s : s + len(seg)] += seg
    return out


# ---------------------------------------------------------------- envelopes
def env_exp(seconds: float, attack: float = 0.004, decay: float = 0.3, hold: float = 0.0) -> np.ndarray:
    """Linear attack, optional hold, exponential decay with time constant `decay`."""
    t = times(seconds)
    e = np.exp(-np.maximum(0, t - attack - hold) / max(decay, 1e-4))
    if attack > 0:
        e = np.where(t < attack, t / attack, e)
    return e.astype(np.float32)


def env_adsr(seconds: float, a: float, d: float, s: float, r: float) -> np.ndarray:
    n = n_of(seconds)
    na, nd, nr = n_of(a), n_of(d), n_of(r)
    ns = max(0, n - na - nd - nr)
    parts = [np.linspace(0, 1, na, endpoint=False), np.linspace(1, s, nd, endpoint=False),
             np.full(ns, s), np.linspace(s, 0, nr)]
    return pad_to(np.concatenate(parts).astype(np.float32), n)


def env_swell(seconds: float, rise: float, fall: float, curve: float = 2.0) -> np.ndarray:
    """Slow rise to a peak at `rise`, then fall over `fall` (reverse-cymbal shapes)."""
    t = times(seconds)
    up = np.clip(t / max(rise, 1e-4), 0, 1) ** curve
    down = np.clip(1 - (t - rise) / max(fall, 1e-4), 0, 1) ** 1.5
    return np.where(t < rise, up, down).astype(np.float32)


def fade(x: np.ndarray, fade_in: float = 0.002, fade_out: float = 0.02) -> np.ndarray:
    y = x.copy()
    ni, no = min(len(y), n_of(fade_in)), min(len(y), n_of(fade_out))
    ramp_in = np.linspace(0, 1, ni, dtype=np.float32)
    ramp_out = np.linspace(1, 0, no, dtype=np.float32)
    if y.ndim == 2:
        ramp_in, ramp_out = ramp_in[:, None], ramp_out[:, None]
    y[:ni] *= ramp_in
    y[len(y) - no :] *= ramp_out
    return y


# ---------------------------------------------------------------- oscillators
def phase_of(freq: float | np.ndarray, n: int) -> np.ndarray:
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    return 2 * np.pi * np.cumsum(f) / SR


def sine(freq, seconds: float, phase0: float = 0.0) -> np.ndarray:
    n = n_of(seconds)
    return np.sin(phase_of(freq, n) + phase0).astype(np.float32)


def glide(f0: float, f1: float, seconds: float, curve: float = 1.0) -> np.ndarray:
    t = np.linspace(0, 1, n_of(seconds)) ** curve
    return (f0 * (f1 / f0) ** t).astype(np.float64)


def saw(freq, seconds: float, partials: int | None = None) -> np.ndarray:
    """Band-limited sawtooth by additive synthesis (no aliasing for musical notes)."""
    n = n_of(seconds)
    ph = phase_of(freq, n)
    base = float(np.max(np.asarray(freq)))
    k_max = partials or max(1, int((SR * 0.45) // max(base, 1)))
    k_max = min(k_max, 60)
    out = np.zeros(n)
    for k in range(1, k_max + 1):
        out += np.sin(k * ph) / k
    return (out * (2 / np.pi)).astype(np.float32)


def square(freq, seconds: float, partials: int | None = None) -> np.ndarray:
    n = n_of(seconds)
    ph = phase_of(freq, n)
    base = float(np.max(np.asarray(freq)))
    k_max = min(partials or max(1, int((SR * 0.45) // max(base, 1))), 60)
    out = np.zeros(n)
    for k in range(1, k_max + 1, 2):
        out += np.sin(k * ph) / k
    return (out * (4 / np.pi)).astype(np.float32)


def noise(seconds: float, color: str = "white") -> np.ndarray:
    n = n_of(seconds)
    w = rng.standard_normal(n)
    if color == "pink":
        b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
        w = signal.lfilter(b, a, w) * 3.0
    elif color == "brown":
        w = np.cumsum(w)
        w = signal.lfilter([1, -1], [1, -0.995], w) * 0.06
    w = w / (np.max(np.abs(w)) + 1e-9)
    return w.astype(np.float32)


def fm_bell(freq: float, seconds: float, ratio: float = 1.4, index: float = 3.0, decay: float = 0.9,
            brightness_decay: float = 0.35) -> np.ndarray:
    """Chowning-style FM bell: inharmonic ratio, modulation index decaying faster than amplitude."""
    t = times(seconds)
    idx = index * np.exp(-t / brightness_decay)
    mod = np.sin(2 * np.pi * freq * ratio * t)
    car = np.sin(2 * np.pi * freq * t + idx * mod)
    return (car * env_exp(seconds, 0.002, decay)).astype(np.float32)


def church_bell(freq: float, seconds: float, decay: float = 2.2) -> np.ndarray:
    """Additive bell with the classic hum / prime / tierce / quint / nominal partials."""
    t = times(seconds)
    partials = [(0.5, 0.55, 1.0), (1.0, 1.0, 0.8), (1.19, 0.45, 0.55), (1.5, 0.35, 0.5),
                (2.0, 0.6, 0.45), (2.52, 0.22, 0.3), (3.0, 0.18, 0.25), (4.07, 0.1, 0.18)]
    out = np.zeros(len(t))
    for ratio, amp, dscale in partials:
        beat = 1 + 0.0015 * np.sin(2 * np.pi * 1.3 * ratio * t)  # gentle shimmer
        out += amp * np.sin(2 * np.pi * freq * ratio * t * beat) * np.exp(-t / (decay * dscale))
    out *= np.minimum(1, t / 0.003)
    return (out / 2.5).astype(np.float32)


def metal(freq: float, seconds: float, decay: float = 0.5) -> np.ndarray:
    """Clang: strongly inharmonic modes (circular plate ratios)."""
    t = times(seconds)
    modes = [(1.0, 1.0), (1.59, 0.7), (2.14, 0.55), (2.3, 0.5), (2.65, 0.4), (2.92, 0.35), (3.16, 0.25), (3.5, 0.2)]
    out = np.zeros(len(t))
    for i, (ratio, amp) in enumerate(modes):
        out += amp * np.sin(2 * np.pi * freq * ratio * t + i) * np.exp(-t / (decay * (1.0 - i * 0.07)))
    return (out / 3).astype(np.float32)


def pluck(freq: float, seconds: float, damping: float = 0.996, brightness: float = 0.5) -> np.ndarray:
    """Karplus–Strong plucked string (harp / lute)."""
    n = n_of(seconds)
    period = max(2, int(round(SR / freq)))
    buf = rng.uniform(-1, 1, period)
    buf = signal.lfilter([brightness, 1 - brightness], [1], buf)  # soften the excitation
    out = np.empty(n)
    idx = 0
    prev = 0.0
    for i in range(n):
        cur = buf[idx]
        out[i] = cur
        nxt = damping * 0.5 * (cur + prev)
        prev = cur
        buf[idx] = nxt
        idx = (idx + 1) % period
    return (out * np.minimum(1, np.arange(n) / 20)).astype(np.float32)


def membrane(freq: float, seconds: float, drop: float = 0.55, decay: float = 0.25, snap: float = 0.25) -> np.ndarray:
    """Drum / timpani / thud: sine with a fast pitch drop plus a short noise snap."""
    t = times(seconds)
    f = freq * (1 + drop * np.exp(-t / 0.03))
    body = np.sin(phase_of(f, len(t))) * np.exp(-t / decay)
    hit = lowpass(noise(seconds), 1800) * np.exp(-t / 0.02) * snap
    return (body + hit).astype(np.float32)


# ---------------------------------------------------------------- filters
def _sos(kind: str, freq, order: int = 2):
    nyq = SR / 2
    if isinstance(freq, (list, tuple)):
        wn = [min(0.999, max(1e-4, f / nyq)) for f in freq]
    else:
        wn = min(0.999, max(1e-4, freq / nyq))
    return signal.butter(order, wn, btype=kind, output="sos")


def lowpass(x: np.ndarray, freq: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("lowpass", freq, order), x, axis=0).astype(np.float32)


def highpass(x: np.ndarray, freq: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("highpass", freq, order), x, axis=0).astype(np.float32)


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x, axis=0).astype(np.float32)


def sweep(x: np.ndarray, kind: str, f_from: float, f_to: float, q_width: float = 0.6, block: int = 256,
          curve: float = 1.0) -> np.ndarray:
    """Time-varying filter by blocks (carries state). kind: lowpass | highpass | bandpass."""
    n = len(x)
    out = np.zeros_like(x, dtype=np.float32)
    zi = None
    blocks = (n + block - 1) // block
    for b in range(blocks):
        p = (b / max(1, blocks - 1)) ** curve
        f = f_from * (f_to / f_from) ** p
        if kind == "bandpass":
            sos = _sos("bandpass", [f * (1 - q_width / 2), f * (1 + q_width / 2)])
        else:
            sos = _sos(kind, f)
        if zi is None or zi.shape[0] != sos.shape[0]:
            zi = np.zeros((sos.shape[0], 2) + x.shape[1:])
        seg = x[b * block : (b + 1) * block]
        y, zi = signal.sosfilt(sos, seg, axis=0, zi=zi)
        out[b * block : (b + 1) * block] = y
    return out


def formant(x: np.ndarray, vowel: str = "ah") -> np.ndarray:
    table = {"ah": [(730, 1.0), (1090, 0.5), (2440, 0.25)], "oh": [(570, 1.0), (840, 0.45), (2410, 0.2)],
             "oo": [(300, 1.0), (870, 0.3), (2240, 0.12)]}
    out = np.zeros_like(x)
    for f, g in table[vowel]:
        out += g * bandpass(x, f * 0.88, f * 1.12)
    return out.astype(np.float32)


def saturate(x: np.ndarray, drive: float = 1.5) -> np.ndarray:
    return (np.tanh(x * drive) / np.tanh(drive)).astype(np.float32)


# ---------------------------------------------------------------- space
def stereo(x: np.ndarray, pan: float = 0.0, width: float = 0.0) -> np.ndarray:
    """Equal-power pan (-1 left … 1 right); `width` adds a tiny Haas delay on one side."""
    if x.ndim == 2:
        return x
    angle = (pan + 1) * np.pi / 4
    left, right = x * np.cos(angle), x * np.sin(angle)
    if width > 0:
        d = n_of(width)
        right = np.concatenate([np.zeros(d, dtype=np.float32), right[:-d]]) if d < len(right) else right
    return np.stack([left, right], axis=1).astype(np.float32) * np.sqrt(2)


def reverb_ir(seconds: float = 2.0, damping: float = 0.55, predelay: float = 0.012) -> np.ndarray:
    """Stereo impulse response: decorrelated noise, exponential decay, highs dying faster."""
    n = n_of(seconds)
    t = np.arange(n) / SR
    rt = seconds / 6.9  # time constant for -60 dB at `seconds`
    ir = np.zeros((n, 2))
    for ch in range(2):
        w = rng.standard_normal(n)
        low = lowpass(w, 900).astype(np.float64)
        mid = bandpass(w, 900, 4000).astype(np.float64)
        high = highpass(w, 4000).astype(np.float64)
        ir[:, ch] = (low * np.exp(-t / rt) + mid * np.exp(-t / (rt * (1 - damping * 0.4)))
                     + high * np.exp(-t / (rt * (1 - damping * 0.75))))
    # A few early reflections for body.
    for delay, gain in [(0.011, 0.6), (0.019, 0.45), (0.027, 0.35), (0.041, 0.25)]:
        i = n_of(delay)
        ir[i, 0] += gain
        ir[min(n - 1, i + 37), 1] += gain
    ir *= np.minimum(1, t / 0.006)[:, None]
    pre = np.zeros((n_of(predelay), 2))
    ir = np.concatenate([pre, ir])
    ir /= np.sqrt(np.sum(ir ** 2) / 2) + 1e-9
    return ir.astype(np.float32)


_IR_CACHE: dict[tuple, np.ndarray] = {}


def reverb(x: np.ndarray, wet: float = 0.3, seconds: float = 2.0, damping: float = 0.55,
           predelay: float = 0.012) -> np.ndarray:
    key = (round(seconds, 2), round(damping, 2), round(predelay, 3))
    if key not in _IR_CACHE:
        _IR_CACHE[key] = reverb_ir(seconds, damping, predelay)
    ir = _IR_CACHE[key]
    dry = stereo(x) if x.ndim == 1 else x
    mono_in = dry.mean(axis=1)
    tail = np.stack([signal.fftconvolve(mono_in, ir[:, 0]), signal.fftconvolve(mono_in, ir[:, 1])], axis=1)
    tail *= 0.18
    dry_full = pad_to(dry, len(tail))
    return (dry_full * (1 - wet * 0.5) + tail * wet).astype(np.float32)


def echo(x: np.ndarray, delay: float, feedback: float = 0.35, taps: int = 4) -> np.ndarray:
    out = pad_to(x.copy(), len(x) + n_of(delay * taps))
    for k in range(1, taps + 1):
        s = n_of(delay * k)
        out[s : s + len(x)] += x * (feedback ** k)
    return out


# ---------------------------------------------------------------- finishing
def trim_silence(x: np.ndarray, threshold_db: float = -60.0, keep_tail: float = 0.01) -> np.ndarray:
    mono = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
    peak = np.max(mono) + 1e-9
    idx = np.where(mono > peak * 10 ** (threshold_db / 20))[0]
    if len(idx) == 0:
        return x
    return x[idx[0] : min(len(x), idx[-1] + n_of(keep_tail))]


def normalize(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    peak = np.max(np.abs(x)) + 1e-9
    return (x * (10 ** (peak_db / 20) / peak)).astype(np.float32)


def punch(x: np.ndarray, drive: float = 3.0, amount: float = 0.5) -> np.ndarray:
    """Bass harmonics for phone speakers: saturate the signal so a 60 Hz thud gains
    180/300/420 Hz overtones a small speaker can reproduce, then blend it in."""
    harmonics = lowpass(saturate(x, drive), 2600)
    return (x * (1 - amount) + harmonics * amount).astype(np.float32)


def phone_weighted(x: np.ndarray) -> np.ndarray:
    """What an iPhone speaker roughly hears: little below ~200 Hz."""
    return highpass(x, 200, order=2)


def loudness(x: np.ndarray, weighted: bool = True) -> float:
    """Short-term RMS of the loudest 400 ms window, in dBFS, phone-speaker weighted."""
    if weighted:
        x = phone_weighted(x)
    mono = x if x.ndim == 1 else x.mean(axis=1)
    w = n_of(0.4)
    if len(mono) <= w:
        return 20 * np.log10(np.sqrt(np.mean(mono ** 2)) + 1e-9)
    power = signal.fftconvolve(mono ** 2, np.ones(w) / w, mode="valid")
    return 10 * np.log10(np.max(power) + 1e-12)


def match_loudness(x: np.ndarray, target_db: float, ceiling_db: float = -1.0) -> np.ndarray:
    gain = 10 ** ((target_db - loudness(x)) / 20)
    y = x * gain
    limit = 10 ** (ceiling_db / 20)
    if np.max(np.abs(y)) > limit:
        # Soft saturation near the ceiling rather than a hard clip.
        y = limit * np.tanh(y / limit)
    return y.astype(np.float32)
