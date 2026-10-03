import SwiftUI
import PhotosUI
import UIKit

struct ManaPoolHUD: View {
    let manaPool: ManaPool?
    var vertical = false
    var compact = false
    var grid = false
    var payableSymbols: Set<String> = []
    var payMana: ((String) -> Void)? = nil

    private var values: [(String, Int)] {
        [
            ("W", manaPool?.W ?? 0),
            ("U", manaPool?.U ?? 0),
            ("B", manaPool?.B ?? 0),
            ("R", manaPool?.R ?? 0),
            ("G", manaPool?.G ?? 0),
            ("C", manaPool?.C ?? 0)
        ]
    }

    var body: some View {
        Group {
            if grid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 5) {
                    manaContent
                }
                .padding(5)
            } else if vertical {
                VStack(spacing: 5) {
                    manaContent
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 9)
            } else {
                HStack(spacing: compact ? 2 : 5) {
                    manaContent
                }
                .padding(.horizontal, compact ? 4 : 9)
                .padding(.vertical, payableSymbols.isEmpty ? 6 : 4)
            }
        }
        .background(MagicPalette.iron.opacity(0.76), in: RoundedRectangle(cornerRadius: vertical ? 12 : 16))
        .overlay(RoundedRectangle(cornerRadius: vertical ? 12 : 16).stroke(MagicPalette.antiqueGold.opacity(0.38), lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 10, y: 5)
    }

    @ViewBuilder
    private var manaContent: some View {
        ForEach(values, id: \.0) { symbol, count in
            if payableSymbols.contains(symbol), !grid, let payMana {
                Button { payMana(symbol) } label: {
                    manaValue(symbol: symbol, count: count)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(MagicPalette.antiqueGold.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.9), lineWidth: 1.5))
                        .shadow(color: MagicPalette.antiqueGold.opacity(0.65), radius: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Spend floating \(symbol) mana, \(count) available")
                .accessibilityIdentifier("board.mana.spend.\(symbol)")
            } else {
                manaValue(symbol: symbol, count: count)
                    .opacity(count > 0 ? 1 : 0.45)
                    .background(payableSymbols.contains(symbol) ? MagicPalette.antiqueGold.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: payableSymbols.contains(symbol) ? MagicPalette.antiqueGold : .clear, radius: 4)
            }
        }
    }

    private func manaValue(symbol: String, count: Int) -> some View {
        HStack(spacing: 2) {
                ManaSymbolView(symbol: symbol, size: compact ? 13 : 18)
                Text("\(count)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .frame(minWidth: 8)
            }
    }
}

struct ManaSymbolView: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        if let url = CardImageURL.symbol("{\(symbol)}"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if let assetName = CardImageURL.bundledSymbolAssetName(for: symbol),
                  let image = UIImage(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(symbol)
                .font(.system(size: size * 0.58, weight: .black))
                .foregroundStyle(foregroundColor)
                .frame(width: size, height: size)
                .background(backgroundColor, in: Circle())
                .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 1))
        }
    }

    private var backgroundColor: Color {
        switch symbol {
        case "W": return Color(red: 0.92, green: 0.86, blue: 0.66)
        case "U": return Color(red: 0.32, green: 0.55, blue: 0.78)
        case "B": return Color(red: 0.18, green: 0.16, blue: 0.15)
        case "R": return Color(red: 0.78, green: 0.25, blue: 0.16)
        case "G": return Color(red: 0.25, green: 0.52, blue: 0.25)
        default: return Color(red: 0.60, green: 0.57, blue: 0.50)
        }
    }

    private var foregroundColor: Color {
        symbol == "B" ? .white : .black
    }
}

struct StackPeek: View {
    let cards: [ZoneCard]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("STACK")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)

            HStack(spacing: 8) {
                HStack(spacing: -14) {
                    ForEach(Array(cards.suffix(4).enumerated()), id: \.element.id) { index, card in
                        CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: "Stack", width: 38, height: 54)
                            .zIndex(Double(index))
                            .onCardInteraction(tap: {
                                selectedCard = card
                                inspectedCard = nil
                            }, inspect: {
                                inspectedCard = card
                            }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                    }
                }

                Text(cards.last?.card.name ?? "Resolving")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.24)))
    }
}

struct XmageStackPeek: View {
    let objects: [XmageStackObject]
    let legalActions: [LegalAction]
    let promptText: String?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?

    private var topObject: XmageStackObject? {
        objects.last
    }

    private var topDisplayCard: ZoneCard? {
        topObject?.displaySourceCard
    }

    private var passAvailable: Bool {
        legalActions.contains { ["pass_priority", "pass_until_response", "advance_phase"].contains($0.type) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("STACK")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold)
                Text("\(objects.count)")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer(minLength: 0)
                Text(passAvailable ? "RESPOND" : "WAIT")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(passAvailable ? MagicPalette.legalEmerald : .white.opacity(0.55))
            }

            HStack(spacing: 9) {
                if let card = topDisplayCard {
                    CardTile(card: card, selected: selectedCard?.id == card.id, legal: false, zoneName: "Stack", width: 128, height: 179, ignoreTappedRotation: true, imageVariant: .inspection)
                        .onCardInteraction(tap: {
                            selectedCard = nil
                            inspectedCard = card
                        }, inspect: {
                            inspectedCard = card
                        }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                } else {
                    SyntheticStackObjectTile(object: topObject, width: 128, height: 179)
                }

                Spacer(minLength: 0)
            }

            if let topObject {
                Text(topObject.displayName).font(.caption.bold()).foregroundStyle(MagicPalette.parchment)
                if let rules = topObject.rulesText, !rules.isEmpty {
                    GameRulesText(source: rules, cardName: topObject.displayName).font(.caption)
                        .foregroundStyle(MagicPalette.parchment.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .background(MagicPalette.iron.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.30)))
    }
}

struct SyntheticStackObjectTile: View {
    let object: XmageStackObject?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text(object?.syntheticTileSubtitle.uppercased() ?? "STACK")
                .font(.system(size: 6, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text(object?.syntheticTileTitle ?? "Ability")
                .font(.system(size: 7.5, weight: .black))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.50)
            Text(object?.syntheticTileDetail ?? "Source card image unavailable")
                .font(.system(size: 5.8, weight: .bold))
                .foregroundStyle(MagicPalette.parchment.opacity(0.70))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.48)
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: height)
        .background(
            LinearGradient(
                colors: [MagicPalette.leather.opacity(0.78), MagicPalette.iron.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(MagicPalette.antiqueGold.opacity(0.55), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Text("STACK")
                .font(.system(size: 5.5, weight: .black))
                .foregroundStyle(.black.opacity(0.72))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(MagicPalette.antiqueGold.opacity(0.88), in: Capsule())
                .padding(3)
        }
    }
}

enum BoardDecisionPresentation {
    static func showsGuidance(_ snapshot: GameSnapshot) -> Bool {
        PromptGuidance(snapshot: snapshot, isWaitingOnHuman: snapshot.isViewer(snapshot.waitingOnPlayerId)).isUrgent
    }

    static func needsCenterSpace(_ snapshot: GameSnapshot, hasRejection: Bool = false) -> Bool {
        showsGuidance(snapshot) || hasRejection ||
        snapshot.xmage?.revealed.contains(where: { !$0.cards.isEmpty }) == true ||
        snapshot.xmage?.lookedAt.contains(where: { !$0.cards.isEmpty }) == true
    }
}

struct PromptPill: View {
    let snapshot: GameSnapshot
    var combatSelection = CombatSelectionState()
    /// While declaring attackers or blockers: take back the last creature you declared.
    var back: (() -> Void)? = nil

    private var isWaitingOnHuman: Bool {
        snapshot.isViewer(snapshot.waitingOnPlayerId)
            || (snapshot.waitingOnPlayerId == nil && snapshot.isViewer(snapshot.priorityPlayerId))
            || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty
    }

    private var guidance: PromptGuidance {
        PromptGuidance(snapshot: snapshot, isWaitingOnHuman: isWaitingOnHuman, combatSelection: combatSelection)
    }
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        if tavern && TavernUIKit.available {
            tavernRibbon
        } else {
            classicPill
        }
    }

    /// The tavern's leather ribbon; the tag's jewel keeps the prompt's colour cue.
    private var tavernRibbon: some View {
        HStack(spacing: 10) {
            TavernTag(text: guidance.label, accent: guidance.color)
            Text(guidance.message)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(TavernPalette.parchment)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            if let back { backButton(back).buttonStyle(TavernButtonStyle(kind: .secondary, compact: true)) }
        }
        .modifier(TavernRibbon())
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Back", systemImage: "arrow.uturn.backward")
        }
        .accessibilityLabel("Take back the last declaration")
        .accessibilityIdentifier("board.combat.back")
    }

    private var classicPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(guidance.color)
                .frame(width: 8, height: 8)
                .shadow(color: guidance.color.opacity(0.8), radius: 5)

            Text(guidance.label)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(guidance.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(guidance.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            Text(guidance.message)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Spacer()
            if let back { backButton(back).buttonStyle(CompactActionButtonStyle(isPrimary: false)) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(MagicPalette.iron.opacity(0.74), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(guidance.color.opacity(guidance.isUrgent ? 0.72 : 0.5), lineWidth: 1.5))
    }
}

enum InlinePaymentPromptState {
    static func isActive(in snapshot: GameSnapshot) -> Bool {
        paymentPrompt(in: snapshot) != nil
    }

    static func paymentPrompt(in snapshot: GameSnapshot) -> PromptEnvelopeV2? {
        if let prompt = snapshot.promptEnvelopeV2, CompactPromptPopup.isManaPaymentPrompt(prompt) {
            return prompt
        }
        if CompactPromptPopup.shouldShowStackPaymentTray(in: snapshot) {
            return CompactPromptPopup.syntheticStackPaymentPrompt(in: snapshot)
        }
        return nil
    }
}

struct InlinePaymentPromptBar: View {
    let snapshot: GameSnapshot
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let openDetails: () -> Void
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        if tavern && TavernUIKit.available {
            tavernRibbon
        } else {
            classicBar
        }
    }

    /// The tavern's leather ribbon: a parchment PAY COST tag, the remaining cost on brass
    /// coins and crystal gems.
    private var tavernRibbon: some View {
        HStack(spacing: 8) {
            TavernTag(text: "PAY COST")
            if let prompt = InlinePaymentPromptState.paymentPrompt(in: snapshot) {
                ManaPaymentTray(
                    snapshot: snapshot,
                    prompt: prompt,
                    pendingActionId: pendingActionId,
                    runAction: runAction,
                    runCommand: runCommand,
                    compact: true
                )
            } else {
                Text("Tap mana sources")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(TavernPalette.parchment)
            }
            Spacer(minLength: 0)
            if snapshot.source == "xmage-ondevice" {
                Button(action: openDetails) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(IconButtonStyle(small: true))
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Payment choices")
            }
        }
        .modifier(TavernRibbon())
    }

    private var classicBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(MagicPalette.antiqueGold)
                .frame(width: 8, height: 8)
                .shadow(color: MagicPalette.antiqueGold.opacity(0.8), radius: 5)

            Text("PAY COST")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MagicPalette.antiqueGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            if let prompt = InlinePaymentPromptState.paymentPrompt(in: snapshot) {
                ManaPaymentTray(
                    snapshot: snapshot,
                    prompt: prompt,
                    pendingActionId: pendingActionId,
                    runAction: runAction,
                    runCommand: runCommand,
                    compact: true
                )
            } else {
                Text("Tap mana sources")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)
            if snapshot.source == "xmage-ondevice" {
                Button(action: openDetails) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(IconButtonStyle(small: true))
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Payment choices")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(MagicPalette.iron.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.antiqueGold.opacity(0.72), lineWidth: 1.5))
    }
}

struct PromptGuidance {
    let label: String
    let message: String
    let color: Color
    let isUrgent: Bool

    init(snapshot: GameSnapshot, isWaitingOnHuman: Bool, combatSelection: CombatSelectionState = CombatSelectionState()) {
        let promptType = snapshot.promptEnvelopeV2?.responseCommand?.type?.lowercased()
            ?? snapshot.promptEnvelopeV2?.responseKind.lowercased()
            ?? ""
        let method = snapshot.promptEnvelopeV2?.method.uppercased() ?? ""
        if snapshot.manaPayment?.active == true || snapshot.promptEnvelopeV2.map(CompactPromptPopup.isManaPaymentPrompt) == true {
            label = "PAY COST"
            message = snapshot.manaPayment?.remainingText ?? "Tap mana sources"
            color = MagicPalette.antiqueGold
            isUrgent = true
        } else if promptType == "choose_target" || method.contains("TARGET") {
            label = "SELECT TARGET"
            message = snapshot.promptText ?? "Choose a highlighted target"
            color = MagicPalette.oxblood
            isUrgent = true
        } else if CombatSelectionState.isDeclareAttackers(snapshot) {
            let selectableAttackers = combatSelection.attackerHighlightIds(actions: snapshot.legalActions ?? [])
            label = combatSelection.selectedAttackerIds.isEmpty ? "SELECT ATTACKERS" : "SELECT DEFENDER"
            message = combatSelection.selectedAttackerIds.isEmpty
                ? (selectableAttackers.isEmpty ? "No creatures can attack — choose No Attacks" : "Choose a highlighted attacker")
                : "Choose who to attack"
            color = MagicPalette.oxblood
            isUrgent = true
        } else if CombatSelectionState.isDeclareBlockers(snapshot) {
            let selectableBlockers = combatSelection.blockerHighlightIds(actions: snapshot.legalActions ?? [])
            label = combatSelection.selectedBlockerId == nil ? "SELECT BLOCKERS" : "SELECT ATTACKER"
            message = combatSelection.selectedBlockerId == nil
                ? (selectableBlockers.isEmpty ? "No creatures can block — choose No Blocks" : "Choose a highlighted blocker")
                : "Choose attacker to block"
            color = MagicPalette.warningAmber
            isUrgent = true
        } else if isWaitingOnHuman {
            label = "YOUR DECISION"
            message = snapshot.promptText ?? "Play spells and abilities"
            color = MagicPalette.emerald
            isUrgent = false
        } else {
            label = "\(snapshot.playerLabel(snapshot.waitingOnPlayerId ?? snapshot.priorityPlayerId).uppercased()) DECISION"
            message = snapshot.promptText ?? "Waiting for XMage"
            color = MagicPalette.arcaneBlue
            isUrgent = false
        }
    }
}

/// UIKit arbitrates the hold before selection, including inside a scrolling sheet.
/// A recognized hold can never also invoke the tap action.
struct AbilityChoiceTouchSurface: UIViewRepresentable {
    let enabled: Bool
    let choose: () -> Void
    let inspect: () -> Void
    let releaseInspection: () -> Void
    @Environment(\.holdCardInspection) private var inspection

    func makeUIView(context: Context) -> TouchView { TouchView() }
    func updateUIView(_ view: TouchView, context: Context) {
        view.isUserInteractionEnabled = enabled
        view.choose = choose
        view.inspect = { inspection?.begin(dismiss: releaseInspection); inspect() }
        view.releaseInspection = { if let inspection { inspection.end() } else { releaseInspection() } }
    }

    static func dismantleUIView(_ view: TouchView, coordinator: ()) { view.finishInspection() }

    final class TouchView: UIView {
        var choose: (() -> Void)?
        var inspect: (() -> Void)?
        var releaseInspection: (() -> Void)?
        private var inspecting = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isAccessibilityElement = false
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.35
            hold.allowableMovement = 8
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.require(toFail: hold)
            addGestureRecognizer(hold)
            addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func tapped() { choose?() }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: inspecting = true; inspect?()
            case .ended, .cancelled, .failed: finishInspection()
            default: break
            }
        }
        func finishInspection() {
            guard inspecting else { return }
            inspecting = false
            releaseInspection?()
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { finishInspection() }
        }
    }
}
