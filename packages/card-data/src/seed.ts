import type { MagicMobileCard } from "./models";

export const seedCards: MagicMobileCard[] = [
  {
    id: "seed-atraxa-praetors-voice",
    name: "Atraxa, Praetors' Voice",
    manaValue: 4,
    manaCost: "{G}{W}{U}{B}",
    colorIdentity: ["W", "U", "B", "G"],
    colors: ["W", "U", "B", "G"],
    typeLine: "Legendary Creature — Phyrexian Angel Horror",
    oracleText: "Flying, vigilance, deathtouch, lifelink. At the beginning of your end step, proliferate.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-sol-ring",
    name: "Sol Ring",
    manaValue: 1,
    manaCost: "{1}",
    colorIdentity: ["C"],
    colors: [],
    typeLine: "Artifact",
    oracleText: "{T}: Add {C}{C}.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-arcane-signet",
    name: "Arcane Signet",
    manaValue: 2,
    manaCost: "{2}",
    colorIdentity: ["C"],
    colors: [],
    typeLine: "Artifact",
    oracleText: "{T}: Add one mana of any color in your commander's color identity.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-mana-crypt",
    name: "Mana Crypt",
    manaValue: 0,
    manaCost: "{0}",
    colorIdentity: ["C"],
    colors: [],
    typeLine: "Artifact",
    oracleText: "{T}: Add {C}{C}.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-swords-to-plowshares",
    name: "Swords to Plowshares",
    manaValue: 1,
    manaCost: "{W}",
    colorIdentity: ["W"],
    colors: ["W"],
    typeLine: "Instant",
    oracleText: "Exile target creature. Its controller gains life equal to its power.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-counterspell",
    name: "Counterspell",
    manaValue: 2,
    manaCost: "{U}{U}",
    colorIdentity: ["U"],
    colors: ["U"],
    typeLine: "Instant",
    oracleText: "Counter target spell.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-cultivate",
    name: "Cultivate",
    manaValue: 3,
    manaCost: "{2}{G}",
    colorIdentity: ["G"],
    colors: ["G"],
    typeLine: "Sorcery",
    oracleText:
      "Search your library for up to two basic land cards, reveal those cards, put one onto the battlefield tapped and the other into your hand, then shuffle.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-wrath-of-god",
    name: "Wrath of God",
    manaValue: 4,
    manaCost: "{2}{W}{W}",
    colorIdentity: ["W"],
    colors: ["W"],
    typeLine: "Sorcery",
    oracleText: "Destroy all creatures. They can't be regenerated.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-rhystic-study",
    name: "Rhystic Study",
    manaValue: 3,
    manaCost: "{2}{U}",
    colorIdentity: ["U"],
    colors: ["U"],
    typeLine: "Enchantment",
    oracleText:
      "Whenever an opponent casts a spell, you may draw a card unless that player pays {1}.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-demonic-tutor",
    name: "Demonic Tutor",
    manaValue: 2,
    manaCost: "{1}{B}",
    colorIdentity: ["B"],
    colors: ["B"],
    typeLine: "Sorcery",
    oracleText: "Search your library for a card, put that card into your hand, then shuffle.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-vampiric-tutor",
    name: "Vampiric Tutor",
    manaValue: 1,
    manaCost: "{B}",
    colorIdentity: ["B"],
    colors: ["B"],
    typeLine: "Instant",
    oracleText:
      "Search your library for a card, then shuffle and put that card on top. You lose 2 life.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-beast-within",
    name: "Beast Within",
    manaValue: 3,
    manaCost: "{2}{G}",
    colorIdentity: ["G"],
    colors: ["G"],
    typeLine: "Instant",
    oracleText:
      "Destroy target permanent. Its controller creates a 3/3 green Beast creature token.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-cyclonic-rift",
    name: "Cyclonic Rift",
    manaValue: 2,
    manaCost: "{1}{U}",
    colorIdentity: ["U"],
    colors: ["U"],
    typeLine: "Instant",
    oracleText:
      "Return target nonland permanent you don't control to its owner's hand. Overload {6}{U}.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-smothering-tithe",
    name: "Smothering Tithe",
    manaValue: 4,
    manaCost: "{3}{W}",
    colorIdentity: ["W"],
    colors: ["W"],
    typeLine: "Enchantment",
    oracleText:
      "Whenever an opponent draws a card, that player may pay {2}. If the player doesn't, you create a Treasure token.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-lightning-bolt",
    name: "Lightning Bolt",
    manaValue: 1,
    manaCost: "{R}",
    colorIdentity: ["R"],
    colors: ["R"],
    typeLine: "Instant",
    oracleText: "Lightning Bolt deals 3 damage to any target.",
    legalities: { commander: "legal" }
  },
  {
    id: "seed-plains",
    name: "Plains",
    manaValue: 0,
    colorIdentity: ["W"],
    typeLine: "Basic Land — Plains",
    oracleText: "({T}: Add {W}.)",
    isBasicLand: true,
    legalities: { commander: "legal" }
  },
  {
    id: "seed-island",
    name: "Island",
    manaValue: 0,
    colorIdentity: ["U"],
    typeLine: "Basic Land — Island",
    oracleText: "({T}: Add {U}.)",
    isBasicLand: true,
    legalities: { commander: "legal" }
  },
  {
    id: "seed-swamp",
    name: "Swamp",
    manaValue: 0,
    colorIdentity: ["B"],
    typeLine: "Basic Land — Swamp",
    oracleText: "({T}: Add {B}.)",
    isBasicLand: true,
    legalities: { commander: "legal" }
  },
  {
    id: "seed-forest",
    name: "Forest",
    manaValue: 0,
    colorIdentity: ["G"],
    typeLine: "Basic Land — Forest",
    oracleText: "({T}: Add {G}.)",
    isBasicLand: true,
    legalities: { commander: "legal" }
  }
];
