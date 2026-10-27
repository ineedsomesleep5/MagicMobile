import Foundation

/// Voice chat at online tables (voiceChat.ts / VoiceChatRules.kt, parity/voice-cases.json; docs/VOICE_CHAT.md). Each
/// game has its own Agora channel, "mm-" + the game's epoch: a UUID only that table's players receive, so knowing the
/// channel is being at the table. Each player joins as their seat id. Nobody is in voice until they tap the mic.
enum VoiceChatRules {
    /// The server switch (mm_app_config). Off unless the server turns it on, unlike the older switches.
    static let switchName = "voiceChat"
    /// A level (0–1) at or past this is speech.
    static let speakingLevel = 0.08
    /// A speaker stays lit this long after the last loud report, so a sentence doesn't flicker.
    static let holdSeconds = 0.6

    /// The game's channel, lower case (iOS writes UUIDs upper case, Android and the web lower case).
    static func channel(epoch: String?) -> String? {
        guard let lower = epoch?.lowercased(), lower.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
                                                         options: .regularExpression) != nil else { return nil }
        return "mm-\(lower)"
    }

    /// The Agora account for a seat: the seat id itself.
    static func account(seat: String?) -> String? {
        guard let seat, seat.range(of: #"^player[1-9]$"#, options: .regularExpression) != nil else { return nil }
        return seat
    }

    static func isSpeaking(level: Double) -> Bool { level >= speakingLevel }

    static func stillSpeaking(heardAt: Double?, now: Double) -> Bool {
        guard let heardAt else { return false }
        return now - heardAt <= holdSeconds + 1e-9
    }

    /// Whether the board shows the mic: the switch on, a table with people, the game started, the server able to answer.
    static func shown(switchOn: Bool, solo: Bool, channel: Bool, account: Bool, unavailable: Bool) -> Bool {
        switchOn && !solo && channel && account && !unavailable
    }
}

/// What the board shows of a game's voice channel (VoiceRoom publishes it).
struct VoiceChatState: Equatable {
    enum Stage: Equatable { case off, joining, live, unavailable }
    var stage = Stage.off
    /// Your microphone is off (you still hear the table).
    var muted = false
    /// The microphone permission was refused: you hear the table but can't talk.
    var micBlocked = false
    /// Seats in the channel, yours included while live.
    var inVoice: Set<String> = []
    /// Seats talking right now (lit `holdSeconds` past the last loud report).
    var speaking: Set<String> = []
    /// Seats that turned their own microphone off.
    var selfMuted: Set<String> = []
    /// Seats you silenced for yourself.
    var silenced: Set<String> = []
}
