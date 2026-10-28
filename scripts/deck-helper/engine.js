const RULES = __RULES__;
const POWER = __POWER__;
const SAMPLES = __SAMPLES__;
const PARTS = ['speed','mana','interaction','consistency','threats','synergy','commander','combos','resilience'];
const ROLES = ['ramp','draw','removal','counter','wipe','tutor','protection','recursion','finisher','engine']; // = TAGS
const ROLE_LABEL = { ramp:'Ramp', draw:'Draw', removal:'Removal', counter:'Counter', wipe:'Wipe', tutor:'Tutor', protection:'Protection', recursion:'Recursion', finisher:'Finisher', engine:'Engine' };
const TEMPLATES = {
  pod:  { lands:[36,38], ramp:[10,12], draw:[10,12], targeted:[10,12], mass:[3,6], plan:[26,32] },
  duel: { lands:[36,38], ramp:[10,12], draw:[10,12], targeted:[11,14], mass:[2,4], plan:[26,32] },
};
const FLAGS = __FLAGS__;
const TAGS = __TAGS__;
// Staples the Upgrades section may suggest, by template category. Flags, legality and prices come from Scryfall at run time.
const STAPLES = {
  ramp: ['Sol Ring','Arcane Signet','Fellwar Stone','Mind Stone','Thought Vessel','Wayfarer\'s Bauble','Talisman of Dominance','Talisman of Progress','Talisman of Indulgence','Talisman of Creativity','Talisman of Unity','Talisman of Hierarchy','Talisman of Impulse','Talisman of Conviction','Talisman of Resilience','Talisman of Curiosity','Rampant Growth','Nature\'s Lore','Three Visits','Farseek','Cultivate','Kodama\'s Reach','Llanowar Elves','Elvish Mystic','Birds of Paradise','Fyndhorn Elves','Sakura-Tribe Elder','Wood Elves','Smothering Tithe','Dark Ritual','Jeska\'s Will','Deep Gnome Terramancer','Knight of the White Orchid','Archaeomancer\'s Map','Mana Vault','Chrome Mox','Mox Diamond','Ancient Tomb'],
  draw: ['Rhystic Study','Mystic Remora','Brainstorm','Ponder','Preordain','Fact or Fiction','Windfall','Night\'s Whisper','Sign in Blood','Phyrexian Arena','Necropotence','Black Market Connections','Beast Whisperer','Guardian Project','Harmonize','Garruk\'s Uprising','The Great Henge','Faithless Looting','Wheel of Fortune','Big Score','Esper Sentinel','Welcoming Vampire','Tocasia\'s Welcome','Skullclamp','The One Ring','Consecrated Sphinx','Painful Truths','Read the Bones','Return of the Wildspeaker','Toski, Bearer of Secrets','Idol of Oblivion','Bitter Triumph'],
  targeted: ['Swords to Plowshares','Path to Exile','Generous Gift','Fateful Absence','Counterspell','Swan Song','An Offer You Can\'t Refuse','Arcane Denial','Pongify','Rapid Hybridization','Go for the Throat','Feed the Swarm','Infernal Grasp','Deadly Rollick','Chaos Warp','Abrade','Vandalblast','Beast Within','Nature\'s Claim','Krosan Grip','Assassin\'s Trophy','Anguished Unmaking','Vindicate','Terminate','Lightning Bolt','Fierce Guardianship','Negate','Dovin\'s Veto','Reality Shift','Stroke of Midnight','Bitter Triumph','Heartless Act','Dismember','Baleful Mastery','Return to Dust','Mana Drain'],
  mass: ['Blasphemous Act','Wrath of God','Damnation','Farewell','Toxic Deluge','Vanquish the Horde','Cyclonic Rift','Austere Command','Hour of Revelation','Evacuation','Ezuri\'s Predation','Pernicious Deed','Crux of Fate','Sunfall','Shatter the Sky','Fell the Mighty'],
  tutor: ['Demonic Tutor','Vampiric Tutor','Enlightened Tutor','Mystical Tutor','Worldly Tutor','Green Sun\'s Zenith','Diabolic Tutor','Finale of Devastation','Idyllic Tutor','Gamble','Chord of Calling','Eladamri\'s Call','Grim Tutor','Fierce Empath','Sylvan Tutor','Imperial Seal','Profane Tutor','Wishclaw Talisman','Fabricate','Whir of Invention','Steelshaper\'s Gift','Open the Armory','Recruiter of the Guard'],
  protection: ['Heroic Intervention','Teferi\'s Protection','Swiftfoot Boots','Lightning Greaves','Flawless Maneuver','Deflecting Swat','Tamiyo\'s Safekeeping','Snakeskin Veil','Blossoming Defense','Boros Charm','Clever Concealment','Wrap in Vigor','Darksteel Plate','Malakir Rebirth // Malakir Mire','Loran\'s Escape','Akroma\'s Will'],
};
const BRACKET_NAMES = {1:'Exhibition',2:'Core',3:'Upgraded',4:'Optimized',5:'cEDH'};
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const fmt = (n, d=1) => (Math.round(n * 10**d) / 10**d).toFixed(d);
const lin = (v, [z, o]) => Math.max(0, Math.min(1, (v - z) / (o - z)));
const mix = (vals, sh) => vals.reduce((a, v, i) => a + v * sh[i], 0) / sh.reduce((a, b) => a + b, 0);
const storage = { get(k, d){ try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } }, set(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch {} } };

// ---------- Parsing ----------
function parseList(text) {
  const entries = [], commander = [];
  let section = 'main';
  for (let raw of text.split(/\r?\n/)) {
    let line = raw.trim();
    if (!line) continue;
    const header = line.replace(/[:#/\[\]()*_-]/g, ' ').replace(/\s+/g, ' ').trim().toLowerCase();
    if (/^(commander|commanders|command zone)( \(\d+\))?$/.test(header)) { section = 'commander'; continue; }
    if (/^(deck|main|mainboard|main deck|the 99|creatures?|instants?|sorcer(y|ies)|artifacts?|enchantments?|lands?|planeswalkers?|battles?|other|spells?|nonland|non land|companion|about|name .*)( \(\d+\))?( \d+)?$/.test(header)) { if (!/^name/.test(header)) section = 'main'; continue; }
    if (/^(sideboard|maybeboard|maybe|considering|cuts?|tokens?|outside|removed)( \(\d+\))?( \d+)?$/.test(header)) { section = 'skip'; continue; }
    if (line.startsWith('//')) continue;
    if (section === 'skip') continue;
    const isCmdr = /\*CMDR\*|\[commander(\{top\})?\]|\{commander\}/i.test(line);
    line = line.replace(/\*CMDR\*|\[commander(\{top\})?\]|\{commander\}/ig, '');
    let qty = 1, name = line, m;
    if ((m = line.match(/^(\d+)\s*x?\s+(.+)$/i))) { qty = parseInt(m[1], 10); name = m[2]; }
    else if ((m = line.match(/^(.+?)\s+x(\d+)$/i))) { name = m[1]; qty = parseInt(m[2], 10); }
    name = name.replace(/\s*\^[^^]*\^\s*$/, '').replace(/\s*\*[FE]\*\s*/ig, ' ').replace(/\s*\[[^\]]*\]\s*/g, ' ')
      .replace(/\s*\(([A-Za-z0-9]{2,6})\)(\s+[\w★-]+)?\s*$/, '').replace(/\s+#.*$/, '').replace(/\s+/g, ' ').trim();
    if (!name) continue;
    (section === 'commander' || isCmdr ? commander : entries).push({ name, qty });
  }
  return { commander, entries };
}

// ---------- Card data (built once from Scryfall's bulk file; see build/classifier.js) ----------
const shardCache = {};
const fold = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const keyOf = n => fold(n.split(' // ')[0].trim());
const letterOf = k => /^[a-z]/.test(k) ? k[0] : '0';
function decode(rec) {
  const [name, cmc, front_type, mana_cost, ciStr, power, produced, rank, gc, flagBits, tagBits, themeStr, tapped, usd, id] = rec;
  const f = {}; FLAGS.forEach((k, i) => { f[k] = !!(flagBits & (1 << i)); }); f.tapped = tapped; f.power = power || 0;
  const tags = new Set(); TAGS.forEach((k, i) => { if (tagBits & (1 << i)) tags.add(k); });
  return { name, cmc, front_type, type_line: front_type, mana_cost, ci: ciStr.split('').filter(Boolean), power, produced: produced.split('').filter(Boolean), rank: rank || null, gc: !!gc,
    baseTags: tags, baseF: f, theme: themeStr ? themeStr.split('|') : [], layout: f.mdfc ? 'modal_dfc' : '', usd: usd || 0, id: id || '' };
}
async function loadCards(names, onProgress) {
  const letters = [...new Set(names.map(n => letterOf(keyOf(n))))];
  const need = letters.filter(l => !shardCache[l]);
  if (need.length) {
    onProgress && onProgress(`Loading card data (${need.length} file${need.length === 1 ? '' : 's'})…`);
    await Promise.all(need.map(async l => { const r = await fetch(`cards/${l}.json`); if (!r.ok) throw new Error(`card data ${l}.json is missing (${r.status})`); shardCache[l] = await r.json(); }));
  }
  const result = new Map(), unknown = [];
  for (const n of names) { const k = keyOf(n); const rec = shardCache[letterOf(k)] && shardCache[letterOf(k)][k]; if (rec) result.set(n, decode(rec)); else unknown.push(n); }
  return { result, unknown };
}
const imgUrl = (card, size = 'small') => card && card.id ? `https://cards.scryfall.io/${size}/front/${card.id[0]}/${card.id[1]}/${card.id}.jpg` : '';
const scryfallLink = name => `https://scryfall.com/search?q=${encodeURIComponent('!"' + name.split(' // ')[0] + '"')}`;
const edhrecLink = name => `https://edhrec.com/commanders/${keyOf(name).replace(/[^a-z0-9 -]/g, '').replace(/\s+/g, '-')}`;
// EDHREC commander pages, trimmed at build time (scripts/deck-helper/fetch-edhrec.py): per card [name, inclusion %, synergy %, category, flags].
const edhCache = {};
async function loadCommander(name) {
  const k = keyOf(name), l = letterOf(k);
  if (!(l in edhCache)) { try { const r = await fetch(`edhrec/${l}.json`); edhCache[l] = r.ok ? await r.json() : {}; } catch { edhCache[l] = {}; } }
  const entry = edhCache[l][k];
  if (!entry) return null;
  const index = new Map(entry.cards.map(card => [keyOf(card[0]), { name: card[0], inc: card[1], syn: card[2], cat: card[3], flags: card[4] }]));
  return { ...entry, index, short: entry.name.split(',')[0].split(' // ')[0] };
}
let landPool = null;
async function loadLandPool() {
  if (!landPool) { try { const r = await fetch('cards/lands.json'); landPool = r.ok ? (await r.json()).map(([name, ci, produced, tapped, usd, rank]) => ({ name, ci: ci.split(''), produced: produced.split(''), tapped, usd, rank })) : []; } catch { landPool = []; } }
  return landPool;
}

// ---------- Classification: the record's roles and flags, the commander's theme, the player's corrections ----------
function classify(card, theme, overrides) {
  const f = { ...card.baseF }; const tags = new Set(card.baseTags);
  const front = card.name.split(' // ')[0];
  f.gc = card.gc || RULES.gameChangers.includes(card.name) || RULES.gameChangers.includes(front);
  f.mld = RULES.massLandDenial.includes(card.name) || RULES.massLandDenial.includes(front);
  f.extraTurn = RULES.extraTurns.includes(card.name) || RULES.extraTurns.includes(front);
  f.themed = f.changeling || card.theme.some(w => theme.includes(w)) || (f.haste && theme.some(w => ['gowide', 'attack', 'token'].includes(w)));
  const o = overrides[card.name];
  if (o) { for (const r of ROLES) { if (o[r] === true) tags.add(r); if (o[r] === false) tags.delete(r); } }
  return { tags, f };
}
// The commander's plan: its creature types, the mechanics its text names, the tribes it names.
function commanderTheme(card) { return card ? card.theme.filter(w => w !== 'commander') : []; }

// ---------- Deck analysis ----------
// The deck's plan, read from the deck itself: the commander's own themes plus any theme a fifth of the nonland cards share.
const GENERIC_THEMES = new Set(['commander', 'draw', 'discard', 'counterspell', 'equipment', 'vehicle', 'saga', 'planeswalker']);
function deckPlan(deck, cards, commanderCard) {
  const counts = new Map(); let n = 0;
  for (const e of deck.entries) { const card = cards.get(e.name); if (!card || card.baseF.land) continue; n += e.qty; for (const w of new Set(card.theme)) counts.set(w, (counts.get(w) || 0) + e.qty); }
  const plan = new Set(commanderTheme(commanderCard).filter(w => !GENERIC_THEMES.has(w)));
  for (const [w, k] of counts) if (!GENERIC_THEMES.has(w) && n && k / n >= 0.2) plan.add(w);
  // A tribal deck (the commander's own creature type on 30%+ of the cards) also wants the "choose a creature type" cards.
  const types = commanderCard ? ((commanderCard.front_type || '').split('—')[1] || '').toLowerCase().trim().split(/\s+/) : [];
  if (types.some(w => n && (counts.get(w) || 0) / n >= 0.3)) { plan.add('tribal'); counts.set('tribal', Math.max(...types.map(w => counts.get(w) || 0))); }
  // Themes the deck does not actually carry (a commander's own creature types with no followers) drop out; the rest sort by weight.
  const themes = [...plan].filter(w => (counts.get(w) || 0) > 0).sort((x, y) => (counts.get(y) || 0) - (counts.get(x) || 0));
  return { themes, share: Object.fromEntries(themes.map(w => [w, counts.get(w) || 0])), nonland: n };
}
function analyseDeck(deck, cards, commanderCard, mode, overrides, commanderStrength, edh) {
  const plan = deckPlan(deck, cards, commanderCard);
  const theme = plan.themes;
  const rows = [];
  const c = { lands: 0, tapped: 0, ramp: 0, cheapRamp: 0, otherRamp: 0, creatureRamp: 0, draw: 0, targeted: 0, counters: 0, mass: 0, interaction: 0, instant: 0, tutors: 0, protection: 0, recursion: 0, creatures: 0, big: 0, evasive: 0, finishers: 0, themed: 0, free: 0, cheat: 0, reanimate: 0, ritual: 0, reduce: 0, gameChangers: 0, multiplayer: 0, cheap: 0, nonland: 0, mdfc: 0, fastMana: 0, plan: 0, combos: 0 };
  const curve = [0, 0, 0, 0, 0, 0, 0, 0], pipNeed = { W: 0, U: 0, B: 0, R: 0, G: 0 }, sources = { W: 0, U: 0, B: 0, R: 0, G: 0, any: 0 };
  const nonland = []; let mvTotal = 0;
  const removalMV = [];
  const names = new Set();
  const all = [...deck.entries];
  if (commanderCard) all.push({ name: commanderCard.name, qty: 1, isCommander: true });
  for (const e of all) {
    const card = cards.get(e.name); if (!card) continue;
    names.add(card.name); names.add(card.name.split(' // ')[0]);
    const { tags, f } = classify(card, theme, overrides);
    const row = { entry: e, card, tags, f, isCommander: !!e.isCommander, edh: edh && !e.isCommander ? edh.index.get(keyOf(card.name)) : undefined };
    rows.push(row);
    const q = e.qty;
    if (f.land || f.mdfc) { c.lands += q; if (f.mdfc) c.mdfc += q; c.tapped += (f.tapped || 0) * q;
      for (const col of (card.produced || [])) if (sources[col] != null) sources[col] += q;
      if (f.land && tags.has('ramp')) c.ramp += q, c.otherRamp += q;
      if (f.land) continue; }
    if (e.isCommander) { /* the commander is always available: count it as a plan card, not in the 99's roles */ }
    c.nonland += q; mvTotal += card.cmc * q; curve[Math.min(7, Math.round(card.cmc))] += q;
    for (const m of (card.mana_cost || '').matchAll(/\{([WUBRG])(?:\/[WUBRGP])?\}/g)) pipNeed[m[1]] += q;
    if (card.cmc <= 2) c.cheap += q;
    nonland.push({ mv: card.cmc, creature: f.creature, selfReduce: f.selfReduce, q });
    if (tags.has('ramp')) { c.ramp += q; const kind = f.creature ? 'creatureRamp' : card.cmc <= 2 ? 'cheapRamp' : 'otherRamp'; c[kind] += q; if (f.rock && !f.creature && card.cmc <= 2 && !f.land) { for (const col of (card.produced || [])) if (sources[col] != null) sources[col] += q; } }
    if (tags.has('draw')) c.draw += q;
    if (tags.has('removal') || tags.has('counter')) { c.targeted += q; if (tags.has('counter')) c.counters += q; c.interaction += q; removalMV.push(card.cmc); if (f.instantSpeed) c.instant += q; }
    if (tags.has('wipe')) { c.mass += q; if (!tags.has('removal') && !tags.has('counter')) { c.interaction += q * (POWER.norms.interaction.wipeFactor || 0.5); if (f.instantSpeed) c.instant += q; } }
    if (tags.has('tutor')) c.tutors += q;
    if (tags.has('protection')) c.protection += q;
    if (tags.has('recursion')) c.recursion += q;
    if (f.creature) { c.creatures += q; if (f.big) c.big += q; if (f.evasive) c.evasive += q; }
    if (tags.has('finisher')) c.finishers += q;
    if (!e.isCommander && f.themed) c.themed += q;
    const copies = e.isCommander ? (POWER.norms.cheats.commanderCopies || 3) : q;
    if (f.free) c.free += copies; if (f.cheat) c.cheat += copies; if (f.reanimate) c.reanimate += copies; if (f.ritual) c.ritual += copies; if (f.reduce) c.reduce += copies;
    if (f.gc) c.gameChangers += q;
    if (f.multiplayer) c.multiplayer += q;
    if (f.fastMana) c.fastMana += q;
    const staple = tags.has('ramp') || tags.has('draw') || tags.has('removal') || tags.has('counter') || tags.has('wipe');
    if (!staple && !e.isCommander) c.plan += q;
  }
  // Effective curve: big cards cost less when the deck cheats them out (docs/DECK_POWER.md).
  const k = POWER.norms.cheats;
  const share = enablers => k.maxShare * Math.min(1, enablers / k.saturation);
  const creatureShare = share(c.reduce + c.cheat + c.reanimate + c.free + c.ritual), otherShare = share(c.reduce + c.free + c.ritual);
  let total = 0, weight = 0;
  for (const n of nonland) {
    let eff = n.selfReduce ? Math.max(1, n.mv - k.selfDiscount) : n.mv;
    if (n.mv >= k.bigManaValue && eff > k.keep) eff -= (eff - k.keep) * (n.creature ? creatureShare : otherShare);
    total += eff * n.q; weight += n.q;
  }
  c.effectiveManaValue = weight ? total / weight : 0; c.manaValue = weight ? mvTotal / weight : 0; c.cheatShare = creatureShare;
  // Combos and bracket, as the app evaluates them (CommanderBrackets.swift).
  const combos = RULES.combos.filter(cb => cb.cards.every(n => names.has(n)));
  c.combos = combos.length;
  const gcs = rows.filter(r => r.f.gc).map(r => r.card.name), mld = rows.filter(r => r.f.mld).map(r => r.card.name), turns = rows.filter(r => r.f.extraTurn).map(r => r.card.name);
  let minimum = 2;
  if (gcs.length) minimum = Math.max(minimum, gcs.length <= 3 ? 3 : 4);
  if (mld.length) minimum = 4;
  if (turns.length >= RULES.chainedExtraTurns) minimum = 4;
  for (const cb of combos) minimum = Math.max(minimum, cb.early ? 4 : 3);
  const bracket = { minimum, gcs, mld, turns, combos };
  const ai = aiPower(c, commanderStrength);
  const table = tablePower({ ramp: c.ramp, draw: c.draw, targeted: c.targeted, fastMana: c.fastMana, tutors: c.tutors, gcs: c.gameChangers, combos: c.combos, effMV: c.effectiveManaValue, tappedShare: c.lands ? c.tapped / c.lands : 0, removalMV: removalMV.length ? removalMV.reduce((a, b) => a + b, 0) / removalMV.length : 3, lands: c.lands }, mode);
  // How typical the 99 is for this commander: average EDHREC inclusion over the nonbasic cards (absent from its lists counts 0).
  let edhFit = null;
  if (edh) {
    const judged = rows.filter(r => !r.isCommander && !/^Basic Land/.test(r.card.front_type));
    const listed = judged.filter(r => r.edh);
    const total = judged.reduce((s, r) => s + r.entry.qty, 0);
    edhFit = { avgInc: total ? Math.round(listed.reduce((s, r) => s + r.edh.inc * r.entry.qty, 0) / total) : 0, listed: listed.reduce((s, r) => s + r.entry.qty, 0), total,
      avgSyn: listed.length ? Math.round(listed.reduce((s, r) => s + r.edh.syn, 0) / listed.length) : 0 };
  }
  return { rows, counts: c, curve, pipNeed, sources, bracket, ai, table, theme, plan, removalMV, edh, edhFit };
}
function aiPower(c, commanderStrength) {
  const n = POWER.norms, w = POWER.weights;
  const idealLands = n.mana.idealLands - n.mana.landsPerRamp * c.ramp;
  const parts = {
    speed: mix([lin(c.effectiveManaValue, n.speed.effectiveManaValue), lin(c.cheap, n.speed.cheapPlays)], n.speed.mix),
    mana: mix([lin(c.cheapRamp * n.mana.cheapRampFactor + c.otherRamp + c.creatureRamp * n.mana.creatureRampFactor, n.mana.ramp), 1 - Math.min(1, Math.abs(c.lands - idealLands) / n.mana.landSpread), 1 - lin(c.tapped / Math.max(1, c.lands), n.mana.tappedShare)], n.mana.mix),
    interaction: lin(c.interaction + n.interaction.instantBonus * c.instant, n.interaction.count),
    consistency: mix([lin(c.draw, n.consistency.draw), lin(c.tutors, n.consistency.tutors)], n.consistency.mix),
    threats: mix([lin(c.evasive, n.threats.evasive), lin(c.big, n.threats.big), lin(c.finishers, n.threats.finishers), lin(c.creatures, n.threats.creatures)], n.threats.mix),
    synergy: lin(c.themed / Math.max(1, c.nonland), n.synergy.themeShare),
    commander: commanderStrength,
    combos: lin(c.combos * n.combos.comboPoints + Math.min(c.gameChangers, n.combos.gameChangersFull) + n.combos.gameChangerBeyond * Math.max(0, c.gameChangers - n.combos.gameChangersFull), n.combos.points),
    resilience: mix([lin(c.protection, n.resilience.protection), lin(c.recursion, n.resilience.recursion)], n.resilience.mix),
  };
  const totalW = PARTS.reduce((a, p) => a + w[p], 0);
  const penalty = Math.min(POWER.penalties.multiplayerCards.max, POWER.penalties.multiplayerCards.perCard * c.multiplayer);
  return { parts, penalty, power: Math.max(1, Math.min(10, 1 + 9 * PARTS.reduce((a, p) => a + parts[p] * w[p], 0) / totalW - penalty)) };
}
function tablePower(i, mode) {
  const T = TEMPLATES[mode];
  const cover = (n, [lo, hi]) => Math.min(1.2, n / hi);
  const d = {};
  d.ramp = 0.5 * cover(i.ramp, T.ramp) - 0.25;      // −0.25 at none, +0.25 at target, +0.35 over
  d.draw = 0.5 * cover(i.draw, T.draw) - 0.25;
  d.removal = 0.5 * cover(i.targeted, T.targeted) - 0.25;
  d.fastMana = Math.min(1.5, 0.3 * i.fastMana);
  d.tutors = Math.min(1.5, 0.25 * i.tutors);
  d.gcs = Math.min(3, 0.4 * Math.min(3, i.gcs) + 0.6 * Math.max(0, i.gcs - 3));
  d.combos = Math.min(2, 1.0 * i.combos);
  d.curve = Math.max(-1, Math.min(0.8, (3.4 - i.effMV) / 1.0));
  d.tapped = i.tappedShare > 0.25 ? -0.5 : i.tappedShare < 0.1 ? 0.3 : 0;
  d.cheapRemoval = i.removalMV <= 2 ? 0.3 : i.removalMV >= 3.5 ? -0.2 : 0;
  d.lands = i.lands < 33 ? -0.4 : 0;
  const power = Math.max(1, Math.min(10, 4 + Object.values(d).reduce((a, b) => a + b, 0)));
  return { parts: d, power };
}
const bandOf = p => p < 2.5 ? 'Exhibition' : p < 4.5 ? 'Core' : p < 6.5 ? 'Upgraded' : p < 8.5 ? 'Optimized' : 'cEDH';
function tierOf(p) {
  for (const t of POWER.ladder.tiers) if (p >= t.power[0] && p < t.power[1]) return t.name;
  return p < 3 ? 'below Bronze' : 'above Mythic';
}

// ---------- Cuts ----------
function cutCandidates(a, mode, useEdh = true) {
  const T = TEMPLATES[mode]; const c = a.counts;
  const over = { ramp: c.ramp > T.ramp[1], draw: c.draw > T.draw[1], targeted: c.targeted > T.targeted[1], mass: c.mass > T.mass[1], lands: c.lands > T.lands[1] + 1 };
  const narrow = ['overrun', 'extraCombat', 'anthem', 'haste', 'doubler'];
  const narrowRows = {}; for (const k of narrow) narrowRows[k] = a.rows.filter(r => !r.isCommander && r.f[k]).sort((x, y) => x.card.cmc - y.card.cmc);
  const out = [];
  for (const r of a.rows) {
    if (r.isCommander) continue;
    const { card, tags, f } = r; const reasons = []; let score = 0;
    if (f.land || f.mdfc) { if (over.lands && !f.mdfc && !tags.has('ramp') && !tags.has('draw')) { score += 1.5; reasons.push(`lands over target (${c.lands}/${T.lands[1]}): cut a land last, or make it an MDFC`); } else { out.push({ row: r, score: -1, reasons: ['land'], protectedBy: 'land' }); continue; } }
    const staple = tags.has('ramp') ? 'ramp' : tags.has('draw') ? 'draw' : (tags.has('removal') || tags.has('counter')) ? 'targeted' : tags.has('wipe') ? 'mass' : null;
    if (staple && !over[staple]) { out.push({ row: r, score: -1, reasons: [`${staple === 'targeted' ? 'removal' : staple} (${staple === 'targeted' ? c.targeted : c[staple]}/${T[staple][1]})`], protectedBy: staple }); continue; }
    if (staple && over[staple]) { score += 1; reasons.push(`${staple === 'targeted' ? 'removal' : staple} over target (${staple === 'targeted' ? c.targeted : c[staple]}/${T[staple][1]}): keep the cheapest and cleanest`); }
    if (tags.has('engine')) {
      const feeders = Math.max(0, ...card.theme.filter(w => a.theme.includes(w)).map(w => a.plan.share[w] || 0));
      if (feeders >= 15) { score += f.creature ? 0.25 : 0.5; reasons.push(`its engine is your plan: ${feeders} cards feed it`); }
      else { score += f.creature ? 1 : 2; reasons.push(f.creature ? 'a body, but its text needs a board state' : 'needs a board state before it does anything'); }
    }
    if (!tags.has('finisher')) {
      const discount = f.creature ? c.cheatShare : Math.min(c.cheatShare, 0.3);
      if (card.cmc >= 6) { score += 2 * (1 - discount); reasons.push(discount > 0.2 ? `${card.cmc} mana (the deck cheats some of that)` : `${card.cmc} mana: does it win on its own?`); }
      else if (card.cmc >= 5) { score += 1 * (1 - discount); reasons.push('5 mana: it has to do a lot'); }
    } else { score -= 1.5; reasons.push('finisher: keep the best one or two'); }
    for (const k of narrow) { const list = narrowRows[k]; const idx = list.indexOf(r); if (idx >= 2) { score += 1; reasons.push(`${ordinal(idx + 1)} ${({ overrun: 'overrun', extraCombat: 'extra-combat', anthem: 'anthem', haste: 'haste enabler', doubler: 'doubler' })[k]} effect`); } }
    if (!f.themed && !staple && !tags.has('finisher') && !tags.has('protection') && !tags.has('tutor') && !tags.has('recursion') && a.theme.length) { score += 1; reasons.push(`off your deck's plan (${a.theme.slice(0, 3).join(', ')})`); }
    if (f.multiplayer) { if (mode === 'duel') { score += 1.5; reasons.push('weak with one opponent'); } else { reasons.push('table politics card'); } }
    if (f.conditional && !staple) { score += 0.5; reasons.push('conditional wording'); }
    const shared = card.theme.filter(w => a.theme.includes(w)).sort((x, y) => (a.plan.share[y] || 0) - (a.plan.share[x] || 0));
    if (f.themed && !staple && shared.length) { score -= 0.5; reasons.push(`on plan: ${shared[0]}, like ${a.plan.share[shared[0]] || 0} of your cards`); }
    if (card.cmc <= 2 && !tags.has('engine')) score -= 0.5;
    if (tags.has('tutor') || f.fastMana) { score -= 1; reasons.push(tags.has('tutor') ? 'tutor: finds the plan' : 'fast mana'); }
    // EDHREC is a tie-breaker only: at most half a point either way, shown apart from the deck's own reasons.
    let edhNudge = 0, edhNote = '';
    if (a.edh) {
      const who = a.edh.short;
      if (r.edh) { edhNudge = r.edh.inc < 5 ? 0.5 : r.edh.inc < 15 ? 0.25 : r.edh.inc >= 40 ? -0.5 : r.edh.inc >= 25 ? -0.25 : 0; edhNote = `EDHREC: in ${r.edh.inc}% of ${who} decks`; }
      else { edhNudge = 0.25; edhNote = `EDHREC: not in ${who}'s lists`; }
    } else if (card.rank) { edhNudge = card.rank > 30000 ? 0.25 : 0; edhNote = `EDHREC #${card.rank.toLocaleString()} overall`; }
    if (!useEdh) edhNudge = 0;
    out.push({ row: r, score: score + edhNudge, deckScore: score, edhNudge, edhNote, reasons });
  }
  return out;
}
const ordinal = n => n + (['th', 'st', 'nd', 'rd'][(n % 100 > 10 && n % 100 < 14) ? 0 : Math.min(n % 10, 4) % 4] || 'th');

// ---------- Levers ----------
function levers(a, mode, commanderStrength) {
  const c = a.counts; const base = aiPower(c, commanderStrength).power; const t0 = a.table.power;
  const tbl = patch => tablePower({ ramp: c.ramp, draw: c.draw, targeted: c.targeted, fastMana: c.fastMana, tutors: c.tutors, gcs: c.gameChangers, combos: c.combos, effMV: c.effectiveManaValue, tappedShare: c.lands ? c.tapped / c.lands : 0, removalMV: a.removalMV.length ? a.removalMV.reduce((x, y) => x + y, 0) / a.removalMV.length : 3, lands: c.lands, ...patch }, mode).power;
  const ai = patch => aiPower({ ...c, ...patch }, commanderStrength).power;
  const curveAfter = (cut, mvFrom, mvTo) => Math.max(1, (c.effectiveManaValue * c.nonland - cut * mvFrom + cut * mvTo) / c.nonland);
  const list = [
    ['Add two cheap mana rocks (for two plan cards)', ai({ ramp: c.ramp + 2, cheapRamp: c.cheapRamp + 2, cheap: c.cheap + 2, plan: c.plan - 2 }), tbl({ ramp: c.ramp + 2 })],
    ['Swap four tapped lands for untapped ones', ai({ tapped: Math.max(0, c.tapped - 4) }), tbl({ tappedShare: Math.max(0, c.tapped - 4) / Math.max(1, c.lands) })],
    ['Add two tutors', ai({ tutors: c.tutors + 2 }), tbl({ tutors: c.tutors + 2 })],
    ['Add three instant-speed removal spells', ai({ interaction: c.interaction + 3, instant: c.instant + 3, targeted: c.targeted + 3 }), tbl({ targeted: c.targeted + 3, removalMV: 2 })],
    ['Cut three 6-drops for three 2-drops', ai({ effectiveManaValue: curveAfter(3, 6, 2), cheap: c.cheap + 3 }), tbl({ effMV: curveAfter(3, 6, 2) })],
    ['Add two evasive 5-power creatures', ai({ evasive: c.evasive + 2, big: c.big + 2, creatures: c.creatures + 2 }), t0],
    ['Add three draw spells', ai({ draw: c.draw + 3 }), tbl({ draw: c.draw + 3 })],
    ['Add one fast-mana piece (Game Changer)', ai({ gameChangers: c.gameChangers + 1, cheapRamp: c.cheapRamp + 1, ramp: c.ramp + 1 }), tbl({ fastMana: c.fastMana + 1, gcs: c.gameChangers + 1, ramp: c.ramp + 1 })],
    ['Add one two-card combo', ai({ combos: c.combos + 1 }), tbl({ combos: c.combos + 1 })],
  ];
  return list.map(([label, p, t]) => ({ label, dAI: p - base, dTable: t - t0 }));
}

