#!/usr/bin/env python3
"""Assemble the Deck Helper test-bed page (docs/DECK_HELPER.md).

  python3 scripts/deck-helper/build.py [--out build_output/deck-helper] [--bulk oracle-cards.jsonl] [--edhrec-cache DIR]

Writes <out>/deck-helper.html (also as <out>/index.html for a static server) from deck-helper.template.html,
engine.js (parsing, card data, analysis, cuts, levers) and ui.js (the screens). With --bulk it rebuilds <out>/cards/*.json
(one shard per first letter, every Commander-legal card classified by classifier.js, plus lands.json); with
--edhrec-cache, <out>/edhrec/*.json from fetch-edhrec.py's cache.

Serve it locally for card images (the artifact sandbox blocks outside images):
  python3 -m http.server 8765 --directory build_output/deck-helper      # or the "deck-helper" entry in .claude/launch.json
The bulk file is Scryfall's "Oracle Cards" (https://api.scryfall.com/bulk-data/oracle-cards, `jsonl_download_uri`,
gunzipped); it, the EDHREC cache and the built data stay out of the repo. The page embeds the bracket rules the apps ship
and Deck Power's weights, so retuning the Power estimate is a data change here as it is in scripts/ranked/deck_power.py.
"""
from __future__ import annotations
import argparse, json, re, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', type=Path, default=REPO / 'build_output/deck-helper')
    parser.add_argument('--bulk', type=Path, help="Scryfall's oracle-cards.jsonl (or .json); rebuilds <out>/cards")
    parser.add_argument('--weights', type=Path, default=REPO / 'scripts/ranked/deck-power-weights.json')
    parser.add_argument('--brackets', type=Path, default=REPO / 'apps/ios/MagicMobile/Resources/commander-brackets.json')
    parser.add_argument('--edhrec-cache', type=Path, help='fetch-edhrec.py cache; rebuilds <out>/edhrec from it')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    cards = args.out / 'cards'
    if args.bulk:
        subprocess.run(['node', '--max-old-space-size=768', str(HERE / 'build-cards.js'), str(args.bulk), str(cards)], check=True)
    if args.edhrec_cache:
        subprocess.run([sys.executable, str(HERE / 'fetch-edhrec.py'), 'build', '--cache', str(args.edhrec_cache), '--out', str(args.out / 'edhrec')], check=True)
    index_path = cards / 'index.json'
    if not index_path.exists():
        sys.exit(f'{index_path} is missing: pass --bulk once to build the card shards')
    index = json.loads(index_path.read_text())
    brackets = json.loads(args.brackets.read_text())
    rules = {k: brackets[k] for k in ('rulesDate', 'brackets', 'chainedExtraTurns', 'gameChangers', 'massLandDenial', 'extraTurns', 'combos')}
    weights = json.loads(args.weights.read_text())
    power = {k: weights[k] for k in ('weights', 'norms', 'penalties', 'ladder', 'scale')}
    samples = {'krenko': (HERE / 'sample-krenko-core.txt').read_text(), 'edgar': (HERE / 'sample-edgar-core.txt').read_text()}
    js = lambda o: json.dumps(o, ensure_ascii=False).replace('</', '<\\/')
    engine = (HERE / 'engine.js').read_text()
    for key, value in (('__RULES__', rules), ('__POWER__', power), ('__SAMPLES__', samples), ('__FLAGS__', index['flags']), ('__TAGS__', index['tags'])):
        if key not in engine:
            sys.exit(f'{key} is missing from engine.js')
        engine = engine.replace(key, js(value))
    script = engine + '\n' + (HERE / 'ui.js').read_text()
    html = (HERE / 'deck-helper.template.html').read_text()
    if '__SCRIPT__' not in html:
        sys.exit('__SCRIPT__ is missing from the template')
    html = html.replace('__SCRIPT__', script)
    (args.out / 'deck-helper.check.js').write_text(script)
    subprocess.run(['node', '--check', str(args.out / 'deck-helper.check.js')], check=True)
    (args.out / 'deck-helper.html').write_text(html)
    # A static server wants index.html with a real document skeleton (the artifact tool adds its own).
    (args.out / 'index.html').write_text('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body style="margin:0">' + html + '</body></html>')
    print(f"wrote {args.out / 'deck-helper.html'} ({len(html) // 1000} KB) with {index['cards']} cards in {len(index['shards'])} shards")


if __name__ == '__main__':
    main()
