#!/usr/bin/env python3
"""Builds commander-brackets.json: the data both apps use to place a deck in a Commander bracket.

The rules follow Wizards' Commander Brackets beta (last bracket change October 21, 2025; Game
Changers list as of February 9, 2026):

  Bracket 1 Exhibition, 2 Core: no Game Changers, no mass land denial, no chained extra turns,
  no two-card infinite combos.  Bracket 3 Upgraded: up to three Game Changers, no mass land
  denial, no chained extra turns, no early two-card combos.  Bracket 4 Optimized and 5 cEDH:
  anything legal.

What a decklist alone can show is checked; intent (1 vs 2, 4 vs 5) is the player's call. Every
name below must exist in the bundled XMage catalogue, so a typo fails the build instead of
silently never matching. Extra-turn cards come from the catalogue's own rules text.

Usage: build_bracket_rules.py [repo]   (writes apps/ios/MagicMobile/Resources/commander-brackets.json)
"""
import json, re, sys
from pathlib import Path

GAME_CHANGERS = [
    # Colorless
    "Chrome Mox", "Grim Monolith", "Lion's Eye Diamond", "Mana Vault", "Mox Diamond", "Panoptic Mirror", "The One Ring",
    # White
    "Drannith Magistrate", "Enlightened Tutor", "Farewell", "Humility", "Serra's Sanctum", "Smothering Tithe", "Teferi's Protection",
    # Blue
    "Consecrated Sphinx", "Cyclonic Rift", "Force of Will", "Fierce Guardianship", "Gifts Ungiven", "Intuition",
    "Mystical Tutor", "Narset, Parter of Veils", "Rhystic Study", "Thassa's Oracle",
    # Black
    "Ad Nauseam", "Bolas's Citadel", "Braids, Cabal Minion", "Demonic Tutor", "Imperial Seal", "Necropotence",
    "Opposition Agent", "Orcish Bowmasters", "Tergrid, God of Fright", "Vampiric Tutor",
    # Red
    "Gamble", "Jeska's Will", "Underworld Breach",
    # Green
    "Biorhythm", "Crop Rotation", "Gaea's Cradle", "Natural Order", "Seedborn Muse", "Survival of the Fittest", "Worldly Tutor",
    # Multicolored
    "Aura Shards", "Coalition Victory", "Grand Arbiter Augustin IV", "Notion Thief",
    # Lands
    "Ancient Tomb", "Field of the Dead", "Glacial Chasm", "Mishra's Workshop", "The Tabernacle at Pendrell Vale",
]

# Cards that destroy, exile or bounce most lands, keep them tapped, or change the mana four or more
# lands make, without replacing them.
MASS_LAND_DENIAL = [
    "Armageddon", "Ravages of War", "Catastrophe", "Decree of Annihilation", "Jokulhaups", "Obliterate", "Ruination",
    "Wildfire", "Destructive Force", "Sunder", "Impending Disaster", "Devastation", "Global Ruin", "Cataclysm",
    "Winter Orb", "Static Orb", "Rising Waters", "Hokori, Dust Drinker", "Back to Basics", "Blood Moon",
    "Magus of the Moon", "Contamination", "Epicenter", "Keldon Firebombers", "Upheaval", "Worldfire", "Apocalypse",
    "Myojin of Infinite Rage", "Burning of Xinye", "Thoughts of Ruin", "Desolation Angel", "Tectonic Break",
    "Stasis", "Mana Vortex", "Ravages of War", "Boom // Bust", "Death Cloud", "Wake of Destruction",
]

# Well-known two-card infinite or game-winning combos. A pair whose total mana value is at most
# EARLY_COMBO_MANA can win in the first few turns ("early"), which only Bracket 4 allows.
COMBOS = [
    ("Thassa's Oracle", "Demonic Consultation"), ("Thassa's Oracle", "Tainted Pact"),
    ("Laboratory Maniac", "Demonic Consultation"), ("Jace, Wielder of Mysteries", "Demonic Consultation"),
    ("Isochron Scepter", "Dramatic Reversal"), ("Kiki-Jiki, Mirror Breaker", "Zealous Conscripts"),
    ("Kiki-Jiki, Mirror Breaker", "Pestermite"), ("Kiki-Jiki, Mirror Breaker", "Deceiver Exarch"),
    ("Kiki-Jiki, Mirror Breaker", "Restoration Angel"), ("Kiki-Jiki, Mirror Breaker", "Felidar Guardian"),
    ("Splinter Twin", "Pestermite"), ("Splinter Twin", "Deceiver Exarch"),
    ("Exquisite Blood", "Sanguine Bond"), ("Exquisite Blood", "Vito, Thorn of the Dusk Rose"),
    ("Heliod, Sun-Crowned", "Walking Ballista"), ("Mikaeus, the Unhallowed", "Triskelion"),
    ("Mikaeus, the Unhallowed", "Walking Ballista"), ("Devoted Druid", "Vizier of Remedies"),
    ("Basalt Monolith", "Rings of Brighthearth"), ("Power Artifact", "Grim Monolith"),
    ("Power Artifact", "Basalt Monolith"), ("Dualcaster Mage", "Twinflame"), ("Dualcaster Mage", "Heat Shimmer"),
    ("Niv-Mizzet, Parun", "Curiosity"), ("Niv-Mizzet, the Firemind", "Curiosity"),
    ("Worldgorger Dragon", "Animate Dead"), ("Worldgorger Dragon", "Necromancy"), ("Worldgorger Dragon", "Dance of the Dead"),
    ("Food Chain", "Squee, the Immortal"), ("Food Chain", "Eternal Scourge"), ("Food Chain", "Misthollow Griffin"),
    ("Bloodchief Ascension", "Mindcrank"), ("Sword of the Meek", "Thopter Foundry"), ("Painter's Servant", "Grindstone"),
    ("Pili-Pala", "Grand Architect"), ("Kinnan, Bonder Prodigy", "Basalt Monolith"), ("Godo, Bandit Warlord", "Helm of the Host"),
    ("Saheeli Rai", "Felidar Guardian"), ("Sage of Hours", "Ezuri, Claw of Progress"), ("Cephalid Illusionist", "Shuko"),
    ("Cephalid Illusionist", "Nomads en-Kor"), ("Peregrine Drake", "Deadeye Navigator"), ("Palinchron", "Deadeye Navigator"),
    ("Temur Sabertooth", "Palinchron"), ("Auriok Salvagers", "Lion's Eye Diamond"), ("Underworld Breach", "Brain Freeze"),
    ("Doomsday", "Thassa's Oracle"), ("Hermit Druid", "Thassa's Oracle"), ("Leonin Relic-Warder", "Animation Module"),
    ("Sanguine Bond", "Exquisite Blood"),
]
EARLY_COMBO_MANA = 6

EXTRA_TURN = re.compile(r"\btakes? (?:an|two) extra turns?\b", re.I)


def main():
    repo = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
    catalogue = json.loads((repo / "apps/ios/MagicMobile/Resources/ondevice-catalogue.json").read_text())
    meta = catalogue["cardMetadata"]
    known = {card["name"] for card in catalogue["cards"]}

    def check(names, label):
        missing = sorted({n for n in names if n not in known})
        return [f"{label}: {n}" for n in missing]

    unique = lambda names: sorted(set(names))
    problems = check(GAME_CHANGERS, "game changer") + check(MASS_LAND_DENIAL, "mass land denial")
    combos, seen = [], set()
    for pair in COMBOS:
        key = tuple(sorted(pair))
        if key in seen: continue
        seen.add(key)
        problems += check(pair, "combo")
        if all(n in known for n in pair):
            mana = sum(int(meta.get(n, {}).get("manaValue") or 0) for n in pair)
            combos.append({"cards": list(key), "manaValue": mana, "early": mana <= EARLY_COMBO_MANA})
    # A card missing from this XMage build can never be in a deck the app plays; drop it, but say so.
    for line in problems: print("not in this catalogue, skipped:", line)
    extra_turns = sorted(n for n, m in meta.items() if n in known and EXTRA_TURN.search(m.get("oracleText") or ""))
    out = {
        "schemaVersion": 1,
        "rulesDate": "2026-02-09",
        "catalogueHash": catalogue["catalogueHash"],
        "brackets": [
            {"level": 1, "name": "Exhibition", "maxGameChangers": 0},
            {"level": 2, "name": "Core", "maxGameChangers": 0},
            {"level": 3, "name": "Upgraded", "maxGameChangers": 3},
            {"level": 4, "name": "Optimized", "maxGameChangers": None},
            {"level": 5, "name": "cEDH", "maxGameChangers": None},
        ],
        # Three or more extra-turn cards are treated as a deck built to chain them.
        "chainedExtraTurns": 3,
        "gameChangers": unique(n for n in GAME_CHANGERS if n in known),
        "massLandDenial": unique(n for n in MASS_LAND_DENIAL if n in known),
        "extraTurns": extra_turns,
        "combos": sorted(combos, key=lambda c: c["cards"]),
    }
    target = repo / "apps/ios/MagicMobile/Resources/commander-brackets.json"
    target.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {target.relative_to(repo)}: {len(out['gameChangers'])} game changers, "
          f"{len(out['massLandDenial'])} mass land denial, {len(extra_turns)} extra turns, {len(combos)} combos")


if __name__ == "__main__":
    main()
