import AVFoundation
import SwiftUI

/// Groups of sounds a player can switch off separately in the Sound Lab.
enum GameSoundCategory: String, CaseIterable, Identifiable {
    case interface, cards, spells, combat, moments

    var id: String { rawValue }
    var key: String { "magicmobile.sfx.\(rawValue)" }

    var title: String {
        switch self {
        case .interface: return String(localized: "Menus & alerts")
        case .cards: return String(localized: "Cards & board")
        case .spells: return String(localized: "Spells")
        case .combat: return String(localized: "Combat & life")
        case .moments: return String(localized: "Big moments")
        }
    }

    var detail: String {
        switch self {
        case .interface: return String(localized: "Confirm buttons, sheets, “your decision” and emotes.")
        case .cards: return String(localized: "Drawing, playing, lands, creatures and their kinds, artifacts and counters.")
        case .spells: return String(localized: "Instants, sorceries, other spells, big spells and your commander.")
        case .combat: return String(localized: "Attacks, blocks, hits, deaths, exile and life changes.")
        case .moments: return String(localized: "Your turn, the versus reveal, victory, defeat and dice.")
        }
    }
}

/// Every sound effect in the game. File names match Resources/Audio, rendered from
/// professional recordings by scripts/audio/build_game_audio.py (see CREDITS.txt).
enum GameSound: String, CaseIterable, Identifiable {
    // Interface
    case uiTap = "ui-tap", uiConfirm = "ui-confirm", uiBack = "ui-back", uiOpen = "ui-open",
         uiClose = "ui-close", uiToggle = "ui-toggle", uiTick = "ui-tick", uiError = "ui-error",
         responseAlert = "response-alert", menuPlay = "menu-play", pageFlip = "page-flip", emote,
         bookOpen = "book-open", bookClose = "book-close"
    // Cards and board
    case cardDraw = "card-draw", cardPickup = "card-pickup", cardPlay = "card-play", shuffle,
         landDrop = "land-drop", counter, ability, steal,
         // A card arriving (BoardFXArrivalSound): one sound per kind of card, never a wood knock under it. A creature
         // plays its type's voice alone, or lands as a card placed on the table when its type has no voice yet; a basic
         // land plays its place. Water, fire and leaves are only ever the lands'.
         arriveCreature = "arrive-creature", arriveCreatureHeavy = "arrive-creature-heavy", arriveArtifact = "arrive-artifact",
         arriveEnchantment = "arrive-enchantment", arrivePlaneswalker = "arrive-planeswalker",
         // Creature voices, one per BoardFXArrivalSound.creatureVoices slot
         creatureHuman = "creature-human", creatureGoblin = "creature-goblin", creatureElf = "creature-elf", creatureDragon = "creature-dragon", creatureSliver = "creature-sliver", creatureSquirrel = "creature-squirrel", creatureOrc = "creature-orc", creatureGiant = "creature-giant", creatureBear = "creature-bear", creatureDinosaur = "creature-dinosaur", creatureBeast = "creature-beast", creatureHorror = "creature-horror", creatureCritter = "creature-critter", creatureFaerie = "creature-faerie", creatureAngel = "creature-angel", creatureVampire = "creature-vampire", creatureZombie = "creature-zombie", creatureWolf = "creature-wolf", creatureCat = "creature-cat", creatureBird = "creature-bird", creatureOoze = "creature-ooze", creatureWizard = "creature-wizard", creatureInsect = "creature-insect", creatureRat = "creature-rat", creatureEldrazi = "creature-eldrazi",
         landPlains = "land-plains", landIsland = "land-island", landSwamp = "land-swamp", landMountain = "land-mountain",
         landForest = "land-forest"
    // Spells by card type (BoardFXCastSound), never colour
    case castInstant = "cast-instant", castSorcery = "cast-sorcery", castPermanent = "cast-permanent",
         spellBig = "spell-big", commanderCast = "commander-cast"
    // Combat and life
    case attack, block, strike, playerHit = "player-hit", death, exile,
         lifeGain = "life-gain", lifeLoss = "life-loss"
    // Big moments
    case turnYou = "turn-you", versus, victory, defeat, diceRoll = "dice-roll", diceLand = "dice-land"

    var id: String { rawValue }

    var category: GameSoundCategory {
        switch self {
        case .uiTap, .uiConfirm, .uiBack, .uiOpen, .uiClose, .uiToggle, .uiTick, .uiError,
             .responseAlert, .menuPlay, .pageFlip, .emote, .bookOpen, .bookClose: return .interface
        case .cardDraw, .cardPickup, .cardPlay, .shuffle, .landDrop, .counter, .ability, .steal, .arriveCreature, .arriveCreatureHeavy, .arriveArtifact, .arriveEnchantment, .arrivePlaneswalker,
             .creatureHuman, .creatureGoblin, .creatureElf, .creatureDragon, .creatureSliver, .creatureSquirrel, .creatureOrc, .creatureGiant, .creatureBear, .creatureDinosaur, .creatureBeast, .creatureHorror, .creatureCritter, .creatureFaerie, .creatureAngel, .creatureVampire, .creatureZombie, .creatureWolf, .creatureCat, .creatureBird, .creatureOoze, .creatureWizard, .creatureInsect, .creatureRat, .creatureEldrazi, .landPlains, .landIsland, .landSwamp, .landMountain, .landForest: return .cards
        case .castInstant, .castSorcery, .castPermanent, .spellBig, .commanderCast: return .spells
        case .attack, .block, .strike, .playerHit, .death, .exile, .lifeGain, .lifeLoss: return .combat
        case .turnYou, .versus, .victory, .defeat, .diceRoll, .diceLand: return .moments
        }
    }

    /// Sound Lab name.
    var title: String {
        switch self {
        case .uiTap: return String(localized: "Game button")
        case .uiConfirm: return String(localized: "Confirm")
        case .uiBack: return String(localized: "Back")
        case .uiOpen: return String(localized: "Open a panel")
        case .uiClose: return String(localized: "Close a panel")
        case .uiToggle: return String(localized: "Switch")
        case .uiTick: return String(localized: "Slider tick")
        case .uiError: return String(localized: "Not allowed")
        case .responseAlert: return String(localized: "Your decision")
        case .menuPlay: return String(localized: "Play")
        case .pageFlip: return String(localized: "Page turn")
        case .bookOpen: return String(localized: "Spell book opens")
        case .bookClose: return String(localized: "Spell book closes")
        case .emote: return String(localized: "Emote")
        case .cardDraw: return String(localized: "Draw a card")
        case .cardPickup: return String(localized: "Pick up a card")
        case .cardPlay: return String(localized: "Play a card")
        case .shuffle: return String(localized: "Shuffle (mulligan)")
        case .landDrop: return String(localized: "Land")
        case .counter: return String(localized: "Counter")
        case .ability: return String(localized: "Your ability")
        case .steal: return String(localized: "Stolen permanent")
        case .arriveCreature: return String(localized: "Creature lands")
        case .arriveCreatureHeavy: return String(localized: "Big creature lands")
        case .arriveArtifact: return String(localized: "Artifact")
        case .arriveEnchantment: return String(localized: "Enchantment")
        case .arrivePlaneswalker: return String(localized: "Planeswalker")
        case .creatureHuman: return String(localized: "Human")
        case .creatureGoblin: return String(localized: "Goblin")
        case .creatureElf: return String(localized: "Elf")
        case .creatureDragon: return String(localized: "Dragon")
        case .creatureSliver: return String(localized: "Sliver")
        case .creatureSquirrel: return String(localized: "Squirrel")
        case .creatureOrc: return String(localized: "Orc, ogre, troll")
        case .creatureGiant: return String(localized: "Giant")
        case .creatureBear: return String(localized: "Bear")
        case .creatureDinosaur: return String(localized: "Dinosaur")
        case .creatureBeast: return String(localized: "Beast, hydra")
        case .creatureHorror: return String(localized: "Horror, demon, wurm")
        case .creatureCritter: return String(localized: "Small critter")
        case .creatureFaerie: return String(localized: "Faerie")
        case .creatureAngel: return String(localized: "Angel")
        case .creatureVampire: return String(localized: "Vampire")
        case .creatureZombie: return String(localized: "Zombie")
        case .creatureWolf: return String(localized: "Wolf, dog")
        case .creatureCat: return String(localized: "Cat")
        case .creatureBird: return String(localized: "Bird")
        case .creatureOoze: return String(localized: "Ooze")
        case .creatureWizard: return String(localized: "Wizard")
        case .creatureInsect: return String(localized: "Insect, spider")
        case .creatureRat: return String(localized: "Rat, mouse")
        case .creatureEldrazi: return String(localized: "Eldrazi")
        case .landPlains: return String(localized: "Plains")
        case .landIsland: return String(localized: "Island")
        case .landSwamp: return String(localized: "Swamp")
        case .landMountain: return String(localized: "Mountain")
        case .landForest: return String(localized: "Forest")
        case .castInstant: return String(localized: "Instant")
        case .castSorcery: return String(localized: "Sorcery")
        case .castPermanent: return String(localized: "Permanent spell")
        case .spellBig: return String(localized: "Big spell")
        case .commanderCast: return String(localized: "Commander")
        case .attack: return String(localized: "Attack")
        case .block: return String(localized: "Block")
        case .strike: return String(localized: "Creature hit")
        case .playerHit: return String(localized: "You’re hit")
        case .death: return String(localized: "Creature dies")
        case .exile: return String(localized: "Exile")
        case .lifeGain: return String(localized: "Life gain")
        case .lifeLoss: return String(localized: "Life loss")
        case .turnYou: return String(localized: "Your turn")
        case .versus: return String(localized: "Versus")
        case .victory: return String(localized: "Victory")
        case .defeat: return String(localized: "Defeat")
        case .diceRoll: return String(localized: "Dice roll")
        case .diceLand: return String(localized: "Die lands")
        }
    }

    /// Numbered files ("attack-1…3") give repeated sounds natural variety; a creature type with several voices picks one.
    var variants: Int {
        switch self {
        case .attack: return 3
        case .creatureGiant, .creatureFaerie, .creatureZombie, .creatureCat, .creatureOoze, .creatureWizard, .creatureInsect: return 2
        case .creatureDragon, .creatureSquirrel, .creatureOrc, .creatureHorror: return 3
        default: return 1
        }
    }

    /// The files a sound plays from: Giants share the first two orc voices (Caleb: the third is not for giants).
    var fileBase: String { self == .creatureGiant ? GameSound.creatureOrc.rawValue : rawValue }

    /// Mix level. Files are already loudness-matched (audio-manifest.json); this sets the
    /// balance: interface quiet, the board clear, big moments on top.
    var volume: Float {
        switch self {
        case .uiTap, .uiTick, .uiToggle, .uiBack, .uiOpen, .uiClose: return 0.5
        case .uiConfirm, .uiError, .pageFlip, .emote, .bookOpen, .bookClose: return 0.65
        case .responseAlert, .menuPlay: return 0.8
        case .cardDraw, .cardPickup, .counter, .ability: return 0.7
        case .cardPlay, .shuffle, .landDrop, .arriveCreature, .arriveCreatureHeavy, .arriveArtifact, .arriveEnchantment, .arrivePlaneswalker,
             .creatureHuman, .creatureGoblin, .creatureElf, .creatureDragon, .creatureSliver, .creatureSquirrel, .creatureOrc, .creatureGiant, .creatureBear, .creatureDinosaur, .creatureBeast, .creatureHorror, .creatureCritter, .creatureFaerie, .creatureAngel, .creatureVampire, .creatureZombie, .creatureWolf, .creatureCat, .creatureBird, .creatureOoze, .creatureWizard, .creatureInsect, .creatureRat, .creatureEldrazi, .landPlains, .landIsland, .landSwamp, .landMountain, .landForest: return 0.85
        case .castInstant, .castSorcery, .castPermanent: return 0.85
        case .spellBig, .commanderCast, .attack, .block, .strike, .playerHit: return 0.9
        case .death, .exile, .lifeGain, .lifeLoss, .steal: return 0.75
        case .turnYou, .versus, .victory, .defeat: return 0.9
        case .diceRoll, .diceLand: return 0.85
        }
    }

    /// A little pitch variation keeps repeated foley from sounding mechanical; musical
    /// cues stay in tune.
    var pitchVariation: Float {
        switch self {
        case .cardDraw, .cardPickup, .cardPlay, .landDrop, .strike, .playerHit, .death, .attack, .block, .counter, .shuffle,
             .diceLand, .arriveCreature, .arriveCreatureHeavy, .arriveArtifact:
            return 0.04
        default: return 0
        }
    }

    /// Simultaneous copies allowed (a board wipe plays several deaths at once).
    var voices: Int {
        switch self {
        case .strike, .death, .cardDraw, .arriveCreature, .arriveCreatureHeavy, .arriveArtifact, .arriveEnchantment, .arrivePlaneswalker, .creatureHuman, .creatureGoblin, .creatureElf, .creatureDragon, .creatureSliver, .creatureSquirrel, .creatureOrc, .creatureGiant, .creatureBear, .creatureDinosaur, .creatureBeast, .creatureHorror, .creatureCritter, .creatureFaerie, .creatureAngel, .creatureVampire, .creatureZombie, .creatureWolf, .creatureCat, .creatureBird, .creatureOoze, .creatureWizard, .creatureInsect, .creatureRat, .creatureEldrazi: return 3
        case .victory, .defeat, .versus, .turnYou, .menuPlay, .responseAlert: return 1
        default: return 2
        }
    }

    /// Minimum time between two plays of this cue. Twelve triggers resolving together
    /// should read as a flurry, not a wall of identical sounds.
    var cooldown: TimeInterval {
        switch self {
        case .uiTick: return 0.08
        case .cardDraw, .uiTap: return 0.1
        case .strike, .death, .landDrop, .arriveCreature, .arriveCreatureHeavy, .arriveArtifact, .arriveEnchantment, .arrivePlaneswalker,
             .landPlains, .landIsland, .landSwamp, .landMountain, .landForest: return 0.12
        case .counter, .lifeGain: return 0.3
        case .castInstant, .castSorcery, .castPermanent: return 0.25
        case .ability: return 0.8
        case .responseAlert: return 1.2
        case .turnYou, .versus, .victory, .defeat: return 1.5
        default: return 0.12
        }
    }

    var isCreatureVoice: Bool { rawValue.hasPrefix("creature-") }

    /// A creature voice slot (BoardFXArrivalSound.creatureVoices) to its sound.
    static func voice(_ slot: String) -> GameSound? { GameSound(rawValue: "creature-\(slot)") }

    static func cast(_ kind: BoardFXCastSound) -> GameSound {
        switch kind {
        case .instant: return .castInstant
        case .sorcery: return .castSorcery
        case .permanent: return .castPermanent
        }
    }

    static func sounds(in category: GameSoundCategory) -> [GameSound] {
        allCases.filter { $0.category == category }
    }
}

/// One recorded music track (Kevin MacLeod, incompetech.com, CC BY 4.0).
struct MusicTrack: Identifiable, Hashable {
    let file: String
    let title: String
    var id: String { file }
}

/// Music plays as a playlist per scene: whole tracks, one after another.
enum GameMusic: String, CaseIterable, Identifiable {
    case menu, game

    var id: String { rawValue }
    var level: Float { self == .menu ? 0.6 : 0.42 }
    /// "shuffle" or one track's file name.
    var choiceKey: String { "magicmobile.music.\(rawValue)" }

    var title: String {
        self == .menu ? String(localized: "Lobby music") : String(localized: "In-game music")
    }

    var tracks: [MusicTrack] {
        switch self {
        case .menu:
            return [MusicTrack(file: "music-menu-1", title: "Midnight Tale"),
                    MusicTrack(file: "music-menu-2", title: "Industrious Ferret"),
                    MusicTrack(file: "music-menu-3", title: "Village Consort"),
                    MusicTrack(file: "music-menu-4", title: "Thatched Villagers")]
        case .game:
            return [MusicTrack(file: "music-game-1", title: "Teller of the Tales"),
                    MusicTrack(file: "music-game-2", title: "Lord of the Land"),
                    MusicTrack(file: "music-game-3", title: "Suonatore di Liuto"),
                    MusicTrack(file: "music-game-4", title: "Pippin the Hunchback")]
        }
    }

}

/// Sound effects and music. Effects honor the Ring/Silent switch (ambient session) and
/// mix with the player's own audio, like other iPhone games.
@MainActor
final class GameAudio {
    static let shared = GameAudio()

    static let effectsKey = "magicmobile.boardSoundsEnabled"
    static let musicKey = "magicmobile.musicEnabled"
    static let effectsVolumeKey = "magicmobile.effectsVolume"
    static let musicVolumeKey = "magicmobile.musicVolume"
    static let defaultMusicVolume = 0.6

    private var pools: [String: [AVAudioPlayer]] = [:]
    private var nextVoice: [String: Int] = [:]
    private var lastPlayed: [GameSound: TimeInterval] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var fadingPlayers: [AVAudioPlayer] = []
    private let musicEnd = MusicEndObserver()
    private(set) var currentTrack: GameMusic?
    private(set) var nowPlaying: MusicTrack?
    private var previewing = false
    private var lastTrack: [GameMusic: String] = [:]
    private var duckedUntil: TimeInterval = 0
    private var sessionReady = false
    /// Silent under unit and UI tests and for scripted screenshot runs (`MAGICMOBILE_MUTE_AUDIO`): AVAudioPlayer.play
    /// waits on the audio device on the main thread, and a stalled simulator audio device holds the app on its launch
    /// screen.
    private let isTesting = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.arguments.contains("--ondevice-setup-ui-test")
        || ProcessInfo.processInfo.environment["MAGICMOBILE_MUTE_AUDIO"] != nil

    private var defaults: UserDefaults { MagicMobilePreferences.current }
    var effectsEnabled: Bool { defaults.object(forKey: Self.effectsKey) as? Bool ?? true }
    /// A music level of zero is the same as music switched off.
    var musicEnabled: Bool { (defaults.object(forKey: Self.musicKey) as? Bool ?? true) && musicVolume > 0 }
    var effectsVolume: Float { Float(defaults.object(forKey: Self.effectsVolumeKey) as? Double ?? 0.9) }
    var musicVolume: Float { Float(defaults.object(forKey: Self.musicVolumeKey) as? Double ?? Self.defaultMusicVolume) }

    func isEnabled(_ category: GameSoundCategory) -> Bool {
        defaults.object(forKey: category.key) as? Bool ?? true
    }

    private init() {
        musicEnd.onFinish = { [weak self] player in self?.trackFinished(player) }
    }

    private func prepareSession() {
        guard !sessionReady else { return }
        sessionReady = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "caf") ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    private func player(for sound: GameSound) -> AVAudioPlayer? {
        let file = sound.variants > 1 ? "\(sound.fileBase)-\(Int.random(in: 1...sound.variants))" : sound.fileBase
        var pool = pools[file] ?? []
        // An idle voice first: making and preparing another player costs ~40 ms, which smeared two sounds meant to start
        // together.
        if let idle = pool.first(where: { !$0.isPlaying }) { return idle }
        if pool.count < sound.voices, let url = url(file), let player = try? AVAudioPlayer(contentsOf: url) {
            player.enableRate = sound.pitchVariation > 0
            player.prepareToPlay()
            pool.append(player)
            pools[file] = pool
        }
        guard !pool.isEmpty else { return nil }
        if let idle = pool.first(where: { !$0.isPlaying }) { return idle }
        // Every voice busy: steal the oldest in round-robin order.
        let index = (nextVoice[file] ?? 0) % pool.count
        nextVoice[file] = index + 1
        return pool[index]
    }

    /// The board's sounds (cards, spells, combat), warmed up when a game appears (NativeGameView).
    static let boardSounds = GameSound.allCases.filter { [.cards, .spells, .combat].contains($0.category) }

    /// Warm up the players used in the first seconds of a game so the first cast is instant.
    func preload(_ sounds: [GameSound]) {
        guard !isTesting else { return }
        for sound in sounds { _ = player(for: sound) }
    }

    /// `audition` plays a sound from the Sound Lab even when its category is off.
    func play(_ sound: GameSound, after delay: TimeInterval = 0, volume scale: Float = 1, audition: Bool = false) {
        play(sound, after: delay, endingWithin: nil, volume: scale, audition: audition)
    }

    /// `endingWithin`: start late enough that the sound finishes this long after `delay` (a creature's voice ends as
    /// its card lands); one longer than that starts at `delay`.
    func play(_ sound: GameSound, after delay: TimeInterval, endingWithin window: TimeInterval?, volume scale: Float = 1,
              audition: Bool = false) {
        guard !isTesting, effectsEnabled || audition, effectsVolume > 0 || audition,
              isEnabled(sound.category) || audition else { return }
        if delay > 0.005 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.play(sound, after: 0, endingWithin: window, volume: scale, audition: audition)
            }
            return
        }
        guard let player = ready(sound, volume: scale, audition: audition) else { return }
        let wait = window.map { max(0, $0 - player.duration / Double(max(player.rate, 0.5))) } ?? 0
        if wait > 0.005 { player.play(atTime: player.deviceCurrentTime + wait) } else { player.play() }
        logPlay(sound, player, wait: wait)
    }

    /// Several cues due at the same moment (a combat flurry), started on the same sample: each
    /// AVAudioPlayer takes a while to start the first time, which smeared them up to ~50 ms apart.
    /// `lead` is how far ahead the shared start is set: long enough to ready every voice first (a few at ~30 ms each).
    func playTogether(_ cues: [(sound: GameSound, volume: Float)], lead: TimeInterval = 0.1) {
        guard !isTesting, effectsEnabled, effectsVolume > 0 else { return }
        let players = cues.filter { isEnabled($0.sound.category) }.compactMap { cue in
            ready(cue.sound, volume: cue.volume, audition: false).map { (cue.sound, $0) }
        }
        guard let clock = players.first?.1.deviceCurrentTime else { return }
        for (sound, player) in players {
            player.play(atTime: clock + lead)
            logPlay(sound, player)
        }
    }

    /// A voice for this cue, levelled and pitched, unless it played too recently.
    private func ready(_ sound: GameSound, volume scale: Float, audition: Bool) -> AVAudioPlayer? {
        let now = ProcessInfo.processInfo.systemUptime
        if !audition, let last = lastPlayed[sound], now - last < sound.cooldown { return nil }
        lastPlayed[sound] = now
        prepareSession()
        guard let player = player(for: sound) else { return nil }
        player.volume = min(1, sound.volume * max(effectsVolume, audition ? 0.6 : 0) * scale)
        if sound.pitchVariation > 0 {
            player.rate = 1 + Float.random(in: -sound.pitchVariation...sound.pitchVariation)
        }
        player.currentTime = 0
        return player
    }

    private func logPlay(_ sound: GameSound, _ player: AVAudioPlayer, wait: TimeInterval = 0) {
        #if DEBUG
        // Visual QA: MAGICMOBILE_LOG_SOUNDS=1 prints each cue as it plays (its start on the device clock too), so a
        // silent simulator recording can be given its soundtrack afterwards. It names the file played, so a random
        // variant ("creature-dragon-2") is the one put back.
        if Self.logsPlays {
            let file = player.url?.deletingPathExtension().lastPathComponent ?? sound.rawValue
            print("MMSOUND \(Date().timeIntervalSince1970 + wait) \(file) \(player.volume) \(player.rate) \(player.deviceCurrentTime + wait)")
        }
        #endif
    }

    #if DEBUG
    private static let logsPlays = ProcessInfo.processInfo.environment["MAGICMOBILE_LOG_SOUNDS"] == "1"
    #endif

    // MARK: Music

    /// The track this scene plays next: the player's pick, or the next one in a shuffle
    /// that never repeats the track just heard.
    private func nextTrack(for scene: GameMusic) -> MusicTrack {
        let choice = defaults.string(forKey: scene.choiceKey) ?? "shuffle"
        if let picked = scene.tracks.first(where: { $0.file == choice }) { return picked }
        let others = scene.tracks.filter { $0.file != lastTrack[scene] }
        return others.randomElement() ?? scene.tracks[0]
    }

    /// Crossfades to the playlist for `scene` (nil fades music out). Safe to call repeatedly.
    func playMusic(_ scene: GameMusic?) {
        guard !isTesting else { return }
        guard musicEnabled, let scene else {
            stopMusic()
            currentTrack = nil
            return
        }
        if currentTrack == scene, musicPlayer?.isPlaying == true, !previewing { return }
        currentTrack = scene
        start(nextTrack(for: scene), scene: scene, fadeIn: 2.0)
    }

    private func start(_ track: MusicTrack, scene: GameMusic, fadeIn: TimeInterval) {
        prepareSession()
        stopMusic(fade: 1.2)
        guard let url = url(track.file), let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = musicEnd
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(targetMusicVolume(scene), fadeDuration: fadeIn)
        musicPlayer = player
        nowPlaying = track
        lastTrack[scene] = track.file
    }

    private func trackFinished(_ player: AVAudioPlayer) {
        guard player === musicPlayer, let scene = currentTrack, musicEnabled else { return }
        previewing = false
        start(nextTrack(for: scene), scene: scene, fadeIn: 1.0)
    }

    /// Sound Lab: hear one track now. The scene's playlist returns with `endPreview`.
    func preview(_ track: MusicTrack, in scene: GameMusic) {
        guard !isTesting else { return }
        previewing = true
        let playing = currentTrack ?? scene
        currentTrack = playing
        start(track, scene: playing, fadeIn: 0.6)
    }

    func endPreview() {
        guard previewing else { return }
        previewing = false
        guard let scene = currentTrack, musicEnabled else { stopMusic(); return }
        start(nextTrack(for: scene), scene: scene, fadeIn: 1.5)
    }

    private func targetMusicVolume(_ scene: GameMusic) -> Float {
        let ducked = ProcessInfo.processInfo.systemUptime < duckedUntil
        return scene.level * max(musicVolume, previewing ? 0.5 : 0) * (ducked ? 0.25 : 1)
    }

    private func stopMusic(fade: TimeInterval = 0.8) {
        guard let player = musicPlayer else { return }
        musicPlayer = nil
        nowPlaying = nil
        player.delegate = nil
        player.setVolume(0, fadeDuration: fade)
        fadingPlayers.append(player)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(fade + 0.1))
            player.stop()
            self?.fadingPlayers.removeAll { $0 === player }
        }
    }

    /// Lowers the music under a fanfare or stinger, then restores it.
    func duckMusic(for seconds: TimeInterval) {
        guard let player = musicPlayer, let scene = currentTrack else { return }
        duckedUntil = ProcessInfo.processInfo.systemUptime + seconds
        player.setVolume(targetMusicVolume(scene), fadeDuration: 0.4)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.musicPlayer === player else { return }
            player.setVolume(self.targetMusicVolume(scene), fadeDuration: 1.5)
        }
    }

    /// Apply changed settings (toggles, sliders or a new track pick) immediately.
    func settingsChanged(trackPickChanged: Bool = false) {
        if !musicEnabled, !previewing {
            stopMusic(fade: 0.4)
        } else if let scene = currentTrack {
            if let player = musicPlayer, !trackPickChanged {
                player.setVolume(targetMusicVolume(scene), fadeDuration: 0.3)
            } else if !previewing {
                start(nextTrack(for: scene), scene: scene, fadeIn: 1.2)
            }
        }
    }

    /// Remembers which playlist belongs on screen even while music is switched off.
    func setScene(_ scene: GameMusic) {
        previewing = false
        if musicEnabled { playMusic(scene) } else { currentTrack = scene }
    }

    /// In the background: free every decoded sound and the music buffer, which lowers the
    /// chance that iOS ends the app. Effects reload on their next play; `resume()` restarts music.
    func unloadBuffers() {
        for player in pools.values.joined() { player.stop() }
        pools.removeAll(); nextVoice.removeAll()
        for player in fadingPlayers { player.stop() }
        fadingPlayers.removeAll()
        if let player = musicPlayer {
            player.delegate = nil
            player.stop()
            musicPlayer = nil
            nowPlaying = nil
        }
        previewing = false
    }

    /// iOS stops an ambient session's players in the background; pick the playlist back up.
    func resume() {
        guard let scene = currentTrack, musicEnabled, musicPlayer?.isPlaying != true else { return }
        musicPlayer = nil
        start(nextTrack(for: scene), scene: scene, fadeIn: 2.0)
    }
}

/// AVAudioPlayer reports the end of a track to an NSObject delegate.
private final class MusicEndObserver: NSObject, AVAudioPlayerDelegate {
    var onFinish: (@MainActor (AVAudioPlayer) -> Void)?

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onFinish?(player) }
    }
}

// MARK: - Interface sounds

extension View {
    /// Plays an interface sound when the control is touched down, like a physical button.
    /// Nil stays silent: most buttons are quiet, and the action's result makes its own sound.
    func pressSound(_ sound: GameSound?, isPressed: Bool) -> some View {
        onChange(of: isPressed) { _, pressed in
            if pressed, let sound { GameAudio.shared.play(sound) }
        }
    }
}

// MARK: - Board sounds the effect timeline does not model

/// Your draws, read from consecutive snapshots.
struct GameSoundSignature: Equatable {
    let gameID: String
    let handCount: Int

    init(_ snapshot: GameSnapshot) {
        gameID = snapshot.id
        handCount = snapshot.players.first { snapshot.isViewer($0.playerId) }?.zones.visibleHandCount ?? 0
    }

    /// At most two draw sounds for a big draw, so an opening hand is a flourish, not a burst.
    static func cues(from old: Self, to new: Self) -> [GameSound] {
        guard old.gameID == new.gameID, new.handCount > old.handCount else { return [] }
        return Array(repeating: .cardDraw, count: min(2, new.handCount - old.handCount))
    }
}
