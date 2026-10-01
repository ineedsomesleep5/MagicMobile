import SwiftUI
import PhotosUI
import UIKit

struct LoadingGameView: View {
    @State private var tipIndex = Int.random(in: 0..<LoadingGameView.tips.count)

    static let tips = [
        "Hold a card to inspect it. Drag a card upward to play it.",
        "Tap the stack beside your mana to see everything waiting to resolve.",
        "Skip ends your turn but stops for anything that needs your answer.",
        "Tap a land to add its mana; the engine pays costs exactly as the rules say.",
        "Your commander returns to the command zone when it would leave play.",
        "Legendary permanents wear a gold edge on the battlefield.",
        "Turn on music and effect sounds in Settings for the full table experience."
    ]

    var body: some View {
        ZStack {
            BrandBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                BrandMark(size: 72)

                Text("Shuffling up…")
                    .brandTitle(26)

                Text("Seating players at the table.")
                    .font(.callout)
                    .foregroundStyle(BrandTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                BrandDivider(title: "Tip").frame(maxWidth: 240).padding(.top, 4)
                Text(Self.tips[tipIndex % Self.tips.count])
                    .font(.footnote)
                    .foregroundStyle(BrandTheme.ink.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 40)
                    .id(tipIndex)
                    .transition(.opacity)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .brandPanel(padding: 0)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeInOut(duration: 0.4)) { tipIndex += 1 }
            }
        }
    }
}

/// Names kept for the many call sites that use them, but every value now resolves through
/// GameBoardTheme so the app has one palette rather than two near-identical ones. This
/// previously held its own gold (0.82/0.62/0.27) alongside the theme's (0.84/0.65/0.25),
/// which is why the menu and the board never quite matched. Prefer GameBoardTheme.current
/// in new code; DESIGN.md treats it as canonical.
enum MagicPalette {
    private static let theme = GameBoardTheme.current
    static let antiqueGold = theme.antiqueGold
    static let brass = theme.brass
    static let warningAmber = theme.warningAmber
    static let moss = theme.mossMid
    static let iron = theme.iron
    static let parchment = theme.whiteReadable
    static let parchmentShadow = theme.parchmentShadow
    static let oxblood = theme.dangerOxblood
    static let leather = theme.leatherMid
    static let carvedWood = theme.carvedWood
    static let emerald = theme.emeraldPriority
    static let arcaneBlue = theme.arcaneBlue
    static let legalEmerald = emerald
    static let priorityArcane = arcaneBlue
    static let panelParchment = theme.agedParchment
    static let borderBronze = theme.brass
    static let borderIron = theme.borderIron
    static let laneWood = theme.oak
}

struct BattlefieldSurface: View {
    var portraitModeEnabled = false
    @AppStorage(BoardAppearancePreference.key) private var appearance = BoardAppearancePreference.defaultValue

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BattlefieldBackdropArt(theme: .resolved(appearance))
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .black.opacity(0.34),
                                .black.opacity(0.05),
                                .black.opacity(0.08),
                                .black.opacity(0.38)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RadialGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.10),
                        .black.opacity(0.24)
                    ],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.20,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.62
                )
            }
        }
    }
}

struct AIWaitFallbackControls: View {
    let snapshot: GameSnapshot
    let pendingActionId: String?
    let liveUpdateStatus: String
    let beganAt: Date
    let didRefresh: Bool
    let didReconnect: Bool
    let didDiagnose: Bool
    let refreshAction: () -> Void
    let reconnectAction: () -> Void

    var body: some View {
        TimelineView(.periodic(from: beganAt, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(beganAt)
            let wait = XmageWaitPresentation.make(
                snapshot: snapshot,
                pendingActionId: pendingActionId,
                liveUpdateStatus: liveUpdateStatus,
                elapsedSeconds: elapsed,
                didRefresh: didRefresh,
                didReconnect: didReconnect,
                didDiagnose: didDiagnose
            )
            VStack(spacing: 7) {
                Text(wait.title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(wait.kind == .snapshotStale || wait.kind == .manualReconnectAvailable ? MagicPalette.warningAmber : MagicPalette.arcaneBlue)
                Text("\(Int(elapsed))s")
                    .font(.system(size: 18, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text(wait.detail)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Button("REFRESH", action: refreshAction)
                    .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                Button("RECONNECT", action: reconnectAction)
                    .buttonStyle(CompactActionButtonStyle(isPrimary: false))
            }
            .padding(8)
            .background(MagicPalette.iron.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke((wait.kind == .snapshotStale || wait.kind == .manualReconnectAvailable ? MagicPalette.warningAmber : MagicPalette.arcaneBlue).opacity(0.46), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        }
    }
}

struct GameRematchTitleKey: EnvironmentKey { static let defaultValue: String? = nil }

/// On-device games concede through the engine. Hosted games keep XMage's own "concede" action.
struct GameConcedeHandler {
    let concede: @MainActor () -> Void
}

struct GameConcedeKey: EnvironmentKey { static let defaultValue: GameConcedeHandler? = nil }

extension EnvironmentValues {
    var gameConcede: GameConcedeHandler? {
        get { self[GameConcedeKey.self] }
        set { self[GameConcedeKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// When set (solo games), the result screen's first button restarts the same match.
    var gameRematchTitle: String? {
        get { self[GameRematchTitleKey.self] }
        set { self[GameRematchTitleKey.self] = newValue }
    }
}

struct GameCompletionOverlay: View {
    let snapshot: GameSnapshot
    var stats: GameStats? = nil
    let newGame: () -> Void
    let quitGame: () -> Void
    @Environment(\.gameRematchTitle) private var rematchTitle

    private var title: String {
        guard let winners = snapshot.winnerPlayerIds, !winners.isEmpty else { return "Game Over" }
        return winners.contains(snapshot.viewerID) ? "Victory" : "Defeat"
    }

    private var winnerText: String {
        let names = snapshot.winnerDisplayNames
        if names.isEmpty { return "XMage has completed the match." }
        if names == ["You"] { return "You won the match." }
        return "Winner: \(names.joined(separator: ", "))"
    }

    private var reasonText: String? {
        guard let reason = snapshot.endReason, !reason.isEmpty else { return nil }
        return reason.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var isVictory: Bool { snapshot.winnerPlayerIds?.contains(snapshot.viewerID) == true }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            GameResultBackdrop(victory: isVictory)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Image(systemName: isVictory ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(isVictory ? MagicPalette.antiqueGold : Color(red: 0.8, green: 0.35, blue: 0.3))
                    .shadow(color: (isVictory ? MagicPalette.antiqueGold : .red).opacity(0.6), radius: 12)

                Text(title.uppercased())
                    .font(.system(size: 48, weight: .black, design: .serif))
                    .tracking(4)
                    .foregroundStyle(LinearGradient(colors: isVictory ? [.white, MagicPalette.antiqueGold, Color(red: 0.7, green: 0.5, blue: 0.16)]
                                                                      : [Color(white: 0.9), Color(red: 0.72, green: 0.2, blue: 0.18)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: (isVictory ? MagicPalette.antiqueGold : .red).opacity(0.55), radius: 16)
                    .scaleEffect(revealed || reduceMotion ? 1 : 1.6)
                    .opacity(revealed || reduceMotion ? 1 : 0)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(winnerText)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(MagicPalette.parchment)
                    .multilineTextAlignment(.center)

                if let reasonText {
                    Text(reasonText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                }

                if let stats, stats.turns > 0 {
                    GameSummaryPanel(stats: stats, victory: isVictory)
                        .opacity(revealed || reduceMotion ? 1 : 0)
                        .offset(y: revealed || reduceMotion ? 0 : 12)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.35), value: revealed)
                }

                HStack(spacing: 10) {
                    Button(rematchTitle ?? "New Game", action: newGame)
                        .accessibilityIdentifier("board.result.rematch")
                        .buttonStyle(CompactActionButtonStyle(isPrimary: true))
                    Button("Main Menu", action: quitGame)
                        .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(MagicPalette.iron.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke((isVictory ? MagicPalette.antiqueGold : Color(red: 0.6, green: 0.2, blue: 0.18)).opacity(0.8), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.48), radius: 18, y: 8)
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.1)) { revealed = true }
            UINotificationFeedbackGenerator().notificationOccurred(isVictory ? .success : .error)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game completed. \(title). \(winnerText)")
    }
}

/// The visible strip of an attachment tucked behind its creature: its name on a small tab.
struct AttachmentNameTab: View {
    let card: ZoneCard
    let height: CGFloat
    /// Further attachments not shown as tabs of their own.
    var more = 0

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: card.card.typeLine.localizedCaseInsensitiveContains("equipment") ? "shield.lefthalf.filled" : "sparkles")
                .font(.system(size: max(7, height * 0.5), weight: .bold))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text(card.card.name)
                .font(.system(size: max(7, height * 0.58), weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            if more > 0 {
                Text("+\(more)")
                    .font(.system(size: max(7, height * 0.55), weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                .fill(LinearGradient(colors: [MagicPalette.iron, Color.black.opacity(0.92)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                .stroke(MagicPalette.antiqueGold.opacity(0.6), lineWidth: 1)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shown instead of your controls once you're out of a pod: the game plays on without you.
struct SpectatorBar: View {
    let snapshot: GameSnapshot
    let leave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MagicPalette.antiqueGold)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().stroke(MagicPalette.antiqueGold.opacity(0.45), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // Whose seat the bottom of the board shows while you watch.
                Text(SpectatorSeatPresentation.title(snapshot))
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(SpectatorSeatPresentation.detail(snapshot))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Leave", action: leave)
                .buttonStyle(CompactActionButtonStyle(isPrimary: false))
                .accessibilityIdentifier("board.spectator.leave")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MagicPalette.iron.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MagicPalette.antiqueGold.opacity(0.42), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.spectator")
    }
}

/// The game in numbers under the result title, with the card that hit hardest.
struct GameSummaryPanel: View {
    let stats: GameStats
    let victory: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                tile(value: "\(stats.turns)", label: "Turns")
                tile(value: "\(stats.combatDamage)", label: "Combat damage")
                tile(value: "\(stats.creaturesDestroyed)", label: "Creatures destroyed")
            }
            if let top = stats.topCard {
                HStack(spacing: 10) {
                    Group {
                        // The battlefield card, so a token draws its own art ("Squirrel", not a card lookup).
                        if let card = top.card {
                            NativeCardArtworkView(card: card, variant: .board, contentMode: .fill, artOnly: true) { _, _ in MagicPalette.iron }
                        } else {
                            NativeCardArtworkView(name: top.name, variant: .board, contentMode: .fill, artOnly: true) { _, _ in MagicPalette.iron }
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.7), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TOP ATTACKER")
                            .font(.system(size: 10, weight: .black)).tracking(1.2)
                            .foregroundStyle(MagicPalette.antiqueGold)
                        Text(top.name)
                            .font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                    Text("\(top.damage) dmg")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(MagicPalette.parchment)
                }
                .padding(8)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board.result.summary")
    }

    private func tile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(victory ? MagicPalette.antiqueGold : MagicPalette.parchment)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2).multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// The dock's stack control: beside the floating mana it shows what is on the stack —
/// the top objects' art, the count and the top object's name, with consecutive identical
/// triggers grouped ("Chatterfang trigger ×12"). Tap to open the full stack.
struct BoardStackTray: View {
    let objects: [XmageStackObject]
    var count: Int? = nil
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Group {
        let object: XmageStackObject
        var count: Int
    }

    /// Groups consecutive objects (top first) with the same name, source and rules text.
    static func groups(_ objects: [XmageStackObject]) -> [Group] {
        var result: [Group] = []
        for object in objects {
            if let last = result.last, key(last.object) == key(object) { result[result.count - 1].count += 1 }
            else { result.append(Group(object: object, count: 1)) }
        }
        return result
    }

    private static func key(_ object: XmageStackObject) -> String {
        [object.displayName, object.sourceName ?? "", object.rulesText ?? ""].joined(separator: "\u{1F}")
    }

    static func title(_ group: Group) -> String {
        group.count > 1 ? "\(group.object.displayName) ×\(group.count)" : group.object.displayName
    }

    private var total: Int { max(count ?? 0, objects.count) }

    var body: some View {
        let groups = Self.groups(objects)
        Button(action: open) {
            if let top = groups.first {
                HStack(spacing: 7) {
                    ZStack(alignment: .leading) {
                        ForEach(Array(groups.prefix(3).enumerated().reversed()), id: \.offset) { index, group in
                            thumbnail(group.object)
                                .rotationEffect(.degrees(Double(index) * 6))
                                .offset(x: CGFloat(index) * 7)
                        }
                    }
                    .frame(width: 24 + CGFloat(max(min(groups.count, 3) - 1, 0)) * 7, height: 32, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("STACK · \(total)")
                            .font(.system(size: 8, weight: .black)).tracking(0.6)
                            .foregroundStyle(MagicPalette.antiqueGold)
                        HStack(spacing: 3) {
                            // The name may truncate; the trigger count never does.
                            Text(top.object.displayName).lineLimit(1)
                            if top.count > 1 {
                                Text("×\(top.count)").foregroundStyle(MagicPalette.antiqueGold).fixedSize()
                            }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    }
                    .frame(maxWidth: 118, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .background(MagicPalette.iron.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MagicPalette.antiqueGold.opacity(0.7), lineWidth: 1.5))
                .shadow(color: MagicPalette.antiqueGold.opacity(0.35), radius: 6)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                    Text("\(total)").monospacedDigit()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MagicPalette.parchment.opacity(total > 0 ? 0.9 : 0.5))
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: groups.isEmpty)
        .accessibilityLabel("Inspect stack")
        .accessibilityValue(groups.first.map { "\(total) \(total == 1 ? "item" : "items"). Top: \(Self.title($0))" } ?? "Empty")
        .accessibilityIdentifier("board.stack.tray")
    }

    @ViewBuilder
    private func thumbnail(_ object: XmageStackObject) -> some View {
        if let card = object.displaySourceCard {
            CardTile(card: card, selected: false, zoneName: "Stack", width: 23, height: 32, ignoreTappedRotation: true)
                .allowsHitTesting(false)
        } else {
            SyntheticStackObjectTile(object: object, width: 23, height: 32)
        }
    }
}

struct FloatingZoneChip: View {
    let title: String
    let count: Int
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text("\(title) (\(count))")
                    .font(.system(size: 10, weight: .black))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MagicPalette.iron.opacity(0.95), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.5), lineWidth: 1.5))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct CommanderHudSummary: Equatable {
    let life: Int
    let commanderTax: Int?
    let handCount: Int
    let libraryCount: Int
    let graveyardCount: Int
    let exileCount: Int
    let commanderDamage: Int?

    var commanderTaxLabel: String { commanderTax.map(String.init) ?? "—" }
    var commanderDamageLabel: String { commanderDamage.map(String.init) ?? "—" }
    var commandZoneLabel: String { commanderTax.map { "Command (\($0))" } ?? "Command" }

    init(player: PlayerGameState, opponentId: String?) {
        life = player.life
        commanderTax = player.hasKnownCommanderTax ? player.commanderTax : nil
        handCount = player.zones.visibleHandCount
        libraryCount = player.zones.visibleLibraryCount
        graveyardCount = player.zones.graveyard.count
        exileCount = player.zones.exile.count
        commanderDamage = player.commanderDamage.map { damage in opponentId.flatMap { damage[$0] } ?? 0 }
    }
}

/// Fits the narrow landscape rail without intruding into the battlefield.
struct LandscapePlayerSummary: View {
    let name: String
    let player: PlayerGameState
    var active = false
    var opponentId: String?
    var combatTargetable = false
    var combatTargetAction: (() -> Void)?
    var thinking = false
    /// Your own summary opens quick chat when on-device games provide it.
    var chatSnapshot: GameSnapshot? = nil
    @Environment(\.emoteCenter) private var emoteCenter
    @State private var chatOpen = false

    var body: some View {
        let summary = CommanderHudSummary(player: player, opponentId: opponentId)
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 11, weight: .bold)).lineLimit(1)
            // The portrait stands in for the heart; the column is narrow.
            HStack(spacing: 5) {
                PlayerPortrait(player: player, size: 24, active: active, thinking: thinking)
                BoardLifeTotal(life: summary.life).id(player.playerId)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(summary.life) life")
            }
            Text("Hand \(summary.handCount) · Lib \(summary.libraryCount)")
                .font(.system(size: 9, weight: .semibold)).lineLimit(1)
            Text("Tax \(summary.commanderTaxLabel) · Dmg \(summary.commanderDamageLabel)")
                .font(.system(size: 9, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(MagicPalette.parchment)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagicPalette.iron.opacity(0.64), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(
            combatTargetable ? MagicPalette.oxblood : MagicPalette.antiqueGold.opacity(active ? 0.8 : 0.3),
            lineWidth: combatTargetable ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if combatTargetable { combatTargetAction?() } else if chatSnapshot != nil, emoteCenter != nil { chatOpen = true }
        }
        .overlay(alignment: .topTrailing) {
            if let emoteCenter {
                EmoteBubbleSlot(center: emoteCenter, playerID: player.playerId)
                    .fixedSize()
                    .offset(x: 12, y: -18)
            }
        }
        .popover(isPresented: $chatOpen) {
            if let emoteCenter, let chatSnapshot {
                EmotePicker(center: emoteCenter, snapshot: chatSnapshot) { chatOpen = false }
                    .presentationCompactAdaptation(.popover)
            }
        }
        .accessibilityActions {
            if chatSnapshot != nil, emoteCenter != nil {
                Button("Quick chat") { chatOpen = true }
            }
        }
    }
}

struct GameLogAccessButton: View {
    var entryCount = 0
    let openLog: () -> Void

    var body: some View {
        Button(action: openLog) {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text("\(entryCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(MagicPalette.parchment.opacity(0.58))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.black.opacity(0.30), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.borderBronze.opacity(0.28)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open game log")
        .accessibilityValue("\(entryCount) actions")
    }
}

struct ActionRejectionInlineView: View {
    let notice: ActionRejectionNotice
    let recoveryAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.category == .staleSnapshot ? "arrow.clockwise.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .black))
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 9, weight: .black))
                Text(notice.message)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
            }
            Spacer(minLength: 2)
            if let recoveryTitle = notice.recoveryTitle {
                Button(recoveryTitle, action: recoveryAction)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(MagicPalette.warningAmber.opacity(0.22), in: Capsule())
            }
        }
        .foregroundStyle(MagicPalette.warningAmber)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(MagicPalette.iron.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MagicPalette.warningAmber.opacity(0.42), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notice.title). \(notice.message)")
    }
}

enum GameplayAffordances {
    static func dismissesZone(action: LegalAction) -> Bool { action.type == "cast_spell" }

    static func commanderCastAvailable(player: PlayerGameState, snapshot: GameSnapshot, pendingActionID: String?) -> Bool {
        guard pendingActionID == nil, snapshot.human?.playerId == player.playerId else { return false }
        return player.zones.command.contains { card in
            GameBoardInteractionState.cardActions(for: card, actions: snapshot.legalActions ?? []).contains {
                $0.type == "cast_spell" && $0.playerId == player.playerId
            }
        }
    }

    static func floatingManaSymbols(in snapshot: GameSnapshot, pendingActionID: String?) -> Set<String> {
        guard pendingActionID == nil else { return [] }
        return Set(["W", "U", "B", "R", "G", "C"].filter { floatingManaCommand(symbol: $0, in: snapshot) != nil })
    }

    static func floatingManaCommand(symbol: String, in snapshot: GameSnapshot) -> GameCommand? {
        guard let human = snapshot.human, let pool = human.manaPool,
              let prompt = snapshot.promptEnvelopeV2, prompt.playerId == human.playerId,
              CompactPromptPopup.isManaPaymentPrompt(prompt),
              let choice = prompt.manaChoices?.first(where: { ($0.manaType ?? $0.id) == symbol }),
              snapshot.source != "xmage-ondevice" || (choice.amount ?? 0) > 0 else { return nil }
        let counts = ["W": pool.W, "U": pool.U, "B": pool.B, "R": pool.R, "G": pool.G, "C": pool.C]
        guard (counts[symbol] ?? 0) > 0 else { return nil }
        return UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id, bridgeRevision: snapshot.bridgeRevision, promptEnvelope: prompt,
            type: snapshot.source == "xmage-ondevice" ? "play_mana" : prompt.responseCommand?.type ?? "play_mana",
            promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId,
            ids: [symbol], manaType: symbol
        )
    }
}
