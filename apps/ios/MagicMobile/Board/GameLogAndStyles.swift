import SwiftUI
import PhotosUI
import UIKit

struct GameLogBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct GameLogDrawer: View {
    let log: [GameLogEntry]
    /// One-line combat reasons by entry ID (CombatLogReasons).
    var reasons: [String: String] = [:]
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var followingLatest = true
    @State private var inspectedLogCard: ZoneCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOG")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle(small: true))
                .accessibilityLabel("Close game log")
            }

            ScrollViewReader { proxy in
                GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if log.isEmpty {
                            Text("No public game actions yet.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(log) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                GameLogText(message: entry.message, usesDarkBackground: true, onInspect: { reference in
                                    // The public log authorizes the printed identity, not a lookup
                                    // of this object's current (possibly hidden) game state.
                                    guard NativeCardArtworkPolicy.permitsLookup(name: reference.name) else { return }
                                    inspectedLogCard = ZoneCard(instanceId: reference.objectID.uuidString,
                                        card: CardIdentity(name: reference.name, typeLine: "Card referenced in game log",
                                                           oracleText: "Loading local card text…"),
                                        tapped: nil, summoningSickness: nil, cardIcons: nil, counters: nil,
                                        power: nil, toughness: nil, isCreaturePermanent: nil, damage: nil,
                                        isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
                                    Task { @MainActor in
                                        // Disk-only catalogue lookup off the UI thread. Never resolve
                                        // the historical object UUID against live/private game state.
                                        let printed = await Task.detached(priority: .userInitiated) {
                                            (try? NativeDeckMetadataCatalogue.bundled())?.card(named: reference.name)
                                        }.value
                                        guard inspectedLogCard?.instanceId == reference.objectID.uuidString,
                                              inspectedLogCard?.card.name == reference.name else { return }
                                        inspectedLogCard = ZoneCard(instanceId: reference.objectID.uuidString,
                                            card: CardIdentity(name: reference.name,
                                                typeLine: printed?.typeLine ?? "Card referenced in game log",
                                                oracleText: printed?.oracleText ?? "Rules unavailable in the local catalogue.",
                                                manaCost: printed?.manaCost),
                                            tapped: nil, summoningSickness: nil, cardIcons: nil, counters: nil,
                                            power: nil, toughness: nil, isCreaturePermanent: nil, damage: nil,
                                            isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
                                    }
                                })
                                    .font(.subheadline)
                                // One line of public combat context under the engine's line.
                                if let reason = reasons[entry.id] {
                                    Text(reason)
                                        .font(.caption.italic())
                                        .foregroundStyle(.white.opacity(0.62))
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                        .accessibilityIdentifier("log.reason")
                                }
                            }
                            .padding(.top, GameLogPresentation(entry.message).plainText.hasPrefix("TURN ") ? 12 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("log-bottom")
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: GameLogBottomKey.self, value: geometry.frame(in: .named("game-log-scroll")).maxY)
                            })
                    }
                }
                .coordinateSpace(name: "game-log-scroll")
                .onPreferenceChange(GameLogBottomKey.self) { bottom in
                    followingLatest = bottom > 0 && bottom < viewport.size.height + 80
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followingLatest {
                        Button("Latest actions ↓") {
                            proxy.scrollTo("log-bottom", anchor: .bottom)
                            followingLatest = true
                        }.buttonStyle(.borderedProminent).padding(8)
                    }
                }
                .onAppear {
                    if let lastId = log.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onChange(of: log.last?.id) { _, _ in
                    if followingLatest, let lastId = log.last?.id {
                        if GameBoardMotion.reduced(accessibilityReduceMotion) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16)))
        .sheet(item: $inspectedLogCard) { card in
            VStack(spacing: 8) {
                HStack {
                    Text("From the game log").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { inspectedLogCard = nil }.frame(minHeight: 44)
                }
                CardInspector(card: card)
            }
            .padding(12).presentationDetents([.large])
        }
    }
}

struct CompactActionButtonStyle: ButtonStyle {
    var isDanger = false
    var isPrimary = false
    @Environment(\.tavernBoard) private var tavern

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if tavern && TavernUIKit.available {
            TavernButtonStyle(kind: isDanger ? .danger : (isPrimary ? .primary : .secondary), compact: true)
                .makeBody(configuration: configuration)
        } else {
            CompactActionFace(label: configuration.label, pressed: configuration.isPressed, style: self)
        }
    }

    fileprivate func backgroundColor(isPressed: Bool) -> Color {
        if isDanger {
            return isPressed ? MagicPalette.oxblood.opacity(0.66) : MagicPalette.oxblood.opacity(0.84)
        }
        if isPrimary {
            return isPressed ? MagicPalette.brass.opacity(0.70) : MagicPalette.antiqueGold.opacity(0.88)
        }
        return isPressed ? MagicPalette.panelParchment.opacity(0.18) : MagicPalette.iron.opacity(0.58)
    }
}

/// A view, so a disabled button reads as disabled (dimmed, desaturated) wherever it is used.
struct CompactActionFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let style: CompactActionButtonStyle
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .font(.system(size: style.isPrimary ? 15 : 13, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, style.isPrimary ? 15 : 12)
            .padding(.vertical, style.isPrimary ? 10 : 8)
            .frame(minWidth: style.isPrimary ? 112 : 94, minHeight: 44, alignment: .center)
            .background(style.backgroundColor(isPressed: pressed), in: Capsule())
            .saturation(isEnabled ? 1 : 0.1)
            .opacity(pressed ? 0.82 : isEnabled ? 1 : 0.5)
    }
}

struct IconButtonStyle: ButtonStyle {
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 12 : 16, weight: .black))
            .foregroundStyle(.white)
            .frame(width: small ? 28 : 42, height: small ? 28 : 42)
            .background(configuration.isPressed ? Color.white.opacity(0.18) : Color.black.opacity(0.45), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.16)))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
