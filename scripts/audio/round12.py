#!/usr/bin/env python3
"""Round 12 auditions: Caleb's Keeps from the Tavern Sound Bin (Pixabay and OpenGameArt CC0 clips), rendered the way the
game would play them. Creature voices sit on the shipped landing thock and are levelled like rounds 9-11; enchantment
chimes sit on the beech knock; card clips are levelled to the card cue they would replace.

  ~/.venvs/mm-audio/bin/python scripts/audio/round12.py --sonniss build_output/audio-sources/sonniss-wav \\
      --kenney build_output/audio-sources/kenney-wav --sources build_output/audio-sources \\
      --out build_output/audio-trials/round12
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_game_audio as game  # noqa: E402
from build_game_audio import layer  # noqa: E402
from gamedsp import SR, highpass, loudness, match_loudness  # noqa: E402

VOICE_AT = 0.05   # where rounds 9-12 started a voice after the thock
# How loud a voice sits against the thock, as the shipped voices do: small ones about 2 dB under it (goblin -2.7,
# squirrel -3.1, sliver -1.7, elf -1.5), big ones over it (dragon +1.9).
BIG = {"dragon", "beast", "wolf", "orc", "zombie", "angel"}
VOICE_VS_THOCK = {True: 1.0, False: -2.0}
P, O = "pixabay-raw", "oga-raw"

# (slot, label, source file under --sources, longest seconds kept)
VOICES = [
    ("goblin", "mad-laughter", f"{P}/goblin/applehillstudios-mad-goblin-laughter-1-543569.mp3", 0.8),
    ("goblin", "oga-goblin-7", f"{O}/goblins/goblins/goblin-7.wav", 0.8),
    ("goblin", "small-monster-attack", f"{P}/goblin/daviddumaisaudio-small-monster-attack-195712.mp3", 0.7),
    ("squirrel", "chirping", f"{P}/squirrel/freesound_community-squirrel-chirping-28364.mp3", 0.6),
    ("squirrel", "squirrel-89831", f"{P}/squirrel/freesound_community-squirrel-89831.mp3", 0.6),
    ("squirrel", "chipmunk", f"{P}/chipmunk/freesound_community-046634_chipmunk-63290.mp3", 0.6),
    ("dragon", "epic-roar", f"{P}/dragon/dragon-studio-epic-dragon-roar-364481.mp3", 1.1),
    ("dragon", "growl", f"{P}/dragon/freesound_community-dragon-growl-37570.mp3", 1.1),
    ("insect", "bug-04", f"{O}/creatures1/bug_04.ogg", 0.6),
    ("insect", "bug-10", f"{O}/creatures2/bug_10.ogg", 0.6),
    ("insect", "giant-footsteps", f"{P}/insect/yodguard-giant-insect-footsteps-1-482548.mp3", 0.7),
    ("orc", "large-monster-attack", f"{P}/orc/daviddumaisaudio-large-monster-attack-195713.mp3", 0.8),
    ("orc", "grunt-01", f"{O}/creatures1/grunt_01.ogg", 0.7),
    ("orc", "grunt-04", f"{O}/creatures1/grunt_04.ogg", 0.7),
    ("orc", "ogre", f"{P}/orc/magiaz-ogre-387364.mp3", 0.9),
    ("beast", "beast-growl", f"{P}/beast/dragon-studio-beast-growl-494304.mp3", 1.0),
    ("beast", "beast-growl-sound", f"{P}/beast/dragon-studio-beast-growl-sound-376873.mp3", 1.0),
    ("beast", "dinosaur-growl", f"{P}/beast/dragon-studio-dinosaur-growl-487679.mp3", 1.0),
    ("beast", "growl-of-the-beast", f"{P}/beast/dragon-studio-growl-of-the-beast-504021.mp3", 1.0),
    ("beast", "monster-growl", f"{P}/beast/dragon-studio-monster-growl-376892.mp3", 1.0),
    ("beast", "weretiger-roar", f"{P}/beast/the-vampires-monster-weretiger-yarik-roar-6-321637.mp3", 1.0),
    ("beast", "oga-monster-01", f"{O}/creatures1/monster_01.ogg", 0.9),
    ("beast", "oga-monster-02", f"{O}/creatures1/monster_02.ogg", 0.9),
    ("beast", "oga-roar-05", f"{O}/creatures2/roar_05.ogg", 1.0),
    ("beast", "oga-howl", f"{O}/creatures1/howl.ogg", 1.0),
    ("critter", "cute-01", f"{O}/creatures1/cute_01.ogg", 0.6),
    ("critter", "cute-02", f"{O}/creatures1/cute_02.ogg", 0.6),
    ("critter", "cute-03", f"{O}/creatures1/cute_03.ogg", 0.6),
    ("critter", "cute-04", f"{O}/creatures1/cute_04.ogg", 0.6),
    ("critter", "cute-05", f"{O}/creatures1/cute_05.ogg", 0.6),
    ("faerie", "fairy-sparkle", f"{P}/fairy/humordome-fairy-sparkle-451414.mp3", 0.9),
    ("faerie", "fairy-flyby", f"{P}/fairy/freesound_community-fairy-flyby-2-106731.mp3", 0.9),
    ("angel", "ahhhh-choir", f"{P}/angel/freesound_community-ahhhh-37191.mp3", 1.1),
    ("vampire", "hiss", f"{P}/vampire/alesiadavina-female-vampire-attack-hiss-sound-effect-dark-sfx-552124.mp3", 0.8),
    ("zombie", "zombie-sound-2", f"{P}/zombie/dragon-studio-zombie-sound-2-357976.mp3", 1.0),
    ("zombie", "zombie-groan", f"{P}/zombie/freesound_community-zombie-groan-95051.mp3", 1.0),
    ("wolf", "spooky-howl", f"{P}/wolf/dragon-studio-spooky-wolf-howl-410547.mp3", 1.2),
    ("cat", "meow-fx", f"{P}/cat/soundreality-cat-meow-fx-461188.mp3", 0.8),
    ("cat", "cute-meow", f"{P}/cat/dragon-studio-cute-cat-meow-472372.mp3", 0.8),
    ("bird", "chirp", f"{P}/bird/loswin23-bird-chirp-485390.mp3", 0.8),
    ("ooze", "slime-01", f"{O}/creatures2/slime_01.ogg", 0.7),
    ("ooze", "slime-06", f"{O}/creatures2/slime_06.ogg", 0.7),
    ("ooze", "slime-04", f"{O}/creatures2/slime_04.ogg", 0.7),
    ("ooze", "burble-01", f"{O}/creatures1/burble_01.ogg", 0.7),
    ("wizard", "magical-spell-cast", f"{P}/wizard/daviddumaisaudio-magical-spell-cast-190272.mp3", 1.0),
    ("wizard", "spell-casting", f"{P}/wizard/universfield-spell-casting-229208.mp3", 1.0),
    ("odd", "misc-08", f"{O}/creatures1/misc_08.ogg", 0.8),
    ("odd", "misc-10", f"{O}/creatures2/misc_10.ogg", 0.8),
    ("odd", "misc-12", f"{O}/creatures2/misc_12.ogg", 0.8),
]

# Enchantment arrivals: the beech knock plus a chime, at the shipped arrive-enchantment level.
ENCHANTMENTS = [
    ("mystical-chime", f"{P}/enchantment/u_1cwn0vj1yq-mystical-chime-196405.mp3", 1.0),
    ("magic-church-bell", f"{P}/enchantment/u_jt9vdte8nd-magic-church-bell-293423.mp3", 1.0),
    ("sacred-rune-lock", f"{P}/enchantment/coghezzi-sacred-rune-lock-holy-magic-seal-activation-533277.mp3", 1.0),
]

# Card clips, each levelled to the shipped cue it would replace: (slot, label, source, longest, target dB).
CARDS = [
    ("card-draw", "taking-card", f"{P}/cards/oxidvideos-taking-playing-card-522520.mp3", 0.4, -25),
    ("card-draw", "card-sounds", f"{P}/cards/freesound_community-card-sounds-35956.mp3", 0.4, -25),
    ("card-play", "placing-card", f"{P}/cards/oxidvideos-placing-playing-card-522514.mp3", 0.5, -23),
    ("shuffle", "card-shuffle", f"{P}/cards/freesound_community-card-shuffle-94662.mp3", 1.3, -24),
    ("shuffle", "card-mixing", f"{P}/cards/freesound_community-card-mixing-48088.mp3", 1.3, -24),
]


# Where to start reading a clip whose first sound is not the one we want (Caleb: the bird's chirp came halfway in
# and was cut off).
STARTS = {("bird", "chirp"): 0.62}


def voice_clip(sources: str, slot: str, label: str, src: str, longest: float) -> np.ndarray:
    x = decode(os.path.join(sources, src))
    return cut(x[int(STARTS.get((slot, label), 0.0) * SR):], longest)


def decode(path: str) -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "x.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "wav", wav], check=True)
        return wavfile.read(wav)[1].astype(np.float32) / 32768.0


def cut(x: np.ndarray, longest: float) -> np.ndarray:
    """From just before the first strong onset, up to `longest` seconds or until it falls quiet, faded and levelled
    to -20 dBFS RMS so every voice starts from the same place."""
    env = np.convolve(np.abs(x), np.ones(441) / 441, mode="same")
    start = max(0, int(np.argmax(env > env.max() * 0.08)) - int(0.01 * SR))
    seg = x[start:start + int(longest * SR)].copy()
    e = env[start:start + len(seg)]
    loud = np.where(e > e.max() * 0.03)[0]
    if len(loud):
        seg = seg[: loud[-1] + int(0.08 * SR)]
    n = len(seg)
    fi, fo = min(int(0.004 * SR), n // 4), min(int(0.15 * SR), n // 3)
    seg[:fi] *= np.linspace(0, 1, fi)
    seg[n - fo:] *= np.linspace(1, 0, fo)
    return seg * (10 ** (-20 / 20) / (np.sqrt(np.mean(seg ** 2)) + 1e-9))


def save(name: str, y: np.ndarray, out: str) -> None:
    info = game.write(name, y, out, False)
    print(f"{name:40s} {info['seconds']:.2f} s  loudness {loudness(y):6.1f} dB  peak {info['peak_db']:5.1f} dB")


def landing_bases(sources: str) -> dict[str, np.ndarray]:
    """Round 13: what a creature lands with. Caleb found the wood thock wrong and liked a card hitting the table, so
    each card take is levelled to the shipped thock's loudness and can sit under any voice."""
    shipped = game.creature_sound(False)
    level = loudness(shipped)
    place = cut(decode(os.path.join(sources, f"{P}/cards/oxidvideos-placing-playing-card-522514.mp3")), 0.35)
    take = cut(decode(os.path.join(sources, f"{P}/cards/oxidvideos-taking-playing-card-522520.mp3")), 0.35)
    take3 = cut(decode(os.path.join(sources, f"{P}/cards/oxidvideos-taking-playing-card-3-522513.mp3")), 0.35)
    soft_thud = game.deep_thud(0.0)[0] * 10 ** (-12 / 20)
    return {
        "wood-thock": shipped,
        "card-place": match_loudness(highpass(place, 80, order=2), level, -1.0),
        "card-take": match_loudness(highpass(take, 80, order=2), level, -1.0),
        "card-take-3": match_loudness(highpass(take3, 80, order=2), level, -1.0),
        "card-place-soft-thud": match_loudness(highpass(layer((place, 0.0, 0.0), (soft_thud, 0.0, 0.0)), 60, order=2),
                                               level, -1.0),
    }


def layers(args) -> None:
    """Bases and voices as separate files, so the Sound Bin can put any voice on any landing sound. Each voice keeps
    the level it has in its round 12 take relative to the shipped thock."""
    out = os.path.join(args.out, "layers")
    os.makedirs(out, exist_ok=True)
    for name, x in landing_bases(args.sources).items():
        save(f"base--{name}", x, out)
    thock = highpass(layer(*game.creature_parts(False)), 60, order=2)
    shipped_gain = np.abs(game.creature_sound(False)).max() / np.abs(thock).max()
    for slot, label, src, longest in VOICES:
        voice = voice_clip(args.sources, slot, label, src, longest)
        gain = VOICE_VS_THOCK[slot in BIG] - (loudness(highpass(voice, 60, order=2)) - loudness(thock))
        save(f"{slot}--{label}", layer((highpass(voice, 60, order=2), VOICE_AT, gain)) * shipped_gain, out)


def alone(args) -> None:
    """Round 13 rule: no wood knock under anything. A creature with a voice plays the voice alone; one without plays a
    card placed on the table; artifacts, enchantments and planeswalkers play their accent alone. Writes the accents
    to OUT/alone and, for the Sound Bin, the gain each voice file needs to stand alone at arrival loudness."""
    import json
    out = os.path.join(args.out, "alone")
    os.makedirs(out, exist_ok=True)
    accents = {
        "artifact": ((game.sonniss("IMPACT METAL Short Slam_03", 0.13, 0.65, fade_out=0.25), 0.0, 0.0),),
        "enchantment": ((game.sonniss("Magic_Spells_Impact_Creation20", 0.06, 0.90, fade_out=0.4), 0.0, 0.0),),
        "planeswalker": (game.ks("impactBell_heavy_002", 0.0, 0.0),
                         (game.sonniss("Magic_Spells_Impact_Creation20", 0.06, 0.90, fade_out=0.4), 0.02, -6.0)),
    }
    for name, parts in accents.items():
        save(f"{name}-alone", match_loudness(highpass(layer(*parts), 60, order=2), ARRIVAL_ALONE[name], -1.0), out)
    for label, src, longest in ENCHANTMENTS:
        chime = cut(decode(os.path.join(args.sources, src)), longest)
        save(f"enchantment-alone--{label}", match_loudness(highpass(chime, 60, order=2), ARRIVAL_ALONE["enchantment"], -1.0), out)
    gains = {}
    shipped_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../apps/ios/MagicMobile/Resources/Audio")
    for kind in game.SONNISS_VOICES:
        if not os.path.exists(os.path.join(shipped_dir, f"creature-{kind}.m4a")):
            continue   # shipped as numbered variants since round 13
        x = decode(os.path.join(shipped_dir, f"creature-{kind}.m4a"))
        gains[f"now/creature-{kind}.m4a"] = round(float(ARRIVAL_ALONE["big" if kind == "dragon" else "small"] - loudness(x)), 1)
    layer_dir = os.path.join(args.out, "layers")
    for slot, label, _src, _longest in VOICES:
        f = next(os.path.join(layer_dir, f"{slot}--{label}{ext}") for ext in (".m4a", ".caf")
                 if os.path.exists(os.path.join(layer_dir, f"{slot}--{label}{ext}")))
        gains[f"a/r12-{slot}/{label}.m4a"] = round(float(ARRIVAL_ALONE["big" if slot in BIG else "small"] - loudness(decode(f))), 1)
    json.dump(gains, open(os.path.join(out, "alone-gains.json"), "w"), indent=1)
    print(f"{len(gains)} voice gains")


# Loudness for a sound that plays alone on arrival (the round 8 arrival levels).
ARRIVAL_ALONE = {"small": -21.0, "big": -20.0, "artifact": -22.0, "enchantment": -23.0, "planeswalker": -21.0}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sonniss", required=True)
    parser.add_argument("--kenney", required=True)
    parser.add_argument("--sources", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--layers", action="store_true", help="write landing bases and bare voices to OUT/layers")
    parser.add_argument("--alone", action="store_true", help="write lone accents and voice gains to OUT/alone")
    args = parser.parse_args()
    game.SONNISS, game.KENNEY = args.sonniss, args.kenney
    os.makedirs(args.out, exist_ok=True)
    if args.layers:
        layers(args)
        return
    if args.alone:
        alone(args)
        return
    thock = highpass(layer(*game.creature_parts(False)), 60, order=2)
    for slot, label, src, longest in VOICES:
        voice = voice_clip(args.sources, slot, label, src, longest)
        gain = VOICE_VS_THOCK[slot in BIG] - (loudness(highpass(voice, 60, order=2)) - loudness(thock))
        mix = layer(*game.creature_parts(False), (voice, VOICE_AT, gain))
        save(f"{slot}--{label}", match_loudness(highpass(mix, 60, order=2), -20.0, -1.0), args.out)
    for label, src, longest in ENCHANTMENTS:
        chime = cut(decode(os.path.join(args.sources, src)), longest)
        mix = layer(game.beech(-8.0), (chime, 0.01, -2.0))
        save(f"enchantment--{label}", match_loudness(highpass(mix, 60, order=2), -23.0, -1.0), args.out)
    for slot, label, src, longest, target in CARDS:
        clip = cut(decode(os.path.join(args.sources, src)), longest)
        save(f"{slot}--{label}", match_loudness(highpass(clip, 80, order=2), target, -1.0), args.out)


if __name__ == "__main__":
    main()
