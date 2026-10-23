/**
 * Copies Scryfall's card symbols ({T}, {W}, {2/B}, {E}…) into apps/web/public/symbols/, so the page draws them from its
 * own origin: a work or school filter that blocks svgs.scryfall.io then can't turn them into letters (2026-10-23), and
 * no symbol waits on a second server. File names match manaSymbolURL: the symbol without braces or slashes, upper case.
 *
 *   node apps/web/scripts/fetch_symbols.mjs        # run again when Scryfall adds symbols; commit the result
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const out = join(import.meta.dirname, "..", "public", "symbols");
mkdirSync(out, { recursive: true });
const headers = { "User-Agent": "MagicMobile/0.1 (symbol cache)", Accept: "application/json" };
const listing = await (await fetch("https://api.scryfall.com/symbology", { headers })).json();
let written = 0;
const names = [];
for (const entry of listing.data) {
  const symbol = String(entry.symbol).replace(/^\{|\}$/g, "");
  if (!entry.svg_uri) continue;
  const name = symbol.toUpperCase().replace(/\//g, "");
  const svg = await (await fetch(entry.svg_uri, { headers: { "User-Agent": headers["User-Agent"] } })).text();
  if (!svg.includes("<svg")) throw new Error(`Not an SVG for {${symbol}}`);
  writeFileSync(join(out, `${name}.svg`), svg);
  names.push(name);
  written += 1;
  await new Promise((resolve) => setTimeout(resolve, 60)); // Scryfall asks for 50–100 ms between requests
}
writeFileSync(join(out, "index.json"), JSON.stringify(names.sort()) + "\n");
console.log(`${written} symbols in ${out}`);
