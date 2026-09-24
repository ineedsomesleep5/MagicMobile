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
        case .cards: return String(localized: "Drawing, playing, lands, creatures, tokens and counters.")
        case .spells: return String(localized: "A cast sound for each color, big spells and your commander.")
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
         responseAlert = "response-alert", menuPlay = "menu-play", pageFlip = "page-flip", emote
    // Cards and board
    case cardDraw = "card-draw", cardPickup = "card-pickup", cardPlay = "card-play", shuffle,
         landDrop = "land-drop", creatureEnter = "creature-enter", tokenCreate = "token-create",
         counter, ability
    // Spells by color identity
    case castWhite = "cast-white", castBlue = "cast-blue", castBlack = "cast-black", castRed = "cast-red",
         castGreen = "cast-green", castColorless = "cast-colorless", castMulti = "cast-multi",
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
             .responseAlert, .menuPlay, .pageFlip, .emote: return .interface
        case .cardDraw, .cardPickup, .cardPlay, .shuffle, .landDrop, .creatureEnter, .tokenCreate,
             .counter, .ability: return .cards
        case .castWhite, .castBlue, .castBlack, .castRed, .castGreen, .castColorless, .castMulti,
             .spellBig, .commanderCast: return .spells
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
        case .emote: return String(localized: "Emote")
        case .cardDraw: return String(localized: "Draw a card")
        case .cardPickup: return String(localized: "Pick up a card")
        case .cardPlay: return String(localized: "Play a card")
        case .shuffle: return String(localized: "Shuffle (mulligan)")
        case .landDrop: return String(localized: "Land")
        case .creatureEnter: return String(localized: "Creature arrives")
        case .tokenCreate: return String(localized: "Token")
        case .counter: return String(localized: "Counter")
        case .ability: return String(localized: "Your ability")
        case .castWhite: return String(localized: "White spell")
        case .castBlue: return String(localized: "Blue spell")
        case .castBlack: return String(localized: "Black spell")
        case .castRed: return String(localized: "Red spell")
        case .castGreen: return String(localized: "Green spell")
        case .castColorless: return String(localized: "Colorless spell")
        case .castMulti: return String(localized: "Multicolor spell")
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

    /// Numbered files ("card-draw-1…3") give repeated sounds natural variety.
    var variants: Int {
        switch self {
        case .cardDraw, .attack: return 3
        default: return 1
        }
    }

    /// Mix level. Files are already loudness-matched (audio-manifest.json); this sets the
    /// balance: interface quiet, the board clear, big moments on top.
    var volume: Float {
        switch self {
        case .uiTap, .uiTick, .uiToggle, .uiBack, .uiOpen, .uiClose: return 0.5
        case .uiConfirm, .uiError, .pageFlip, .emote: return 0.65
        case .responseAlert, .menuPlay: return 0.8
        case .cardDraw, .cardPickup, .counter, .ability: return 0.7
        case .cardPlay, .shuffle, .landDrop, .creatureEnter, .tokenCreate: return 0.85
        case .castWhite, .castBlue, .castBlack, .castRed, .castGreen, .castColorless, .castMulti: return 0.85
        case .spellBig, .commanderCast, .attack, .block, .strike, .playerHit: return 0.9
        case .death, .exile, .lifeGain, .lifeLoss: return 0.75
        case .turnYou, .versus, .victory, .defeat: return 0.9
        case .diceRoll, .diceLand: return 0.85
        }
    }

    /// A little pitch variation keeps repeated foley from sounding mechanical; musical
    /// cues stay in tune.
    var pitchVariation: Float {
        switch self {
        case .cardDraw, .cardPickup, .cardPlay, .landDrop, .creatureEnter, .strike, .playerHit,
             .death, .attack, .block, .counter, .tokenCreate, .shuffle, .diceLand:
            return 0.04
        default: return 0
        }
    }

    /// Simultaneous copies allowed (a board wipe plays several deaths at once).
    var voices: Int {
        switch self {
        case .strike, .death, .cardDraw, .tokenCreate, .creatureEnter: return 3
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
        case .strike, .death, .tokenCreate, .creatureEnter, .landDrop: return 0.12
        case .counter, .lifeGain: return 0.3
        case .castWhite, .castBlue, .castBlack, .castRed, .castGreen, .castColorless, .castMulti: return 0.25
        case .ability: return 0.8
        case .responseAlert: return 1.2
        case .turnYou, .versus, .victory, .defeat: return 1.5
        default: return 0.12
        }
    }

    static func cast(for tint: BoardFXTint) -> GameSound {
        switch tint {
        case .white: return .castWhite
        case .blue: return .castBlue
        case .black: return .castBlack
        case .red: return .castRed
        case .green: return .castGreen
        case .multicolor: return .castMulti
        case .colorless: return .castColorless
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
    private let isTesting = NSClassFromString("XCTestCase") != nil

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
        let file = sound.variants > 1 ? "\(sound.rawValue)-\(Int.random(in: 1...sound.variants))" : sound.rawValue
        var pool = pools[file] ?? []
        if pool.count < sound.voices, let url = url(file), let player = try? AVAudioPlayer(contentsOf: url) {
            player.enableRate = sound.pitchVariation > 0
            player.prepareToPlay()
            pool.append(player)
            pools[file] = pool
        }
        guard !pool.isEmpty else { return nil }
        // Prefer an idle voice; otherwise steal the oldest in round-robin order.
        if let idle = pool.first(where: { !$0.isPlaying }) { return idle }
        let index = (nextVoice[file] ?? 0) % pool.count
        nextVoice[file] = index + 1
        return pool[index]
    }

    /// Warm up the players used in the first seconds of a game so the first cast is instant.
    func preload(_ sounds: [GameSound]) {
        guard !isTesting else { return }
        for sound in sounds { _ = player(for: sound) }
    }

    /// `audition` plays a sound from the Sound Lab even when its category is off.
    func play(_ sound: GameSound, after delay: TimeInterval = 0, volume scale: Float = 1, audition: Bool = false) {
        guard !isTesting, effectsEnabled || audition, effectsVolume > 0 || audition,
              isEnabled(sound.category) || audition else { return }
        if delay > 0.005 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.play(sound, after: 0, volume: scale, audition: audition)
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if !audition, let last = lastPlayed[sound], now - last < sound.cooldown { return }
        lastPlayed[sound] = now
        prepareSession()
        guard let player = player(for: sound) else { return }
        player.volume = min(1, sound.volume * max(effectsVolume, audition ? 0.6 : 0) * scale)
        if sound.pitchVariation > 0 {
            player.rate = 1 + Float.random(in: -sound.pitchVariation...sound.pitchVariation)
        }
        player.currentTime = 0
        player.play()
    }

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
