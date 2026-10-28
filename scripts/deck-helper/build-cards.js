// node build-cards.js <oracle-cards.jsonl> <out dir>: one JSON shard per first letter, records as classifier.js emits them.
// JSONL is read one line at a time (a few MB of memory instead of the whole 200 MB file); a .json array still works.
'use strict';
const fs = require('fs'), path = require('path'), readline = require('readline');
const { classify, FLAGS, TAGS } = require('./classifier');
const [,, bulkPath, outDir] = process.argv;
if (!bulkPath || !outDir) { console.error('usage: build-cards.js <oracle-cards.jsonl> <out dir>'); process.exit(1); }
const fold = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

async function* cardsOf(file) {
  if (file.endsWith('.json')) { yield* JSON.parse(fs.readFileSync(file, 'utf8')); return; }
  for await (const line of readline.createInterface({ input: fs.createReadStream(file), crlfDelay: Infinity })) if (line.trim()) yield JSON.parse(line);
}

(async () => {
  const shards = {};
  let kept = 0, skipped = 0;
  for await (const c of cardsOf(bulkPath)) {
    if (c.lang && c.lang !== 'en') { skipped++; continue; }
    const rec = classify(c);
    if (!rec) { skipped++; continue; }
    const frontName = fold(c.name.split(' // ')[0]);
    const letter = /^[a-z]/.test(frontName) ? frontName[0] : '0';
    (shards[letter] = shards[letter] || {})[frontName] = rec;
    kept++;
  }
  fs.mkdirSync(outDir, { recursive: true });
  // lands.json: every multicolor nonbasic land plus the popular utility lands, for the Lands screen's suggestions.
  const LAND = FLAGS.indexOf('land');
  const lands = [];
  for (const map of Object.values(shards)) for (const r of Object.values(map)) {
    if (!(r[9] & (1 << LAND))) continue;
    if (/^Basic Land/.test(r[2])) continue;
    if (r[4].length >= 2 || (r[7] && r[7] <= 4000)) lands.push([r[0], r[4], r[6], r[12], r[13], r[7]]);
  }
  fs.writeFileSync(path.join(outDir, 'lands.json'), JSON.stringify(lands));
  let total = 0;
  for (const [letter, map] of Object.entries(shards)) {
    const s = JSON.stringify(map);
    fs.writeFileSync(path.join(outDir, `${letter}.json`), s);
    total += s.length;
  }
  fs.writeFileSync(path.join(outDir, 'index.json'), JSON.stringify({ built: new Date().toISOString().slice(0, 10), source: 'Scryfall bulk oracle-cards', cards: kept, flags: FLAGS, tags: TAGS, shards: Object.keys(shards).sort() }));
  console.log(`kept ${kept}, skipped ${skipped}, ${Object.keys(shards).length} shards, ${(total / 1e6).toFixed(1)} MB`);
})();
