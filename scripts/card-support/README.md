# Card support page

A private claude.ai page that shows which cards and commanders XMage plays compared with what MagicMobile ships,
with card pictures. `.github/workflows/magicmobile-card-support.yml` rebuilds its data every Monday.

- `build_card_support.py` reads XMage's set files from two sparse, blob-less clones of magefree/mage (latest
  master and the commit pinned in `packages/ondevice-engine/upstream.lock.json`) and compares them with
  `apps/ios/MagicMobile/Resources/ondevice-catalogue.json`. It writes `data.json`. Read-only on XMage.
- `make_sprites.py` adds Scryfall's small card pictures for the new cards and every commander, 100 per JPEG sheet,
  and records where each card sits in `data.json`. The page can't load pictures from other sites, so they ship
  with it.
- `page/index.html` is the page. It reads `data.json` and `img/sheet-N.jpg`.

The workflow force-pushes the output (`index.html`, `data.json`, `img/`) as a single commit to the
`card-support-data` branch. A Claude routine fetches that branch and republishes the page at the same link.

```
python3 scripts/card-support/build_card_support.py --repo . --workdir /tmp/xmage-cards --out out
python3 scripts/card-support/make_sprites.py --data out/data.json --out out/img
python3 -m unittest discover -s scripts/card-support -p 'test_*.py'
```
