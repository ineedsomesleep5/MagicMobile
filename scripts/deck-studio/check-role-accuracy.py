#!/usr/bin/env python3
"""Measure role coverage of the shipped catalogue against hand-labelled Commander staples.

This is the accuracy bar for Deck Studio's "What your cards do" panel. It reads the
catalogue the app actually ships and checks the curated roles baked into it, so a
regression in the tag fetch, the role mapping or the exporter shows up here rather than
on a phone.

Labels below are the roles a Commander player would expect to see for that card. They
are a deliberate floor, not an exhaustive description: extra roles are reported but do
not fail, because a card can legitimately do more than one thing.

Run: python3 check-role-accuracy.py [--min-recall 0.95]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

CATALOGUE = Path(__file__).resolve().parents[2] / 'apps/ios/MagicMobile/Resources/ondevice-catalogue.json'

# card -> roles a player expects Deck Studio to report for it
STAPLES: dict[str, set[str]] = {
    # Ramp
    'Sol Ring': {'ramp'}, 'Arcane Signet': {'ramp'}, 'Fellwar Stone': {'ramp'},
    'Cultivate': {'ramp'}, "Kodama's Reach": {'ramp'}, 'Rampant Growth': {'ramp'},
    'Farseek': {'ramp'}, "Nature's Lore": {'ramp'}, 'Three Visits': {'ramp'},
    'Birds of Paradise': {'ramp'}, 'Llanowar Elves': {'ramp'}, 'Mana Crypt': {'ramp'},
    'Talisman of Dominance': {'ramp'}, 'Chrome Mox': {'ramp'},
    # Draw / card flow
    'Rhystic Study': {'cardFlow'}, 'Phyrexian Arena': {'cardFlow'}, 'Sign in Blood': {'cardFlow'},
    "Night's Whisper": {'cardFlow'}, 'Brainstorm': {'cardFlow'}, 'Ponder': {'cardFlow'},
    'Preordain': {'cardFlow'}, 'Harmonize': {'cardFlow'}, 'Sylvan Library': {'cardFlow'},
    'Mystic Remora': {'cardFlow'}, 'Necropotence': {'cardFlow'}, 'Fact or Fiction': {'cardFlow'},
    # Targeted interaction (removal and countermagic)
    'Swords to Plowshares': {'interaction'}, 'Path to Exile': {'interaction'},
    'Beast Within': {'interaction'}, 'Chaos Warp': {'interaction'},
    'Generous Gift': {'interaction'}, 'Counterspell': {'interaction'},
    'Swan Song': {'interaction'}, 'Force of Will': {'interaction'},
    "Nature's Claim": {'interaction'}, 'Krosan Grip': {'interaction'},
    'Anguished Unmaking': {'interaction'}, "Assassin's Trophy": {'interaction'},
    # Board wipes
    'Wrath of God': {'boardWipe'}, 'Damnation': {'boardWipe'}, 'Blasphemous Act': {'boardWipe'},
    'Toxic Deluge': {'boardWipe'}, 'Cyclonic Rift': {'boardWipe'}, 'Austere Command': {'boardWipe'},
    'Farewell': {'boardWipe'}, 'Languish': {'boardWipe'}, 'Supreme Verdict': {'boardWipe'},
    # Protection
    'Heroic Intervention': {'protection'}, "Teferi's Protection": {'protection'},
    'Boros Charm': {'protection'}, 'Flawless Maneuver': {'protection'},
    'Lightning Greaves': {'protection'}, 'Swiftfoot Boots': {'protection'},
    'Veil of Summer': {'protection'},
    # Graveyard interaction
    'Bojuka Bog': {'graveyardHate'}, 'Scavenging Ooze': {'graveyardHate'},
    'Relic of Progenitus': {'graveyardHate'}, 'Rest in Peace': {'graveyardHate'},
    'Leyline of the Void': {'graveyardHate'}, 'Soul-Guide Lantern': {'graveyardHate'},
    # Recursion
    'Eternal Witness': {'recursion'}, 'Regrowth': {'recursion'}, 'Sun Titan': {'recursion'},
    'Animate Dead': {'recursion'}, 'Reanimate': {'recursion'}, 'Gravecrawler': {'recursion'},
    # Tutors
    'Demonic Tutor': {'tutor'}, 'Vampiric Tutor': {'tutor'}, 'Enlightened Tutor': {'tutor'},
    'Mystical Tutor': {'tutor'}, 'Worldly Tutor': {'tutor'}, 'Gamble': {'tutor'},
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--min-recall', type=float, default=0.95)
    parser.add_argument('--catalogue', type=Path, default=CATALOGUE)
    args = parser.parse_args()

    metadata = json.loads(args.catalogue.read_bytes())['cardMetadata']
    missing_from_catalogue, expected, found = [], 0, 0
    misses: list[str] = []
    for name, wanted in sorted(STAPLES.items()):
        entry = metadata.get(name)
        if entry is None:
            missing_from_catalogue.append(name)
            continue
        roles = set(entry.get('roles', []))
        expected += len(wanted)
        found += len(wanted & roles)
        if wanted - roles:
            misses.append(f'  {name}: expected {sorted(wanted)}, got {sorted(roles) or "no roles"}')

    if missing_from_catalogue:
        print(f'Not in the shipped catalogue ({len(missing_from_catalogue)}), skipped:', file=sys.stderr)
        for name in missing_from_catalogue:
            print(f'  {name}', file=sys.stderr)
    if misses:
        print(f'Missed labels ({len(misses)}):', file=sys.stderr)
        print('\n'.join(misses), file=sys.stderr)

    recall = found / expected if expected else 0.0
    checked = len(STAPLES) - len(missing_from_catalogue)
    print(f'Role recall on hand-labelled staples: {found}/{expected} = {recall:.1%} '
          f'across {checked} cards (bar {args.min_recall:.0%}).')
    if recall < args.min_recall:
        print('FAIL: curated role coverage regressed below the bar.', file=sys.stderr)
        return 1
    print('PASS: curated role coverage meets the bar. Label set is a floor, not exhaustive '
          'card evaluation or phone acceptance.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
