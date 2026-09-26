#!/usr/bin/env python3
"""SPIKE ONLY: resolve the bundled iOS precon lists (PreconCatalog.swift) into engine deck JSON.

Printing choice reuses packages/ondevice-engine/scripts/resolve_deck.py (read-only import),
so the decks match what the JVM harness would build from the same text lists.
"""
import argparse, json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ondevice-engine/scripts'))
from resolve_deck import resolve  # noqa: E402

DECK = re.compile(r'id:\s*"([^"]+)".*?commander:\s*"([^"]+)".*?rawList:\s*"""\n(.*?)"""', re.S)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--catalogue', type=Path, required=True)
    p.add_argument('--swift', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    rows = [json.loads(line) for line in a.catalogue.read_text().splitlines() if line.strip()]
    a.output.mkdir(parents=True, exist_ok=True)
    found = DECK.findall(a.swift.read_text())
    if not found:
        raise SystemExit('No precons found in ' + str(a.swift))
    for deck_id, commander, raw in found:
        lines = [line.strip() for line in raw.splitlines() if line.strip()]
        # PreconDeck.deckList drops the commander from the main list and adds it once.
        main = [line for line in lines if line.split(' ', 1)[1] != commander]
        deck = resolve('\n'.join(['1 ' + commander] + main), rows, [commander], [])
        deck['name'] = deck_id
        (a.output / (deck_id + '.json')).write_text(json.dumps(deck, ensure_ascii=False, indent=2) + '\n')
    print(f'Resolved {len(found)} precons into {a.output}')


if __name__ == '__main__':
    main()
