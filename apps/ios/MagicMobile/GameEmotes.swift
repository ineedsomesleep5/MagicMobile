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

    /// One line in the table's chat: a typed message or a quick-chat emote.
    struct ChatLine: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let text: String
        let isLocal: Bool
        let emote: GameEmote?
    }

    @Published private(set) var bubbles: [String: Bubble] = [:]
    @Published private(set) var canSend = true
    /// Game Center: delivers your emote to the other players.
    var send: ((GameEmote) -> Void)?
    /// Tables with other people: delivers your typed message. Nil in AI games (no chat panel).
    var sendText: ((String) -> Void)? { didSet { objectWillChange.send() } }
    var canChat: Bool { sendText != nil }
    @Published private(set) var lines: [ChatLine] = []
    @Published private(set) var unread = 0
    @Published var isChatOpen = false { didSet { if isChatOpen { unread = 0 } } }
    /// Table names whose messages you have hidden for this game.
    @Published private(set) var muted: Set<String> = []
    private var lastHeard: [String: Date] = [:]
    private var lastText = Date.distantPast
    static let maxLines = 150

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
        if canChat { append(ChatLine(name: String(localized: "You"), text: emote.text, isLocal: true, emote: emote)) }
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
        guard !muted.contains(name) else { return }
        show(emote, from: player.playerId)
        append(ChatLine(name: name, text: emote.text, isLocal: false, emote: emote))
    }

    /// Sends a typed message. False when there is nothing to send or it came too soon after the last.
    @discardableResult
    func say(text raw: String) -> Bool {
        guard let sendText, let text = TableChatText.sanitize(raw), Date().timeIntervalSince(lastText) >= 0.7 else { return false }
        lastText = Date()
        sendText(text)
        append(ChatLine(name: String(localized: "You"), text: text, isLocal: true, emote: nil))
        return true
    }

    /// Another player's message, already checked by the table.
    func receive(text: String, fromName name: String) {
        guard !muted.contains(name) else { return }
        append(ChatLine(name: name, text: text, isLocal: false, emote: nil))
        GameAudio.shared.play(.emote)
    }

    func mute(_ name: String) {
        muted.insert(name)
        lines.removeAll { !$0.isLocal && $0.name == name }
    }

    func unmute(_ name: String) { muted.remove(name) }

    private func append(_ line: ChatLine) {
        lines.append(line)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        if !line.isLocal, !isChatOpen { unread += 1 }
    }

    func reset() { bubbles = [:]; lastHeard = [:]; lines = []; unread = 0; muted = []; isChatOpen = false }
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

/// Opens the table's chat, with a badge for messages you have not seen. Only tables with
/// other people have chat; AI games keep quick chat on the life orb.
struct TableChatButton: View {
    @ObservedObject var center: EmoteCenter

    var body: some View {
        if center.canChat {
            Button { center.isChatOpen = true } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.9))
                    .frame(minWidth: 44, minHeight: 44)
                    .overlay(alignment: .topTrailing) {
                        if center.unread > 0 {
                            Text(center.unread > 99 ? "99+" : "\(center.unread)")
                                .font(.system(size: 10, weight: .black)).monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(MagicPalette.oxblood, in: Capsule())
                                .overlay(Capsule().stroke(.black.opacity(0.6), lineWidth: 1))
                                .offset(x: 2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Chat")
            .accessibilityValue(center.unread > 0 ? "\(center.unread) unread" : "")
            .accessibilityIdentifier("board.chat")
        }
    }
}

/// The table's chat: typed messages and quick chat, newest at the bottom. Other players'
/// messages can be muted for this game or reported.
struct TableChatPanel: View {
    @ObservedObject var center: EmoteCenter
    let snapshot: GameSnapshot?
    /// Sends a report of another player's message; nil when reporting is unavailable.
    var report: ((EmoteCenter.ChatLine) -> Void)?
    /// Blocks a player by their table name (their profile name); nil without a profile.
    var block: ((String) -> Void)?
    /// Opens a player's profile by their table name; nil without a profile.
    var viewProfile: ((String) -> Void)?
    @AppStorage("magicmobile.chat.filterLanguage") private var filterLanguage = true
    @State private var draft = ""
    @State private var reported: Set<UUID> = []
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if center.lines.isEmpty {
                                Text("Say hi to the table. Messages last for this game only.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.top, 24)
                            }
                            ForEach(center.lines) { line in row(line).id(line.id) }
                        }
                        .padding(16)
                    }
                    .onAppear { if let last = center.lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .onChange(of: center.lines.last?.id) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                if let snapshot {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GameEmote.allCases) { emote in
                                Button { center.say(emote, in: snapshot) } label: {
                                    Label(emote.text, systemImage: emote.symbol)
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .padding(.horizontal, 10).frame(minHeight: 36)
                                }
                                .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                                .disabled(!center.canSend)
                                .accessibilityIdentifier("chat.emote.\(emote.rawValue)")
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .accessibilityIdentifier("chat.field")
                    Button(action: send) {
                        Image(systemName: "paperplane.fill").font(.system(size: 17, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(TableChatText.sanitize(draft) == nil)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("chat.send")
                }
                .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 4)
            }
            .tavernList()
            .navigationTitle("Table chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Filter language", isOn: $filterLanguage)
                        if !center.muted.isEmpty {
                            Section("Muted") {
                                ForEach(center.muted.sorted(), id: \.self) { name in
                                    Button("Unmute \(name)") { center.unmute(name) }
                                }
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Chat options")
                }
            }
        }
        .onAppear { center.isChatOpen = true }
        .onDisappear { center.isChatOpen = false }
    }

    private func send() {
        if center.say(text: draft) { draft = "" }
        fieldFocused = true
    }

    private func shown(_ line: EmoteCenter.ChatLine) -> String {
        filterLanguage && !line.isLocal ? TableChatFilter.filtered(line.text) : line.text
    }

    @ViewBuilder
    private func row(_ line: EmoteCenter.ChatLine) -> some View {
        VStack(alignment: line.isLocal ? .trailing : .leading, spacing: 3) {
            Text(line.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let emote = line.emote { Image(systemName: emote.symbol).foregroundStyle(MagicPalette.antiqueGold) }
                Text(shown(line)).font(.body)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(line.isLocal ? MagicPalette.antiqueGold.opacity(0.28) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if reported.contains(line.id) {
                Text("Reported").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: line.isLocal ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if !line.isLocal {
                if let viewProfile {
                    Button("View \(line.name)'s profile", systemImage: "person.crop.circle") { viewProfile(line.name) }
                }
                Button("Mute \(line.name)", systemImage: "speaker.slash") { center.mute(line.name) }
                if let block {
                    Button("Block \(line.name)", systemImage: "hand.raised") { block(line.name) }
                }
                if let report, !reported.contains(line.id) {
                    Button("Report message", systemImage: "exclamationmark.bubble", role: .destructive) {
                        report(line); reported.insert(line.id)
                    }
                }
            }
        }
    }
}
