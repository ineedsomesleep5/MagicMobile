import CoreGraphics
import Foundation

// Pure presentation rules for board cards, shared with Android's core
// game/BoardCardPresentation.kt: the token copy frame, the held-card inspector's
// fit, and the showcase banner. Views live in ContentView.swift and BoardFXOverlay.swift.

/// A token that copies a visible card. It is drawn as its own card frame (name, type
/// line and live power/toughness) around the source card's illustration, never as the
/// printed source card, whose name or stats can differ from the token's.
enum TokenCopyPresentation {
    /// Below this width the tag cannot name the source legibly.
    static let namedTagMinimumWidth: CGFloat = 120

    /// The copied card's name, only for a face-up token the engine explicitly marked as a copy.
    static func sourceName(isToken: Bool?, copySourceArtworkName: String?) -> String? {
        guard isToken == true else { return nil }
        let source = copySourceArtworkName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return source.isEmpty ? nil : source
    }

    static func tag(source: String, cardWidth: CGFloat) -> String {
        cardWidth >= namedTagMinimumWidth ? "Token copy · \(source)" : "Token copy"
    }
}

extension ZoneCard {
    /// Non-nil when this card renders as a token copy frame.
    var tokenCopySourceName: String? {
        TokenCopyPresentation.sourceName(isToken: card.isToken, copySourceArtworkName: card.copySourceArtworkName)
    }
}

/// Regions of the token copy frame, in the card's own coordinates. Proportions follow a
/// printed card, so the compact battlefield face (which crops the tile to its art) still
/// shows the illustration.
struct TokenCopyFrameLayout: Equatable {
    let size: CGSize
    /// Room the tag leaves free at the frame's trailing edge, for badges drawn over it.
    let tagTrailingReserve: CGFloat

    init(size: CGSize, tagTrailingReserve: CGFloat = 0) {
        self.size = size
        self.tagTrailingReserve = max(0, tagTrailingReserve)
    }

    var border: CGFloat { max(size.width * 0.045, 2) }
    private var gap: CGFloat { max(size.height * 0.012, 1) }

    var nameBar: CGRect {
        CGRect(x: border, y: border, width: size.width - border * 2, height: max(size.height * 0.085, 8))
    }

    var art: CGRect {
        let top = nameBar.maxY + gap
        return CGRect(x: border, y: top, width: size.width - border * 2, height: max(size.height * 0.555 - top, 1))
    }

    var typeBar: CGRect {
        CGRect(x: border, y: art.maxY + gap, width: size.width - border * 2, height: max(size.height * 0.07, 7))
    }

    var textBox: CGRect {
        let top = typeBar.maxY + gap
        return CGRect(x: border, y: top, width: size.width - border * 2, height: max(size.height - border - top, 1))
    }

    /// Bottom-right, over the text box's corner like a printed P/T box.
    var powerToughnessBox: CGRect {
        let width = max(size.width * 0.27, 16), height = max(size.height * 0.075, 8)
        return CGRect(x: size.width - border - width, y: size.height - border - height, width: width, height: height)
    }

    /// Rules text area: the text box above the P/T box.
    func rulesArea(showsPowerToughness: Bool) -> CGRect {
        var area = textBox.insetBy(dx: max(size.width * 0.03, 1.5), dy: max(size.height * 0.01, 1))
        if showsPowerToughness { area.size.height = max(powerToughnessBox.minY - area.minY - gap, 1) }
        return area
    }

    /// Where the token copy tag sits: the art's top-leading corner, which the compact
    /// battlefield face (ArenaBattlefieldCard) keeps in view just under its name header.
    /// The art's bottom edge falls behind that face's P/T footer. The tag ends before
    /// `tagTrailingReserve`; its text shrinks, then truncates, to fit.
    var tagSlot: CGRect {
        let height = max(size.height * 0.06, 9)
        let inset = max(size.width * 0.04, 2)
        let minX = art.minX + inset
        let width = min(art.width - inset * 2, size.width - tagTrailingReserve - minX)
        return CGRect(x: minX, y: art.minY + inset * 0.6, width: max(width, 1), height: height)
    }

    var nameFontSize: CGFloat { max(size.width * 0.085, 6) }
    var typeFontSize: CGFloat { max(size.width * 0.062, 5) }
    var rulesFontSize: CGFloat { max(size.width * 0.052, 4) }
    var powerToughnessFontSize: CGFloat { max(size.width * 0.085, 6) }
    var tagFontSize: CGFloat { max(tagSlot.height * 0.52, 4.5) }
    /// Rules are drawn only where they could be read.
    var showsRules: Bool { size.width >= 60 }

    /// Whole rules lines that fit the text box; the rest is truncated, as on a printed card
    /// too small to read. The inspector shows the full text beside the card.
    func rulesLineLimit(showsPowerToughness: Bool) -> Int {
        max(1, Int(rulesArea(showsPowerToughness: showsPowerToughness).height / (rulesFontSize * 1.25)))
    }
}

/// The compact battlefield face (ArenaBattlefieldCard): a name header over a CardTile cropped to
/// its art, with counter badges in a trailing column just under the header. A token copy's tag
/// sits in that same band, so while counters show, the tag ends before their column.
enum BattlefieldCardFaceLayout {
    static let headerHeight: CGFloat = 15
    /// Top of the counter badge column, just under the header.
    static let counterTop: CGFloat = 16
    /// Clear space between the tag's end and the counter column.
    static let counterGap: CGFloat = 2

    /// The CardTile the face shows, in the face's coordinates: 8% wider and centered, lifted so
    /// its art starts under the header.
    static func tileFrame(cardWidth: CGFloat) -> CGRect {
        CGRect(x: -cardWidth * 0.04, y: headerHeight - cardWidth * 0.19, width: cardWidth * 1.08, height: cardWidth * 1.51)
    }

    /// The counter badges are capped to this width at the face's trailing edge.
    static func counterColumnWidth(cardWidth: CGFloat) -> CGFloat { max(28, cardWidth * 0.36) }

    /// What the tile's token copy tag leaves free at its trailing edge (tile coordinates).
    static func tagTrailingReserve(cardWidth: CGFloat, showsCounters: Bool) -> CGFloat {
        guard showsCounters else { return 0 }
        let columnStart = cardWidth - counterColumnWidth(cardWidth: cardWidth) - counterGap
        return max(0, tileFrame(cardWidth: cardWidth).maxX - columnStart)
    }

    /// The token copy tag's slot in the face's coordinates.
    static func tokenCopyTagSlot(cardWidth: CGFloat, showsCounters: Bool) -> CGRect {
        let tile = tileFrame(cardWidth: cardWidth)
        let frame = TokenCopyFrameLayout(size: tile.size,
                                         tagTrailingReserve: tagTrailingReserve(cardWidth: cardWidth, showsCounters: showsCounters))
        return frame.tagSlot.offsetBy(dx: tile.minX, dy: tile.minY)
    }
}

/// Where to draw a whole printed card image so only its illustration window fills a box.
/// The window is NativeDeckArtwork.illustrationImage's crop; used where the image is not
/// already cropped (AsyncImage in design previews and hosted games).
enum CardIllustrationCrop {
    static let window = CGRect(x: 0.08, y: 0.145, width: 0.84, height: 0.385)
    /// Scryfall card images are 488 × 680.
    static let printedImageAspect: CGFloat = 680.0 / 488.0

    static func imageFrame(filling box: CGSize, imageAspect: CGFloat = printedImageAspect) -> CGRect {
        let width = max(box.width / window.width, box.height / (window.height * imageAspect))
        let height = width * imageAspect
        return CGRect(x: -window.minX * width - (window.width * width - box.width) / 2,
                      y: -window.minY * height - (window.height * height - box.height) / 2,
                      width: width, height: height)
    }
}

/// Held-card inspection cannot scroll (the finger is down), so the rules text gets the
/// room it needs first and the card image shrinks instead, down to a floor. Text shrinks
/// only when even the smallest card leaves too little room.
struct CardInspectorFit: Equatable {
    var cardSize: CGSize
    /// `.zero` when there is nothing to show beside the card.
    var footerSize: CGSize
    var horizontal: Bool
    /// The footer's natural height fits its room at full text size.
    var footerFits: Bool

    static let spacing: CGFloat = 8
    static let columnSpacing: CGFloat = 16
    /// Portrait: the card keeps at least this share of the height.
    static let minimumCardFraction: CGFloat = 0.34
    /// Landscape: the card column is at most this share of the width.
    static let landscapeCardFraction: CGFloat = 0.55
    /// Landscape: card sizes to try (shares of the largest card), largest first.
    static let landscapeCardScales: [CGFloat] = [1, 0.86, 0.74, 0.64]
    /// Text sizes to try when the footer still does not fit, largest first.
    static let textScales: [CGFloat] = [1, 0.9, 0.8, 0.7, 0.6]

    /// `footerHeight(width)` is the footer's natural height at full text size for a width.
    static func plan(available: CGSize, cardAspect: CGFloat = 88.0 / 63.0, hasFooter: Bool,
                     footerHeight: (CGFloat) -> CGFloat) -> CardInspectorFit {
        let width = max(available.width, 1), height = max(available.height, 1)
        if width > height {
            let largestCard = min(width * landscapeCardFraction, height / cardAspect)
            guard hasFooter else {
                return CardInspectorFit(cardSize: CGSize(width: largestCard, height: largestCard * cardAspect),
                                        footerSize: .zero, horizontal: true, footerFits: true)
            }
            var chosen: (card: CGFloat, footer: CGFloat, needed: CGFloat)?
            for scale in landscapeCardScales {
                let cardWidth = largestCard * scale
                let footerWidth = max(width - cardWidth - columnSpacing, 1)
                let needed = footerHeight(footerWidth)
                chosen = (cardWidth, footerWidth, needed)
                if needed <= height { break }
            }
            let result = chosen!
            return CardInspectorFit(cardSize: CGSize(width: result.card, height: result.card * cardAspect),
                                    footerSize: CGSize(width: result.footer, height: min(result.needed, height)),
                                    horizontal: true, footerFits: result.needed <= height)
        }
        guard hasFooter else {
            let cardHeight = min(height, width * cardAspect)
            return CardInspectorFit(cardSize: CGSize(width: cardHeight / cardAspect, height: cardHeight),
                                    footerSize: .zero, horizontal: false, footerFits: true)
        }
        let needed = footerHeight(width)
        let room = max(height - spacing, 1)
        let maximumCard = min(width * cardAspect, room)
        let minimumCard = min(maximumCard, height * minimumCardFraction)
        let cardHeight = max(minimumCard, min(maximumCard, room - needed))
        let footerRoom = max(room - cardHeight, 0)
        return CardInspectorFit(cardSize: CGSize(width: cardHeight / cardAspect, height: cardHeight),
                                footerSize: CGSize(width: width, height: min(needed, footerRoom)),
                                horizontal: false, footerFits: needed <= footerRoom)
    }

    /// The largest text scale whose footer fits `height`; the smallest when none does.
    static func textScale(fitting height: CGFloat, heightAtScale: (CGFloat) -> CGFloat) -> CGFloat {
        textScales.first { heightAtScale($0) <= height } ?? textScales[textScales.count - 1]
    }
}

/// The name banner under a showcased stack object.
enum BoardFXBannerPlan {
    /// Reduced effects draw no card, so the banner sits just under the stack point.
    static let reducedOffset: CGFloat = 54

    /// Distance from the stack point to the banner's center. With motion the banner sits
    /// below the showcased card, abilities included.
    static func offset(showcaseHeight: CGFloat, motion: Bool) -> CGFloat {
        motion ? showcaseHeight / 2 + 22 : reducedOffset
    }

    /// Abilities read as "<source> · ability"; spells keep their own name.
    static func title(name: String, isAbility: Bool, sourceName: String?) -> String {
        guard isAbility else { return name }
        let source = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !source.isEmpty { return "\(source) · ability" }
        return name.localizedCaseInsensitiveContains("ability") ? name : "\(name) · ability"
    }
}

/// Combat keywords a battlefield card shows while it attacks or blocks. They come from the
/// permanent's current engine view: XMage's keyword icons and bare keyword rules lines are
/// built from the permanent's live abilities, so keywords gained from other effects (Atarka
/// giving an attacking Dragon double strike) are included. The view carries no printed/gained
/// provenance, so a gained keyword looks the same as a printed one. Case order is badge priority.
enum CombatKeyword: String, CaseIterable, Equatable, Hashable {
    case doubleStrike, firstStrike, deathtouch, trample, lifelink, indestructible, menace, flying, reach, vigilance

    var label: String {
        switch self {
        case .doubleStrike: return "Double strike"
        case .firstStrike: return "First strike"
        case .deathtouch: return "Deathtouch"
        case .trample: return "Trample"
        case .lifelink: return "Lifelink"
        case .indestructible: return "Indestructible"
        case .menace: return "Menace"
        case .flying: return "Flying"
        case .reach: return "Reach"
        case .vigilance: return "Vigilance"
        }
    }

    /// For narrow cards.
    var shortLabel: String {
        switch self {
        case .doubleStrike: return "2× strike"
        case .firstStrike: return "1st strike"
        case .indestructible: return "Indestr."
        default: return label
        }
    }

    var iconType: String {
        switch self {
        case .doubleStrike: return "ABILITY_DOUBLE_STRIKE"
        case .firstStrike: return "ABILITY_FIRST_STRIKE"
        case .deathtouch: return "ABILITY_DEATHTOUCH"
        case .trample: return "ABILITY_TRAMPLE"
        case .lifelink: return "ABILITY_LIFELINK"
        case .indestructible: return "ABILITY_INDESTRUCTIBLE"
        case .menace: return "ABILITY_MENACE"
        case .flying: return "ABILITY_FLYING"
        case .reach: return "ABILITY_REACH"
        case .vigilance: return "ABILITY_VIGILANCE"
        }
    }

    /// Deals combat damage in the first-strike damage step.
    static func strikesFirst(_ keywords: Set<CombatKeyword>) -> Bool {
        keywords.contains(.firstStrike) || keywords.contains(.doubleStrike)
    }

    /// Deals combat damage in the regular damage step (no first strike, or double strike).
    static func strikesInRegularStep(_ keywords: Set<CombatKeyword>) -> Bool {
        !keywords.contains(.firstStrike) || keywords.contains(.doubleStrike)
    }

    private static let byIcon = Dictionary(uniqueKeysWithValues: allCases.map { ($0.iconType, $0) })
    private static let byWord = Dictionary(uniqueKeysWithValues: allCases.map { ($0.label.lowercased(), $0) })
    private static let markup = try! NSRegularExpression(pattern: #"<[^>]*>"#)
    private static let reminder = try! NSRegularExpression(pattern: #"\([^)]*\)"#)

    /// Keywords from engine icons and from rules lines made only of keywords ("Double strike",
    /// "Flying, trample", "Menace <i>(reminder)</i>"). Sentences that merely mention a keyword
    /// ("Creatures you control have flying") never count. Badge order, no duplicates.
    static func of(icons: [XmageCardIcon]?, rules: String?) -> [CombatKeyword] {
        var found = Set<CombatKeyword>()
        for icon in icons ?? [] {
            if let keyword = byIcon[icon.iconType.uppercased()] { found.insert(keyword) }
        }
        for rawLine in (rules ?? "").split(whereSeparator: \.isNewline) {
            var line = String(rawLine)
            for pattern in [markup, reminder] {
                line = pattern.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length), withTemplate: "")
            }
            line = line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
            guard !line.isEmpty else { continue }
            let words = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let keywords = words.compactMap { byWord[$0] }
            guard keywords.count == words.count else { continue }
            found.formUnion(keywords)
        }
        return allCases.filter(found.contains)
    }
}

extension ZoneCard {
    /// Attacking or blocking in the public combat groups.
    var isInCombat: Bool { isAttacking == true || !(blocking ?? []).isEmpty }

    var combatKeywords: [CombatKeyword] { CombatKeyword.of(icons: cardIcons, rules: card.oracleText) }
}

/// Which combat keyword badges fit on a battlefield card that is attacking or blocking.
/// Double strike already says first strike, so first strike is not repeated beside it.
struct CombatKeywordBadgePlan: Equatable {
    let visible: [CombatKeyword]
    /// Keywords that do not fit; they keep their icon in the card's ability row.
    let hiddenCount: Int
    /// Narrow cards use short labels ("2× strike").
    let compact: Bool

    static let compactWidth: CGFloat = 66

    init(keywords: [CombatKeyword], cardWidth: CGFloat, cardHeight: CGFloat) {
        let shown = keywords.contains(.doubleStrike) ? keywords.filter { $0 != .firstStrike } : keywords
        let row = Self.fontSize(cardWidth: cardWidth) + 7
        // Room between the name header and the footer with its icon row.
        let slots = max(1, min(3, Int((cardHeight - 56) / row)))
        visible = Array(shown.prefix(slots))
        hiddenCount = shown.count - visible.count
        compact = cardWidth < Self.compactWidth
    }

    func label(_ keyword: CombatKeyword) -> String { compact ? keyword.shortLabel : keyword.label }

    static func fontSize(cardWidth: CGFloat) -> CGFloat { min(9, max(6.5, cardWidth * 0.1)) }
}
