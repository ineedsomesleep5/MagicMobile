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
        let theme = BattlefieldBackdrop.resolved(appearance)
        GeometryReader { proxy in
            ZStack {
                BattlefieldBackdropArt(theme: theme)
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                if !theme.hasBakedLighting { shading(in: proxy.size) }
            }
        }
    }

    @ViewBuilder
    private func shading(in size: CGSize) -> some View {
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
            startRadius: min(size.width, size.height) * 0.20,
            endRadius: max(size.width, size.height) * 0.62
        )
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
    @Environment(\.tavernBoard) private var tavern
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
            .modifier(TavernPanelChrome(tavern: tavern, cornerRadius: 16, classicFill: MagicPalette.iron.opacity(0.9),
                                        classicStroke: (isVictory ? MagicPalette.antiqueGold : Color(red: 0.6, green: 0.2, blue: 0.18)).opacity(0.8)))
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
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        if tavern, let ribbon = TavernCardParts.ribbon {
            tavernRibbon(ribbon)
        } else {
            classicTab
        }
    }

    /// On the tavern table the tab is a small parchment ribbon, like the tiles' name ribbons.
    private func tavernRibbon(_ ribbon: UIImage) -> some View {
        HStack(spacing: 3) {
            Image(systemName: card.card.typeLine.localizedCaseInsensitiveContains("equipment") ? "shield.lefthalf.filled" : "sparkles")
                .font(.system(size: max(7, height * 0.5), weight: .bold))
                .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.1))
            Text(card.card.name)
                .font(.system(size: max(7, height * 0.6), weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.17, green: 0.10, blue: 0.05))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if more > 0 {
                Text("+\(more)")
                    .font(.system(size: max(7, height * 0.55), weight: .black, design: .serif))
                    .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.1))
            }
        }
        .padding(.horizontal, height * 1.1)
        .frame(height: height * 1.25)
        .frame(maxWidth: .infinity)
        .background {
            // The tab is about the ribbon's own shape (about 5 : 1), so it stretches to fit.
            Image(uiImage: ribbon).resizable().interpolation(.high)
                .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var classicTab: some View {
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

// MARK: - Walnut Tavern chrome

struct TavernBoardKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True on the portrait board while the Walnut Tavern table is the backdrop. Controls
    /// then draw as table objects that sit in the sockets of the rendered plate
    /// (scripts/brand/tavern_layout.json, scripts/brand/tavern_table.py).
    var tavernBoard: Bool {
        get { self[TavernBoardKey.self] }
        set { self[TavernBoardKey.self] = newValue }
    }
}

enum TavernPalette {
    static let brass = Color(red: 0.86, green: 0.64, blue: 0.30)
    static let brassDark = Color(red: 0.36, green: 0.22, blue: 0.08)
    static let leather = Color(red: 0.16, green: 0.08, blue: 0.045)
    static let enamel = Color(red: 0.42, green: 0.07, blue: 0.05)
    static let ember = Color(red: 1.0, green: 0.50, blue: 0.34)
    static let parchment = Color(red: 0.95, green: 0.88, blue: 0.74)
}

/// A rendered sprite from the tavern asset set, or a drawn stand-in while it is missing.
private struct TavernSprite<Fallback: View>: View {
    let name: String
    @ViewBuilder let fallback: Fallback
    var body: some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            fallback
        }
    }
}

/// A carved brass medallion: a round portrait under the brass frame, with the life total
/// in an enamel badge at the bottom, the way the table's sockets are drawn.
struct TavernMedallion<Portrait: View>: View {
    let diameter: CGFloat
    let life: Int?
    var active = false
    var targetable = false
    /// Your commander can be cast: its own breathing glow and a crown spark.
    var commanderReady = false
    @ViewBuilder let portrait: Portrait

    var body: some View {
        ZStack {
            if commanderReady { TavernCommanderReadyGlow(diameter: diameter) }
            portrait
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
            // The table's own brass ring frames the portrait until the Meshy frame ships.
            TavernSprite(name: "tavern-medallion-frame") {
                Circle().strokeBorder(.black.opacity(0.55), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
            }
            .frame(width: diameter * 1.35, height: diameter * 1.35)
            .allowsHitTesting(false)
            if let life {
                BoardLifeTotal(life: life)
                    .font(.system(size: diameter * 0.30, weight: .heavy, design: .serif))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: diameter * 0.58, height: diameter * 0.40)
                    .background(
                        Capsule().fill(RadialGradient(colors: [TavernPalette.enamel, .black.opacity(0.92)],
                                                      center: .center, startRadius: 0, endRadius: diameter * 0.32))
                    )
                    .overlay(Capsule().strokeBorder(TavernPalette.brass, lineWidth: 1.5))
                    .offset(y: diameter * 0.47)
            }
        }
        .shadow(color: active ? TavernPalette.ember.opacity(0.75) : .black.opacity(0.5), radius: active ? 10 : 4)
        .background {
            // A player you can attack glows red: light only, no ring.
            if targetable {
                Circle().fill(Color(red: 1, green: 0.18, blue: 0.1))
                    .frame(width: diameter * 1.3, height: diameter * 1.3)
                    .blur(radius: diameter * 0.12)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: active)
        .animation(.easeInOut(duration: 0.35), value: commanderReady)
    }
}

/// A dark leather plaque with a brass edge, behind text that sits on the table.
struct TavernPlaque: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(colors: [TavernPalette.leather.opacity(0.94), .black.opacity(0.86)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TavernPalette.brass.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }
}

/// The primary action on the tavern table. With the flip frames installed the button draws
/// only the still brass ring and TavernPassStage turns the glass disc beneath it; otherwise
/// it draws the whole painted button. Passing and waiting need no words; other actions
/// (Confirm, Attack…) show a small plaque beside the button, never over it.
struct TavernPrimaryButtonStyle: ButtonStyle {
    var showsTitle = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.tavernCanvas) private var canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let diameter = TavernDesign.passDiameter(in: canvas)
        Group {
            if TavernPassAssets.flips {
                TavernSprite(name: "tavern-pass-ring") { EmptyView() }
                    .frame(width: diameter, height: diameter)
            } else {
                TavernSprite(name: "tavern-hourglass-button") {
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.62, blue: 0.30), TavernPalette.enamel, Color(red: 0.18, green: 0.03, blue: 0.02)],
                                                     center: .center, startRadius: 0, endRadius: diameter / 2))
                        Circle().strokeBorder(.black.opacity(0.45), lineWidth: 2)
                        Image(systemName: "hourglass")
                            .font(.system(size: diameter * 0.40, weight: .heavy))
                            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.55), TavernPalette.brass],
                                                            startPoint: .top, endPoint: .bottom))
                    }
                }
                .frame(width: diameter, height: diameter)
                .saturation(isEnabled ? 1 : 0.35)
                .brightness(isEnabled ? 0 : -0.18)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            }
        }
        .overlay(alignment: .top) {
            // Other actions name themselves on a brass plate riveted to the ring's top, never
            // over the glass.
            if showsTitle {
                TavernNamePlate { configuration.label }
                    .frame(maxWidth: diameter * 0.86)
                    .offset(y: 1)
            }
        }
        .pressSound(.uiTap, isPressed: configuration.isPressed)
        .frame(width: diameter, height: diameter)
        // The whole square takes taps: a slightly bigger target than the round face, and UI
        // tests that aim near the frame's edge still land on the button.
        .contentShape(Rectangle())
    }
}

/// The rendered pass button parts (scripts/brand/pass_button_flip.py): the still ring and
/// the disc's full turn in `frameCount` frames, frame 0 the glowing face.
enum TavernPassAssets {
    static let frameCount = 48
    static let flips = UIImage(named: "tavern-pass-ring") != nil && UIImage(named: "tavern-pass-flip-00") != nil
}

/// The pass button's glass disc, turning inside the still brass ring like Hearthstone's
/// end-turn button: the bright red face while you hold priority, the dim bronze face while
/// you wait (no halo; the face itself says whether it can be tapped). A tap turns it over at once and it turns back when priority returns, so a pass that
/// leaves you with priority spins it all the way round. It lives outside the button, whose
/// identity changes with every action, so a turn is never cut short.
struct TavernPassStage<Content: View>: View {
    let enabled: Bool
    let turnsOnTap: Bool
    let content: Content
    @Environment(\.tavernCanvas) private var canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Half turns: even shows the glowing face, odd the waiting face.
    @State private var turns: Double
    @State private var wantsFront: Bool
    @State private var turning = false

    init(enabled: Bool, turnsOnTap: Bool, @ViewBuilder content: () -> Content) {
        self.enabled = enabled
        self.turnsOnTap = turnsOnTap
        self.content = content()
        _turns = State(initialValue: enabled ? 0 : 1)
        _wantsFront = State(initialValue: enabled)
    }

    var body: some View {
        let diameter = TavernDesign.passDiameter(in: canvas)
        ZStack {
            Circle().fill(Color(red: 0.05, green: 0.03, blue: 0.02))
                .frame(width: diameter * 0.74, height: diameter * 0.74)
            TavernPassDisc(turns: turns)
                .frame(width: diameter, height: diameter)
            content
        }
        .simultaneousGesture(TapGesture().onEnded { if enabled && turnsOnTap { turnOver() } })
        .onChange(of: enabled) { _, now in
            wantsFront = now
            settle()
        }
    }

    private var showsFront: Bool { Int(turns.rounded()) % 2 == 0 }

    private func turnOver() {
        guard !turning else { return }
        turning = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            turns += 1
        } completion: {
            turning = false
            settle()
        }
    }

    /// Turns to the face that matches who holds priority, unless it is already showing.
    private func settle() {
        guard !turning, showsFront != wantsFront else { return }
        turnOver()
    }
}

/// One frame of the disc's turn, picked from the animated number of half turns.
private struct TavernPassDisc: View, Animatable {
    var turns: Double
    var animatableData: Double {
        get { turns }
        set { turns = newValue }
    }

    var body: some View {
        let count = TavernPassAssets.frameCount
        let phase = turns.truncatingRemainder(dividingBy: 2) / 2
        let index = Int((phase * Double(count)).rounded()) % count
        Image(String(format: "tavern-pass-flip-%02d", index))
            .resizable().scaledToFit()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Where the tavern table's sockets are, in points on the 440×956 design canvas the plate is
/// painted for (the plate fills the whole screen, so other sizes scale both axes). Measured
/// from the approved concept plate; the Blender/Meshy render must keep the same points.
enum TavernDesign {
    static let canvas = CGSize(width: 440, height: 956)
    static let opponentMedallion = CGPoint(x: 219.2, y: 95)
    static let opponentHoleRadius: CGFloat = 31
    static let lifeMedallion = CGPoint(x: 74, y: 882.6)  // mirrors the pass button: 74 pt from its edge
    static let lifeHoleRadius: CGFloat = 35.5
    static let passButton = CGPoint(x: 366, y: 877)
    /// The stack tray's slot below the mana rail, between your medallion and the pass button.
    static let stackTray = CGPoint(x: 211, y: 893)
    static let passHoleRadius: CGFloat = 48
    /// The pass button's frame: its brass ring matches the life medallion's frame.
    static func passDiameter(in canvas: CGSize?) -> CGFloat {
        let design = passHoleRadius * 2 * 1.04
        return canvas?.tavernLength(design) ?? design
    }
    static let manaSocketXs: [CGFloat] = [146.0, 175.4, 204.8, 234.7, 264.1, 293.5]
    static let manaSocketY: CGFloat = 846.9
    static let manaSocketRadius: CGFloat = 12.9
    static let matTop: CGFloat = 138.6
    static let matBottom: CGFloat = 723
}

/// The full screen in global coordinates while the tavern table is drawn, so controls can
/// be placed on the plate's sockets regardless of safe-area insets.
struct TavernCanvasKey: EnvironmentKey { static let defaultValue: CGSize? = nil }

extension EnvironmentValues {
    var tavernCanvas: CGSize? {
        get { self[TavernCanvasKey.self] }
        set { self[TavernCanvasKey.self] = newValue }
    }
}

extension CGSize {
    /// The design canvas this screen maps from: portrait 440 x 956 or landscape 956 x 440.
    var tavernDesignCanvas: CGSize { width > height ? TavernSockets.landscape.canvas : TavernDesign.canvas }
    /// A design-canvas point on this screen, in global coordinates.
    func tavernPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * width / tavernDesignCanvas.width, y: point.y * height / tavernDesignCanvas.height)
    }
    func tavernLength(_ value: CGFloat) -> CGFloat { value * width / tavernDesignCanvas.width }
    /// A design-canvas rectangle on this screen, in global coordinates.
    func tavernRect(_ rect: CGRect) -> CGRect {
        let origin = tavernPoint(rect.origin)
        let end = tavernPoint(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
    }
}

/// Where the tavern table's live controls sit, in design points: the portrait plate's sockets
/// (TavernDesign, tavern_layout.json "portrait") or the landscape plate's ("landscape").
struct TavernSockets {
    let canvas: CGSize
    let opponentMedallion: CGPoint
    let opponentHoleRadius: CGFloat
    let opponentNameplate: CGPoint
    let opponentHand: CGPoint
    let phasePlate: CGPoint
    let opponentGlance: CGPoint
    let lifeMedallion: CGPoint
    let lifeHoleRadius: CGFloat
    let chat: CGPoint
    let passButton: CGPoint
    let skip: CGPoint
    let menu: CGPoint
    let stackTray: CGPoint
    let manaSocketXs: [CGFloat]
    let manaSocketY: CGFloat
    /// The leather mat; in landscape the battlefield column is laid on it down to `handBottom`.
    let mat: CGRect
    let handBottom: CGFloat

    static let portrait: TavernSockets = {
        let center = TavernDesign.opponentMedallion
        let pass = TavernDesign.passButton
        return TavernSockets(
            canvas: TavernDesign.canvas, opponentMedallion: center, opponentHoleRadius: TavernDesign.opponentHoleRadius,
            opponentNameplate: CGPoint(x: center.x - 110, y: center.y + 8), opponentHand: CGPoint(x: center.x, y: center.y - 40),
            phasePlate: CGPoint(x: center.x + 110, y: center.y + 8), opponentGlance: CGPoint(x: center.x + 110, y: center.y + 46),
            lifeMedallion: TavernDesign.lifeMedallion, lifeHoleRadius: TavernDesign.lifeHoleRadius,
            chat: CGPoint(x: TavernDesign.lifeMedallion.x + 42, y: TavernDesign.lifeMedallion.y + 52),
            passButton: pass, skip: CGPoint(x: pass.x - 71, y: pass.y + 10), menu: CGPoint(x: pass.x - 51, y: pass.y + 51),
            stackTray: TavernDesign.stackTray, manaSocketXs: TavernDesign.manaSocketXs, manaSocketY: TavernDesign.manaSocketY,
            mat: CGRect(x: 26, y: TavernDesign.matTop, width: 388, height: TavernDesign.matBottom - TavernDesign.matTop),
            handBottom: 830)
    }()

    /// The landscape plate (tavern_layout.json "landscape", 956 x 440 like an iPhone held
    /// sideways): the opponent's medallion and nameplate up the left walnut column with your
    /// medallion at its foot; the phase plate, stack tray and pass button down the right; the
    /// mat between them; the hand resting on a red band under the mat and the mana rail below.
    /// Skip and the controls ring orbit the pass button's upper left.
    static let landscape: TavernSockets = {
        // Caleb (2026-10-02): the playing board as big as it can be. The walnut columns keep
        // just the medallions and the pass button inside the safe area (62 pt each side); the
        // mat runs between them and down to the mana rail, and the hand rests over its foot.
        let pass = CGPoint(x: 846, y: 344)
        return TavernSockets(
            canvas: CGSize(width: 956, height: 440), opponentMedallion: CGPoint(x: 118, y: 76), opponentHoleRadius: 30,
            opponentNameplate: CGPoint(x: 118, y: 144), opponentHand: CGPoint(x: 118, y: 34),
            phasePlate: CGPoint(x: 840, y: 42), opponentGlance: CGPoint(x: 118, y: 188),
            lifeMedallion: CGPoint(x: 118, y: 344), lifeHoleRadius: 34,
            chat: CGPoint(x: 160, y: 404),
            passButton: pass, skip: CGPoint(x: pass.x - 40, y: pass.y - 60), menu: CGPoint(x: pass.x + 20, y: pass.y - 70),
            stackTray: CGPoint(x: 840, y: 180),
            manaSocketXs: [407, 435, 463, 491, 519, 547], manaSocketY: 416,
            mat: CGRect(x: 172, y: 8, width: 610, height: 392), handBottom: 404)
    }()

    static func current(_ canvas: CGSize?) -> TavernSockets {
        guard let canvas, canvas.width > canvas.height else { return .portrait }
        return .landscape
    }
}

extension View {
    /// Positions a view on a tavern socket. `origin` is the global origin of the
    /// coordinate space the view is positioned in.
    func tavernPosition(_ point: CGPoint, canvas: CGSize, origin: CGPoint) -> some View {
        let global = canvas.tavernPoint(point)
        return position(x: global.x - origin.x, y: global.y - origin.y)
    }
}

/// A small brass ring button that sits on the table beside the hourglass.
struct TavernRingLabel: ViewModifier {
    var pressed = false
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(TavernPalette.parchment)
            .frame(width: 34, height: 34)
            .background(
                RadialGradient(colors: [pressed ? TavernPalette.brassDark : Color(red: 0.24, green: 0.13, blue: 0.07), .black.opacity(0.92)],
                               center: .center, startRadius: 0, endRadius: 18),
                in: Circle())
            .overlay(Circle().strokeBorder(
                LinearGradient(colors: [TavernPalette.brass, TavernPalette.brassDark], startPoint: .top, endPoint: .bottom),
                lineWidth: 2.5))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

/// The opponent's hand as face-down cards fanned above their medallion, one per card, the
/// way a player across the table holds them. The notch may cover the top of a big hand.
struct TavernCardBackFan: View {
    let count: Int
    var body: some View {
        let shown = min(count, 20)
        let arc = min(Double(shown) * 7, 84)
        let width = min(CGFloat(shown) * 11, 150)
        ZStack(alignment: .bottom) {
            ForEach(0..<shown, id: \.self) { index in
                let spread = shown > 1 ? (Double(index) / Double(shown - 1) - 0.5) : 0
                // Leather card backs with a brass edge and an ember spark: the tavern's deck, not a blue one.
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.18, blue: 0.08), Color(red: 0.14, green: 0.08, blue: 0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(TavernPalette.brass, lineWidth: 1.2))
                    .overlay(Image(systemName: "sparkle").font(.system(size: 9, weight: .bold)).foregroundStyle(BrandTheme.ember))
                    .frame(width: 24, height: 34)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .rotationEffect(.degrees(spread * arc), anchor: .bottom)
                    .offset(x: spread * width, y: abs(spread) * 8)
            }
        }
        .frame(height: 40, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(count == 1 ? "1 card in hand" : "\(count) cards in hand")
    }
}

/// One mana gem in the tavern rail: the rendered Meshy gem (or the mana symbol until it
/// ships), centred on its socket. It glows in its colour and breathes while that mana is
/// floating, with the amount on a small badge, and sits dim and unlit when the pool has none.
struct TavernManaGemFace: View {
    let symbol: String
    let count: Int
    var payable = false
    var diameter: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var glowColor: Color {
        switch symbol {
        case "W": return Color(red: 1, green: 0.93, blue: 0.70)
        case "U": return Color(red: 0.35, green: 0.62, blue: 1)
        case "B": return Color(red: 0.66, green: 0.42, blue: 0.86)
        case "R": return Color(red: 1, green: 0.38, blue: 0.20)
        case "G": return Color(red: 0.32, green: 0.88, blue: 0.42)
        default: return Color(red: 0.86, green: 0.86, blue: 0.92)
        }
    }

    var body: some View {
        let lit = count > 0
        Group {
            if let image = UIImage(named: "tavern-mana-\(symbol)") {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ManaSymbolView(symbol: symbol, size: diameter * 0.8)
            }
        }
        .frame(width: diameter, height: diameter)
        .saturation(lit ? 1.15 : 0.75)
        .brightness(lit ? (breathing ? 0.12 : 0.04) : -0.08)
        .shadow(color: lit || payable ? glowColor.opacity(breathing ? 0.95 : 0.7) : .black.opacity(0.6),
                radius: lit || payable ? (breathing ? 9 : 6) : 1.5)
        .overlay(alignment: .bottomTrailing) {
            if lit {
                Text("\(count)")
                    .font(.system(size: diameter * 0.36, weight: .heavy, design: .serif)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .overlay(Capsule().strokeBorder(TavernPalette.brass, lineWidth: 1))
                    .offset(x: diameter * 0.12, y: diameter * 0.12)
            }
        }
        .onAppear { updateBreathing(lit) }
        .onChange(of: lit) { _, now in updateBreathing(now) }
    }

    private func updateBreathing(_ lit: Bool) {
        guard lit, !reduceMotion else {
            breathing = false
            return
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathing = true }
    }
}

// MARK: - Walnut Tavern UI kit

/// The Walnut Tavern UI kit: brass parts rendered in Blender (scripts/brand/tavern_ui_kit.py)
/// and leather, parchment and ember fills (scripts/brand/tavern_ui_textures.sh), installed at
/// @3x so the cap insets below are in points. Pop-ups on the tavern board are dressed with
/// these; their text stays live SwiftUI text. Without the assets each piece draws plainly.
enum TavernUIKit {
    static let available = UIImage(named: "tavern-ui-frame") != nil
}

/// A material fill: leather and parchment tile seamlessly, ember glass stretches.
struct TavernFill: View {
    enum Material: String {
        case leather = "tavern-ui-leather"
        case parchment = "tavern-ui-parchment"
        case ember = "tavern-ui-ember"
    }

    let material: Material

    var body: some View {
        if let image = UIImage(named: material.rawValue) {
            if material == .ember {
                Image(uiImage: image).resizable()
            } else {
                Image(uiImage: image).resizable(resizingMode: .tile)
            }
        } else {
            switch material {
            case .leather: TavernPalette.leather
            case .parchment: TavernPalette.parchment
            case .ember: TavernPalette.enamel
            }
        }
    }
}

/// Brass trim around a rectangle, 9-sliced from tavern-ui-frame (96 pt, 24 pt corners with
/// rivets). `scale` shrinks the trim for small plaques: 0.5 gives 12 pt corners.
struct TavernBrassFrame: View {
    var scale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            if let image = UIImage(named: "tavern-ui-frame") {
                Image(uiImage: image)
                    .resizable(capInsets: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
                    .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
            } else {
                RoundedRectangle(cornerRadius: 12 * scale).strokeBorder(TavernPalette.brass, lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A brass capsule rim: riveted for buttons (44 pt tall; its rivets tile as it widens) or
/// thin and plain for tags (22 pt).
struct TavernCapsuleRim: View {
    var thin = false

    var body: some View {
        Group {
            if let image = UIImage(named: thin ? "tavern-ui-capsule-thin" : "tavern-ui-capsule") {
                let cap: CGFloat = thin ? 11 : 22
                Image(uiImage: image)
                    .resizable(capInsets: EdgeInsets(top: cap - 1, leading: cap, bottom: cap - 1, trailing: cap),
                               resizingMode: thin ? .stretch : .tile)
            } else {
                Capsule().strokeBorder(TavernPalette.brass, lineWidth: thin ? 1.5 : 2.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Plaque buttons from the kit: primary is ember glass, secondary dark leather, both in a
/// riveted brass rim, like the pass button.
struct TavernButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }

    var kind: Kind = .primary
    var compact = false
    var fontSize: CGFloat?
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize ?? (compact ? 12 : 14), weight: .heavy, design: .serif))
            .foregroundStyle(kind == .secondary ? TavernPalette.parchment : Color(red: 1, green: 0.91, blue: 0.66))
            .shadow(color: .black.opacity(0.75), radius: 1, y: 1)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, compact ? 16 : 22)
            .padding(.vertical, 6)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background {
                Group {
                    switch kind {
                    case .primary: TavernFill(material: .ember)
                    case .secondary: TavernFill(material: .leather)
                    case .danger: TavernFill(material: .leather).overlay(MagicPalette.oxblood.opacity(0.7))
                    }
                }
                .clipShape(Capsule())
                .padding(3)
            }
            .overlay { TavernCapsuleRim() }
            .contentShape(Capsule())
            .saturation(isEnabled ? 1 : 0.15)
            .brightness(isEnabled ? (configuration.isPressed ? 0.08 : 0) : -0.12)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A small tag in a thin brass rim: parchment for labels ("PAY COST"), leather for status
/// chips. `accent` adds a little coloured jewel that keeps the prompt's colour cue.
struct TavernTag: View {
    let text: String
    var leather = false
    var accent: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let accent {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.9), accent, accent.opacity(0.6)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 5))
                    .frame(width: 8, height: 8)
                    .shadow(color: accent.opacity(0.9), radius: 3)
            }
            Text(text)
                .font(.system(size: 10, weight: .heavy, design: .serif))
                .tracking(0.8)
                .foregroundStyle(leather ? Color(red: 0.98, green: 0.82, blue: 0.48) : Color(red: 0.24, green: 0.12, blue: 0.05))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 22)
        .background {
            TavernFill(material: leather ? .leather : .parchment)
                .clipShape(Capsule())
                .padding(1.5)
        }
        .overlay { TavernCapsuleRim(thin: true) }
        .fixedSize()
    }
}

/// A number struck on a brass coin (a generic mana cost, a count).
struct TavernCoin: View {
    let value: Int
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            if let image = UIImage(named: "tavern-ui-coin") {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Circle().fill(TavernPalette.brass)
            }
            Text("\(value)")
                .font(.system(size: size * 0.52, weight: .black, design: .serif))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.25, green: 0.12, blue: 0.04))
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
        }
        .frame(width: size, height: size)
    }
}

/// A leather ribbon in brass trim with pennant end caps, for the banners across the board
/// (casting cost, targets, combat).
struct TavernRibbon: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background { TavernFill(material: .leather).clipShape(RoundedRectangle(cornerRadius: 6)) }
            .overlay { TavernBrassFrame(scale: 0.5) }
            .overlay(alignment: .leading) { cap("tavern-ui-cap-left").offset(x: -22) }
            .overlay(alignment: .trailing) { cap("tavern-ui-cap-right").offset(x: 22) }
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            // Room for the end caps inside the banner's slot.
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func cap(_ name: String) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .frame(width: 36, height: 36)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A mana symbol drawn as the tavern's crystal gem on the tavern board.
struct TavernAwareManaSymbol: View {
    let symbol: String
    let size: CGFloat
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        if tavern, let image = UIImage(named: "tavern-mana-\(symbol.uppercased())") {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size * 1.2, height: size * 1.2)
        } else {
            ManaSymbolView(symbol: symbol, size: size)
        }
    }
}

/// The backing of tavern sheets: dark tooled leather under a brass rule along the top.
struct TavernSheetBackground: View {
    var body: some View {
        TavernFill(material: .leather)
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                LinearGradient(colors: [TavernPalette.brass, Color(red: 0.42, green: 0.28, blue: 0.09)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 3)
            }
            .ignoresSafeArea()
    }
}

/// A panel title engraved in gold.
struct TavernPanelTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 16, weight: .heavy, design: .serif))
            .tracking(1.2)
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), Color(red: 0.80, green: 0.56, blue: 0.22)],
                                            startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Engraved in capitals, named in normal case (VoiceOver reads capitals letter by letter).
            .accessibilityLabel(text)
    }
}

/// The wax-seal close button of tavern panels: the rendered Meshy seal once installed.
struct TavernSealLabel: View {
    var body: some View {
        Group {
            if let image = UIImage(named: "tavern-ui-seal") {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(red: 0.85, green: 0.16, blue: 0.12), Color(red: 0.45, green: 0.04, blue: 0.03)],
                                                 center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 16))
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.62))
                }
            }
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
}

/// The leather title bar of tavern panels, in brass trim.
struct TavernTitleBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, 12)
            .padding(.trailing, 2)
            .frame(minHeight: 48)
            .background {
                TavernFill(material: .leather)
                    .overlay(Color.black.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .overlay { TavernBrassFrame(scale: 0.5) }
    }
}

extension TavernPalette {
    /// Dark ink for text on parchment.
    static let ink = Color(red: 0.22, green: 0.11, blue: 0.04)
    /// A brass hairline for parchment rows and inset boxes.
    static let brassLine = LinearGradient(colors: [Color(red: 0.92, green: 0.72, blue: 0.38), Color(red: 0.50, green: 0.33, blue: 0.11)],
                                          startPoint: .top, endPoint: .bottom)
}

extension View {
    /// A sheet opened from the tavern board: leather backing, and the tavern kit inside.
    @ViewBuilder
    func tavernSheet(_ active: Bool) -> some View {
        if active && TavernUIKit.available {
            environment(\.tavernBoard, true)
                .presentationBackground { TavernSheetBackground() }
        } else {
            self
        }
    }
}

/// A stock List or Form sheet in the tavern (Caleb, 2026-10-03): the leather sheet backing, rows
/// as darker leather cards with brass separators, parchment serif text and brass controls. Without
/// the kit the sheet is untouched.
struct TavernListChrome: ViewModifier {
    func body(content: Content) -> some View {
        if TavernUIKit.available {
            content
                .scrollContentBackground(.hidden)
                .background(TavernSheetBackground())
                .listRowBackground(TavernListRow())
                .listRowSeparatorTint(TavernPalette.brass.opacity(0.35))
                .foregroundStyle(TavernPalette.parchment)
                .fontDesign(.serif)
                .tint(TavernPalette.brass)
                .toggleStyle(TavernToggleStyle())
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .environment(\.tavernBoard, true)
                .preferredColorScheme(.dark)
        } else {
            content
        }
    }
}

/// One row's backing in a tavern list: leather darkened a shade.
struct TavernListRow: View {
    var body: some View {
        TavernFill(material: .leather)
            .overlay(Color.black.opacity(0.28))
    }
}

extension View {
    /// A List or Form sheet dressed for the tavern (TavernListChrome).
    func tavernList() -> some View { modifier(TavernListChrome()) }
}

/// A floating panel's backing: the classic fill and edge, or on the tavern board tooled leather
/// in brass trim whose corners follow `cornerRadius` (12 pt is the trim's full size).
struct TavernPanelChrome: ViewModifier {
    let tavern: Bool
    var cornerRadius: CGFloat = 12
    var classicFill: Color = MagicPalette.iron.opacity(0.94)
    var classicStroke: Color = MagicPalette.antiqueGold.opacity(0.38)

    func body(content: Content) -> some View {
        if tavern && TavernUIKit.available {
            let scale = min(max(cornerRadius / 12, 0.4), 1)
            content
                .background {
                    TavernFill(material: .leather)
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 12 * scale))
                }
                .overlay { TavernBrassFrame(scale: scale) }
        } else {
            content
                .background(classicFill, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(classicStroke, lineWidth: 1))
        }
    }
}

/// A search field: the system rounded field, or on the tavern board a recessed parchment slot.
struct TavernFieldChrome: ViewModifier {
    let tavern: Bool

    func body(content: Content) -> some View {
        if tavern && TavernUIKit.available {
            content
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(TavernPalette.ink)
                .tint(TavernPalette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background {
                    TavernFill(material: .parchment)
                        .overlay(LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TavernPalette.brassLine, lineWidth: 1.2))
        } else {
            content.textFieldStyle(.roundedBorder)
        }
    }
}

extension View {
    /// A text button as a tavern plaque on the tavern board; untouched elsewhere.
    @ViewBuilder
    func tavernPlaque(_ active: Bool, kind: TavernButtonStyle.Kind) -> some View {
        if active && TavernUIKit.available {
            buttonStyle(TavernButtonStyle(kind: kind, compact: true))
        } else {
            self
        }
    }
}

/// An engraved brass nameplate with a rivet at each end, like the label on a ship's porthole.
struct TavernNamePlate<Label: View>: View {
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: 5) {
            rivet
            label
                .font(.system(size: 8.5, weight: .heavy, design: .serif))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(TavernPalette.ink)
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            rivet
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 16)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.52), Color(red: 0.78, green: 0.55, blue: 0.22),
                                              Color(red: 0.58, green: 0.38, blue: 0.13)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 0.36, green: 0.22, blue: 0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rivet: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), Color(red: 0.45, green: 0.29, blue: 0.09)],
                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 3))
            .frame(width: 5, height: 5)
    }
}

/// The stack on the tavern table: a leather tray below the mana rail with the top spell and
/// how many are waiting; a tap opens the full stack.
struct TavernStackTray: View {
    let count: Int
    let topName: String?
    let open: () -> Void
    /// Narrower in the landscape table's right column.
    var width: CGFloat = 124
    /// The top of the stack, shown as a small framed picture with the count on a coin.
    var topCard: ZoneCard? = nil

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let topCard {
                        TavernArtCrop(card: topCard, zoneName: "Stack")
                            .frame(width: 30, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(BrandTheme.brassGradient, lineWidth: 1))
                            .allowsHitTesting(false)
                        TavernCoin(value: count, size: 16).offset(x: 5, y: 4)
                    } else {
                        TavernCoin(value: count, size: 26)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("STACK")
                        .font(.system(size: 9, weight: .heavy, design: .serif))
                        .tracking(1)
                        .foregroundStyle(Color(red: 0.96, green: 0.80, blue: 0.48))
                    Text(topName ?? "")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(TavernPalette.parchment)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color(red: 0.96, green: 0.80, blue: 0.48))
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(width: width, height: 42)
            .modifier(TavernPanelChrome(tavern: true, cornerRadius: 7))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inspect stack")
        .accessibilityValue(topName.map { "\(count) on the stack, top: \($0)" } ?? "\(count) on the stack")
        .accessibilityIdentifier("board.stack.tray")
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

/// A generic mana cost: the smoky crystal (tavern-mana-generic) with the number engraved in gold.
struct TavernGenericGem: View {
    let value: Int
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            if let image = UIImage(named: "tavern-mana-generic") {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                TavernCoin(value: value, size: size)
            }
            Text("\(value)")
                .font(.system(size: size * 0.46, weight: .black, design: .serif))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.6), Color(red: 0.86, green: 0.6, blue: 0.24)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(value) generic mana")
    }
}

/// How a tavern menu row hands its action to the menu: close first, then act.
private struct TavernMenuSelectKey: EnvironmentKey {
    static let defaultValue: (@escaping () -> Void) -> Void = { $0() }
}

extension EnvironmentValues {
    var tavernMenuSelect: (@escaping () -> Void) -> Void {
        get { self[TavernMenuSelectKey.self] }
        set { self[TavernMenuSelectKey.self] = newValue }
    }
}

/// A menu in the tavern's style instead of the system's: a leather pop-over of brass-edged
/// parchment rows anchored to its button. A chosen row closes the pop-over before its action
/// runs, so actions that open sheets are not blocked by the closing pop-over.
struct TavernMenu<Label: View, Items: View>: View {
    var arrowEdge: Edge = .bottom
    /// Long lists (decks) scroll inside a pop-over of this height.
    var scrollHeight: CGFloat? = nil
    /// The row (by `.id`) a scrolling pop-over opens on, such as the current choice.
    var scrollAnchor: AnyHashable? = nil
    @ViewBuilder let items: Items
    @ViewBuilder let label: Label
    @State private var open = false
    @State private var pending: (() -> Void)?

    var body: some View {
        Button { open = true } label: { label }
            .popover(isPresented: $open, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge) {
                Group {
                    if let scrollHeight {
                        ScrollViewReader { proxy in
                            ScrollView { VStack(alignment: .leading, spacing: 6) { items }.padding(10) }
                                .frame(height: scrollHeight)
                                .onAppear { if let scrollAnchor { proxy.scrollTo(scrollAnchor, anchor: .center) } }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) { items }.padding(10)
                    }
                }
                    .frame(width: 270)
                    .environment(\.tavernBoard, true)
                    .environment(\.tavernMenuSelect) { action in
                        pending = action
                        open = false
                    }
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground { TavernSheetBackground() }
            }
            .onChange(of: open) { _, isOpen in
                guard !isOpen, let action = pending else { return }
                pending = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    action()
                }
            }
    }
}

/// One row of a tavern menu: a parchment strip (oxblood when destructive).
struct TavernMenuItem: View {
    let title: String
    var systemImage: String?
    var destructive = false
    let action: () -> Void
    @Environment(\.tavernMenuSelect) private var select

    var body: some View {
        Button { select(action) } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(PanelActionButtonStyle(isDanger: destructive, isPrimary: true))
    }
}

/// A thin brass rule between groups of tavern menu rows.
struct TavernMenuDivider: View {
    var body: some View {
        Rectangle().fill(TavernPalette.brassLine).frame(height: 1).opacity(0.7).padding(.vertical, 2)
    }
}

/// One choice in a tavern confirmation.
struct TavernDialogAction: Identifiable {
    let id = UUID()
    let title: String
    var destructive = false
    let action: () -> Void
}

extension View {
    /// A confirmation: the tavern's leather dialog on the tavern board, the system's elsewhere.
    func tavernConfirmation(active: Bool, title: String, message: String?, isPresented: Binding<Bool>,
                            actions: [TavernDialogAction], cancelTitle: String = "Cancel",
                            onCancel: @escaping () -> Void = {}) -> some View {
        modifier(TavernConfirmationModifier(active: active, title: title, message: message, isPresented: isPresented,
                                            actions: actions, cancelTitle: cancelTitle, onCancel: onCancel))
    }
}

private struct TavernConfirmationModifier: ViewModifier {
    let active: Bool
    let title: String
    let message: String?
    @Binding var isPresented: Bool
    let actions: [TavernDialogAction]
    let cancelTitle: String
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        if active && TavernUIKit.available {
            content
                .overlay {
                    if isPresented { dialog.transition(.opacity) }
                }
                .animation(.easeOut(duration: 0.2), value: isPresented)
        } else {
            content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                ForEach(actions) { choice in
                    Button(choice.title, role: choice.destructive ? .destructive : nil, action: choice.action)
                }
                Button(cancelTitle, role: .cancel, action: onCancel)
            } message: {
                if let message { Text(message) }
            }
        }
    }

    private var dialog: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Text(title.uppercased())
                    .font(.system(size: 17, weight: .heavy, design: .serif))
                    .tracking(1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), Color(red: 0.80, green: 0.56, blue: 0.22)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                if let message {
                    Text(message)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(TavernPalette.parchment.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 10) {
                    ForEach(actions) { choice in
                        Button(choice.title) {
                            isPresented = false
                            choice.action()
                        }
                        .buttonStyle(TavernButtonStyle(kind: choice.destructive ? .danger : .primary, fullWidth: true))
                    }
                    Button(cancelTitle, action: cancel)
                        .buttonStyle(TavernButtonStyle(kind: .secondary, fullWidth: true))
                }
            }
            .padding(22)
            .frame(maxWidth: 330)
            .modifier(TavernPanelChrome(tavern: true, cornerRadius: 16))
            .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func cancel() {
        isPresented = false
        onCancel()
    }
}

/// The step of the turn in plain words, and which of the five phases it belongs to.
enum TavernPhaseTrack {
    static let phases = ["Beginning", "Main 1", "Combat", "Main 2", "End"]

    static func describe(_ raw: String?) -> (title: String, phase: Int?) {
        guard let raw, !raw.isEmpty else { return ("", nil) }
        switch raw.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "beginning", "untap": return ("Untap step", 0)
        case "upkeep": return ("Upkeep", 0)
        case "draw": return ("Draw step", 0)
        case "precombat-main", "main1": return ("Main phase 1", 1)
        case "combat", "begin-combat": return ("Beginning of combat", 2)
        case "declare-attackers": return ("Declare attackers", 2)
        case "declare-blockers": return ("Declare blockers", 2)
        case "first-combat-damage", "first-strike-damage": return ("First-strike damage", 2)
        case "combat-damage": return ("Combat damage", 2)
        case "end-combat": return ("End of combat", 2)
        case "postcombat-main", "main2": return ("Main phase 2", 3)
        case "ending", "end", "end-turn": return ("End step", 4)
        case "cleanup": return ("Cleanup", 4)
        default: return (EngineDisplayText.phaseLabel(raw), nil)
        }
    }
}

/// The tavern's phase plate, mirroring the opponent's nameplate: the turn number, the step in
/// words and a track of the five phases with the current one lit in ember.
struct TavernPhasePlate: View {
    let step: String?
    let turn: Int
    var width: CGFloat = 118

    var body: some View {
        let described = TavernPhaseTrack.describe(step)
        VStack(alignment: .leading, spacing: 3) {
            Text("TURN \(turn)")
                .font(.system(size: 9, weight: .heavy, design: .serif)).tracking(1)
                .foregroundStyle(BrandTheme.brassGradient)
            Text(described.title)
                .font(.system(size: 12.5, weight: .semibold, design: .serif))
                .foregroundStyle(TavernPalette.parchment)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                ForEach(0..<TavernPhaseTrack.phases.count, id: \.self) { index in
                    let current = index == described.phase
                    Capsule()
                        .fill(current ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.36), BrandTheme.ember],
                                                                     startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(BrandTheme.brass.opacity(0.32)))
                        .frame(height: current ? 5 : 4)
                        .shadow(color: current ? BrandTheme.ember.opacity(0.9) : .clear, radius: 3)
                }
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .modifier(TavernPanelChrome(tavern: true, cornerRadius: 7))
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.3), value: described.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(described.title.isEmpty ? "Turn \(turn)" : "Turn \(turn), \(described.title)")
        .accessibilityIdentifier("board.phase.plate")
    }
}

// MARK: - Player status in the tavern zones pop-over

/// Poison as the Phyrexian symbol: a ring split by an upright stroke.
struct PhyrexianGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.24))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// What a player carries besides their zones (Caleb, 2026-10-02): counters, the monarch and
/// the initiative, commander damage taken and cards attached to them. Shown as icons, never
/// words; each badge still names itself to VoiceOver.
struct PlayerStatusSummary {
    struct Badge: Identifiable {
        enum Icon { case poison, symbol(String), commander(ZoneCard?) }
        let id: String
        let icon: Icon
        let tint: Color
        let count: Int?
        let label: String
        /// Close to losing to it: ten poison, twenty-one commander damage.
        var nearLethal = false
    }

    let badges: [Badge]
    let attachments: [ZoneCard]

    var isEmpty: Bool { badges.isEmpty && attachments.isEmpty }

    init(player: PlayerGameState, snapshot: GameSnapshot?) {
        var badges: [Badge] = BoardPlayerStatus.counters(player).map { counter in
            let name = counter.name.lowercased()
            let (icon, tint): (Badge.Icon, Color) = switch name {
            case "poison": (.poison, Color(red: 0.55, green: 0.9, blue: 0.35))
            case "energy": (.symbol("bolt.fill"), Color(red: 1, green: 0.82, blue: 0.3))
            case "experience": (.symbol("sparkles"), Color(red: 0.98, green: 0.92, blue: 0.7))
            case "rad": (.symbol("atom"), Color(red: 0.75, green: 1, blue: 0.4))
            case "ticket": (.symbol("ticket.fill"), Color(red: 1, green: 0.5, blue: 0.4))
            default: (.symbol("seal.fill"), TavernPalette.parchment)
            }
            return Badge(id: "counter-\(name)", icon: icon, tint: tint, count: counter.count,
                         label: "\(counter.name.capitalized) \(counter.count)",
                         nearLethal: name == "poison" && counter.count >= 7)
        }
        if player.monarch == true {
            badges.append(Badge(id: "monarch", icon: .symbol("crown.fill"), tint: Color(red: 1, green: 0.8, blue: 0.4), count: nil, label: "Monarch"))
        }
        if player.initiative == true {
            badges.append(Badge(id: "initiative", icon: .symbol("flag.fill"), tint: Color(red: 0.95, green: 0.55, blue: 0.35),
                                count: nil, label: "Has the initiative"))
        }
        if let snapshot {
            // Each opposing commander that has hit this player, with its art when it is visible.
            for owner in snapshot.players where owner.playerId != player.playerId {
                for commander in owner.commanders ?? [] {
                    guard let damage = commander.damageToPlayers?[player.playerId], damage > 0 else { continue }
                    let zones = owner.zones
                    let card = (zones.command + zones.battlefield + zones.graveyard + zones.exile + zones.hand)
                        .first { $0.instanceId == commander.id }
                    badges.append(Badge(id: "commander-\(commander.id)", icon: .commander(card), tint: TavernPalette.ember, count: damage,
                                        label: "\(commander.name ?? "Commander") dealt \(damage) commander damage",
                                        nearLethal: damage >= 15))
                }
            }
            attachments = ZoneCard.enchanting(playerID: player.playerId, cards: snapshot.players.flatMap { $0.zones.battlefield })
        } else {
            attachments = []
        }
        self.badges = badges
    }

    var accessibilityText: String {
        (badges.map(\.label) + attachments.map { "\($0.card.name) attached" }).joined(separator: ", ")
    }
}

/// One status badge: a leather coin in a brass ring with its symbol, and its count on a
/// brass coin at the corner. A red ring warns when the player is close to losing to it.
struct TavernStatusBadge: View {
    let badge: PlayerStatusSummary.Badge
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.3, green: 0.17, blue: 0.09), TavernPalette.leather],
                                         center: .init(x: 0.4, y: 0.3), startRadius: 0, endRadius: size * 0.6))
            symbol
            Circle().strokeBorder(badge.nearLethal ? Color(red: 0.95, green: 0.2, blue: 0.12) : TavernPalette.brass,
                                  lineWidth: badge.nearLethal ? 2.4 : 1.6)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let count = badge.count {
                TavernCoin(value: count, size: size * 0.5).offset(x: size * 0.12, y: size * 0.1)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.label)
    }

    @ViewBuilder private var symbol: some View {
        switch badge.icon {
        case .poison:
            PhyrexianGlyph()
                .stroke(badge.tint, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                .frame(width: size * 0.5, height: size * 0.56)
                .shadow(color: badge.tint.opacity(0.7), radius: 3)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(badge.tint)
                .shadow(color: badge.tint.opacity(0.5), radius: 2)
        case .commander(let card):
            ZStack {
                if let card {
                    TavernArtCrop(card: card, zoneName: "Command")
                        .clipShape(Circle())
                        .padding(2)
                } else {
                    Image(systemName: "crown.fill")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(badge.tint)
                }
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: size * 0.26, weight: .heavy))
                    .foregroundStyle(TavernPalette.parchment)
                    .shadow(color: .black, radius: 1.5)
                    .offset(x: -size * 0.3, y: -size * 0.3)
            }
        }
    }
}

/// The top of a player's zones pop-over: their name, their status badges and the cards
/// attached to them (tap one to inspect it).
struct TavernPlayerStatusPanel: View {
    let name: String
    let summary: PlayerStatusSummary
    var inspect: ((String, [ZoneCard]) -> Void)?
    @Environment(\.tavernMenuSelect) private var select

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name.uppercased())
                .font(.system(size: 13, weight: .heavy, design: .serif))
                .tracking(1)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), Color(red: 0.80, green: 0.56, blue: 0.22)],
                                                startPoint: .top, endPoint: .bottom))
                .frame(maxWidth: .infinity)
            if !summary.badges.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                    ForEach(summary.badges) { TavernStatusBadge(badge: $0) }
                }
                .padding(.trailing, 6)
                .accessibilityIdentifier("board.zones.status")
            }
            if !summary.attachments.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TavernPalette.brass)
                        .accessibilityHidden(true)
                    ForEach(summary.attachments) { card in
                        Button { select { inspect?("Attached to \(name)", [card]) } } label: {
                            TavernArtCrop(card: card, zoneName: "Battlefield")
                                .frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(TavernPalette.brass, lineWidth: 1.2))
                                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(card.card.name), attached")
                        .accessibilityIdentifier("board.zones.attached.\(card.instanceId)")
                    }
                }
            }
            if !summary.isEmpty { TavernMenuDivider() }
        }
    }
}

/// The bottom of an opponent's pop-over in a pod: swap to another opponent's information.
/// The current one carries an ember ring.
struct TavernOpponentSwap: View {
    let opponents: [PlayerGameState]
    let current: String
    let label: (String) -> String
    let select: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            TavernMenuDivider()
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.56), TavernPalette.brass],
                                                    startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
                ForEach(opponents) { opponent in
                    let chosen = opponent.playerId == current
                    Button { select(opponent.playerId) } label: {
                        PlayerPortrait(player: opponent, size: 36)
                            .overlay(Circle().strokeBorder(chosen ? TavernPalette.ember : TavernPalette.brass.opacity(0.6),
                                                           lineWidth: chosen ? 2.5 : 1.2))
                            .opacity(opponent.isOut ? 0.45 : 1)
                            .shadow(color: chosen ? TavernPalette.ember.opacity(0.7) : .clear, radius: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Swap to \(label(opponent.playerId))")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityIdentifier("board.zones.swap.\(opponent.playerId)")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A glance at the most pressing status beside a medallion: poison and the worst commander
/// damage. Taps pass through to the medallion, whose pop-over shows everything.
struct TavernStatusGlance: View {
    let summary: PlayerStatusSummary

    var body: some View {
        let pressing = summary.badges.filter {
            if case .poison = $0.icon { return true }
            if case .commander = $0.icon { return true }
            return false
        }
        let worstCommander = pressing.filter { if case .commander = $0.icon { return true } else { return false } }
            .max { ($0.count ?? 0) < ($1.count ?? 0) }
        let shown = pressing.filter { if case .poison = $0.icon { return true } else { return false } } + (worstCommander.map { [$0] } ?? [])
        HStack(spacing: 6) {
            ForEach(shown) { TavernStatusBadge(badge: $0, size: 22) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Glows (light only, no outlines)

/// The tavern board's highlight for a battlefield tile: soft light around the frame, no line.
/// A pre-blurred image tinted to `color` (also the framed tiles' drop shadow, in black): a live
/// blur on every tile was too slow with dozens of tokens on the board.
struct TavernTileGlow: View {
    let color: Color
    var strength: Double = 0.95
    private static let image = UIImage(named: "tavern-tile-glow")

    var body: some View {
        if let image = Self.image {
            GeometryReader { proxy in
                // The image's light runs 30 px past a 240 x 260 card on a 300 x 320 canvas.
                Image(uiImage: image).resizable().renderingMode(.template)
                    .foregroundStyle(color)
                    .frame(width: proxy.size.width * 300 / 240, height: proxy.size.height * 320 / 260)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .opacity(strength)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(color).padding(-4).blur(radius: 9)
                .opacity(strength).allowsHitTesting(false)
        }
    }
}

/// The back of a small brass coin, for badges on the tavern board (abilities, tapped, more).
struct TavernCoinBack: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(red: 0.32, green: 0.19, blue: 0.09), TavernPalette.leather],
                                 center: .init(x: 0.4, y: 0.3), startRadius: 0, endRadius: 14))
            .overlay(Circle().strokeBorder(BrandTheme.brassGradient, lineWidth: 1.2))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
    }
}

/// Your commander medallion when the commander can be cast: an emerald-and-gold ring of light
/// breathing around it and a crown spark above. Distinct from the ember glow of your turn.
struct TavernCommanderReadyGlow: View {
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ring = Circle()
            .strokeBorder(AngularGradient(colors: [Color(red: 0.45, green: 1, blue: 0.55), Color(red: 1, green: 0.86, blue: 0.45),
                                                   Color(red: 0.3, green: 0.9, blue: 0.5), Color(red: 1, green: 0.86, blue: 0.45),
                                                   Color(red: 0.45, green: 1, blue: 0.55)], center: .center),
                          lineWidth: diameter * 0.09)
            .frame(width: diameter * 1.42, height: diameter * 1.42)
            .blur(radius: diameter * 0.07)
        let crown = Image(systemName: "crown.fill")
            .font(.system(size: diameter * 0.26, weight: .bold))
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), Color(red: 0.95, green: 0.7, blue: 0.25)],
                                            startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(red: 0.5, green: 1, blue: 0.55).opacity(0.9), radius: 5)
            .offset(y: -diameter * 0.84)
        ZStack {
            if reduceMotion {
                ring.opacity(0.9)
            } else {
                ring.phaseAnimator([0.45, 1.0]) { view, strength in
                    view.opacity(strength).scaleEffect(0.96 + 0.06 * strength)
                } animation: { _ in .easeInOut(duration: 0.9) }
            }
            crown
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Keys under which the tavern medallions publish their frames (PortraitCardBoundsKey), so
/// attack arrows and life changes point at the medallion rather than a HUD strip.
enum TavernSeatAnchor {
    static let bottom = "tavern-seat:bottom"
    static let top = "tavern-seat:top"
}
