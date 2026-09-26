import SwiftUI
import UIKit

/// Attachment relationships come only from the current public engine snapshot.
/// Invalid/missing links remain visible in their original lane instead of losing cards.
enum BattlefieldAttachments {
    static func isManaRock(_ card: ZoneCard) -> Bool {
        guard card.card.isArtifact, !card.isCreature, !card.card.isLand else { return false }
        guard let rules = card.card.oracleText else { return false }
        // The public snapshot has printed rules but no permanent mana-ability metadata.
        // Match an activated cost and an explicit mana effect, not incidental "add" text.
        return rules.split(separator: "\n").contains { line in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return false }
            let cost = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard !cost.hasPrefix("when "), !cost.hasPrefix("whenever "), !cost.hasPrefix("at "),
                  cost.contains("{t}") || cost.contains("sacrifice") || cost.hasPrefix("tap ") else { return false }
            return parts[1].range(of: #"^\s*add\s+(?:\{[cwubrg]\}|(?:one|two|three|\d+) mana)"#,
                                  options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static func isSupport(_ card: ZoneCard) -> Bool {
        !card.isCreature && !card.card.isPlaneswalker &&
        !card.card.typeLine.localizedCaseInsensitiveContains("battle") &&
        !card.card.typeLine.localizedCaseInsensitiveContains("equipment")
    }

    static func roots(_ cards: [ZoneCard]) -> [String: String] {
        let byID = Dictionary(cards.map { ($0.instanceId, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(cards.map { card in
            var current = card.instanceId
            var seen = Set<String>()
            while let parent = byID[current]?.attachedToInstanceId, byID[parent] != nil {
                guard seen.insert(current).inserted, !seen.contains(parent) else {
                    return (card.instanceId, card.instanceId)
                }
                current = parent
            }
            return (card.instanceId, current)
        }, uniquingKeysWith: { first, _ in first })
    }

    static func lane(ownedCards: [ZoneCard], allCards: [ZoneCard], lands: Bool, playerIDs: Set<String> = [], includesManaRocks: Bool = false) -> [ZoneCard] {
        let roots = roots(allCards)
        let laneRoots = Set(ownedCards.filter {
            ($0.card.isLand || (includesManaRocks && isManaRock($0))) == lands && roots[$0.instanceId] == $0.instanceId && !playerIDs.contains($0.attachedToInstanceId ?? "")
        }.map(\.instanceId))
        return allCards.filter { laneRoots.contains(roots[$0.instanceId] ?? $0.instanceId) }
    }

    static func groups(_ cards: [ZoneCard]) -> [BattlefieldCardGroup] {
        let roots = roots(cards)
        let hostIDs = Set(cards.compactMap { card -> String? in
            guard let root = roots[card.instanceId], root != card.instanceId else { return nil }
            return root
        })
        let unattached = cards.filter { !hostIDs.contains(roots[$0.instanceId] ?? $0.instanceId) }
        var densityGroups = BattlefieldDensityPlanner.groups(cards: unattached)
        var result: [BattlefieldCardGroup] = []
        for card in cards {
            if hostIDs.contains(card.instanceId) {
                let children = cards.filter { $0.instanceId != card.instanceId && roots[$0.instanceId] == card.instanceId }
                result.append(BattlefieldCardGroup(id: "attachment:" + card.instanceId, cards: [card] + children))
            } else if let index = densityGroups.firstIndex(where: { $0.cards.contains(card) }) {
                result.append(densityGroups.remove(at: index))
            }
        }
        return result
    }

    static func enchanting(playerID: String, allCards: [ZoneCard]) -> [ZoneCard] {
        ZoneCard.enchanting(playerID: playerID, cards: allCards)
    }
}

enum BattlefieldRowArrangement: Equatable {
    case automatic, landscapeResources, portraitPermanents

    func rows(_ groups: [BattlefieldCardGroup], flipped: Bool, twoRows: Bool) -> [[BattlefieldCardGroup]] {
        guard twoRows else { return [groups] }
        switch self {
        case .automatic:
            let midpoint = (groups.count + 1) / 2
            return [Array(groups.prefix(midpoint)), Array(groups.dropFirst(midpoint))]
        case .landscapeResources:
            let lands = groups.filter { $0.representative.card.isLand }
            let rocks = groups.filter { !$0.representative.card.isLand }
            if !rocks.isEmpty { return [lands, rocks] }
            let midpoint = (lands.count + 1) / 2
            return [Array(lands.prefix(midpoint)), Array(lands.dropFirst(midpoint))]
        case .portraitPermanents:
            let foreground = groups.filter { !BattlefieldAttachments.isSupport($0.representative) }
            let background = groups.filter { BattlefieldAttachments.isSupport($0.representative) }
            if foreground.isEmpty || background.isEmpty {
                let midpoint = (groups.count + 1) / 2
                return [Array(groups.prefix(midpoint)), Array(groups.dropFirst(midpoint))]
            }
            return flipped ? [background, foreground] : [foreground, background]
        }
    }
}

enum BoardPlayerStatus {
    static func counters(_ player: PlayerGameState) -> [(name: String, count: Int)] {
        var values = player.counters ?? [:]
        if player.poison > 0, !values.keys.contains(where: { $0.lowercased() == "poison" }) { values["Poison"] = player.poison }
        return values.filter { $0.value > 0 }.sorted { left, right in
            if left.key.lowercased() == "poison" { return right.key.lowercased() != "poison" }
            if right.key.lowercased() == "poison" { return false }
            return left.key < right.key
        }.map { ($0.key, $0.value) }
    }
}

/// Public player effects remain next to that player's HUD and use the same zone
/// inspector as battlefield permanents, including legal target/ability actions.
struct BoardPlayerEffects: View {
    let player: PlayerGameState
    var attachments: [ZoneCard] = []
    var viewZone: ((String, [ZoneCard]) -> Void)? = nil
    var opponents: [PlayerGameState] = []
    var selectOpponent: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var counters: [(name: String, count: Int)] { BoardPlayerStatus.counters(player) }
    private var compactIcon: String {
        if opponents.count > 1 { return "person.2.fill" }
        if counters.first?.name.lowercased() == "poison" { return "exclamationmark.shield.fill" }
        return attachments.isEmpty ? "circle.grid.2x2.fill" : "link"
    }
    private var effectsDescription: String {
        var parts = ["\(player.displayName ?? "Player") effects"]
        parts.append(contentsOf: counters.map { "\($0.name) \($0.count)" })
        if player.monarch == true { parts.append("Monarch") }
        if player.initiative == true { parts.append("Initiative") }
        parts.append(contentsOf: attachments.map { "\($0.card.name) attached" })
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if !counters.isEmpty || !attachments.isEmpty || player.monarch == true || player.initiative == true || opponents.count > 1 {
            Menu {
                ForEach(counters, id: \.name) { counter in Text("\(counter.name.capitalized): \(counter.count)") }
                if player.monarch == true { Text("Monarch") }
                if player.initiative == true { Text("Has the initiative") }
                if let viewZone {
                    ForEach(attachments) { card in
                        Button("\(card.card.name) · attached") { viewZone("Enchanting \(player.displayName ?? "player")", attachments) }
                    }
                }
                if opponents.count > 1, let selectOpponent {
                    Section("View opponent") {
                        ForEach(opponents) { opponent in
                            Button(opponent.displayName ?? "Opponent") { selectOpponent(opponent.playerId) }
                        }
                    }
                }
            } label: {
                effectsLabel
            }
            .accessibilityLabel(effectsDescription)
            .accessibilityHint(opponents.count > 1 ? "Choose an opponent or inspect player effects" : "Inspect player effects")
            .accessibilityValue(opponents.count > 1 ? player.displayName ?? "Opponent" : "")
            .accessibilityIdentifier(opponents.count > 1 ? "board.opponentFocus" : "board.player.effects.\(player.playerId)")
        }
    }

    private var effectsLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                if opponents.count > 1 { Image(systemName: "person.2.fill") }
                if let first = counters.first {
                    Text("\(first.name.capitalized) \(first.count)")
                        .contentTransition(.numericText(value: Double(first.count)))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: first.count)
                } else if !attachments.isEmpty { Image(systemName: "link"); Text("\(attachments.count)") }
                else if player.monarch == true { Image(systemName: "crown.fill") }
                else if player.initiative == true { Image(systemName: "flag.fill") }
            }.fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 2) {
                Image(systemName: compactIcon)
                if let first = counters.first { Text("\(first.count)").contentTransition(.numericText(value: Double(first.count))) }
                else if !attachments.isEmpty { Text("\(attachments.count)") }
            }.fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 10, weight: .bold)).foregroundStyle(MagicPalette.antiqueGold)
        .lineLimit(1)
        .padding(.horizontal, 3).frame(minHeight: 44)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Priority is a response opportunity inside a real phase/step, not a new phase.
struct BoardResponseCue: Equatable {
    let title: String
    let detail: String

    static func make(_ snapshot: GameSnapshot) -> Self? {
        guard !snapshot.isCompleted, snapshot.isViewer(snapshot.priorityPlayerId),
              let prompt = snapshot.promptEnvelopeV2, snapshot.isViewer(prompt.playerId),
              prompt.responseKind == "priority" || prompt.responseCommand?.type == "pass_priority" else { return nil }
        let rawStep = snapshot.step ?? snapshot.phase
        let step = EngineDisplayText.phaseLabel(rawStep)
        let waiting = !snapshot.stackTopFirst.isEmpty || snapshot.players.contains { !$0.zones.stack.isEmpty }
        let normalized = rawStep.uppercased().filter { $0.isLetter || $0.isNumber }
        let mainPhase = ["PRECOMBATMAIN", "POSTCOMBATMAIN", "MAIN1", "MAIN2"].contains(normalized)
        if !waiting, snapshot.isViewer(snapshot.activePlayerId), mainPhase { return nil }
        return Self(title: waiting ? "Respond to the stack" : "Your response window",
                    detail: step)
    }
}

struct BoardResponseBanner: View {
    let cue: BoardResponseCue
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(cue.title, systemImage: "bolt.circle.fill").font(.caption.bold())
            Text(cue.detail).font(.caption2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(MagicPalette.parchment)
        .padding(8)
        .background(MagicPalette.iron.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(MagicPalette.antiqueGold.opacity(0.8), lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityIdentifier("board.response.window")
    }
}

/// Changes are visual feedback only; life always comes from the current snapshot.
struct BoardLifeTotal: View {
    let life: Int
    var suffix = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Board effects draw their own floating life number; the badge covers Off only.
    @AppStorage(BoardFXLevel.key) private var boardEffects = BoardFXLevel.defaultValue
    @State private var delta = 0
    @State private var changeToken = UUID()

    var body: some View {
        let showsBadge = BoardFXLevel(rawValue: boardEffects) == .off
        Text("\(life)\(suffix)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(life)))
            .foregroundStyle(delta == 0 ? MagicPalette.antiqueGold : delta < 0 ? Color.red : Color.green)
            .scaleEffect(delta == 0 || reduceMotion ? 1 : 1.16)
            .overlay(alignment: .topTrailing) {
                if delta != 0 && showsBadge {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.caption.bold()).foregroundStyle(delta < 0 ? .red : .green)
                        .padding(3).background(.black.opacity(0.9), in: Capsule())
                        .offset(x: 18, y: -16)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: life)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: delta)
            .onChange(of: life) { old, new in
                delta = new - old
                changeToken = UUID()
            }
            .task(id: changeToken) {
                guard delta != 0 else { return }
                do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                delta = 0
            }
            .accessibilityLabel("\(life) life")
    }
}

/// A second permanent row is used only when both rows retain 44-point targets.
/// Very narrow screens scroll by actual content width, never by card count alone.
struct ArenaPermanentLayout {
    let rows: Int
    let columns: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let contentWidth: CGFloat

    init(count: Int, width: CGFloat, height: CGFloat, maxCardWidth: CGFloat, ratio: CGFloat) {
        self.init(rowCounts: count > 5 ? [(count + 1) / 2, count / 2] : [count], width: width, height: height, maxCardWidth: maxCardWidth, ratio: ratio)
    }

    init(rowCounts: [Int], width: CGFloat, height: CGFloat, maxCardWidth: CGFloat, ratio: CGFloat) {
        let ratio = max(ratio, 1)
        rows = rowCounts.count > 1 && height >= 2 * 44 * ratio + 20 ? 2 : 1
        columns = max(1, rows == 2 ? (rowCounts.max() ?? 0) : rowCounts.reduce(0, +))
        let heightFit = (height - 16 - CGFloat(rows - 1) * 4) / CGFloat(rows) / ratio
        let visibleColumns = CGFloat(min(5, columns))
        let widthFit = (width - 16 - (visibleColumns - 1) * 4) / visibleColumns
        cardWidth = max(44, min(maxCardWidth, heightFit, widthFit))
        cardHeight = cardWidth * ratio
        contentWidth = 16 + CGFloat(columns) * cardWidth + CGFloat(columns - 1) * 4
    }
}

/// Presentation only. Printed costs never substitute for XMage's payment prompt.
struct HandManaCost: View {
    let cost: String?
    var body: some View {
        if let cost, !cost.isEmpty {
            HStack(spacing: 1) {
                ForEach(Array(Self.symbols(cost).enumerated()), id: \.offset) { _, symbol in
                    if symbol == "//" { Text("/").font(.caption2.bold()).foregroundStyle(.white) }
                    else { ManaSymbolView(symbol: symbol, size: 15) }
                }
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .background(.black.opacity(0.88), in: Capsule())
            .accessibilityLabel("Printed mana cost: \(cost)")
        }
    }

    static func symbols(_ cost: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{([0-9WUBRGC/SXP]+)\\}|//") else { return [] }
        let source = cost as NSString
        return regex.matches(in: cost, range: NSRange(location: 0, length: source.length)).map {
            $0.range(at: 1).location == NSNotFound ? "//" : source.substring(with: $0.range(at: 1))
        }
    }
}

/// Keep current public engine icons inside the compact art area, even on narrow cards.
struct BattlefieldAbilityBadgePlan {
    let visible: [XmageCardIcon]
    let hiddenCount: Int

    init(icons: [XmageCardIcon], cardWidth: CGFloat) {
        let slots = min(4, max(1, Int((cardWidth - 4) / (Self.iconSize(for: cardWidth) + 5))))
        let visibleCount = min(icons.count, icons.count > slots ? max(0, slots - 1) : slots)
        visible = Array(icons.prefix(visibleCount))
        hiddenCount = icons.count - visibleCount
    }

    static func iconSize(for cardWidth: CGFloat) -> CGFloat { min(15, max(10, cardWidth * 0.17)) }

    static func accessibleName(for icon: XmageCardIcon) -> String {
        if let name = icon.displayText { return name }
        return icon.iconType.replacingOccurrences(of: "ABILITY_", with: "")
            .replacingOccurrences(of: "_", with: " ").localizedCapitalized
    }
}

private struct BattlefieldAbilityBadges: View {
    let icons: [XmageCardIcon]
    let cardWidth: CGFloat

    private var plan: BattlefieldAbilityBadgePlan { .init(icons: icons, cardWidth: cardWidth) }
    private var size: CGFloat { BattlefieldAbilityBadgePlan.iconSize(for: cardWidth) }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(plan.visible.enumerated()), id: \.offset) { _, icon in
                Group {
                    if icon.textBadge == "Menace" {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: size * 0.72, weight: .bold))
                    } else if let asset = XmageCardIcon.assetName(for: icon.iconType),
                              let image = UIImage(named: asset) {
                        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
                            .padding(2)
                    }
                }
                .foregroundStyle(MagicPalette.parchment)
                .frame(width: size + 4, height: size + 4)
                .background(MagicPalette.iron.opacity(0.88), in: Circle())
            }
            if plan.hiddenCount > 0 {
                Text("+\(plan.hiddenCount)")
                    .font(.system(size: max(7, size * 0.55), weight: .black))
                    .foregroundStyle(MagicPalette.iron)
                    .frame(width: size + 4, height: size + 4)
                    .background(MagicPalette.antiqueGold, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Named combat keywords on an attacking or blocking card (CombatKeywordBadgePlan). Strike
/// keywords are filled red and deathtouch violet, the pair that decides most trades. Keywords
/// that do not fit keep their icon in the card's ability row.
private struct CombatKeywordBadges: View {
    let plan: CombatKeywordBadgePlan
    let cardWidth: CGFloat

    var body: some View {
        let size = CombatKeywordBadgePlan.fontSize(cardWidth: cardWidth)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(plan.visible, id: \.self) { keyword in
                badge(plan.label(keyword).uppercased(), size: size, style: Self.style(keyword))
            }
        }
        .frame(maxWidth: cardWidth - 4, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func badge(_ text: String, size: CGFloat, style: (fill: Color, text: Color)) -> some View {
        Text(text)
            .font(.system(size: size, weight: .black))
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(style.text)
            .padding(.horizontal, 3.5).frame(height: size + 5)
            .background(style.fill, in: Capsule())
            .overlay(Capsule().stroke(.black.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
    }

    static func style(_ keyword: CombatKeyword) -> (fill: Color, text: Color) {
        switch keyword {
        case .doubleStrike, .firstStrike: return (Color(red: 0.86, green: 0.28, blue: 0.12), .white)
        case .deathtouch: return (Color(red: 0.24, green: 0.1, blue: 0.3), Color(red: 0.86, green: 0.7, blue: 1))
        default: return (Color.black.opacity(0.8), MagicPalette.parchment)
        }
    }
}

/// Compact public permanent face; the complete printed card remains in inspection.
/// Keeping a nearly square footprint also prevents a tap from displacing its neighbors.
struct ArenaBattlefieldCard: View {
    let card: ZoneCard
    var selected = false
    var legal = false
    var targetable = false
    let zoneName: String
    let width: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        card.isPhasedOut ? .gray : targetable ? .red : selected ? MagicPalette.antiqueGold : legal ? MagicPalette.legalEmerald : .white.opacity(0.35)
    }

    private var isLegendary: Bool { card.card.typeLine.localizedCaseInsensitiveContains("legendary") }

    /// Stats and summoning sickness need the footer. Tapped state is a badge over the art,
    /// so a tapped land keeps its art instead of trading it for an empty black strip.
    var showsFooter: Bool {
        card.showsPowerToughness || (card.isCreature && card.summoningSickness == true)
    }

    var accessibilityDescription: String {
        card.accessibilityLabel(zoneName: zoneName, selected: selected, legal: legal) +
            card.visibleXmageIcons.filter { $0.displayText == nil }
                .map { ", \(BattlefieldAbilityBadgePlan.accessibleName(for: $0))" }.joined()
    }

    /// Labeled combat keywords while the card attacks or blocks, gained ones included.
    private var combatPlan: CombatKeywordBadgePlan? {
        guard card.isInCombat, !card.isPhasedOut else { return nil }
        let plan = CombatKeywordBadgePlan(keywords: card.combatKeywords, cardWidth: width, cardHeight: height)
        return plan.visible.isEmpty ? nil : plan
    }

    /// The icon row leaves out keywords the combat badges already name.
    private var abilityIcons: [XmageCardIcon] {
        guard let combatPlan else { return card.visibleXmageIcons }
        var named = Set(combatPlan.visible.map(\.iconType))
        if combatPlan.visible.contains(.doubleStrike) { named.insert(CombatKeyword.firstStrike.iconType) }
        return card.visibleXmageIcons.filter { !named.contains($0.iconType.uppercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(card.card.name)
                .font(.system(size: max(8, width * 0.115), weight: .semibold, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 3)
                .frame(height: 15)
            ZStack(alignment: .top) {
                CardTile(card: card, selected: false, zoneName: zoneName,
                         width: width * 1.08, height: width * 1.51, ignoreTappedRotation: true)
                    .offset(y: -width * 0.19)
                    .allowsHitTesting(false).accessibilityIdentifier("").accessibilityHidden(true)
            }
            .frame(width: width, height: max(12, height - 15 - (showsFooter ? 20 : 0)), alignment: .top).clipped()
            if showsFooter {
                HStack(spacing: 2) {
                    if card.isCreature && card.summoningSickness == true {
                        Image(systemName: "hourglass").foregroundStyle(MagicPalette.warningAmber)
                    }
                    Spacer(minLength: 0)
                    if card.showsPowerToughness, let power = card.displayPower, let toughness = card.displayToughness {
                        Text("\(power)/\(toughness)").font(.system(size: max(11, width * 0.17), weight: .black, design: .rounded))
                    }
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 4).frame(height: 20)
            }
        }
        .foregroundStyle(.white)
        .frame(width: width, height: height)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .bottomLeading) {
            BattlefieldAbilityBadges(icons: abilityIcons, cardWidth: width)
                .padding(.leading, 2).padding(.bottom, showsFooter ? 22 : 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if let combatPlan {
                CombatKeywordBadges(plan: combatPlan, cardWidth: width)
                    .padding(.leading, 2).padding(.top, 17)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !card.counterBadges.isEmpty {
                CardCounterBadgeStrip(badges: Array(card.counterBadges.prefix(2)), cardWidth: width)
                    .padding(.top, 16).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if card.tapped == true {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: max(8, width * 0.12), weight: .black))
                    .foregroundStyle(MagicPalette.parchment)
                    .frame(width: max(15, width * 0.24), height: max(15, width * 0.24))
                    .background(.black.opacity(0.78), in: Circle())
                    .overlay(Circle().stroke(MagicPalette.antiqueGold.opacity(0.7), lineWidth: 1))
                    .padding(.trailing, 3).padding(.bottom, showsFooter ? 23 : 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent, lineWidth: legal || targetable || selected ? 2 : 1))
        .overlay {
            // Legendary permanents wear a gold edge unless a play/target state owns the border.
            if isLegendary && !(legal || targetable || selected) && !card.isPhasedOut {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(AngularGradient(colors: [MagicPalette.antiqueGold, Color(red: 1, green: 0.93, blue: 0.62),
                                                           Color(red: 0.62, green: 0.44, blue: 0.14), MagicPalette.antiqueGold],
                                                  center: .center), lineWidth: 2)
                    .shadow(color: MagicPalette.antiqueGold.opacity(0.45), radius: 4)
                    .allowsHitTesting(false)
            }
        }
        .saturation(card.tapped == true ? 0.15 : 1)
        .brightness(card.tapped == true ? -0.16 : 0)
        .rotationEffect(.degrees(card.tapped == true ? -7 : 0))
        .shadow(color: accent.opacity(legal || targetable ? 0.45 : 0.1), radius: 5)
        .opacity(card.isPhasedOut ? 0.42 : 1)
        .overlay(alignment: .center) {
            if card.isPhasedOut {
                Text("Phased out").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(3).background(.black.opacity(0.88), in: Capsule()).allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: card.isPhasedOut)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: card.tapped)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(((card.isPhasedOut ? ["Phased out; inspect only"] : []) +
                             card.visibleXmageIcons.map(BattlefieldAbilityBadgePlan.accessibleName(for:))).joined(separator: ", "))
        .accessibilityIdentifier(card.accessibilityIdentifier(zoneName: zoneName))
        .accessibilityAddTraits(.isButton)
    }
}

enum ArenaHandLayout {
    static func spacing(count: Int, width: CGFloat, cardWidth: CGFloat, expanded: Bool) -> CGFloat {
        guard !expanded, count > 1 else { return 8 }
        // Never reduce the exposed touch strip below 44 points; oversized hands scroll.
        let stride = max(44, min(cardWidth + 8, (width - cardWidth - 12) / CGFloat(count - 1)))
        return stride - cardWidth
    }
    static func restingHeight(cardHeight: CGFloat) -> CGFloat { cardHeight * 0.62 + 48 }
}

enum HandScrubberGeometry {
    static func thumbWidth(trackWidth: CGFloat) -> CGFloat {
        min(max(trackWidth * 0.22, 34), min(72, max(trackWidth, 1)))
    }

    static func progress(location: CGFloat, trackWidth: CGFloat, grabOffset: CGFloat) -> CGFloat {
        let travel = max(1, trackWidth - thumbWidth(trackWidth: trackWidth))
        return min(1, max(0, (location - grabOffset) / travel))
    }
}

struct CombatViewportAnchor: Equatable {
    let point: CGPoint
    let isClipped: Bool
}

enum CombatViewportAnchors {
    // Shared lane order: opponent permanents, opponent lands, your permanents, your lands.
    private static let landscapeResourcePrefix = "landscape-resource:"

    static func laneIndices(human: [ZoneCard], opponent: [ZoneCard]) -> [String: Int] {
        var result: [String: Int] = [:]
        let cards = human + opponent
        for card in BattlefieldAttachments.lane(ownedCards: opponent, allCards: cards, lands: false) { result[card.instanceId] = 0 }
        for card in BattlefieldAttachments.lane(ownedCards: opponent, allCards: cards, lands: true) { result[card.instanceId] = 1 }
        for card in BattlefieldAttachments.lane(ownedCards: human, allCards: cards, lands: false) { result[card.instanceId] = 2 }
        for card in BattlefieldAttachments.lane(ownedCards: human, allCards: cards, lands: true) { result[card.instanceId] = 3 }
        // A mana rock stays in the portrait permanent lane, but uses the right resource
        // lane in landscape. Carry that alternate ownership through the shared overlays.
        let roots = BattlefieldAttachments.roots(cards)
        let byID = Dictionary(cards.map { ($0.instanceId, $0) }, uniquingKeysWith: { first, _ in first })
        for card in cards where byID[roots[card.instanceId] ?? card.instanceId].map(BattlefieldAttachments.isManaRock) == true {
            result[landscapeResourcePrefix + card.instanceId] = 1
        }
        return result
    }

    static func resolve(bounds: [String: CGRect], authorizedIDs: Set<String>, viewports: [CGRect], laneIndices: [String: Int] = [:]) -> [String: CombatViewportAnchor] {
        var result: [String: CombatViewportAnchor] = [:]
        for (id, rect) in bounds where authorizedIDs.contains(id) && !rect.isEmpty && !rect.isInfinite && !rect.isNull {
            // Ownership must survive horizontal scrolling and side-by-side lanes.
            // Geometry alone cannot distinguish an offscreen creature from an animated land.
            let sideBySideResources = viewports.count == 4 && abs(viewports[0].midY - viewports[1].midY) < 1
            let landscapeResource = sideBySideResources && laneIndices[landscapeResourcePrefix + id] != nil
            let index = landscapeResource ? (laneIndices[id].map { $0 + 1 }) : laneIndices[id]
            guard let index = index ?? (viewports.count == 1 ? 0 : nil), viewports.indices.contains(index) else { continue }
            let lane = viewports[index]
            guard rect.midY >= lane.minY && rect.midY <= lane.maxY else { continue }
            let clipped = !lane.contains(rect)
            let point = CGPoint(x: min(max(rect.midX, lane.minX + 12), lane.maxX - 12),
                                y: min(max(rect.midY, lane.minY + 12), lane.maxY - 12))
            result[id] = CombatViewportAnchor(point: point, isClipped: clipped)
        }
        return result
    }
}

struct CombatEdgeIndicators: View {
    let cards: [ZoneCard]
    let combatIDs: Set<String>
    let bounds: [String: CGRect]
    let viewports: [CGRect]
    let laneIndices: [String: Int]
    let inspect: (ZoneCard) -> Void

    var body: some View {
        let anchors = CombatViewportAnchors.resolve(bounds: bounds, authorizedIDs: combatIDs.intersection(Set(cards.map(\.instanceId))), viewports: viewports, laneIndices: laneIndices)
        ForEach(CombatEdgeCluster.groups(anchors: anchors)) { cluster in
            let members = cards.filter { cluster.cardIDs.contains($0.instanceId) }
            Menu {
                ForEach(members) { card in
                    Button("Inspect \(card.card.name)") { inspect(card) }
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.left.and.right.circle.fill")
                        .font(.system(size: 24)).foregroundStyle(.white, Color.red)
                        .frame(width: 44, height: 44)
                    if members.count > 1 { Text("\(members.count)").font(.caption2.bold()).padding(3).background(.black, in: Circle()) }
                }
            }
            .position(cluster.point)
            .accessibilityLabel("\(members.count) offscreen combat cards. Choose a card to inspect")
            .accessibilityIdentifier("board.combat.offscreen.\(cluster.id)")
        }
    }
}

struct CombatEdgeCluster: Identifiable {
    let id: String
    let point: CGPoint
    let cardIDs: [String]

    static func groups(anchors: [String: CombatViewportAnchor]) -> [CombatEdgeCluster] {
        let clipped = anchors.filter { $0.value.isClipped }
        let groups = Dictionary(grouping: clipped.keys) { id in
            let point = clipped[id]!.point
            return "\(Int(point.x.rounded())):\(Int(point.y.rounded()))"
        }
        return groups.keys.sorted().compactMap { key in
            guard let ids = groups[key]?.sorted(), let first = ids.first, let anchor = clipped[first] else { return nil }
            return CombatEdgeCluster(id: key, point: anchor.point, cardIDs: ids)
        }
    }
}
