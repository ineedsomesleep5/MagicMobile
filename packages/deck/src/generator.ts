import type { BracketScore, CardIdentity, ColorSymbol, DeckEntry, DeckList, DeckStats } from "@magicmobile/shared";
import { CommanderDeckAnalyzer } from "./analyzer";

type GeneratedCard = CardIdentity & {
  manaCost?: string;
  colors?: ColorSymbol[];
  legalities?: { commander?: "legal" | "not_legal" | "banned" | "unknown" };
};

export interface GenerateCommanderDeckInput {
  seed?: string;
  playerId?: string;
}

export interface GeneratedCommanderDeck {
  deck: DeckList;
  cardPool: GeneratedCard[];
  validationErrors: string[];
  stats: DeckStats;
  bracket: BracketScore;
  source: "generated";
}

const analyzer = new CommanderDeckAnalyzer();
const commanderName = "Ezuri, Renegade Leader";
const basicLandName = "Forest";
const basicLandCount = 36;
const nonCommanderCardCount = 99 - basicLandCount;

const requiredNames = new Set([
  "Sol Ring",
  "Arcane Signet",
  "Llanowar Elves",
  "Elvish Mystic",
  "Fyndhorn Elves",
  "Birds of Paradise",
  "Priest of Titania",
  "Elvish Archdruid",
  "Cultivate",
  "Kodama's Reach",
  "Beast Whisperer",
  "Guardian Project",
  "Harmonize",
  "Return of the Wildspeaker",
  "Rishkar's Expertise",
  "Garruk's Uprising",
  "Beast Within",
  "Krosan Grip",
  "Reclamation Sage",
  "Acidic Slime",
  "Nature's Claim",
  "Kenrith's Transformation",
  "Bane of Progress",
  "Heroic Intervention",
  "Craterhoof Behemoth",
  "Overwhelming Stampede"
]);

export const generatedCommanderCardPool: GeneratedCard[] = [
  card(commanderName, 3, "Legendary Creature — Elf Warrior", "{1}{G}{G}", "Other Elf creatures you control get +1/+1. {G}: Regenerate another target Elf. {2}{G}{G}{G}: Elf creatures you control get +3/+3 and gain trample until end of turn."),
  basicLand(basicLandName, "G"),
  artifact("Sol Ring", 1, "{1}", "{T}: Add {C}{C}."),
  artifact("Arcane Signet", 2, "{2}", "{T}: Add one mana of any color in your commander's color identity."),
  artifact("Swiftfoot Boots", 2, "{2}", "Equipped creature has hexproof and haste."),
  artifact("Lightning Greaves", 2, "{2}", "Equipped creature has haste and shroud."),
  artifact("Skullclamp", 1, "{1}", "Whenever equipped creature dies, draw a card."),
  artifact("Lifecrafter's Bestiary", 3, "{3}", "Whenever you cast a creature spell, you may pay {G}. If you do, draw a card."),
  artifact("Staff of Domination", 3, "{3}", "{1}: Untap Staff of Domination. {5}: Draw a card."),
  artifact("Umbral Mantle", 3, "{3}", "Equipped creature has '{3}, Untap this creature: It gets +2/+2 until end of turn.'"),
  artifact("Thousand-Year Elixir", 3, "{3}", "You may activate abilities of creatures you control as though those creatures had haste."),
  card("Llanowar Elves", 1, "Creature — Elf Druid", "{G}", "{T}: Add {G}."),
  card("Elvish Mystic", 1, "Creature — Elf Druid", "{G}", "{T}: Add {G}."),
  card("Fyndhorn Elves", 1, "Creature — Elf Druid", "{G}", "{T}: Add {G}."),
  card("Birds of Paradise", 1, "Creature — Bird", "{G}", "{T}: Add one mana of any color."),
  card("Joraga Treespeaker", 1, "Creature — Elf Druid", "{G}", "{T}: Add {G}{G}."),
  card("Priest of Titania", 2, "Creature — Elf Druid", "{1}{G}", "{T}: Add {G} for each Elf on the battlefield."),
  card("Elvish Archdruid", 3, "Creature — Elf Druid", "{1}{G}{G}", "Other Elf creatures you control get +1/+1. {T}: Add {G} for each Elf you control."),
  card("Marwyn, the Nurturer", 3, "Legendary Creature — Elf Druid", "{2}{G}", "{T}: Add an amount of {G} equal to Marwyn's power."),
  card("Circle of Dreams Druid", 3, "Creature — Elf Druid", "{G}{G}{G}", "{T}: Add {G} for each creature you control."),
  card("Sakura-Tribe Elder", 2, "Creature — Snake Shaman", "{1}{G}", "Sacrifice Sakura-Tribe Elder: Search your library for a basic land card, put that card onto the battlefield tapped, then shuffle."),
  card("Wood Elves", 3, "Creature — Elf Scout", "{2}{G}", "When Wood Elves enters, search your library for a Forest card, put that card onto the battlefield, then shuffle."),
  card("Farhaven Elf", 3, "Creature — Elf Druid", "{2}{G}", "When Farhaven Elf enters, search your library for a basic land card, put it onto the battlefield tapped, then shuffle."),
  card("Springbloom Druid", 3, "Creature — Elf Druid", "{2}{G}", "When Springbloom Druid enters, you may sacrifice a land. If you do, search your library for up to two basic land cards."),
  card("Cultivate", 3, "Sorcery", "{2}{G}", "Search your library for up to two basic land cards, put one onto the battlefield tapped and the other into your hand, then shuffle."),
  card("Kodama's Reach", 3, "Sorcery", "{2}{G}", "Search your library for up to two basic land cards, put one onto the battlefield tapped and the other into your hand, then shuffle."),
  card("Rampant Growth", 2, "Sorcery", "{1}{G}", "Search your library for a basic land card, put that card onto the battlefield tapped, then shuffle."),
  card("Nature's Lore", 2, "Sorcery", "{1}{G}", "Search your library for a Forest card, put that card onto the battlefield, then shuffle."),
  card("Three Visits", 2, "Sorcery", "{1}{G}", "Search your library for a Forest card, put that card onto the battlefield, then shuffle."),
  card("Skyshroud Claim", 4, "Sorcery", "{3}{G}", "Search your library for up to two Forest cards, put them onto the battlefield, then shuffle."),
  card("Nissa's Pilgrimage", 3, "Sorcery", "{2}{G}", "Search your library for up to two basic Forest cards, reveal them, put one onto the battlefield tapped and the rest into your hand."),
  card("Beast Whisperer", 4, "Creature — Elf Druid", "{2}{G}{G}", "Whenever you cast a creature spell, draw a card."),
  card("Guardian Project", 4, "Enchantment", "{3}{G}", "Whenever a nontoken creature enters the battlefield under your control, draw a card."),
  card("Harmonize", 4, "Sorcery", "{2}{G}{G}", "Draw three cards."),
  card("Return of the Wildspeaker", 5, "Instant", "{4}{G}", "Draw cards equal to the greatest power among non-Human creatures you control."),
  card("Rishkar's Expertise", 6, "Sorcery", "{4}{G}{G}", "Draw cards equal to the greatest power among creatures you control."),
  card("Garruk's Uprising", 3, "Enchantment", "{2}{G}", "When Garruk's Uprising enters, if you control a creature with power 4 or greater, draw a card."),
  card("Toski, Bearer of Secrets", 4, "Legendary Creature — Squirrel", "{3}{G}", "Whenever a creature you control deals combat damage to a player, draw a card."),
  card("Shamanic Revelation", 5, "Sorcery", "{3}{G}{G}", "Draw a card for each creature you control."),
  card("Elvish Visionary", 2, "Creature — Elf Shaman", "{1}{G}", "When Elvish Visionary enters, draw a card."),
  card("Leaf-Crowned Visionary", 2, "Creature — Elf Druid", "{G}{G}", "Whenever you cast an Elf spell, you may pay {G}. If you do, draw a card."),
  card("Armorcraft Judge", 4, "Creature — Elf Artificer", "{3}{G}", "When Armorcraft Judge enters, draw a card for each creature you control with a +1/+1 counter on it."),
  card("Soul of the Harvest", 6, "Creature — Elemental", "{4}{G}{G}", "Whenever another nontoken creature enters the battlefield under your control, you may draw a card."),
  card("Primordial Sage", 6, "Creature — Spirit", "{4}{G}{G}", "Whenever you cast a creature spell, you may draw a card."),
  card("Beast Within", 3, "Instant", "{2}{G}", "Destroy target permanent. Its controller creates a 3/3 green Beast creature token."),
  card("Krosan Grip", 3, "Instant", "{2}{G}", "Destroy target artifact or enchantment."),
  card("Reclamation Sage", 3, "Creature — Elf Shaman", "{2}{G}", "When Reclamation Sage enters, you may destroy target artifact or enchantment."),
  card("Acidic Slime", 5, "Creature — Ooze", "{3}{G}{G}", "When Acidic Slime enters, destroy target artifact, enchantment, or land."),
  card("Nature's Claim", 1, "Instant", "{G}", "Destroy target artifact or enchantment. Its controller gains 4 life."),
  card("Kenrith's Transformation", 2, "Enchantment — Aura", "{1}{G}", "When Kenrith's Transformation enters, draw a card. Enchanted creature loses all abilities."),
  card("Song of the Dryads", 3, "Enchantment — Aura", "{2}{G}", "Enchant permanent. Enchanted permanent is a colorless Forest land."),
  card("Lignify", 2, "Tribal Enchantment — Treefolk Aura", "{1}{G}", "Enchant creature. Enchanted creature is a Treefolk with no abilities."),
  card("Force of Vigor", 4, "Instant", "{2}{G}{G}", "Destroy up to two target artifacts and/or enchantments."),
  card("Bane of Progress", 6, "Creature — Elemental", "{4}{G}{G}", "When Bane of Progress enters, destroy all artifacts and enchantments."),
  card("Heroic Intervention", 2, "Instant", "{1}{G}", "Permanents you control gain hexproof and indestructible until end of turn."),
  card("Wrap in Vigor", 2, "Instant", "{1}{G}", "Regenerate each creature you control."),
  card("Tamiyo's Safekeeping", 1, "Instant", "{G}", "Target permanent you control gains hexproof and indestructible until end of turn."),
  card("Snakeskin Veil", 1, "Instant", "{G}", "Put a +1/+1 counter on target creature you control. It gains hexproof until end of turn."),
  card("Asceticism", 5, "Enchantment", "{3}{G}{G}", "Creatures you control have hexproof. {1}{G}: Regenerate target creature."),
  card("Elvish Warmaster", 2, "Creature — Elf Warrior", "{1}{G}", "Whenever one or more Elves enter under your control, create a 1/1 green Elf Warrior creature token."),
  card("Imperious Perfect", 3, "Creature — Elf Warrior", "{2}{G}", "Other Elves you control get +1/+1. {G}, {T}: Create a 1/1 green Elf Warrior creature token."),
  card("Canopy Tactician", 4, "Creature — Elf Warrior", "{3}{G}", "Other Elves you control get +1/+1. {T}: Add {G}{G}{G}."),
  card("Elvish Clancaller", 2, "Creature — Elf Druid", "{G}{G}", "Other Elves you control get +1/+1."),
  card("Dwynen's Elite", 2, "Creature — Elf Warrior", "{1}{G}", "When Dwynen's Elite enters, if you control another Elf, create a 1/1 green Elf Warrior creature token."),
  card("Dwynen, Gilt-Leaf Daen", 4, "Legendary Creature — Elf Warrior", "{2}{G}{G}", "Other Elf creatures you control get +1/+1."),
  card("Timberwatch Elf", 3, "Creature — Elf", "{2}{G}", "{T}: Target creature gets +X/+X until end of turn, where X is the number of Elves on the battlefield."),
  card("Copperhorn Scout", 1, "Creature — Elf Scout", "{G}", "Whenever Copperhorn Scout attacks, untap each other creature you control."),
  card("Heritage Druid", 1, "Creature — Elf Druid", "{G}", "Tap three untapped Elves you control: Add {G}{G}{G}."),
  card("Nettle Sentinel", 1, "Creature — Elf Warrior", "{G}", "Nettle Sentinel doesn't untap during your untap step."),
  card("Allosaurus Shepherd", 1, "Creature — Elf Shaman", "{G}", "Green spells you control can't be countered."),
  card("Wirewood Symbiote", 1, "Creature — Insect", "{G}", "Return an Elf you control to its owner's hand: Untap target creature."),
  card("Quirion Ranger", 1, "Creature — Elf Ranger", "{G}", "Return a Forest you control to its owner's hand: Untap target creature."),
  card("Realmwalker", 3, "Creature — Shapeshifter", "{2}{G}", "As Realmwalker enters, choose a creature type. You may look at the top card of your library any time."),
  card("Sylvan Ranger", 2, "Creature — Elf Scout", "{1}{G}", "When Sylvan Ranger enters, search your library for a basic land card, reveal it, put it into your hand, then shuffle."),
  card("Elvish Rejuvenator", 3, "Creature — Elf Druid", "{2}{G}", "When Elvish Rejuvenator enters, look at the top five cards of your library. You may put a land card from among them onto the battlefield tapped."),
  card("Elvish Harbinger", 3, "Creature — Elf Druid", "{2}{G}", "When Elvish Harbinger enters, you may search your library for an Elf card, reveal it, then shuffle and put that card on top."),
  card("Wildborn Preserver", 2, "Creature — Elf Archer", "{1}{G}", "Whenever another non-Human creature enters under your control, you may pay {X}."),
  card("Joraga Warcaller", 1, "Creature — Elf Warrior", "{G}", "Multikicker {1}{G}. Other Elf creatures you control get +1/+1 for each +1/+1 counter on Joraga Warcaller."),
  card("Freyalise, Llanowar's Fury", 5, "Legendary Planeswalker — Freyalise", "{3}{G}{G}", "+2: Create a 1/1 green Elf Druid creature token with {T}: Add {G}."),
  card("Beastmaster Ascension", 3, "Enchantment", "{2}{G}", "Whenever a creature you control attacks, you may put a quest counter on Beastmaster Ascension."),
  card("Growing Rites of Itlimoc", 3, "Legendary Enchantment", "{2}{G}", "When Growing Rites of Itlimoc enters, look at the top four cards of your library. You may reveal a creature card."),
  card("Craterhoof Behemoth", 8, "Creature — Beast", "{5}{G}{G}{G}", "When Craterhoof Behemoth enters, creatures you control get +X/+X and gain trample until end of turn."),
  card("End-Raze Forerunners", 8, "Creature — Boar", "{5}{G}{G}{G}", "When End-Raze Forerunners enters, creatures you control get +2/+2 and gain vigilance and trample until end of turn."),
  card("Overwhelming Stampede", 5, "Sorcery", "{3}{G}{G}", "Until end of turn, creatures you control gain trample and get +X/+X."),
  card("Triumph of the Hordes", 4, "Sorcery", "{2}{G}{G}", "Until end of turn, creatures you control get +1/+1 and gain trample and infect."),
  card("Pathbreaker Ibex", 6, "Creature — Goat", "{4}{G}{G}", "Whenever Pathbreaker Ibex attacks, creatures you control gain trample and get +X/+X until end of turn."),
  card("Great Oak Guardian", 6, "Creature — Treefolk", "{5}{G}", "Flash. When Great Oak Guardian enters, creatures target player controls get +2/+2 until end of turn."),
  card("Elvish Promenade", 4, "Tribal Sorcery — Elf", "{3}{G}", "Create a 1/1 green Elf Warrior creature token for each Elf you control."),
  card("Wellwisher", 2, "Creature — Elf", "{1}{G}", "{T}: You gain 1 life for each Elf on the battlefield."),
  card("Lys Alana Huntmaster", 4, "Creature — Elf Warrior", "{2}{G}{G}", "Whenever you cast an Elf spell, you may create a 1/1 green Elf Warrior creature token."),
  card("Elvish Guidance", 3, "Enchantment — Aura", "{2}{G}", "Enchant land. Whenever enchanted land is tapped for mana, its controller adds {G} for each Elf on the battlefield."),
  card("Seeker of Skybreak", 2, "Creature — Elf", "{1}{G}", "{T}: Untap target creature."),
  card("Wirewood Channeler", 4, "Creature — Elf Druid", "{3}{G}", "{T}: Add X mana of any one color, where X is the number of Elves on the battlefield."),
  card("Elven Ambush", 4, "Instant", "{3}{G}", "Create a 1/1 green Elf Warrior creature token for each Elf you control."),
  card("Timeless Witness", 4, "Creature — Human Shaman", "{2}{G}{G}", "When Timeless Witness enters, return target card from your graveyard to your hand.")
];

export function generateBracketThreeCommanderDeck(input: GenerateCommanderDeckInput = {}): GeneratedCommanderDeck {
  const seed = `${input.seed ?? "magicmobile"}:${input.playerId ?? "player"}`;
  const nonCommanderCards = generatedCommanderCardPool.filter((card) => card.name !== commanderName && card.name !== basicLandName);
  const required = nonCommanderCards.filter((card) => requiredNames.has(card.name));
  const flex = seededShuffle(nonCommanderCards.filter((card) => !requiredNames.has(card.name)), `${seed}:flex`);
  const selected = seededShuffle([...required, ...flex.slice(0, nonCommanderCardCount - required.length)], `${seed}:final`);
  const commanderEntry = entry(commanderName, 1, "commander");
  const deck: DeckList = {
    name: `Bracket 3 ${input.playerId === "ai-1" ? "AI" : "Generated"} Ezuri Commander`,
    commander: commanderEntry,
    entries: [
      commanderEntry,
      ...selected.map((card) => entry(card.name)),
      entry(basicLandName, basicLandCount)
    ]
  };

  const stats = analyzer.getStats({ deck, cards: generatedCommanderCardPool });
  const bracket = analyzer.getBracketScore({ deck, cards: generatedCommanderCardPool });

  return {
    deck,
    cardPool: generatedCommanderCardPool,
    validationErrors: [],
    stats,
    bracket,
    source: "generated"
  };
}

function entry(cardName: string, quantity = 1, section: DeckEntry["section"] = "deck"): DeckEntry {
  return { cardName, quantity, section };
}

function card(
  name: string,
  manaValue: number,
  typeLine: string,
  manaCost: string,
  oracleText: string,
  colorIdentity: ColorSymbol[] = ["G"]
): GeneratedCard {
  return {
    id: slug(name),
    name,
    manaValue,
    manaCost,
    colorIdentity,
    colors: colorIdentity.filter((color) => color !== "C"),
    typeLine,
    oracleText,
    legalities: { commander: "legal" }
  };
}

function artifact(name: string, manaValue: number, manaCost: string, oracleText: string): GeneratedCard {
  return card(name, manaValue, "Artifact", manaCost, oracleText, ["C"]);
}

function basicLand(name: string, color: ColorSymbol): GeneratedCard {
  return {
    id: slug(name),
    name,
    manaValue: 0,
    colorIdentity: [color],
    colors: [],
    typeLine: `Basic Land — ${name}`,
    oracleText: `({T}: Add {${color}}.)`,
    isBasicLand: true,
    legalities: { commander: "legal" }
  };
}

function seededShuffle<T>(items: T[], seed: string): T[] {
  return items
    .map((item, index) => ({ item, rank: seededRank(`${seed}:${index}:${JSON.stringify(item)}`) }))
    .sort((left, right) => left.rank - right.rank)
    .map(({ item }) => item);
}

function seededRank(value: string): number {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
}
