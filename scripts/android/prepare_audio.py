#!/usr/bin/env python3
"""Stage the iOS game audio (apps/ios/MagicMobile/Resources/Audio) for Android.

The iOS bundle is the single source. AAC .m4a files play on Android unchanged. Android
cannot read Apple's CAF container, so each 16-bit linear-PCM .caf is rewritten as a WAV
with identical samples. Pure Python, so it runs on macOS and on the Linux CI runners.

Usage: prepare_audio.py REPO_ROOT OUTPUT_DIR
"""
import shutil
import struct
import sys
import wave
from pathlib import Path


def caf_to_wav(source: Path, target: Path):
    data = source.read_bytes()
    if data[:4] != b"caff":
        raise ValueError(f"{source.name}: not a CAF file")
    offset = 8
    desc = None
    audio = None
    while offset + 12 <= len(data):
        kind = data[offset:offset + 4]
        size = struct.unpack(">q", data[offset + 4:offset + 12])[0]
        body_start = offset + 12
        body_end = len(data) if size == -1 else body_start + size
        body = data[body_start:body_end]
        if kind == b"desc":
            rate, fmt, flags, bytes_per_packet, frames_per_packet, channels, bits = struct.unpack(">d4sIIIII", body[:32])
            desc = (rate, fmt, flags, bytes_per_packet, channels, bits)
        elif kind == b"data":
            audio = body[4:]  # skip the edit count
        offset = body_end
    if desc is None or audio is None:
        raise ValueError(f"{source.name}: missing desc or data chunk")
    rate, fmt, flags, bytes_per_packet, channels, bits = desc
    if fmt != b"lpcm" or bits != 16 or flags & 1:
        raise ValueError(f"{source.name}: expected 16-bit integer PCM, got {fmt!r} {bits}-bit flags={flags}")
    little_endian = bool(flags & 2)
    frame = channels * 2
    audio = audio[: len(audio) - len(audio) % frame]
    if not little_endian:
        swapped = bytearray(audio)
        swapped[0::2], swapped[1::2] = audio[1::2], audio[0::2]
        audio = bytes(swapped)
    with wave.open(str(target), "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(2)
        out.setframerate(int(rate))
        out.writeframes(audio)


def main():
    repo, output = Path(sys.argv[1]), Path(sys.argv[2])
    source = repo / "apps/ios/MagicMobile/Resources/Audio"
    audio_out = output / "audio"
    if audio_out.exists():
        shutil.rmtree(audio_out)
    audio_out.mkdir(parents=True)
    for item in sorted(source.iterdir()):
        if item.suffix == ".m4a" or item.name == "CREDITS.txt":
            shutil.copyfile(item, audio_out / item.name)
        elif item.suffix == ".caf":
            caf_to_wav(item, audio_out / (item.stem + ".wav"))
    print(f"staged {len(list(audio_out.iterdir()))} audio files")


if __name__ == "__main__":
    main()
