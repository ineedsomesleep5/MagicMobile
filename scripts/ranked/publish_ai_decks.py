#!/usr/bin/env python3
"""Publishes ai-decks.json to phones without an app build (docs/SERVER_CONTROLS.md).

  publish_ai_decks.py           checks the file
  publish_ai_decks.py --upload  raises its revision, puts it on a GitHub release, and prints the SQL that offers it

Commit the raised revision: the next app build ships the same file, and a phone then drops its download. The web bundles
the file, so it needs a redeploy.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RESOURCES = REPO / 'apps/ios/MagicMobile/Resources'
GITHUB = 'ineedsomesleep5/MagicMobile'


def problems(file: dict, main: dict, cards: set[str], catalogue: str) -> list[str]:
    """What stops a phone from using this file, or a game from loading a deck. The apps check the same shape again."""
    found = []
    if file.get('catalogueHash') != catalogue:
        found.append(f"catalogueHash {file.get('catalogueHash')} is not this catalogue, {catalogue}")
    ids = [deck['id'] for deck in file['decks']]
    if len(ids) != len(set(ids)):
        found.append('a deck ID repeats')
    found += [f'{deck} is gone: saved games name it (drop its Power to retire it)' for deck in sorted({d['id'] for d in main['decks']} - set(ids))]
    power = file.get('power') or {}
    if len(power.get('rankedTiers', [])) != 6 or len(power.get('quickMatch', {})) != 3:
        found.append('the power block is incomplete')
    for deck in file['decks']:
        entries = deck['entries']
        if not deck['id'].startswith('ai-') or sum(e['section'] == 'commander' for e in entries) != 1 or sum(e['quantity'] for e in entries) != 100:
            found.append(f"{deck['id']} is not a 100-card commander deck")
        found += [f"{deck['id']}: {e['name']} is not in the catalogue" for e in entries if e['name'] not in cards]
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--upload', action='store_true')
    args = parser.parse_args()
    path = RESOURCES / 'ai-decks.json'
    file = json.loads(path.read_text())
    catalogue = json.loads((RESOURCES / 'ondevice-catalogue.json').read_text())
    aliases = catalogue.get('nameAliases') or {}
    cards = {card['name'] for card in catalogue['cards']} | set(aliases) | {name.split(' // ')[0] for name in (card['name'] for card in catalogue['cards'])}
    main_file = json.loads(subprocess.check_output(['git', 'show', 'origin/main:apps/ios/MagicMobile/Resources/ai-decks.json'], cwd=REPO))
    found = problems(file, main_file, cards, catalogue['catalogueHash'])
    if found:
        print('\n'.join(found), file=sys.stderr)
        return 1
    if not args.upload:
        print(f"{len(file['decks'])} decks are fine at revision {file['revision']}")
        return 0
    file['revision'] += 1
    path.write_text(json.dumps(file, indent=1, ensure_ascii=False) + '\n')
    tag = f"ai-decks-{file['revision']}"
    subprocess.check_call(['gh', 'release', 'create', tag, str(path), '-R', GITHUB, '--latest=false', '--title', f"AI decks {file['revision']}",
                           '--notes', 'AI deck file for the apps (docs/SERVER_CONTROLS.md).'])
    offer = {file['catalogueHash']: {'revision': file['revision'], 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                     'url': f'https://github.com/{GITHUB}/releases/download/{tag}/ai-decks.json'}}
    print(f"update public.app_settings set value = '{json.dumps(offer)}', updated_at = now() where key = 'ai_decks';")
    return 0


if __name__ == '__main__':
    sys.exit(main())
