// ---------- Screens (the engine above does the reading; this draws it) ----------
const BASIC_OF = { W: 'Plains', U: 'Island', B: 'Swamp', R: 'Mountain', G: 'Forest' };
const UTILITY_FALLBACK = [['Command Tower', 2], ['Exotic Orchard', 2], ['Path of Ancestry', 1], ["Rogue's Passage", 0], ['Reliquary Tower', 0], ['War Room', 0], ['Bojuka Bog', 0], ['Castle Embereth', 0], ['Castle Ardenvale', 0], ['Castle Vantress', 0], ['Castle Locthwain', 0], ['Castle Garenbrig', 0], ['Den of the Bugbear', 0], ['Hall of Storm Giants', 0], ['Lair of the Hydra', 0], ['Hive of the Eye Tyrant', 0], ['Cave of the Frost Dragon', 0], ['Nykthos, Shrine to Nyx', 0], ['Cavern of Souls', 1], ['Unclaimed Territory', 1], ['Secluded Courtyard', 1], ['Three Tree City', 1]];
const TIER_WORD = { Bronze: 'Bronze', Silver: 'Silver', Gold: 'Gold', Platinum: 'Platinum', Diamond: 'Diamond', Mythic: 'Mythic' };

let current = null;                       // { deck, cards, commanderCard, unknown, edh, analysis }
let overrides = storage.get('dh-overrides-v1', {});
let decisions = { cut: new Set(), keep: new Set(), add: new Set() };
let recordCache = new Map();              // name -> card record, for cards shown outside the deck (adds, lands)

// ----- small helpers -----
const front = name => name.split(' // ')[0];
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
const onErr = `onerror="this.closest('.cardc').classList.add('noimg')"`;
function tile(card, { badge, badgeClass = '', pill, why = [], edh = '', acts = '', state = '', size = 'small', name } = {}) {
  const label = name || (card ? front(card.name) : '');
  return `<div class="cardc ${state}" data-card="${esc(label)}">
    <div class="pic" data-zoom="${esc(label)}">${card && card.id ? `<img loading="lazy" src="${imgUrl(card, size)}" alt="${esc(label)}" ${onErr}>` : ''}<div class="ph">${esc(label)}</div>
      ${badge != null ? `<span class="badge ${badgeClass}">${badge}</span>` : ''}${pill ? `<span class="pill">${pill}</span>` : ''}</div>
    <div class="name">${esc(label)}</div>${why.length ? `<div class="why">${why.map(esc).join(' · ')}</div>` : ''}${edh ? `<div class="why edh">${esc(edh)}</div>` : ''}${acts ? `<div class="acts">${acts}</div>` : ''}
  </div>`;
}
const cutKeepButtons = name => `<button class="btn tiny cut ${decisions.cut.has(name) ? 'on' : ''}" data-act="cut" data-name="${esc(name)}">${decisions.cut.has(name) ? 'Cutting' : 'Cut'}</button><button class="btn tiny keep ${decisions.keep.has(name) ? 'on' : ''}" data-act="keep" data-name="${esc(name)}">${decisions.keep.has(name) ? 'Keeping' : 'Keep'}</button>`;
const addButton = name => `<button class="btn tiny add ${decisions.add.has(name) ? 'on' : ''}" data-act="add" data-name="${esc(name)}">${decisions.add.has(name) ? 'Adding' : 'Add'}</button>`;
const stateOf = name => decisions.cut.has(name) ? 'is-cut' : decisions.keep.has(name) ? 'is-keep' : decisions.add.has(name) ? 'is-add' : '';
const roleChips = (tags, f) => {
  let s = '';
  for (const r of ROLES) if (tags.has(r)) s += `<span class="chip role">${ROLE_LABEL[r]}</span>`;
  if (f.gc) s += '<span class="chip gc">Game Changer</span>';
  if (f.mdfc) s += '<span class="chip">MDFC</span>';
  if (f.land && f.tapped) s += '<span class="chip warn">tapped</span>';
  if (f.evasive) s += '<span class="chip">evasive</span>';
  if (f.fastMana) s += '<span class="chip">fast mana</span>';
  if (f.multiplayer) s += '<span class="chip warn">multiplayer</span>';
  if (f.extraTurn) s += '<span class="chip warn">extra turn</span>';
  if (f.mld) s += '<span class="chip warn">mass land denial</span>';
  return s;
};
async function records(names) {
  const need = names.filter(n => !recordCache.has(n));
  if (need.length) { try { const { result } = await loadCards(need); for (const [k, v] of result) recordCache.set(k, v); } catch {} }
  return name => recordCache.get(name) || (current && current.cards.get(name));
}
function decisionsKey() { return 'dh-decisions:' + (current && current.commanderCard ? keyOf(current.commanderCard.name) : 'none'); }
function saveDecisions() { storage.set(decisionsKey(), { cut: [...decisions.cut], keep: [...decisions.keep], add: [...decisions.add] }); }
function loadDecisions() { const d = storage.get(decisionsKey(), null); decisions = { cut: new Set(d ? d.cut : []), keep: new Set(d ? d.keep : []), add: new Set(d ? d.add : []) }; }

// ----- the whole render -----
function render(a) {
  const c = a.counts, mode = $('mode').value, T = TEMPLATES[mode];
  const commanderCard = current.commanderCard, deck = current.deck;
  const total = deck.entries.reduce((s, e) => s + e.qty, 0) + (commanderCard ? 1 : 0);
  const ci = commanderCard ? commanderCard.ci : [...new Set(a.rows.flatMap(r => r.card.ci))];
  const cutsWanted = parseInt($('cutCount').value, 10) || (total > 100 ? total - 100 : 5);
  $('results').hidden = false; $('tabs').hidden = false; $('deckbar').hidden = false;

  // Deck bar
  const band = bandOf(a.table.power), tier = tierOf(a.ai.power);
  if (commanderCard && commanderCard.id) { $('deckArt').src = imgUrl(commanderCard, 'art_crop'); $('deckArt').hidden = false; } else $('deckArt').hidden = true;
  $('deckName').textContent = commanderCard ? commanderCard.name : 'No commander found';
  $('deckRead').textContent = `${total} cards · Bracket ${a.bracket.minimum} ${BRACKET_NAMES[a.bracket.minimum]} · Power ${fmt(a.table.power)}${a.edhFit ? ` · ${a.edhFit.avgInc}% typical ${a.edh.short}` : ''}`;
  updateDecisionNote(total);

  // Hero
  if (commanderCard && commanderCard.id) { $('heroArt').src = imgUrl(commanderCard, 'normal'); $('heroArt').hidden = false; } else $('heroArt').hidden = true;
  const typical = a.edhFit ? (a.edhFit.avgInc >= 40 ? `built the way most ${a.edh.short} decks are` : a.edhFit.avgInc >= 20 ? `half typical ${a.edh.short}, half your own` : `a brew: most of it is not what ${a.edh.short} decks usually run`) : '';
  $('headline').textContent = `${commanderCard ? front(commanderCard.name) : 'This deck'} reads as ${/^[AEIOU]/.test(band) ? 'an' : 'a'} ${band} deck${typical ? ', ' + typical : ''}.`;
  const shape = [];
  if (c.ramp < T.ramp[0]) shape.push('light on ramp'); if (c.draw < T.draw[0]) shape.push('light on card draw'); if (c.targeted < T.targeted[0]) shape.push('light on removal');
  if (c.lands < T.lands[0]) shape.push('short on lands'); if (c.lands && c.tapped / c.lands > 0.25) shape.push('slow lands'); if (a.curve[6] + a.curve[7] > 6) shape.push('top-heavy');
  $('headlineSub').textContent = shape.length ? `It is ${shape.join(', ')}. The fixes are below.` : 'The counts look healthy; the work is in the card choices.';
  $('numbers').innerHTML = [
    [`${a.bracket.minimum}`, `Bracket · ${BRACKET_NAMES[a.bracket.minimum]}`, a.bracket.gcs.length ? plural(a.bracket.gcs.length, 'Game Changer') : 'no Game Changers' + (a.bracket.combos.length ? `, ${plural(a.bracket.combos.length, 'combo')}` : '')],
    [fmt(a.table.power), 'Power (1–10)', `${band} range, by the card counts`],
    [tier, 'App AI match', `the Ranked tier whose AI decks this resembles`],
    [fmt(c.manaValue, 2), 'Average mana value', `${fmt(c.effectiveManaValue, 2)} once cheat-outs count`],
    ...(a.edhFit ? [[`${a.edhFit.avgInc}%`, `Typical ${esc(a.edh.short)}`, `average inclusion across ${a.edh.decks.toLocaleString()} decks`]] : []),
  ].map(([v, k, cap]) => `<div class="num"><div class="big">${v}</div><div class="eyebrow" style="margin:6px 0 0">${k}</div><div class="cap">${cap}</div></div>`).join('');

  // Do this first
  const todo = [];
  if (total > 100) todo.push([`Cut ${total - 100} to reach 100`, 'The Cuts screen ranks the candidates.', 'cuts']);
  const gap = (n, [lo], word, tab) => { if (n < lo) todo.push([`Add ${plural(lo - n, word)}`, `You run ${n}; the template wants ${lo}+.`, tab]); };
  gap(c.ramp, T.ramp, 'ramp piece', 'adds'); gap(c.draw, T.draw, 'card-draw spell', 'adds'); gap(c.targeted, T.targeted, 'removal spell', 'adds');
  if (c.lands && c.tapped / c.lands > 0.25) todo.push([`Swap ${Math.round(c.tapped)} tapped lands`, 'Over a quarter of your lands enter tapped.', 'lands']);
  if (c.lands < T.lands[0]) todo.push([`Add ${T.lands[0] - c.lands} lands`, `${c.lands} is under the ${T.lands[0]}–${T.lands[1]} range${a.edh ? `; ${a.edh.short} decks average ${a.edh.counts.land}` : ''}.`, 'lands']);
  if (a.curve[6] + a.curve[7] > 6) todo.push([`Trim the top end`, `${a.curve[6] + a.curve[7]} cards cost 6 or more; most decks carry three or four.`, 'cuts']);
  if (c.ramp > T.ramp[1] + 2) todo.push([`Trim ramp to ${T.ramp[1]}`, `${c.ramp} ramp pieces is more than the deck can use.`, 'cuts']);
  if (!todo.length) todo.push(['Play it and watch the engines', 'Nothing structural is missing. The Cuts screen still shows the weakest if-then cards.', 'cuts']);
  $('todo').innerHTML = todo.slice(0, 5).map(([t, s, tab], i) => `<div class="item"><div class="k">${i + 1}</div><div><b>${t}</b><div class="note">${s}</div></div><button class="btn small" data-goto="${tab}">Open</button></div>`).join('');

  // Shape
  $('templateNote').textContent = `Against the Command Zone template (38 lands, 10 ramp, 12 card advantage, 12 targeted disruption, 6 mass disruption, 30 plan cards; a card may count twice)${mode === 'duel' ? ', shifted for one opponent: spot removal matters more, sweepers less' : ''}.${current.unknown.length ? ` Not recognised: ${current.unknown.join(', ')}.` : ''}`;
  const bar = (label, n, [lo, hi], noteText) => { const max = Math.max(hi * 1.5, n + 1); const cls = n < lo ? 'under' : n > hi ? 'over' : 'ok'; const word = n < lo ? `add ${lo - n}` : n > hi ? `${n - hi} over` : 'good'; return `<div class="bar"><div>${label}${noteText ? `<div class="note">${noteText}</div>` : ''}</div><div class="track"><div class="fill ${cls}" style="width:${Math.min(100, 100 * n / max)}%"></div><div class="target" style="left:${100 * lo / max}%"></div><div class="target" style="left:${100 * hi / max}%"></div></div><div class="num2">${n} · ${word}</div></div>`; };
  $('templateBars').innerHTML = [bar('Lands', c.lands, T.lands, c.mdfc ? `${c.mdfc} MDFC counted` : ''), bar('Ramp', c.ramp, T.ramp, `${c.cheapRamp} cheap rocks and spells · ${c.creatureRamp} dorks`), bar('Card draw', c.draw, T.draw), bar('Removal', c.targeted, T.targeted, `${c.counters} counterspells · ${c.instant} at instant speed`), bar('Board wipes', c.mass, T.mass), bar('Plan cards', c.plan, T.plan, `${c.themed} on theme · ${c.finishers} finishers`)].join('');

  // Curve and colors
  const peak = Math.max(1, ...a.curve);
  $('curve').innerHTML = a.curve.map((n, i) => `<div class="col"><div class="stick" style="height:${Math.round(100 * n / peak)}%"></div><div>${n}</div><div>${i === 7 ? '7+' : i}</div></div>`).join('');
  const sixPlus = a.curve[6] + a.curve[7];
  $('curveNote').textContent = `Nonland cards by mana value. ${sixPlus} cost 6 or more${sixPlus > 6 ? ': more than most decks can cast.' : '.'} ${c.cheatShare > 0.2 ? 'The deck cheats big things out, so it plays faster than the curve looks.' : ''}`;
  const pipTotal = Object.values(a.pipNeed).reduce((x, y) => x + y, 0) || 1;
  const colorNames = { W: 'White', U: 'Blue', B: 'Black', R: 'Red', G: 'Green' };
  $('pips').innerHTML = Object.entries(a.pipNeed).filter(([k, v]) => v > 0 || ci.includes(k)).map(([k, v]) => { const need = v / pipTotal, have = a.sources[k], want = Math.round(need * c.lands); return `<div class="pip"><span class="eyebrow">${colorNames[k]}</span><b>${have}</b> sources<div class="note">${Math.round(need * 100)}% of pips · about ${want} wanted${have < want - 2 ? ' · short' : ''}</div></div>`; }).join('') || '<p class="note">No colored pips.</p>';
  $('manaNote').textContent = `Colored pips against the lands and cheap rocks that make each color. ${Math.round(c.tapped)} of ${c.lands} lands enter tapped.`;

  // Levers (plain)
  const lv = levers(a, mode, parseFloat($('cmdStrength').value) || 0.5).map(l => ({ ...l, d: l.dTable })).filter(l => l.d > 0.04).sort((x, y) => y.d - x.d).slice(0, 6);
  $('levers').innerHTML = lv.map(l => `<div class="lever"><div>${l.label}</div><div class="d">+${fmt(l.d, 1)} power${Math.abs(l.dAI) >= 0.1 ? ` · AI ${l.dAI >= 0 ? '+' : ''}${fmt(l.dAI, 1)}` : ''}</div></div>`).join('') || '<p class="note">The counts are already where the Power read wants them.</p>';

  // EDHREC
  $('edhrec').innerHTML = a.edh ? [
    ['Page', `<a href="${edhrecLink(a.edh.name)}" target="_blank" rel="noopener">${esc(a.edh.name)}</a> · ${a.edh.decks.toLocaleString()} decks`],
    ['Themes', a.edh.tags.slice(0, 5).map(([v, n]) => `${esc(v)} ${Number(n).toLocaleString()}`).join(' · ') || '–'],
    ['Average build', ['creature', 'instant', 'sorcery', 'artifact', 'enchantment', 'planeswalker', 'land'].filter(k => a.edh.counts[k]).map(k => `${a.edh.counts[k]} ${k}${a.edh.counts[k] === 1 ? '' : 's'}`).join(' · ') + ` (${a.edh.counts.basic} basics)`],
    ['Brackets claimed', Object.entries(a.edh.brackets).sort().map(([b, n]) => `${BRACKET_NAMES[b] || b} ${Number(n).toLocaleString()}`).join(' · ') || '–'],
    ['Your 99', `${a.edhFit.avgInc}% average inclusion, ${a.edhFit.avgSyn >= 0 ? '+' : ''}${a.edhFit.avgSyn}% average synergy; ${a.edhFit.total - a.edhFit.listed} cards are not in its lists`],
    ['Similar commanders', a.edh.similar.join(', ') || '–'],
  ].map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('') : `<dt>No page bundled</dt><dd>${commanderCard ? `${esc(commanderCard.name)} is not among the commanders fetched (1,000+ decks on EDHREC). Theme matching uses its type line and text instead.` : 'No commander found in the list.'}</dd>`;

  $('howto').innerHTML = `<div class="two">
    <div><h3>Power (1–10)</h3><p class="note">Starts at 4 (a tidy precon). Adds for ramp, draw and removal coverage against the template, fast mana (+0.3 each), tutors (+0.25 each), Game Changers (+0.4 for the first three, +0.6 after), two-card combos (+1 each), a low effective curve (2.6 → +0.8, 4.4 → −1), untapped mana and cheap interaction. Bands: 1–2 Exhibition, 3–4 Core, 5–6 Upgraded, 7–8 Optimized, 9–10 cEDH. A guess to tune, not a measurement.</p></div>
    <div><h3>App AI match</h3><p class="note">Deck Power's formula with its fitted weights (mana 0.34, commander 0.31, threats 0.17, interaction 0.13), the one MagicMobile uses as a starting estimate for its AI decks. It says what the XMage AI plays well, not table strength. Reference precons sit at 6.0; Ranked's tiers aim at Bronze 3–4 … Mythic 8–9. The raw score here: ${fmt(a.ai.power)}.</p></div>
    <div><h3>Cut score</h3><p class="note">Never a land, never the commander, never ramp, draw or removal while their category is at or under target. Then: needs a board state to do anything (+2, or +1 for a creature) unless it wins the game; 6+ mana (+2) or 5 mana (+1), discounted when the deck cheats things out; the 3rd+ copy of a narrow effect (+1); off the commander's plan (+1); weak with one opponent (+1.5 at the MagicMobile table); over a category's target (+1); conditional wording (+0.5). With EDHREC data: under 3% of the commander's decks +1, under 10% +0.5, not listed +0.5, played less with it than elsewhere +0.5; a staple at 35%+ −1, +25% synergy −0.5. Cheap cards, tutors, fast mana and finishers score lower.</p></div>
    <div><h3>Data</h3><p class="note">Every Commander-legal card from Scryfall's bulk file, classified once at build time; EDHREC's page for every commander with 1,000+ decks (1,649 pages, 2026-10-26); the bracket rules and Deck Power weights the apps ship. Card images come from Scryfall and show only when this page is served outside the artifact sandbox.</p></div></div>`;

  renderCuts(a, cutsWanted, mode);
  renderAdds(a, mode, ci);
  renderLands(a, mode, ci);
  renderTable(a);
  $('drawOne').disabled = false;
}

function updateDecisionNote(total) {
  const after = total - decisions.cut.size + decisions.add.size;
  $('decisionNote').textContent = decisions.cut.size || decisions.add.size ? `${decisions.cut.size} out, ${decisions.add.size} in → ${after} cards` : '';
  $('nCuts').textContent = decisions.cut.size ? ` ${decisions.cut.size}` : '';
  $('nAdds').textContent = decisions.add.size ? ` ${decisions.add.size}` : '';
}

const useEdh = () => $('edhMode').value !== 'off';
function renderCuts(a, cutsWanted, mode) {
  const cuts = cutCandidates(a, mode, useEdh());
  const candidates = cuts.filter(x => !x.protectedBy).sort((x, y) => y.score - x.score);
  const protectedRows = cuts.filter(x => x.protectedBy && x.protectedBy !== 'land');
  const total = current.deck.entries.reduce((s, e) => s + e.qty, 0) + (current.commanderCard ? 1 : 0);
  $('cutsTitle').textContent = total > 100 ? `Cut ${total - 100} to reach 100` : `${cutsWanted} cards to cut if you need room`;
  $('cutNote').textContent = `Judged by your deck: what each card does, your category counts, your curve, and the plan your own cards share (${a.theme.slice(0, 4).join(', ') || 'none found'}). Lands, ramp, card draw and removal stay safe while their counts are at or under target. ${useEdh() ? 'EDHREC only breaks ties, half a point at most, and shows in grey.' : 'EDHREC is off.'} Mark Cut or Keep, then copy the new list from the bar above.`;
  const shown = candidates.slice(0, Math.max(cutsWanted + 9, 12));
  $('cuts').innerHTML = shown.map((x, i) => tile(x.row.card, { badge: fmt(Math.max(0, x.score)), badgeClass: i < cutsWanted ? 'bad' : '', pill: `${x.row.card.cmc} mv`, why: x.reasons.slice(0, 3), edh: useEdh() ? x.edhNote : '', acts: cutKeepButtons(x.row.card.name), state: stateOf(x.row.card.name) })).join('') || '<p class="note">Nothing to cut: every card is a land or a staple at target.</p>';
  $('protectedSummary').textContent = `Safe cards (${protectedRows.length})`;
  $('protected').innerHTML = protectedRows.map(x => tile(x.row.card, { pill: esc(x.reasons[0].split(' (')[0]), acts: cutKeepButtons(x.row.card.name), state: stateOf(x.row.card.name) })).join('');
}

async function renderAdds(a, mode, ci) {
  const T = TEMPLATES[mode], c = a.counts, edhOn = useEdh();
  const inDeck = new Set(a.rows.map(r => keyOf(r.card.name)));
  const who = a.edh ? a.edh.short : '';
  // The pool: EDHREC's list for this commander (when on) plus format staples. The deck decides the order.
  const edhCards = a.edh && edhOn ? a.edh.cards.filter(([n, , , cat]) => cat !== 'land' && cat !== 'utilityland') : [];
  const edhOf = new Map(edhCards.map(x => [keyOf(x[0]), x]));
  const pool = [...new Set([...edhCards.map(x => x[0]), ...Object.values(STAPLES).flat()])].filter(n => !inDeck.has(keyOf(n)));
  const rec = await records(pool);
  const gaps = { ramp: [c.ramp, T.ramp, 'ramp', ['ramp']], draw: [c.draw, T.draw, 'card draw', ['draw']], targeted: [c.targeted, T.targeted, 'removal', ['removal', 'counter']], mass: [c.mass, T.mass, 'board wipes', ['wipe']] };
  const short = Object.fromEntries(Object.entries(gaps).map(([k, [n, [lo]]]) => [k, Math.max(0, lo - n)]));
  const over = Object.fromEntries(Object.entries(gaps).map(([k, [n, [, hi]]]) => [k, n > hi]));
  const sixPlus = a.curve[6] + a.curve[7];
  const judged = [];
  for (const name of pool) {
    const card = rec(name);
    if (!card || card.baseF.land || !card.ci.every(col => ci.includes(col))) continue;
    const tags = card.baseTags, f = card.baseF; const why = []; let score = 0; const fills = [];
    for (const [k, [n, [lo, hi], label, roles]] of Object.entries(gaps)) {
      if (!roles.some(r => tags.has(r))) continue;
      if (short[k]) { score += 2 + 0.25 * short[k]; fills.push(k); why.push(`adds ${label}: you have ${n}, want ${lo}+`); }
      else if (over[k]) { score -= 1; why.push(`you already run ${n} ${label}`); }
    }
    const shared = card.theme.filter(w => a.theme.includes(w)).sort((x, y) => (a.plan.share[y] || 0) - (a.plan.share[x] || 0));
    if (shared.length) { score += 1.5; why.push(`${shared[0]}, like ${a.plan.share[shared[0]] || 0} of your cards`); }
    if (card.cmc <= 2 && c.cheap < 25) { score += 0.5; why.push(`${card.cmc} mana: you have ${c.cheap} plays at 2 or less`); }
    if (card.cmc >= 6 && sixPlus >= 5) { score -= 1; why.push(`your top end already has ${sixPlus}`); }
    if (tags.has('finisher') && c.finishers < 2) { score += 1; why.push(`a way to close games (you have ${c.finishers})`); }
    if (tags.has('engine') && !shared.length) { score -= 0.5; why.push('needs a board state'); }
    if (f.multiplayer && mode === 'duel') { score -= 1.5; why.push('weak with one opponent'); }
    if (tags.has('tutor') || f.fastMana) { score += 0.5; why.push(tags.has('tutor') ? 'tutor' : 'fast mana'); }
    const e = edhOf.get(keyOf(name));
    const nudge = e ? Math.min(0.5, e[1] / 80) : 0;
    judged.push({ name, card, score: score + nudge, why, fills, shared, edhNote: e ? `EDHREC: in ${e[1]}% of ${who} decks` : '', gc: card.gc });
  }
  judged.sort((x, y) => y.score - x.score);
  const item = j => tile(j.card, { name: j.name, badge: fmt(Math.max(0, j.score)), badgeClass: 'good', pill: `${j.card.cmc} mv`, why: [...j.why.slice(0, 3), ...(j.gc ? ['Game Changer'] : [])], edh: j.edhNote, acts: addButton(j.name), state: stateOf(j.name) });
  const section = (title, sub, items) => items.length ? `<div style="margin-top:16px"><h3>${title}</h3>${sub ? `<p class="note">${sub}</p>` : ''}<div class="grid" style="margin-top:10px">${items.join('')}</div></div>` : '';
  let html = '';
  const used = new Set();
  for (const [k, [n, [lo], label]] of Object.entries(gaps)) {
    if (!short[k]) continue;
    const picks = judged.filter(j => j.fills.includes(k) && !used.has(j.name)).slice(0, 8);
    picks.forEach(j => used.add(j.name));
    html += section(`Short on ${label}: you have ${n}, add ${short[k]}`, 'Ranked by how well each one fits the rest of your deck.', picks.map(item));
  }
  const planPicks = judged.filter(j => j.shared.length && !used.has(j.name) && j.score > 1).slice(0, 12);
  planPicks.forEach(j => used.add(j.name));
  html += section(`Fits your plan (${a.theme.slice(0, 4).join(', ')})`, 'Cards that share what your own cards are built around.', planPicks.map(item));
  const levers = judged.filter(j => !used.has(j.name) && (j.card.baseTags.has('tutor') || j.card.baseF.fastMana || j.card.baseTags.has('protection'))).slice(0, 8);
  levers.forEach(j => used.add(j.name));
  html += section('Power levers', 'Tutors, fast mana and protection in your colors. More of these raises the deck\'s power and bracket.', levers.map(item));
  if (edhOn && a.edh) {
    const popular = edhCards.filter(x => !inDeck.has(keyOf(x[0])) && !used.has(x[0])).sort((x, y) => y[1] - x[1]).map(x => judged.find(j => j.name === x[0])).filter(Boolean).slice(0, 10);
    if (popular.length) html += `<details style="margin-top:16px"><summary>Also popular with ${esc(who)} on EDHREC (not judged a fit for your list)</summary><div class="grid" style="margin-top:10px">${popular.map(item).join('')}</div></details>`;
  }
  $('upgradeNote').textContent = `Ranked by your deck: what it is short on, the plan your own cards share, your curve and table size. ${edhOn && a.edh ? `EDHREC's ${who} list widens the pool and only nudges ties (shown in grey).` : 'EDHREC is off; the pool is format staples.'} Tap Add to put a card on the new list.`;
  $('upgrades').innerHTML = html || '<p class="note">Nothing to suggest: your counts are on target and nothing in the pool fits the plan better.</p>';
}

async function renderLands(a, mode, ci) {
  const c = a.counts, edh = a.edh, T = TEMPLATES[mode];
  const pool = await loadLandPool();
  const inDeck = new Set(a.rows.map(r => keyOf(r.card.name)));
  const pipTotal = Object.values(a.pipNeed).reduce((x, y) => x + y, 0) || 1;
  const share = Object.fromEntries(Object.entries(a.pipNeed).map(([k, v]) => [k, v / pipTotal]));
  const colors = ci.filter(k => share[k] > 0);
  const mono = colors.length <= 1;
  const edhInc = name => { const e = edh && edh.index.get(keyOf(name)); return e ? e.inc : 0; };
  const score = l => { const made = l.produced.filter(k => colors.includes(k)); return [made.reduce((s, k) => s + share[k], 0) + 0.2 * made.length, -l.tapped, edhInc(l.name), -(l.usd || 999)]; };
  const better = (x, y) => { const sx = score(x), sy = score(y); for (let i = 0; i < sx.length; i++) if (sx[i] !== sy[i]) return sy[i] - sx[i]; return 0; };
  const candidates = pool.filter(l => !inDeck.has(keyOf(l.name)) && l.ci.every(k => ci.includes(k)) && l.produced.filter(k => colors.includes(k)).length >= (mono ? 1 : 2) && l.tapped < 1).sort(better);
  const tapped = a.rows.filter(r => (r.f.land || r.f.mdfc) && r.f.tapped >= 0.5 && !/^Basic Land/.test(r.card.front_type)).sort((x, y) => y.f.tapped - x.f.tapped || edhInc(x.card.name) - edhInc(y.card.name));
  let utilityNames = edh ? edh.cards.filter(x => (x[3] === 'utilityland' || x[3] === 'land') && !inDeck.has(keyOf(x[0])) && !/^(Plains|Island|Swamp|Mountain|Forest)$/.test(x[0])).sort((x, y) => y[1] - x[1]).slice(0, 10).map(x => x[0]) : [];
  if (!utilityNames.length) {
    const tribal = a.theme.some(w => /^(goblin|elf|zombie|vampire|dragon|dinosaur|sliver|human|angel|demon|wizard|warrior|knight|soldier|cat|dog|merfolk|pirate|rat|spirit|elemental|beast|wolf|faerie|rogue|cleric|druid|giant|treefolk|insect|squirrel|ooze|samurai|ninja|dwarf|myr|thopter|construct)$/.test(w));
    utilityNames = UTILITY_FALLBACK.filter(([name, kind]) => !inDeck.has(keyOf(name)) && (kind === 0 || (kind === 1 && tribal) || (kind === 2 && !mono))).map(x => x[0]);
  }
  const swapNames = new Set(); const swapsFor = new Map();
  for (const r of tapped) {
    const makes = r.card.produced.filter(k => colors.includes(k));
    const swaps = candidates.filter(l => l.tapped < r.f.tapped && (mono || l.produced.filter(k => makes.includes(k)).length >= Math.min(2, makes.length))).slice(0, 3);
    swapsFor.set(r.card.name, swaps); swaps.forEach(l => swapNames.add(l.name));
  }
  const rec = await records([...new Set([...swapNames, ...candidates.slice(0, 12).map(l => l.name), ...utilityNames, ...colors.map(k => BASIC_OF[k])])]);
  const landTile = (l, extra = []) => { const card = rec(l.name); return tile(card, { name: l.name, pill: edhInc(l.name) ? `${edhInc(l.name)}%` : (l.usd ? `$${l.usd}` : undefined), why: [...(l.tapped ? ['sometimes tapped'] : []), ...extra], acts: addButton(l.name), state: stateOf(l.name) }); };
  $('landsSwap').innerHTML = tapped.length ? tapped.map(r => {
    const swaps = swapsFor.get(r.card.name) || [];
    return `<div class="swap">${tile(r.card, { pill: r.f.tapped === 1 ? 'tapped' : 'tapped sometimes', why: edhInc(r.card.name) ? [`in ${edhInc(r.card.name)}% of ${edh.short} decks`] : [], acts: cutKeepButtons(r.card.name), state: stateOf(r.card.name) })}<div class="arrow">→</div><div class="grid">${swaps.length ? swaps.map(l => landTile(l)).join('') : `<p class="note">${mono ? 'A basic does the same job untapped.' : 'No untapped land left in these colors.'}</p>`}</div></div>`;
  }).join('') : '<p class="note" style="margin-top:6px">Every nonbasic land enters untapped.</p>';
  $('landsAdd').innerHTML = candidates.length ? candidates.slice(0, 12).map(l => landTile(l)).join('') : `<p class="note">${mono ? 'In one color the basics are the untapped lands.' : 'Nothing left to add.'}</p>`;
  const utilityItems = utilityNames.filter(n => { const card = rec(n); return card && card.ci.every(k => ci.includes(k)); }).slice(0, 10);
  $('landsUtility').innerHTML = utilityItems.map(n => { const card = rec(n); const e = edh && edh.index.get(keyOf(n)); return tile(card, { name: n, pill: e ? `${e.inc}%` : undefined, why: e ? [`+${e.syn}% synergy`] : [], acts: addButton(n), state: stateOf(n) }); }).join('') || '<p class="note">Nothing to add.</p>';
  const target = edh ? edh.counts.land : T.lands[1];
  const nonbasic = a.rows.filter(r => (r.f.land || r.f.mdfc) && !/^Basic Land/.test(r.card.front_type)).reduce((s, r) => s + r.entry.qty, 0);
  const basicsNow = Object.fromEntries(colors.map(k => [k, a.rows.filter(r => r.card.front_type === `Basic Land — ${BASIC_OF[k]}` || r.card.front_type === `Basic Snow Land — ${BASIC_OF[k]}`).reduce((s, r) => s + r.entry.qty, 0)]));
  const slots = Math.max(0, target - nonbasic);
  const want = {}; let given = 0;
  colors.forEach((k, i) => { want[k] = i === colors.length - 1 ? slots - given : Math.round(slots * share[k]); given += want[k]; });
  $('landsBasics').innerHTML = colors.length ? `<div class="grid small">${colors.map(k => tile(rec(BASIC_OF[k]), { name: BASIC_OF[k], badge: `${basicsNow[k]}`, why: [`about ${Math.max(0, want[k])} for ${Math.round(share[k] * 100)}% of pips`] })).join('')}</div><p class="note" style="margin-top:8px">${target} lands${edh ? ` (${esc(edh.short)} decks average ${edh.counts.land}, ${edh.counts.nonbasic} nonbasic)` : ' (the template)'} minus your ${nonbasic} nonbasic leaves ${slots} basic slots. The badge is what you run now.</p>` : '<p class="note">A colorless deck: Wastes and utility lands.</p>';
  $('landsNote').textContent = `${c.lands} lands, ${nonbasic} nonbasic, ${Math.round(c.tapped)} entering tapped. ${edh ? `${edh.short} decks average ${edh.counts.land} lands.` : `The template says ${T.lands[0]}–${T.lands[1]}.`} ${c.effectiveManaValue < 2.8 && c.ramp >= 8 ? 'A low curve with this much ramp can sit at the bottom of that range.' : ''}`;
}

function renderTable(a) {
  const sorted = [...a.rows].sort((x, y) => (x.f.land || x.f.mdfc) - (y.f.land || y.f.mdfc) || x.card.cmc - y.card.cmc || x.card.name.localeCompare(y.card.name));
  $('allCards').innerHTML = `<thead><tr><th>Card</th><th class="n">MV</th><th>Type</th><th>Roles and flags</th><th class="n">${a.edh ? 'EDHREC incl · syn' : 'EDHREC rank'}</th><th></th></tr></thead><tbody>` + sorted.map(r => `<tr class="clickable" data-zoom="${esc(front(r.card.name))}"><td><img class="thumb" loading="lazy" src="${imgUrl(r.card, 'small')}" alt="" onerror="this.remove()"><b>${esc(r.card.name)}</b>${r.isCommander ? ' <span class="chip keep">commander</span>' : ''}${r.entry.qty > 1 ? ` ×${r.entry.qty}` : ''}</td><td class="n">${r.card.cmc}</td><td>${esc((r.card.front_type || '').replace('Legendary ', 'L. '))}</td><td>${roleChips(r.tags, r.f) || '<span class="note">plan card</span>'}</td><td class="n">${a.edh ? (r.edh ? `${r.edh.inc}% · ${r.edh.syn >= 0 ? '+' : ''}${r.edh.syn}%` : (r.isCommander ? '' : '–')) : (r.card.rank ? '#' + r.card.rank.toLocaleString() : '–')}</td><td><a href="${scryfallLink(r.card.name)}" target="_blank" rel="noopener" onclick="event.stopPropagation()">text</a></td></tr>`).join('') + '</tbody>';
}

// ----- zoom overlay with the role editor -----
function openZoom(label) {
  const row = current && current.analysis.rows.find(r => front(r.card.name) === label || r.card.name === label);
  const card = row ? row.card : recordCache.get(label) || [...recordCache.values()].find(x => front(x.name) === label);
  if (!card) return;
  const inDeck = !!row;
  const tags = row ? row.tags : card.baseTags, f = row ? row.f : card.baseF;
  const edh = current && current.edh && current.edh.index.get(keyOf(card.name));
  $('overlay').innerHTML = `<div class="box" role="dialog" aria-label="${esc(card.name)}">
    <div>${card.id ? `<img src="${imgUrl(card, 'normal')}" alt="${esc(card.name)}" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'ph',textContent:'${esc(front(card.name)).replace(/'/g, "\\'")}'}))">` : `<div class="ph">${esc(front(card.name))}</div>`}</div>
    <div>
      <h2 style="color:var(--ink)">${esc(card.name)}</h2>
      <p class="sub">${esc(card.front_type)} · ${card.cmc} mana${card.usd ? ` · $${card.usd}` : ''}${edh ? ` · in ${edh.inc}% of ${esc(current.edh.short)} decks, ${edh.syn >= 0 ? '+' : ''}${edh.syn}% synergy` : card.rank ? ` · EDHREC #${card.rank.toLocaleString()}` : ''}</p>
      <div style="margin-top:8px">${roleChips(tags, f) || '<span class="note">plan card</span>'}</div>
      <p class="note" style="margin-top:8px"><a href="${scryfallLink(card.name)}" target="_blank" rel="noopener">Card text on Scryfall</a></p>
      ${inDeck ? `<span class="eyebrow" style="margin-top:14px">Fix its roles</span><div class="roles">${ROLES.map(r => `<label><input type="checkbox" data-role="${r}" data-name="${esc(card.name)}" ${tags.has(r) ? 'checked' : ''}> ${ROLE_LABEL[r]}</label>`).join('')}</div>
      <div class="row" style="margin-top:12px">${row.isCommander ? '' : cutKeepButtons(card.name)}${overrides[card.name] ? `<button class="btn tiny" data-act="forget" data-name="${esc(card.name)}">Forget my correction</button>` : ''}</div>` : `<div class="row" style="margin-top:12px">${addButton(card.name)}</div>`}
      <div class="row" style="margin-top:16px"><button class="btn small" data-act="close">Close</button></div>
    </div></div>`;
  $('overlay').hidden = false;
}

// ----- the new list -----
function buildNewList() {
  const lines = [];
  if (current.commanderCard) lines.push('Commander', `1 ${current.commanderCard.name}`, '');
  lines.push('Deck');
  for (const e of current.deck.entries) if (!decisions.cut.has(e.name) && !decisions.cut.has(front(e.name))) lines.push(`${e.qty} ${e.name}`);
  for (const n of decisions.add) lines.push(`1 ${n}`);
  return lines.join('\n') + '\n';
}
async function copyList() {
  const text = buildNewList();
  try { await navigator.clipboard.writeText(text); $('decisionNote').textContent = 'Copied.'; setTimeout(() => updateDecisionNote(current.deck.entries.reduce((s, e) => s + e.qty, 0) + (current.commanderCard ? 1 : 0)), 1500); }
  catch { $('overlay').innerHTML = `<div class="box" style="grid-template-columns:1fr"><div><h2>Your new list</h2><p class="note">Select all and copy.</p><textarea class="copybox" id="copyArea">${esc(text)}</textarea><div class="row" style="margin-top:10px"><button class="btn small" data-act="close">Close</button></div></div></div>`; $('overlay').hidden = false; $('copyArea').select(); }
}

// ----- flow -----
function rerun() {
  if (!current) return;
  const a = analyseDeck(current.deck, current.cards, current.commanderCard, $('mode').value, overrides, parseFloat($('cmdStrength').value) || 0.5, current.edh);
  current.analysis = a;
  render(a);
}
async function run() {
  const status = $('status'); status.className = 'status';
  const text = $('decklist').value; storage.set('dh-list', text);
  const deck = parseList(text);
  if (!deck.entries.length && !deck.commander.length) { status.textContent = 'Paste a decklist first.'; return; }
  $('analyze').disabled = true;
  try {
    const typed = $('commander').value.trim();
    const names = [...new Set([...deck.commander.map(e => e.name), ...deck.entries.map(e => e.name), ...(typed ? [typed] : [])])];
    const { result: cards, unknown } = await loadCards(names, m => status.textContent = m);
    let cmdName = typed || (deck.commander[0] && deck.commander[0].name);
    if (!cmdName) { const leg = deck.entries.find(e => { const card = cards.get(e.name); return card && /legendary/i.test(card.front_type) && /creature/i.test(card.front_type); }); if (leg) cmdName = leg.name; }
    const commanderCard = cmdName ? cards.get(cmdName) : null;
    if (commanderCard) { deck.entries = deck.entries.filter(e => cards.get(e.name) !== commanderCard); $('commander').value = commanderCard.name; }
    if (deck.commander.length > 1) for (const e of deck.commander.slice(1)) deck.entries.push(e);
    status.textContent = "Loading the commander's EDHREC page…";
    const edh = commanderCard ? await loadCommander(commanderCard.name) : null;
    current = { deck, cards, commanderCard, unknown, edh };
    loadDecisions();
    rerun();
    const total = deck.entries.reduce((s, e) => s + e.qty, 0) + (commanderCard ? 1 : 0);
    status.textContent = `${total} cards read${commanderCard ? `, commander ${commanderCard.name}` : ', no commander found'}${unknown.length ? `, ${unknown.length} not recognised` : ''}${edh ? `, EDHREC ${edh.decks.toLocaleString()} decks` : commanderCard ? ', no EDHREC page bundled' : ''}.`;
    $('intake').hidden = true;
    showTab(location.hash.replace('#', '') || 'overview');
    $('deckbar').scrollIntoView({ behavior: 'smooth', block: 'start' });
  } catch (err) { status.className = 'status err'; status.textContent = `Could not read the deck: ${err.message}.`; }
  $('analyze').disabled = false;
}
function showTab(name) {
  if (!['overview', 'cuts', 'adds', 'lands', 'cards'].includes(name)) name = 'overview';
  document.querySelectorAll('.tab').forEach(t => t.setAttribute('aria-selected', String(t.dataset.tab === name)));
  document.querySelectorAll('[data-screen]').forEach(s => { s.hidden = s.dataset.screen !== name; });
  try { history.replaceState(null, '', '#' + name); } catch {}
}
function refreshDecisionUI() {
  for (const el of document.querySelectorAll('.cardc[data-card]')) { const name = el.dataset.card; el.classList.remove('is-cut', 'is-keep', 'is-add'); const s = stateOf(name) || stateOf([...current.cards.keys()].find(k => front(k) === name) || name); if (s) el.classList.add(s); }
  for (const b of document.querySelectorAll('button[data-act]')) { const act = b.dataset.act, name = b.dataset.name; if (!['cut', 'keep', 'add'].includes(act)) continue; const on = decisions[act].has(name); b.classList.toggle('on', on); b.textContent = on ? ({ cut: 'Cutting', keep: 'Keeping', add: 'Adding' })[act] : ({ cut: 'Cut', keep: 'Keep', add: 'Add' })[act]; }
  updateDecisionNote(current.deck.entries.reduce((s, e) => s + e.qty, 0) + (current.commanderCard ? 1 : 0));
}

// Sample hand with images.
let library = [];
function drawHand() { if (!current) return; const pool = []; for (const e of current.deck.entries) { const card = current.cards.get(e.name); if (card) for (let i = 0; i < e.qty; i++) pool.push(card); } for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]]; } library = pool; $('hand').innerHTML = ''; for (let i = 0; i < 7; i++) drawOne(); }
function drawOne() {
  if (!library.length) return; const card = library.shift(); const isLand = /\bland\b/i.test((card.front_type || '').split('—')[0]) || card.layout === 'modal_dfc';
  $('hand').insertAdjacentHTML('beforeend', tile(card, { pill: isLand ? 'land' : `${card.cmc} mv` }));
  const lands = [...$('hand').querySelectorAll('.pill')].filter(p => p.textContent === 'land').length, n = $('hand').children.length;
  $('handNote').textContent = `${n} cards · ${lands} lands${n === 7 ? (lands < 2 ? ' · mulligan?' : lands > 5 ? ' · flood' : '') : ''}`;
}

// ----- events -----
document.addEventListener('click', e => {
  const tab = e.target.closest('.tab'); if (tab) { showTab(tab.dataset.tab); return; }
  const go = e.target.closest('[data-goto]'); if (go) { showTab(go.dataset.goto); window.scrollTo({ top: 0, behavior: 'smooth' }); return; }
  const act = e.target.closest('[data-act]');
  if (act) {
    const name = act.dataset.name, kind = act.dataset.act;
    if (kind === 'close') { $('overlay').hidden = true; return; }
    if (kind === 'forget') { delete overrides[name]; storage.set('dh-overrides-v1', overrides); $('overlay').hidden = true; rerun(); return; }
    if (kind === 'cut' || kind === 'keep') { const other = kind === 'cut' ? 'keep' : 'cut'; if (decisions[kind].has(name)) decisions[kind].delete(name); else { decisions[kind].add(name); decisions[other].delete(name); } }
    if (kind === 'add') { if (decisions.add.has(name)) decisions.add.delete(name); else decisions.add.add(name); }
    saveDecisions(); refreshDecisionUI(); return;
  }
  const zoom = e.target.closest('[data-zoom]'); if (zoom) { openZoom(zoom.dataset.zoom); return; }
  if (e.target === $('overlay')) $('overlay').hidden = true;
});
document.addEventListener('change', e => {
  const role = e.target.dataset && e.target.dataset.role;
  if (role) { const name = e.target.dataset.name; overrides[name] = overrides[name] || {}; overrides[name][role] = e.target.checked; storage.set('dh-overrides-v1', overrides); rerun(); openZoom(front(name)); }
});
document.addEventListener('keydown', e => { if (e.key === 'Escape') $('overlay').hidden = true; });
$('analyze').addEventListener('click', run);
$('decklist').addEventListener('keydown', e => { if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') run(); });
$('mode').addEventListener('change', rerun); $('edhMode').addEventListener('change', rerun); $('cutCount').addEventListener('change', rerun); $('cmdStrength').addEventListener('change', rerun);
$('exKrenko').addEventListener('click', () => { $('decklist').value = SAMPLES.krenko; $('commander').value = ''; run(); });
$('exEdgar').addEventListener('click', () => { $('decklist').value = SAMPLES.edgar; $('commander').value = ''; run(); });
$('editList').addEventListener('click', () => { $('intake').hidden = false; $('intake').scrollIntoView({ behavior: 'smooth' }); });
$('copyList').addEventListener('click', copyList);
$('drawHand').addEventListener('click', drawHand); $('drawOne').addEventListener('click', drawOne);
$('decklist').value = storage.get('dh-list', '') || SAMPLES.krenko;
run();
