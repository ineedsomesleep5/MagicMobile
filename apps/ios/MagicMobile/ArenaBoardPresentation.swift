import SwiftUI

/// Changes are visual feedback only; life always comes from the current snapshot.
struct BoardLifeTotal: View {
    let life: Int
    var suffix = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var delta = 0
    @State private var changeToken = UUID()

    var body: some View {
        Text("\(life)\(suffix)")
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(life)))
            .foregroundStyle(delta == 0 ? MagicPalette.antiqueGold : delta < 0 ? Color.red : Color.green)
            .scaleEffect(delta == 0 || reduceMotion ? 1 : 1.16)
            .overlay(alignment: .topTrailing) {
                if delta != 0 {
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
        let ratio = max(ratio, 1)
        rows = count > 5 && height >= 2 * 44 * ratio + 20 ? 2 : 1
        columns = max(1, (count + rows - 1) / rows)
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
        targetable ? .red : selected ? MagicPalette.antiqueGold : legal ? MagicPalette.legalEmerald : .white.opacity(0.35)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(card.card.name)
                .font(.system(size: max(8, width * 0.115), weight: .semibold, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 3)
                .frame(height: 15)
            ZStack(alignment: .top) {
                CardTile(card: card, selected: false, zoneName: zoneName,
                         width: width * 1.08, height: width * 1.51, ignoreTappedRotation: true)
                    .offset(y: -width * 0.19)
                    .allowsHitTesting(false).accessibilityIdentifier("").accessibilityHidden(true)
            }
            .frame(width: width, height: max(12, height - 35), alignment: .top).clipped()
            HStack(spacing: 2) {
                if card.tapped == true {
                    Image(systemName: "arrow.turn.down.right").accessibilityLabel("Tapped")
                } else if card.isCreature && card.summoningSickness == true {
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
        .foregroundStyle(.white)
        .frame(width: width, height: height)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            XmageCardIconStrip(icons: card.visibleXmageIcons, cardWidth: width)
                .padding(.leading, 2).allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if !card.counterBadges.isEmpty {
                CardCounterBadgeStrip(badges: Array(card.counterBadges.prefix(2)), cardWidth: width)
                    .padding(.top, 16).allowsHitTesting(false)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(accent, lineWidth: legal || targetable || selected ? 2 : 1))
        .saturation(card.tapped == true ? 0.15 : 1)
        .brightness(card.tapped == true ? -0.16 : 0)
        .rotationEffect(.degrees(card.tapped == true ? -7 : 0))
        .shadow(color: accent.opacity(legal || targetable ? 0.45 : 0.1), radius: 5)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: card.tapped)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel(zoneName: zoneName, selected: selected, legal: legal))
        .accessibilityValue(card.visibleXmageIcons.compactMap(\.displayText).joined(separator: ", "))
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
    static func laneIndices(human: [ZoneCard], opponent: [ZoneCard]) -> [String: Int] {
        var result: [String: Int] = [:]
        for card in opponent { result[card.instanceId] = card.card.isLand ? 1 : 0 }
        for card in human { result[card.instanceId] = card.card.isLand ? 3 : 2 }
        return result
    }

    static func resolve(bounds: [String: CGRect], authorizedIDs: Set<String>, viewports: [CGRect], laneIndices: [String: Int] = [:]) -> [String: CombatViewportAnchor] {
        var result: [String: CombatViewportAnchor] = [:]
        for (id, rect) in bounds where authorizedIDs.contains(id) && !rect.isEmpty && !rect.isInfinite && !rect.isNull {
            // Ownership must survive horizontal scrolling and side-by-side lanes.
            // Geometry alone cannot distinguish an offscreen creature from an animated land.
            guard let index = laneIndices[id] ?? (viewports.count == 1 ? 0 : nil), viewports.indices.contains(index) else { continue }
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
