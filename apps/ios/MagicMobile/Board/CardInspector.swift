import SwiftUI
import PhotosUI
import UIKit

/// True while a card view shows the drawn placeholder instead of the real card image.
struct CardArtPlaceholderShownKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Held-card inspection. Inspection lasts only while the finger is down, so nothing
/// here can scroll: the printed card carries its own rules, and the panel adds only
/// live state. The rules text appears only when the real image is not showing
/// (placeholder, hidden or token art), and it shrinks to fit instead of clipping.
/// Every permanent visible on the battlefield, so an inspector can show what is attached.
struct InspectorBattlefieldKey: EnvironmentKey { static let defaultValue: [ZoneCard] = [] }

extension EnvironmentValues {
    var inspectorBattlefield: [ZoneCard] {
        get { self[InspectorBattlefieldKey.self] }
        set { self[InspectorBattlefieldKey.self] = newValue }
    }
}

extension GameSnapshot {
    var visibleBattlefield: [ZoneCard] { players.flatMap(\.zones.battlefield) }
}

struct CardInspector: View {
    let card: ZoneCard
    @Environment(\.inspectorBattlefield) private var battlefield
    @Environment(\.holdCardInspection) private var hold
    @State private var artMissing = false
    /// A double-faced card's other face, and whether it is turned up. A held card turns over by itself
    /// after a moment (a finger holding it can't tap); an opened one turns with its Flip button.
    @State private var otherFace: DoubleFacedCards.Face?
    @State private var turned = false

    /// Inspection is held with a finger, so the attachment list reads, never scrolls or taps.
    private var shown: ZoneCard { card }

    /// Auras, Equipment and anything else attached to the shown card, in table order.
    private var attachments: [ZoneCard] {
        battlefield.filter { $0.attachedToInstanceId == shown.instanceId && $0.instanceId != shown.instanceId }
    }

    private var attachedTo: ZoneCard? {
        guard let parent = shown.attachedToInstanceId else { return nil }
        return battlefield.first { $0.instanceId == parent }
    }

    /// Always at least the card's type; then live state on the table.
    private var liveState: [String] {
        let card = shown
        var details: [String] = []
        if card.card.isToken == true {
            details.append(card.card.copySourceArtworkName == nil ? "Token" : "Token copy")
        }
        if !card.card.typeLine.isEmpty { details.append(card.card.typeLine) }
        if card.visibleXmageIcons.contains(where: { $0.iconType == "COMMANDER" }) { details.append("Commander") }
        if card.showsPowerToughness, let power = card.displayPower, let toughness = card.displayToughness {
            details.append("\(power)/\(toughness)")
        }
        if let tapped = card.tapped { details.append(tapped ? "Tapped" : "Untapped") }
        if card.isCreature && card.summoningSickness == true { details.append("Summoning sick") }
        if card.isAttacking == true { details.append("Attacking") }
        if let blocking = card.blocking, !blocking.isEmpty { details.append(blocking.count == 1 ? "Blocking" : "Blocking \(blocking.count)") }
        if let damage = card.damage, damage > 0 { details.append("\(damage) damage") }
        if card.attachedToInstanceId != nil { details.append(attachedTo.map { "Attached to \($0.card.name)" } ?? "Attached") }
        if card.isPhasedOut { details.append("Phased out") }
        details += card.counterBadges.map { "\($0.label) ×\($0.count)" }
        details += card.visibleXmageIcons.compactMap { icon in
            icon.displayText ?? XmageCardIcon.keywordName(for: icon.iconType)
        }
        var seen = Set<String>()
        return details.filter { seen.insert($0.lowercased()).inserted }
    }

    private var showsRules: Bool {
        artMissing || shown.card.isToken == true || !NativeCardArtworkPolicy.permitsLookup(card: shown)
    }

    /// Solid, so the board never shows through the text while you read.
    static let backdrop = Color(red: 0.07, green: 0.08, blue: 0.10)

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize: CGFloat = 13
    @Environment(\.tavernBoard) private var tavern
    @Environment(\.arenaBoard) private var arena

    var body: some View {
        Group {
            if arena { arenaBody } else { tavernBody }
        }
        .onPreferenceChange(CardArtPlaceholderShownKey.self) { artMissing = $0 }
        .task(id: card.card.name) {
            turned = false
            otherFace = nil
            guard NativeCardArtworkPolicy.permitsLookup(card: card), card.card.isToken != true else { return }
            otherFace = await DoubleFacedCards.shared.loadedOtherFace(of: card.card.name)
            guard otherFace != nil else { return }
            // Held: show the other face after a moment, then keep turning while the finger stays down.
            var wait = Duration.milliseconds(1400)
            while !Task.isCancelled {
                do { try await Task.sleep(for: wait) } catch { return }
                guard hold?.isActive == true else { continue }
                turned.toggle()
                wait = .milliseconds(2600)
            }
        }
    }

    /// The Arena board's inspection, the reference's way (docs/ARENA_STYLE.md): the card large with no panel round it,
    /// and beside it (below it in portrait) glass notes: what it is right now, what its keywords mean, its rules when
    /// the picture can't show them, and what is attached to it.
    private var arenaBody: some View {
        let card = shown
        let rules = card.card.oracleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let glossary = ArenaKeywordGlossary.entries(rules: rules)
        let reminder = CardRulesReminder.text(for: card)
        let attached = attachments
        let hasNotes = !liveState.isEmpty || !glossary.isEmpty || (showsRules && !rules.isEmpty) || reminder != nil || !attached.isEmpty
        return GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let ratio = BattlefieldLayoutMetrics.magicCardHeightToWidth
            let notesWidth: CGFloat = landscape ? min(300, max(0, proxy.size.width * 0.45)) : proxy.size.width
            let cardHeight: CGFloat = landscape
                ? min(proxy.size.height, (proxy.size.width - (hasNotes ? notesWidth + 16 : 0)) * ratio)
                : min(proxy.size.height * (hasNotes ? 0.66 : 1), proxy.size.width * ratio)
            let layout = landscape ? AnyLayout(HStackLayout(alignment: .center, spacing: 16)) : AnyLayout(VStackLayout(spacing: 10))
            layout {
                InspectorCardFace(card: card, otherFace: otherFace, turned: turned) { turned.toggle() }
                    .frame(width: cardHeight / ratio, height: cardHeight)
                    .shadow(color: .black.opacity(0.7), radius: 16, y: 8)
                if hasNotes {
                    arenaNotes(card: card, rules: showsRules ? rules : "", glossary: glossary, reminder: reminder, attached: attached,
                               compact: !landscape)
                        .frame(width: notesWidth)
                        .frame(maxHeight: landscape ? cardHeight : proxy.size.height - cardHeight - 10, alignment: .top)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector.arena")
    }

    private func arenaNotes(card: ZoneCard, rules: String, glossary: [(keyword: String, meaning: String)], reminder: String?,
                            attached: [ZoneCard], compact: Bool) -> some View {
        let gold = Color(red: 0.98, green: 0.84, blue: 0.52)
        func note<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .modifier(ArenaGlassPanel(cornerRadius: 10))
        }
        return VStack(alignment: .leading, spacing: 8) {
            if !liveState.isEmpty {
                note {
                    Text(liveState.joined(separator: "  •  "))
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(ArenaGlass.text)
                        .lineLimit(3).minimumScaleFactor(0.8)
                }
            }
            ForEach(Array(glossary.prefix(compact ? 3 : 4).enumerated()), id: \.offset) { _, entry in
                note {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.keyword).font(.system(size: 14, weight: .bold, design: .serif)).foregroundStyle(gold)
                        GameRulesText(source: entry.meaning, symbolSize: 13)
                            .font(.system(size: 13, design: .serif)).foregroundStyle(ArenaGlass.text.opacity(0.9))
                            .lineLimit(3).minimumScaleFactor(0.8)
                    }
                }
            }
            if !rules.isEmpty {
                note {
                    GameRulesText(source: rules, cardName: card.card.name, isHidden: !NativeCardArtworkPolicy.permitsLookup(card: card), symbolSize: 14)
                        .font(.system(size: 14, design: .serif)).foregroundStyle(ArenaGlass.text)
                        .lineLimit(compact ? 5 : 9).minimumScaleFactor(0.75)
                }
            }
            if let reminder {
                note {
                    Text(reminder).font(.system(size: 12, design: .serif).italic()).foregroundStyle(ArenaGlass.text.opacity(0.85))
                        .lineLimit(4).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("inspector.rulesReminder")
                }
            }
            if !attached.isEmpty {
                note {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ATTACHED").font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1).foregroundStyle(gold)
                        Text(attached.map(\.card.name).joined(separator: ", "))
                            .font(.system(size: 13, design: .serif)).foregroundStyle(ArenaGlass.text).lineLimit(2)
                    }
                }
            }
        }
    }

    private var tavernBody: some View {
        let card = shown
        let rules = card.card.oracleText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rulesVisible = showsRules && !rules.isEmpty
        let state = liveState
        let attached = attachments
        let reminder = CardRulesReminder.text(for: card)
        // Rules get their room first; CardInspectorFit shrinks the card, then the text.
        return CardInspectorLayout {
            InspectorCardFace(card: card, otherFace: otherFace, turned: turned) { turned.toggle() }
            if rulesVisible || !state.isEmpty || !attached.isEmpty || reminder != nil {
                ViewThatFits(in: .vertical) {
                    ForEach(CardInspectorFit.textScales, id: \.self) { scale in
                        footer(scale: scale, card: card, rules: rulesVisible ? rules : nil, state: state,
                               reminder: reminder, attached: attached)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(9)
        .modifier(InspectorChrome(tavern: tavern))
    }

    private func footer(scale: CGFloat, card: ZoneCard, rules: String?, state: [String], reminder: String?,
                        attached: [ZoneCard]) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            if !state.isEmpty {
                InspectorStateChips(items: state, scale: scale)
            }
            if let rules {
                GameRulesText(source: rules, cardName: card.card.name,
                              isHidden: !NativeCardArtworkPolicy.permitsLookup(card: card), symbolSize: 16 * scale)
                    .font(.system(size: bodySize * scale)).lineSpacing(3 * scale)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reminder {
                Label(reminder, systemImage: "info.circle")
                    .font(.system(size: footnoteSize * scale, weight: .semibold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.rulesReminder")
            }
            if !attached.isEmpty {
                InspectorAttachmentList(cards: attached, scale: scale)
                    // A thumbnail's missing art must not read as the main card's.
                    .transformPreference(CardArtPlaceholderShownKey.self) { $0 = false }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .foregroundStyle(MagicPalette.parchment)
    }
}

/// The inspected card, as large as its slot allows.
struct InspectorCardFace: View {
    let card: ZoneCard
    var otherFace: DoubleFacedCards.Face? = nil
    var turned = false
    var flip: () -> Void = {}
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        GeometryReader { proxy in
            let height = max(1, min(proxy.size.height, proxy.size.width * BattlefieldLayoutMetrics.magicCardHeightToWidth))
            let width = height / BattlefieldLayoutMetrics.magicCardHeightToWidth
            CardFlipView(flipped: turned && otherFace != nil) {
                CardTile(card: card, selected: false, zoneName: "Inspector", width: width, height: height,
                         ignoreTappedRotation: true, imageVariant: .inspection)
                    .modifier(InspectionFoil(size: CGSize(width: width, height: height)))
                    .id(card.instanceId)
            } back: {
                if let otherFace { otherSide(otherFace, width: width, height: height) }
            }
            .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) { if let otherFace { flipButton(otherFace) } }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    /// The other face is a picture of the card, without the live state the table puts on this one.
    private func otherSide(_ face: DoubleFacedCards.Face, width: CGFloat, height: CGFloat) -> some View {
        NativeCardArtworkView(name: face.name, variant: .inspection, contentMode: .fit) { _, _ in
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.title2)
                Text(face.name).font(.system(size: 17, weight: .bold, design: .serif)).multilineTextAlignment(.center)
                Text(face.isBack ? "Back face" : "Front face").font(.caption)
            }.padding(12).frame(width: width, height: height)
                .foregroundStyle(MagicPalette.parchment)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: width * 0.045))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.045))
        // The other face's missing art must not read as this card's: its rules text would be the wrong face's.
        .transformPreference(CardArtPlaceholderShownKey.self) { $0 = false }
        .accessibilityLabel("\(face.name), \(face.isBack ? "back" : "front") face of \(card.card.name)")
    }

    /// Turns the card over. While a finger holds the card it turns by itself instead.
    private func flipButton(_ face: DoubleFacedCards.Face) -> some View {
        Button(action: flip) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tavern ? AnyShapeStyle(BrandTheme.brassGradient) : AnyShapeStyle(MagicPalette.parchment))
                .frame(width: 38, height: 38)
                .background {
                    if tavern { TavernFill(material: .leather).clipShape(Circle()) }
                    else { Circle().fill(MagicPalette.iron.opacity(0.92)) }
                }
                .overlay(Circle().stroke(tavern ? AnyShapeStyle(BrandTheme.brassGradient) : AnyShapeStyle(MagicPalette.antiqueGold.opacity(0.6)), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel(turned ? "Show \(card.card.name)" : "Turn over to \(face.name)")
        .accessibilityIdentifier("inspector.flip")
    }
}

/// Card above (portrait) or beside (landscape) the footer, sized by CardInspectorFit from the
/// footer's natural height. The footer is then offered all the room left under the card.
struct CardInspectorLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 480))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let face = subviews.first else { return }
        let footer = subviews.count > 1 ? subviews[1] : nil
        let fit = CardInspectorFit.plan(available: bounds.size, cardAspect: BattlefieldLayoutMetrics.magicCardHeightToWidth,
                                        hasFooter: footer != nil) { width in
            footer?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        }
        if fit.horizontal {
            face.place(at: bounds.origin, proposal: ProposedViewSize(fit.cardSize))
            footer?.place(at: CGPoint(x: bounds.minX + fit.cardSize.width + CardInspectorFit.columnSpacing, y: bounds.minY),
                          proposal: ProposedViewSize(width: fit.footerSize.width, height: bounds.height))
        } else {
            face.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(fit.cardSize))
            let top = fit.cardSize.height + CardInspectorFit.spacing
            footer?.place(at: CGPoint(x: bounds.minX, y: bounds.minY + top),
                          proposal: ProposedViewSize(width: bounds.width, height: max(bounds.height - top, 0)))
        }
    }
}

/// What is attached to the inspected card: each Aura or Equipment with its rules text.
struct InspectorAttachmentList: View {
    let cards: [ZoneCard]
    var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var rulesSize: CGFloat = 13

    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text(cards.count == 1 ? "ATTACHED" : "ATTACHED · \(cards.count)")
                .font(.system(size: captionSize * scale, weight: .black, design: tavern ? .serif : .default)).tracking(1.2)
                .foregroundStyle(tavern ? AnyShapeStyle(BrandTheme.brassGradient) : AnyShapeStyle(MagicPalette.antiqueGold))
            ForEach(cards.prefix(4)) { attachment in
                HStack(alignment: .top, spacing: 10 * scale) {
                    CardTile(card: attachment, selected: false, zoneName: "Inspector attachment",
                             width: 40 * scale, height: 40 * scale * BattlefieldLayoutMetrics.magicCardHeightToWidth,
                             ignoreTappedRotation: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.card.name)
                            .font(.system(size: nameSize * scale, weight: .heavy, design: tavern ? .serif : .default))
                            .foregroundStyle(tavern ? TavernPalette.parchment : .white)
                        if !attachment.card.typeLine.isEmpty {
                            Text(attachment.card.typeLine)
                                .font(.system(size: captionSize * scale, weight: .semibold))
                                .foregroundStyle(MagicPalette.parchment.opacity(0.7))
                        }
                        if let text = attachment.card.oracleText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            GameRulesText(source: text, cardName: attachment.card.name,
                                          isHidden: !NativeCardArtworkPolicy.permitsLookup(card: attachment), symbolSize: 16 * scale)
                                .font(.system(size: rulesSize * scale)).lineSpacing(1)
                                .foregroundStyle(MagicPalette.parchment)
                                .lineLimit(4)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(7)
                .background(tavern ? Color.black.opacity(0.24) : MagicPalette.iron.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(tavern ? AnyShapeStyle(TavernPalette.brassLine) : AnyShapeStyle(MagicPalette.antiqueGold.opacity(0.35)), lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("inspector.attachment.\(attachment.instanceId)")
            }
            if cards.count > 4 {
                Text("+\(cards.count - 4) more attached")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.75))
            }
        }
    }
}

/// Short notes for rules players often read differently than the engine applies them.
enum CardRulesReminder {
    static func text(for card: ZoneCard) -> String? {
        let rules = (card.card.oracleText ?? "").lowercased()
        if rules.contains("triggers an additional time") {
            return String(localized: "Only triggered abilities (“when”, “whenever”, “at”) happen again. Effects that say “instead”, like Chatterfang’s extra Squirrels, are not triggers and are not doubled.")
        }
        return nil
    }
}

/// Live card state as compact chips that wrap onto as many lines as they need
/// (Android's FlowRow), so the inspector's fit measures their real height.
struct InspectorStateChips: View {
    let items: [String]
    var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 15
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        InspectorChipFlow(spacing: 6 * scale) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if tavern && TavernUIKit.available {
                    // Parchment tags in a thin brass rim.
                    Text(item)
                        .font(.system(size: chipSize * scale, weight: .semibold, design: .serif))
                        .foregroundStyle(TavernPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 11 * scale).padding(.vertical, 4 * scale)
                        .background { TavernFill(material: .parchment).clipShape(Capsule()) }
                        .overlay { Capsule().strokeBorder(TavernPalette.brassLine, lineWidth: 1.4) }
                } else {
                    Text(item)
                        .font(.system(size: chipSize * scale, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8 * scale).padding(.vertical, 3 * scale)
                        .background(MagicPalette.iron.opacity(0.9), in: Capsule())
                        .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.55), lineWidth: 1))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Left-to-right rows that wrap at the proposed width.
struct InspectorChipFlow: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if !rows[rows.count - 1].isEmpty && x + spacing + size.width > width {
                rows.append([])
                x = 0
            }
            x += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].append((index, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        // Explicit CGFloat types keep these closures cheap to type-check on older Xcode.
        let heights: [CGFloat] = rows.map { row in row.map { $0.size.height }.max() ?? 0 }
        let widths: [CGFloat] = rows.map { row in
            let cards: CGFloat = row.reduce(CGFloat(0)) { $0 + $1.size.width }
            return cards + spacing * CGFloat(max(row.count - 1, 0))
        }
        let height: CGFloat = heights.reduce(CGFloat(0), +) + spacing * CGFloat(max(rows.count - 1, 0))
        let used: CGFloat = widths.max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += height + spacing
        }
    }
}

/// The inspector's backing: solid charcoal, or on the tavern board leather in brass trim.
private struct InspectorChrome: ViewModifier {
    let tavern: Bool

    func body(content: Content) -> some View {
        if tavern && TavernUIKit.available {
            content.modifier(TavernPanelChrome(tavern: true, cornerRadius: 12))
        } else {
            content
                .background(CardInspector.backdrop, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.cyan.opacity(0.35)))
        }
    }
}
