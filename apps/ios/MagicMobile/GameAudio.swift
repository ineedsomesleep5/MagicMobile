import AVFoundation
import SwiftUI

/// Every sound effect in the game. File names match Resources/Audio, rendered by
/// scripts/audio/build_game_audio.py (Kenney CC0 foley plus original synthesis).
enum GameSound: String, CaseIterable {
    // Interface
    case uiTap = "ui-tap", uiConfirm = "ui-confirm", uiBack = "ui-back", uiOpen = "ui-open",
         uiClose = "ui-close", uiToggle = "ui-toggle", uiTick = "ui-tick", uiError = "ui-error",
         responseAlert = "response-alert", menuPlay = "menu-play", pageFlip = "page-flip"
    // Cards
    case cardDraw = "card-draw", cardPickup = "card-pickup", cardPlay = "card-play", handFan = "hand-fan",
         shuffle, cardPlace = "card-place"
    // Board
    case landDrop = "land-drop", creatureEnter = "creature-enter", tokenCreate = "token-create",
         manaTap = "mana-tap", counter, ability
    // Spells by color identity
    case castWhite = "cast-white", castBlue = "cast-blue", castBlack = "cast-black", castRed = "cast-red",
         castGreen = "cast-green", castColorless = "cast-colorless", castMulti = "cast-multi",
         spellBig = "spell-big", commanderCast = "commander-cast"
    // Combat and life
    case attack, block, strike, playerHit = "player-hit", death, exile,
         lifeGain = "life-gain", lifeLoss = "life-loss", stackResolve = "stack-resolve"
    // Big moments
    case turnYou = "turn-you", turnOpponent = "turn-opponent", gameStart = "game-start", versus,
         victory, defeat, diceRoll = "dice-roll", diceLand = "dice-land"

    /// Numbered files ("card-draw-1…3") give repeated sounds natural variety.
    var variants: Int {
        switch self {
        case .cardDraw: return 3
        case .manaTap: return 2
        default: return 1
        }
    }

    /// Mix level, balanced by ear-free loudness measurements (see audio-manifest.json).
    var volume: Float {
        switch self {
        case .uiTap, .uiTick, .uiToggle: return 0.55
        case .uiBack, .uiOpen, .uiClose, .pageFlip: return 0.6
        case .uiConfirm, .uiError, .responseAlert: return 0.7
        case .cardDraw, .cardPickup, .handFan: return 0.75
        case .cardPlay, .cardPlace, .shuffle: return 0.8
        case .landDrop, .creatureEnter, .playerHit, .attack: return 1.0
        case .manaTap, .counter, .stackResolve: return 0.6
        case .tokenCreate, .ability, .exile, .lifeGain, .lifeLoss: return 0.75
        case .castWhite, .castBlue, .castBlack, .castRed, .castGreen, .castColorless, .castMulti: return 0.85
        case .spellBig, .commanderCast, .block, .strike, .death: return 0.9
        case .turnYou, .gameStart, .versus, .victory, .defeat, .menuPlay: return 0.9
        case .turnOpponent: return 0.6
        case .diceRoll, .diceLand: return 0.85
        }
    }

    /// A little pitch variation keeps repeated foley from sounding mechanical; musical
    /// cues stay in tune.
    var pitchVariation: Float {
        switch self {
        case .cardDraw, .cardPickup, .cardPlay, .cardPlace, .landDrop, .creatureEnter, .strike,
             .playerHit, .death, .attack, .block, .uiTap, .counter, .manaTap, .tokenCreate, .shuffle:
            return 0.045
        default: return 0
        }
    }

    /// Simultaneous copies allowed (a board wipe plays several deaths at once).
    var voices: Int {
        switch self {
        case .strike, .death, .manaTap, .cardDraw, .counter, .tokenCreate, .uiTap, .creatureEnter: return 4
        case .victory, .defeat, .gameStart, .versus, .turnYou, .turnOpponent, .menuPlay: return 1
        default: return 2
        }
    }

    /// Minimum time between two plays of this cue. Twelve triggers resolving together
    /// should read as a flurry, not a wall of identical sounds.
    var cooldown: TimeInterval {
        switch self {
        case .uiTap, .uiTick, .cardDraw, .manaTap, .counter: return 0.05
        case .strike, .death, .tokenCreate, .creatureEnter, .landDrop, .cardPlace: return 0.08
        case .castWhite, .castBlue, .castBlack, .castRed, .castGreen, .castColorless, .castMulti, .ability: return 0.2
        case .turnYou, .turnOpponent, .gameStart, .versus, .victory, .defeat: return 1.5
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
}

enum GameMusic: String {
    case menu = "music-menu", game = "music-game"

    var level: Float { self == .menu ? 0.55 : 0.4 }
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

    private var pools: [String: [AVAudioPlayer]] = [:]
    private var nextVoice: [String: Int] = [:]
    private var lastPlayed: [GameSound: TimeInterval] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var fadingPlayers: [AVAudioPlayer] = []
    private(set) var currentTrack: GameMusic?
    private var duckedUntil: TimeInterval = 0
    private var sessionReady = false
    private let isTesting = NSClassFromString("XCTestCase") != nil

    private var defaults: UserDefaults { MagicMobilePreferences.current }
    var effectsEnabled: Bool { defaults.object(forKey: Self.effectsKey) as? Bool ?? true }
    var musicEnabled: Bool { defaults.object(forKey: Self.musicKey) as? Bool ?? true }
    var effectsVolume: Float { Float(defaults.object(forKey: Self.effectsVolumeKey) as? Double ?? 0.9) }
    var musicVolume: Float { Float(defaults.object(forKey: Self.musicVolumeKey) as? Double ?? 0.6) }

    private init() {}

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

    func play(_ sound: GameSound, after delay: TimeInterval = 0, volume scale: Float = 1) {
        guard !isTesting, effectsEnabled, effectsVolume > 0 else { return }
        if delay > 0.005 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.play(sound, after: 0, volume: scale)
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[sound], now - last < sound.cooldown { return }
        lastPlayed[sound] = now
        prepareSession()
        guard let player = player(for: sound) else { return }
        player.volume = min(1, sound.volume * effectsVolume * scale)
        if sound.pitchVariation > 0 {
            player.rate = 1 + Float.random(in: -sound.pitchVariation...sound.pitchVariation)
        }
        player.currentTime = 0
        player.play()
    }

    // MARK: Music

    /// Crossfades to `track` (nil fades music out). Safe to call repeatedly.
    func playMusic(_ track: GameMusic?) {
        guard !isTesting else { return }
        guard musicEnabled, musicVolume > 0, let track else {
            stopMusic()
            currentTrack = nil
            return
        }
        if currentTrack == track, musicPlayer?.isPlaying == true { return }
        prepareSession()
        stopMusic(fade: 1.2)
        guard let url = url(track.rawValue), let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(targetMusicVolume(track), fadeDuration: 2.0)
        musicPlayer = player
        currentTrack = track
    }

    private func targetMusicVolume(_ track: GameMusic) -> Float {
        let ducked = ProcessInfo.processInfo.systemUptime < duckedUntil
        return track.level * musicVolume * (ducked ? 0.25 : 1)
    }

    private func stopMusic(fade: TimeInterval = 0.8) {
        guard let player = musicPlayer else { return }
        musicPlayer = nil
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
        guard let player = musicPlayer, let track = currentTrack else { return }
        duckedUntil = ProcessInfo.processInfo.systemUptime + seconds
        player.setVolume(targetMusicVolume(track), fadeDuration: 0.4)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.musicPlayer === player else { return }
            player.setVolume(self.targetMusicVolume(track), fadeDuration: 1.5)
        }
    }

    /// Apply changed settings (toggles or sliders) immediately.
    func settingsChanged() {
        if !musicEnabled || musicVolume <= 0 {
            stopMusic(fade: 0.4)
        } else if let track = currentTrack {
            if let player = musicPlayer {
                player.setVolume(targetMusicVolume(track), fadeDuration: 0.3)
            } else {
                currentTrack = nil
                playMusic(track)
            }
        }
    }

    /// Remembers which track belongs on screen even while music is switched off.
    func setScene(_ track: GameMusic) {
        if musicEnabled { playMusic(track) } else { currentTrack = track }
    }

    /// iOS stops an ambient session's players in the background; pick the track back up.
    func resume() {
        guard let track = currentTrack, musicEnabled, musicPlayer?.isPlaying != true else { return }
        musicPlayer = nil
        currentTrack = nil
        playMusic(track)
    }
}

// MARK: - Interface sounds

extension View {
    /// Plays a soft interface click when the control is touched down, like a physical button.
    func pressSound(_ sound: GameSound = .uiTap, isPressed: Bool) -> some View {
        onChange(of: isPressed) { _, pressed in
            if pressed { GameAudio.shared.play(sound) }
        }
    }
}

// MARK: - Board sounds the effect timeline does not model

/// Your draws, your mana taps and stack resolutions, read from consecutive snapshots.
struct GameSoundSignature: Equatable {
    let gameID: String
    let handCount: Int
    let tappedLands: Int
    let stackCount: Int

    init(_ snapshot: GameSnapshot) {
        gameID = snapshot.id
        let viewer = snapshot.players.first { snapshot.isViewer($0.playerId) }
        handCount = viewer?.zones.visibleHandCount ?? 0
        tappedLands = viewer?.zones.battlefield.filter {
            $0.tapped == true && $0.card.typeLine.localizedCaseInsensitiveContains("land")
        }.count ?? 0
        stackCount = snapshot.xmage?.stack.count ?? viewer?.zones.stack.count ?? 0
    }

    /// At most three draw sounds for a big draw; one tap and one resolution per update.
    static func cues(from old: Self, to new: Self) -> [GameSound] {
        guard old.gameID == new.gameID else { return [] }
        var cues: [GameSound] = []
        if new.handCount > old.handCount {
            cues += Array(repeating: .cardDraw, count: min(3, new.handCount - old.handCount))
        }
        if new.tappedLands > old.tappedLands { cues.append(.manaTap) }
        if new.stackCount < old.stackCount { cues.append(.stackResolve) }
        return cues
    }
}
