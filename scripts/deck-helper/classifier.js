// Build-time card classifier for the Deck Helper test bed: rules over oracle text, run once over Scryfall's bulk
// file, so the page itself only does arithmetic (the app bakes its roles into the catalogue the same way).
'use strict';

const FLAGS = ['land', 'mdfc', 'creature', 'instantSpeed', 'rock', 'dork', 'ritual', 'treasure', 'cantrip', 'engineStatic', 'immediate', 'evasive', 'big', 'haste', 'overrun', 'extraCombat', 'anthem', 'doubler', 'tokens', 'multiplayer', 'conditional', 'free', 'cheat', 'reanimate', 'selfReduce', 'reduce', 'fastMana', 'changeling', 'legendary'];
const TAGS = ['ramp', 'draw', 'removal', 'counter', 'wipe', 'tutor', 'protection', 'recursion', 'finisher', 'engine'];
const FAST_MANA = new Set(['Sol Ring', 'Mana Vault', 'Chrome Mox', 'Mox Diamond', 'Mox Opal', 'Mox Amber', 'Grim Monolith', 'Ancient Tomb', 'Lotus Petal', 'Dark Ritual', 'Cabal Ritual', "Jeska's Will", 'Simian Spirit Guide', 'Elvish Spirit Guide', 'Mana Crypt', 'Jeweled Lotus', "Lion's Eye Diamond", 'Rite of Flame', 'Seething Song', 'Treasonous Ogre', 'City of Traitors', 'Gemstone Caverns', 'Culling the Weak', 'Basalt Monolith', 'Thran Dynamo', 'Gilded Lotus', 'Mana Drain', 'Mox Tantalite']);

const RX = {
  tapped: /enters (the battlefield )?tapped/i,
  tappedConditional: /enters (the battlefield )?tapped unless|unless you control|if you control (two|three)|as (it|~|this land) enters, you may|you may pay \d+ life/i,
  rock: /^(\{[0-9]\}, )?\{t\}(, [^:]+)?: add (\{[wubrgc]\}|one mana of any color|\{c\}|two mana|an amount of)|^sacrifice (a|an|another) \w+: add \{/im,
  landRamp: /search your library for (a|an|up to \w+|two|x) ((basic|forest|plains|island|swamp|mountain|snow)[^.]*?)?lands? cards?[^.]*?put (it|them|one of them|that card|those cards|one onto the battlefield|them onto the battlefield)[^.]*?onto the battlefield|put (a|target|up to \w+) land cards? from your hand onto the battlefield/i,
  treasure: /create (a|two|three|x|that many) treasure tokens?/i,
  ritual: /^add \{[wubrgc]\}\{[wubrgc]\}|^add \{[wubrgc]\} for each|add (three|four|five|six|seven|eight|an amount of) mana|^add \{[wubrgc]\}\{[wubrgc]\}\{[wubrgc]\}/im,
  draw: /draws? (two|three|four|five|six|seven|x|that many|\d+) cards?|cast [^.]*spells? from the top of your library|reveal the top card[^.]*put it into your hand|draw cards equal|whenever[^.]*, draw a card|whenever[^.]*, you may draw a card|you may play (that card|it|them|those cards)|may play lands and cast spells from the top|look at the top \w+ cards[^.]*put (one|two|one of them|up to)[^.]*into your hand|investigate|reveal cards from the top[^.]*into your hand|each (player|opponent) draws|draw a card for each|draw a card at the beginning|draw an additional card|draws? a card\. then|^draw a card, then|draw a card and|draw a card if|draw a card unless/i,
  cantrip: /^draw a card\.?$|\ndraw a card\.?$/im,
  removal: /(destroy|exile) target (creature|artifact|enchantment|permanent|nonland permanent|planeswalker|land|nonbasic land|attacking|blocking|tapped|creature or|artifact or|enchantment or|noncreature)(?![^.]*you control)|deals? (\d+|x|that much|damage equal) damage to (any target|target creature|target creature or planeswalker|target creature or player|target creature an opponent|target attacking|target blocking|each creature target)|target creature (gets|an opponent controls gets) -\d+\/-\d+|-x\/-x|return target (creature|nonland permanent|permanent|artifact|enchantment)[^.]*to (its|their) owner's hand|target creature[^.]*fights?|(fights?|deals? damage equal to its power to) target creature|target (player|opponent) sacrifices a (creature|permanent)|target creature's controller sacrifices|exile target (nonland permanent|creature|permanent)[^.]*(an opponent controls|you don't control)|destroy target (creature|permanent)[^.]*(an opponent controls|you don't control)|counter target|target (permanent|creature)[^.]*(shuffles it into|into (its|their) owner's library)|gain control of target (creature|permanent|artifact|enchantment)/i,
  counter: /counter target (spell|noncreature spell|creature spell|activated ability|instant or sorcery spell|activated or triggered)/i,
  wipe: /(destroy|exile) all (creatures|artifacts|enchantments|nonland permanents|permanents|other creatures|other nonland|artifacts and enchantments|creatures and planeswalkers)|each (player|opponent) sacrifices (all|half|each|two|three|a creature)|deals? \d+ damage to each (creature|opponent and each creature|creature and each)|all creatures get -\d+\/-\d+|return all (nonland |other )?(creatures|permanents|nonland permanents)[^.]*to their owners' hands|creatures (your opponents control|you don't control) get -\d+|destroy all (nonbasic )?lands|each creature (deals damage to itself|gets -)/i,
  tutor: /search your library for (a|an|up to \w+|two|x|any number of) ((?!land|basic)[^.])*?card(s)?[^.]*?(into your hand|reveal (it|them)|onto the battlefield|on top of your library)|search your library for a card,/i,
  landTutor: /search your library for (a|an|up to \w+)[^.]*?land/i,
  protection: /(gain|have|has|gains) (hexproof|indestructible|shroud|protection from|ward)|change the target|choose new targets|(equipped|enchanted) creature (has|gets|gains)[^.]*(hexproof|shroud|indestructible|protection from)|phase out|can't be countered|\bregenerate\b|hexproof and indestructible until end of turn|counter target spell that targets|return[^.]*you control[^.]*to (its|their) owner's hand\. (reveal|if)|prevent all (combat )?damage that would be dealt to (creatures|permanents) you control/i,
  recursion: /return (target|all|up to \w+|any number of|each) [^.]*cards? from your graveyard to (your hand|the battlefield)|from your graveyard (onto|to) the battlefield|return [^.]*creature card[^.]*from (your|a) graveyard/i,
  finisher: /creatures you control (get \+x|get \+\d+\/\+\d+ until end of turn|gain (trample|double strike|flying|haste) until)|additional combat phase|each opponent loses (x|half|that much|[3-9]|\d\d) life|you win the game|infect|deals? damage equal to (the number of|its power to each opponent)|for each creature you control, (it|~) deals|opponents? loses? life equal to|double the power/i,
  evasion: /(^|\n)[^.\n]*\b(flying|trample|menace|shadow|intimidate|fear|horsemanship|skulk|unblockable)\b[^.\n]*$|can't be blocked/im,
  haste: /creatures you control have haste|other creatures you control have haste|creatures you control gain haste/i,
  engineStatic: /^(other )?(creatures|\w+s|\w+ creatures|permanents|tokens|spells) you control (get|have|cost|enter|can't be)|^other \w+( creatures)? (get|have) |^(creatures|\w+) you control (get|have) \+|^whenever (a|an|another|one or more)[^.]*you control|^whenever you (cast|create|sacrifice|gain life|draw|attack)|^at the beginning of (your|each)|^as long as you control|for each (creature|other|artifact|enchantment|\w+) you control|^if (a|an|one or more)[^.]*would (enter|die|be created)[^.]*instead|double (the number of|that many)|twice that many/im,
  immediate: /^when (~|this creature|this permanent|this artifact|this enchantment|this land) enters|^(~|this \w+) enters (the battlefield )?with|^when you cast (~|this spell)|^\{t\}|^\{[0-9wubrgcx]+\}[^:]*:|^sacrifice ~:|^\{[0-9]\}, \{t\}:|^cast this spell|^flash\b/im,
  multiplayer: /\bgoad|myriad|each player draws|unless (that player|they|its controller|an opponent) pays?|will of the council|council's dilemma|\btempt\b|each opponent may draw|each other player (may|discards)|each player (may )?(creates|gains|draws|puts)|all players|each opponent[^.]*(may|chooses)/i,
  conditional: /unless|you may pay|you may reveal|if you control|only if|if you (have|cast|attacked)|as long as/i,
  free: /cascade|discover \d|ripple|without paying (its|their) mana cost/i,
  cheat: /put (a|an|any number of|up to \w+|that|those|target)[^.]*?(creature|permanent|dragon|dinosaur|elf|goblin|zombie|vampire|angel|demon)[^.]*?cards?[^.]*? onto the battlefield|search your library for [^.]*creature cards?[^.]* put (it|them|that card) onto the battlefield/i,
  reanimate: /(return|put) target creature card[^.]*graveyard[^.]*(to|onto) the battlefield|creature cards? from (your|a|all) graveyards?[^.]*onto the battlefield/i,
  selfReduce: /convoke|affinity for|delve|improvise|(this spell|~) costs? \{\w+\} less/i,
  bigReduce: /spells? you cast costs? \{\d\} less|spells? (you cast )?cost \{\d\} less/i,
  tokens: /create (a|an|two|three|four|x|that many)[^.]*token/i,
  overrun: /creatures you control (get \+x\/\+x|get \+\d+\/\+\d+ until end of turn|gain trample)/i,
  extraCombat: /additional combat phase/i,
  anthem: /^(other )?(creatures|\w+s|\w+ creatures) you control get \+\d+\/\+\d+(\.| and)|^other \w+( creatures)? get \+\d+\/\+\d+/im,
  doubler: /double (the number of|that many)|twice that many|create a token that's a copy|would create one or more tokens[^.]*instead/i,
};
const MECHANICS = [[/\btokens?\b/, 'token'], [/\+1\/\+1 counter/, 'counter+1'], [/sacrifice/, 'sacrifice'], [/graveyard/, 'graveyard'], [/\bartifacts?\b/, 'artifact'], [/\benchantments?\b/, 'enchantment'], [/instant or sorcery|noncreature spell|prowess|magecraft/, 'spells'], [/gains? (\d+|x|that much|life equal)[^.]*life|gain life|gains life|lifelink|life you gained|you gain life/, 'lifegain'], [/\bequip/, 'equip'], [/\baura\b|enchanted creature/, 'aura'], [/\bdraw/, 'draw'], [/discard/, 'discard'], [/treasure/, 'treasure'], [/landfall|whenever a land (you control )?enters|lands you control|land cards? from your graveyard/, 'landfall'], [/counter target/, 'counterspell'], [/commander/, 'commander'],
  [/create [^.]*creature tokens?|whenever (a|another|one or more) (other )?(nontoken )?creatures? (you control )?enters?|(other )?creatures you control get \+|for each (other )?creature you control|for each (other )?attacking creature/, 'gowide'],
  [/whenever [^.]*(attacks|deals combat damage)|attacking creatures?|additional combat/, 'attack'],
  [/choose a creature type|of the chosen type|shares? a creature type|creature type of your choice/, 'tribal'],
  [/deals? (\d+|x|that much|that many|double|twice|damage equal)[^.]*damage|noncombat damage|damage to (an|each|target|that) opponent|would deal damage[^.]*instead|damage (dealt|is dealt) to (an|each) opponent/, 'damage']];
const TRIBES = /\b(dragon|goblin|elf|elves|zombie|vampire|dinosaur|sliver|human|angel|demon|wizard|warrior|knight|soldier|cat|dog|bird|merfolk|pirate|rat|spirit|elemental|beast|hydra|wolf|faerie|rogue|cleric|shaman|druid|giant|treefolk|insect|squirrel|ooze|horror|phyrexian|samurai|ninja|kor|dwarf|golem|myr|thopter|construct|wall|frog|snake|skeleton|vehicle|equipment|saga|planeswalker)s?\b/g;

const escapeRx = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function clean(frontName, oracle) { return (oracle || '').replace(new RegExp(escapeRx(frontName), 'g'), '~').replace(/\(([^)]*)\)/g, ''); }

/** A Scryfall card object -> the compact record the page reads. Returns null for cards the helper ignores. */
function classify(c) {
  if (!c.legalities || c.legalities.commander !== 'legal') return null;
  if (['token', 'double_faced_token', 'emblem', 'art_series', 'augment', 'host', 'planar', 'scheme', 'vanguard'].includes(c.layout)) return null;
  const faces = c.card_faces && c.card_faces.length ? c.card_faces : [c];
  const front = faces[0];
  const frontName = front.name || c.name;
  const frontType = front.type_line || c.type_line || '';
  const oracle = faces.map(f => f.oracle_text || '').join('\n');
  const frontIsLand = /\bland\b/.test((faces[0].type_line || '').toLowerCase().split('—')[0]);
  // Roles come from the spell faces: a land on the back of an MDFC or a transforming god is not a mana rock.
  const roleText = frontIsLand ? oracle : faces.filter(f => !/\bLand\b/.test(f.type_line || '')).map(f => f.oracle_text || '').join('\n');
  const t = clean(frontName, roleText);
  const types = frontType.toLowerCase();
  const f = {}, tags = new Set();
  f.land = /\bland\b/.test(types.split('—')[0]);
  f.mdfc = c.layout === 'modal_dfc' && faces.length > 1 && /land/i.test(faces[1].type_line || '') && !f.land;
  f.creature = /\bcreature\b/.test(types);
  f.legendary = /\blegendary\b/.test(types);
  f.instantSpeed = /\binstant\b/.test(types) || /^flash\b/im.test(t);
  f.changeling = /changeling/i.test(t);
  const powerNum = front.power != null && /^-?\d+$/.test(front.power) ? parseInt(front.power, 10) : 0;
  let tapped = 0;
  if (f.land) {
    tapped = RX.tapped.test(t) ? (RX.tappedConditional.test(t) ? 0.5 : 1) : 0;
    if (RX.landRamp.test(t) && /sacrifice ~/i.test(t)) tags.add('ramp');
    if (RX.draw.test(t) && !/cycling/i.test(t)) tags.add('draw');
  } else {
    const ramp = (RX.rock.test(t) && !/^\{t\}: add \{[wubrgc]\}\. spend this mana only/im.test(t)) || RX.landRamp.test(t) || RX.treasure.test(t) || (RX.ritual.test(t) && /instant|sorcery/.test(types));
    if (ramp) tags.add('ramp');
    f.rock = RX.rock.test(t) && !f.creature; f.dork = RX.rock.test(t) && f.creature; f.ritual = RX.ritual.test(t) && /instant|sorcery/.test(types); f.treasure = RX.treasure.test(t);
    if (RX.draw.test(t) && !/cycling \{/i.test(t)) tags.add('draw');
    f.cantrip = !tags.has('draw') && RX.cantrip.test(t);
    if (RX.counter.test(t)) tags.add('counter');
    if (RX.removal.test(t) && !RX.counter.test(t)) tags.add('removal');
    if (RX.wipe.test(t)) { tags.add('wipe'); if (tags.has('removal') && !/target/i.test(t)) tags.delete('removal'); }
    if (RX.tutor.test(t) && !(RX.landTutor.test(t) && !/creature|artifact|enchantment|instant|sorcery|card with/i.test(t))) tags.add('tutor');
    if (RX.protection.test(t) && !/protection from (red|white|blue|black|green|all colors|each color|everything)\b(?![^.]*(you control|target))/i.test(t)) tags.add('protection');
    if (RX.recursion.test(t)) tags.add('recursion');
    if (RX.finisher.test(t) || (f.creature && powerNum >= 7 && RX.evasion.test(t))) tags.add('finisher');
    f.engineStatic = RX.engineStatic.test(t);
    f.immediate = RX.immediate.test(t) || /instant|sorcery/.test(types) || tags.has('ramp') || tags.has('draw') || tags.has('removal') || tags.has('counter') || tags.has('wipe') || tags.has('tutor') || (f.creature && powerNum >= 3) || (RX.tokens.test(t) && /^when ~ enters|^enters/im.test(t));
    if (f.engineStatic && !f.immediate && !tags.has('finisher')) tags.add('engine');
    f.evasive = f.creature && RX.evasion.test(t);
    f.big = f.creature && powerNum >= 5;
    f.haste = RX.haste.test(t); f.overrun = RX.overrun.test(t); f.extraCombat = RX.extraCombat.test(t); f.anthem = RX.anthem.test(t); f.doubler = RX.doubler.test(t); f.tokens = RX.tokens.test(t);
    f.multiplayer = RX.multiplayer.test(t); f.conditional = RX.conditional.test(t);
    f.free = RX.free.test(t); f.cheat = RX.cheat.test(t); f.reanimate = RX.reanimate.test(t); f.selfReduce = RX.selfReduce.test(t); f.reduce = RX.bigReduce.test(t) && !f.selfReduce;
    f.fastMana = FAST_MANA.has(c.name) || FAST_MANA.has(frontName);
  }
  // Theme tokens: creature subtypes, mechanics and tribes the text names. A card is on a commander's plan when they share one.
  const theme = new Set();
  const sub = frontType.split('—')[1];
  if (sub) for (const w of sub.trim().toLowerCase().split(/\s+/)) if (w.length > 2) theme.add(w);
  const lower = oracle.toLowerCase();
  for (const [rx, word] of MECHANICS) if (rx.test(lower)) theme.add(word);
  for (const m of lower.matchAll(TRIBES)) theme.add(m[1] === 'elves' ? 'elf' : m[1]);
  let flagBits = 0; FLAGS.forEach((k, i) => { if (f[k]) flagBits |= (1 << i); });
  let tagBits = 0; TAGS.forEach((k, i) => { if (tags.has(k)) tagBits |= (1 << i); });
  const produced = (c.produced_mana || []).filter(x => 'WUBRG'.includes(x)).join('');
  const usd = c.prices && (parseFloat(c.prices.usd) || parseFloat(c.prices.usd_foil) || parseFloat(c.prices.usd_etched)) || 0;
  return [c.name, c.cmc || 0, frontType, front.mana_cost || c.mana_cost || '', (c.color_identity || []).join(''), f.creature ? powerNum : null, produced,
    c.edhrec_rank || 0, c.game_changer ? 1 : 0, flagBits, tagBits, [...theme].join('|'), tapped, Math.round(usd * 100) / 100, c.id || ''];
}

module.exports = { classify, FLAGS, TAGS, RX, FAST_MANA };
