import SwiftUI

/// Quick chat: a fixed set of friendly lines, never free text.
enum GameEmote: String, CaseIterable, Identifiable {
    case hello, wellPlayed, thanks, oops, wow, goodGame

    var id: String { rawValue }

    var text: String {
        switch self {
        case .hello: return String(localized: "Hello!")
        case .wellPlayed: return String(localized: "Well played!")
        case .thanks: return String(localized: "Thanks!")
        case .oops: return String(localized: "Oops!")
        case .wow: return String(localized: "Wow!")
        case .goodGame: return String(localized: "Good game!")
        }
    }

    var symbol: String {
        switch self {
        case .hello: return "hand.wave.fill"
        case .wellPlayed: return "hands.clap.fill"
        case .thanks: return "heart.fill"
        case .oops: return "exclamationmark.bubble.fill"
        case .wow: return "sparkles"
        case .goodGame: return "flag.checkered"
        }
    }

    /// What an AI opponent says back, when it answers at all.
    var aiReply: GameEmote? {
        switch self {
        case .hello: return .hello
        case .wellPlayed: return .thanks
        case .goodGame: return .goodGame
        case .wow: return .thanks
        case .oops, .thanks: return nil
        }
    }
}

/// Speech bubbles on the table, keyed by engine player ID, plus the way out to other players.
@MainActor
final class EmoteCenter: ObservableObject {
    struct Bubble: Equatable {
        let id = UUID()
        let emote: GameEmote
    }

    @Published private(set) var bubbles: [String: Bubble] = [:]
    @Published private(set) var canSend = true
    /// Game Center: delivers your emote to the other players.
    var send: ((GameEmote) -> Void)?
    private var lastHeard: [String: Date] = [:]

    func show(_ emote: GameEmote, from playerID: String) {
        let bubble = Bubble(emote: emote)
        bubbles[playerID] = bubble
        GameAudio.shared.play(.emote)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            if self?.bubbles[playerID]?.id == bubble.id { self?.bubbles[playerID] = nil }
        }
    }

    /// You emote: show it, tell the other players, and let an AI opponent answer now and then.
    func say(_ emote: GameEmote, in snapshot: GameSnapshot) {
        guard canSend else { return }
        canSend = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.canSend = true
        }
        show(emote, from: snapshot.viewerID)
        send?(emote)
        let bots = snapshot.players.filter { !snapshot.isViewer($0.playerId) && $0.isHuman == false && !$0.isOut }
        if let reply = emote.aiReply, let bot = bots.randomElement(), Double.random(in: 0..<1) < 0.6 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Double.random(in: 1.1...2.0)))
                self?.show(reply, from: bot.playerId)
            }
        }
    }

    /// A Game Center player's emote, matched to their seat by the name shown at the table.
    func receive(_ emote: GameEmote, fromName name: String, in snapshot: GameSnapshot?) {
        guard let snapshot, let player = snapshot.players.first(where: {
            !snapshot.isViewer($0.playerId) && $0.displayName == name
        }) else { return }
        if let last = lastHeard[player.playerId], Date().timeIntervalSince(last) < 1.5 { return }
        lastHeard[player.playerId] = Date()
        show(emote, from: player.playerId)
    }

    func reset() { bubbles = [:]; lastHeard = [:] }
}

private struct EmoteCenterKey: EnvironmentKey { static let defaultValue: EmoteCenter? = nil }

extension EnvironmentValues {
    /// Set by on-device games; the hosted board has no quick chat.
    var emoteCenter: EmoteCenter? {
        get { self[EmoteCenterKey.self] }
        set { self[EmoteCenterKey.self] = newValue }
    }
}

/// The bubble for one player, if they just emoted.
struct EmoteBubbleSlot: View {
    @ObservedObject var center: EmoteCenter
    let playerID: String
    var pointsUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let bubble = center.bubbles[playerID] {
                EmoteBubble(emote: bubble.emote, pointsUp: pointsUp)
                    .id(bubble.id)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4, anchor: pointsUp ? .top : .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.62), value: center.bubbles[playerID])
        .allowsHitTesting(false)
    }
}

/// The latest opponent emote, named when it is not the opponent in focus.
struct OpponentEmoteSlot: View {
    @ObservedObject var center: EmoteCenter
    let snapshot: GameSnapshot
    let focusedID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var latest: (player: PlayerGameState, bubble: EmoteCenter.Bubble)? {
        snapshot.players.filter { !snapshot.isViewer($0.playerId) }
            .compactMap { player in center.bubbles[player.playerId].map { (player, $0) } }
            .first { $0.player.playerId == focusedID } ?? snapshot.players.filter { !snapshot.isViewer($0.playerId) }
            .compactMap { player in center.bubbles[player.playerId].map { (player, $0) } }.first
    }

    var body: some View {
        ZStack {
            if let latest {
                EmoteBubble(emote: latest.bubble.emote,
                            name: latest.player.playerId == focusedID ? nil : latest.player.displayName)
                    .id(latest.bubble.id)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.62), value: latest?.bubble)
        .allowsHitTesting(false)
    }
}

struct EmoteBubble: View {
    let emote: GameEmote
    var pointsUp = false
    var name: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: emote.symbol).font(.system(size: 13, weight: .bold))
                .foregroundStyle(MagicPalette.oxblood)
            if let name {
                Text("\(name):")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(MagicPalette.oxblood)
                    .fixedSize()
            }
            Text(emote.text)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.11, blue: 0.08))
                .fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.98, blue: 0.92), Color(red: 0.93, green: 0.87, blue: 0.74)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MagicPalette.antiqueGold, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Emote choices shown when you tap your own life orb.
struct EmotePicker: View {
    @ObservedObject var center: EmoteCenter
    let snapshot: GameSnapshot
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK CHAT")
                .font(.system(size: 11, weight: .black)).tracking(1.6)
                .foregroundStyle(MagicPalette.antiqueGold)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(GameEmote.allCases) { emote in
                    Button {
                        center.say(emote, in: snapshot)
                        done()
                    } label: {
                        Label(emote.text, systemImage: emote.symbol)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                    .disabled(!center.canSend)
                    .accessibilityIdentifier("board.emote.\(emote.rawValue)")
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(MagicPalette.iron.opacity(0.97))
    }
}
