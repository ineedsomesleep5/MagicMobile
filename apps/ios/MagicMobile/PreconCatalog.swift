import Foundation

struct PreconDeck: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let colors: String
    let commander: String
    let sourceURL: URL
    let rawList: String

    var deckList: DeckList {
        let commanderEntry = DeckEntry(cardName: commander, quantity: 1, section: "commander")
        let entries = rawList
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> DeckEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2, let quantity = Int(parts[0]), parts[1] != commander else {
                    return nil
                }
                return DeckEntry(cardName: parts[1], quantity: quantity, section: "deck")
            }
        return DeckList(name: name, commander: commanderEntry, entries: entries)
    }
}

enum PreconCatalog {
    static let all: [PreconDeck] = [
        PreconDeck(
            id: "token-triumph",
            name: "Token Triumph",
            subtitle: "Selesnya go-wide tokens",
            colors: "GW",
            commander: "Emmara, Soul of the Accord",
            sourceURL: URL(string: "https://www.mtggoldfish.com/deck/5172736")!,
            rawList: """
1 Ajani, Caller of the Pride
1 Arcane Signet
1 Aura Mutation
1 Avacyn's Pilgrim
1 Blossoming Sands
1 Camaraderie
1 Canopy Vista
1 Champion of Lambholt
1 Citanul Hierophants
1 Citywide Bust
1 Collective Blessing
1 Collective Unconscious
1 Command Tower
1 Commander's Insignia
1 Commander's Sphere
1 Conclave Tribunal
1 Curse of Bounty
1 Dauntless Escort
1 Dawn of Hope
1 Devouring Light
1 Dictate of Heliod
1 Elfhame Palace
1 Emmara, Soul of the Accord
1 Eternal Witness
1 Farhaven Elf
1 Felidar Retreat
15 Forest
1 Fortified Village
1 Graypelt Refuge
1 Great Oak Guardian
1 Harmonize
1 Harvest Season
1 Holdout Settlement
1 Hornet Nest
1 Hornet Queen
1 Hour of Reckoning
1 Idol of Oblivion
1 Jade Mage
1 Jaspera Sentinel
1 Karametra's Favor
1 Leafkin Druid
1 Loyal Guardian
1 Maja, Bretagard Protector
1 March of the Multitudes
1 Mentor of the Meek
1 Nissa's Expedition
1 Nullmage Shepherd
1 Overrun
1 Overwhelming Instinct
1 Path to Exile
14 Plains
1 Presence of Gond
1 Reclamation Sage
1 Rishkar, Peema Renegade
1 Rootborn Defenses
1 Scatter the Seeds
1 Scavenging Ooze
1 Selesnya Evangel
1 Selesnya Guildmage
1 Slate of Ancestry
1 Sol Ring
1 Sporemound
1 Sylvan Reclamation
1 Talisman of Unity
1 Temple of Plenty
1 Thunderfoot Baloth
1 Tranquil Expanse
1 Trostani Discordant
1 Valor in Akros
1 Verdant Force
1 Vitu-Ghazi, the City-Tree
1 Voice of Many
1 White Sun's Zenith
"""
        ),
        PreconDeck(
            id: "first-flight",
            name: "First Flight",
            subtitle: "Azorius flyers and control",
            colors: "WU",
            commander: "Isperia, Supreme Judge",
            sourceURL: URL(string: "https://www.mtggoldfish.com/deck/7577594")!,
            rawList: """
1 Absorb
1 Aetherize
1 Angler Turtle
1 Arcane Signet
1 Archon of Redemption
1 Aven Gagglemaster
1 Azorius Signet
1 Banishing Light
1 Bident of Thassa
1 Cartographer's Hawk
1 Cleansing Nova
1 Cloudblazer
1 Coastal Tower
1 Command Tower
1 Commander's Sphere
1 Condemn
1 Counterspell
1 Crush Contraband
1 Diluvian Primordial
1 Disenchant
1 Emeria Angel
1 Empyrean Eagle
1 Ever-Watching Threshold
1 Faerie Formation
1 Favorable Winds
1 Generous Gift
1 Gideon Jura
1 Gravitational Shift
1 Hanged Executioner
1 Hedron Archive
1 Inspired Sphinx
15 Island
1 Isperia, Supreme Judge
1 Jubilant Skybonder
1 Kangee's Lieutenant
1 Kangee, Sky Warden
1 Meandering River
1 Migratory Route
1 Moorland Haunt
1 Negate
1 Pilgrim's Eye
15 Plains
1 Port Town
1 Prairie Stream
1 Rally of Wings
1 Remorseful Cleric
1 Sejiri Refuge
1 Sephara, Sky's Blade
1 Sharding Sphinx
1 Sky Diamond
1 Skycat Sovereign
1 Skyscanner
1 Sol Ring
1 Soul Snare
1 Sphinx of Enlightenment
1 Sphinx's Revelation
1 Staggering Insight
1 Steel-Plume Marshal
1 Storm Herd
1 Swords to Plowshares
1 Talisman of Progress
1 Temple of Enlightenment
1 Thought Vessel
1 Thunderclap Wyvern
1 Tide Skimmer
1 Time Wipe
1 Tranquil Cove
1 True Conviction
1 Vow of Duty
1 Warden of Evos Isle
1 Windreader Sphinx
1 Winged Words
"""
        ),
        PreconDeck(
            id: "grave-danger",
            name: "Grave Danger",
            subtitle: "Dimir zombies and recursion",
            colors: "UB",
            commander: "Gisa and Geralf",
            sourceURL: URL(string: "https://www.mtggoldfish.com/deck/5185689")!,
            rawList: """
1 Arcane Signet
1 Army of the Damned
1 Cemetery Reaper
1 Champion of the Perished
1 Choked Estuary
1 Command Tower
1 Commander's Sphere
1 Crippling Fear
1 Cruel Revival
1 Curse of Disturbance
1 Deep Analysis
1 Dimir Signet
1 Diregraf Captain
1 Dismal Backwater
1 Distant Melody
1 Enter the God-Eternals
1 Eternal Skylord
1 Feed the Swarm
1 Fleshbag Marauder
1 Geralf's Mindcrusher
1 Gisa and Geralf
1 Gleaming Overseer
1 Gravespawn Sovereign
1 Gray Merchant of Asphodel
1 Grimoire of the Dead
1 Havengul Lich
1 Heraldic Banner
13 Island
1 Josu Vess, Lich Knight
1 Jwar Isle Refuge
1 Laboratory Drudge
1 Lazotep Plating
1 Lazotep Reaver
1 Liliana's Devotee
1 Liliana's Mastery
1 Liliana's Standard Bearer
1 Liliana, Untouched by Death
1 Lord of the Accursed
1 Lotleth Giant
1 Loyal Subordinate
1 Midnight Reaper
1 Mire Triton
1 Murder
1 Necromantic Selection
1 Necrotic Hex
1 Open the Graves
1 Overseer of the Damned
1 Pilfered Plans
1 Salt Marsh
1 Scourge of Nel Toth
1 Sinister Sabotage
1 Sol Ring
1 Spark Reaper
1 Submerged Boneyard
1 Sunken Hollow
18 Swamp
1 Syphon Flesh
1 Talisman of Dominance
1 Temple of Deceit
1 Unbreathing Horde
1 Undead Augur
1 Undermine
1 Unstable Obelisk
1 Vampiric Rites
1 Vela the Night-Clad
1 Vengeful Dead
1 Victimize
1 Vizier of the Scorpion
1 Wayfarer's Bauble
1 Withered Wretch
1 Zombie Apocalypse
"""
        ),
        PreconDeck(
            id: "chaos-incarnate",
            name: "Chaos Incarnate",
            subtitle: "Rakdos pressure and table politics",
            colors: "BR",
            commander: "Kardur, Doomscourge",
            sourceURL: URL(string: "https://www.mtggoldfish.com/deck/5906326")!,
            rawList: """
1 Abrade
1 Akoum Refuge
1 Ambition's Cost
1 Arcane Signet
1 Archfiend of Depravity
1 Blasphemous Act
1 Bloodfell Caves
1 Bloodgift Demon
1 Brash Taunter
1 Breath of Malfegor
1 Burnished Hart
1 Chaos Warp
1 Cinder Barrens
1 Combustible Gearhulk
1 Command Tower
1 Commander's Sphere
1 Coveted Jewel
1 Deadly Tempest
1 Dictate of the Twin Gods
1 Dredge the Mire
1 Explosion of Riches
1 Feed the Swarm
1 Fiery Confluence
1 Foreboding Ruins
1 Geode Rager
1 Guttersnipe
1 Hate Mirage
1 Indulgent Tormentor
1 Kaervek the Merciless
1 Kardur, Doomscourge
1 Kazuul, Tyrant of the Cliffs
1 Lightning Greaves
1 Magmatic Force
1 Mana Geyser
1 Molten Slagheap
14 Mountain
1 Myriad Landscape
1 Nihil Spellbomb
1 Ob Nixilis Reignited
1 Profane Command
1 Rakdos Charm
1 Rakdos Signet
1 Rakshasa Debaser
1 Read the Bones
1 Reign of the Pit
1 Sangromancer
1 Scythe Specter
1 Sepulchral Primordial
1 Sign in Blood
1 Smoldering Marsh
1 Sol Ring
1 Solemn Simulacrum
1 Soul Shatter
1 Spiteful Visions
1 Stensia Bloodhall
1 Stormfist Crusader
1 Sunbird's Invocation
15 Swamp
1 Syphon Mind
1 Talisman of Indulgence
1 Tectonic Giant
1 Temple of Malice
1 Terminate
1 Theater of Horrors
1 Thermo-Alchemist
1 Titan Hunter
1 Unlicensed Disintegration
1 Urborg Volcano
1 Vampire Nighthawk
1 Wayfarer's Bauble
1 Wild Ricochet
1 Wildfire Devils
1 Worn Powerstone
"""
        ),
        PreconDeck(
            id: "draconic-destruction",
            name: "Draconic Destruction",
            subtitle: "Gruul dragons and combat damage",
            colors: "RG",
            commander: "Atarka, World Render",
            sourceURL: URL(string: "https://www.mtggoldfish.com/deck/5172735")!,
            rawList: """
1 Akoum Hellkite
1 Arcane Signet
1 Atarka Monument
1 Atarka, World Render
1 Beast Within
1 Blossoming Defense
1 Chain Reaction
1 Cinder Glade
1 Clan Defiance
1 Command Tower
1 Commander's Sphere
1 Crucible of Fire
1 Cultivate
1 Demanding Dragon
1 Draconic Disciple
1 Dragon Mage
1 Dragon Tempest
1 Dragon's Hoard
1 Dragonkin Berserker
1 Dragonlord's Servant
1 Dragonmaster Outcast
1 Dragonspeaker Shaman
1 Drakuseth, Maw of Flames
1 Dream Pillager
1 Drumhunter
1 Elemental Bond
1 Fires of Yavimaya
1 Flameblast Dragon
1 Foe-Razer Regent
12 Forest
1 Frontier Siege
1 Furnace Whelp
1 Game Trail
1 Garruk's Uprising
1 Harbinger of the Hunt
1 Harmonize
1 Haven of the Spirit Dragon
1 Hoard-Smelter Dragon
1 Hunter's Insight
1 Hunter's Prowess
1 Kazandu Refuge
1 Loaming Shaman
1 Magmaquake
1 Mordant Dragon
18 Mountain
1 Path of Ancestry
1 Primal Might
1 Provoke the Trolls
1 Rapacious Dragon
1 Return to Nature
1 Rugged Highlands
1 Runehorn Hellkite
1 Sakura-Tribe Elder
1 Sarkhan, the Dragonspeaker
1 Savage Ventmaw
1 Scourge of Valkas
1 Shamanic Revelation
1 Shivan Oasis
1 Sol Ring
1 Spit Flame
1 Steel Hellkite
1 Sweltering Suns
1 Swiftfoot Boots
1 Talisman of Impulse
1 Temple of Abandon
1 Thunderbreak Regent
1 Thundermaw Hellkite
1 Timber Gorge
1 Tyrant's Familiar
1 Unleash Fury
1 Vandalblast
1 Verix Bladewing
"""
        )
    ]
}
