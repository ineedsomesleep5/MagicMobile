import SwiftUI
import PhotosUI
import UIKit

struct CombatSubmitPill: View {
    let title: String
    let count: Int
    let submit: () -> Void

    var body: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .black))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black))
                Text("\(count)")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.28), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(MagicPalette.oxblood.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(MagicPalette.antiqueGold.opacity(0.45), lineWidth: 1.2))
            .shadow(color: MagicPalette.oxblood.opacity(0.42), radius: 10)
        }
        .buttonStyle(.plain)
    }
}

struct CombatHighlightSet {
    let cardIds: Set<String>
    let defenderIds: Set<String>

    init(selection: CombatSelectionState, actions: [LegalAction], combatGroups: [XmageCombatGroup]) {
        var cards = Set<String>()
        cards.formUnion(selection.attackerHighlightIds(actions: actions))
        cards.formUnion(selection.blockerHighlightIds(actions: actions))
        cards.formUnion(selection.attackingCreatureHighlightIds(actions: actions, combatGroups: combatGroups))
        cards.formUnion(selection.selectedAttackerIds)
        if let blocker = selection.selectedBlockerId {
            cards.insert(blocker)
        }
        let defenders = selection.defenderHighlightIds(actions: actions)
        cards.formUnion(defenders)
        self.cardIds = cards
        self.defenderIds = defenders
    }

    func matches(card: ZoneCard) -> Bool {
        CombatSelectionState.matchingCardId(for: card, in: cardIds) != nil
    }

    func matches(id: String) -> Bool {
        cardIds.contains(id) || defenderIds.contains(id)
    }
}

struct CombatSelectionState: Equatable {
    var selectedAttackerIds: Set<String> = []
    var selectedBlockerId: String?
    private(set) var blockerPairs: [BlockDeclaration] = []

    var hasPendingBlockers: Bool { !blockerPairs.isEmpty }
    var blockerPairCount: Int { blockerPairs.count }
    var selectedAttackerId: String? { selectedAttackerIds.count == 1 ? selectedAttackerIds.first : nil }

    static func matchingCardId(for card: ZoneCard, in ids: Set<String>) -> String? {
        if ids.contains(card.instanceId) {
            return card.instanceId
        }
        if ids.contains(card.id) {
            return card.id
        }
        return nil
    }

    mutating func toggleAttacker(_ id: String) {
        if selectedAttackerIds.contains(id) {
            selectedAttackerIds.remove(id)
        } else {
            selectedAttackerIds.insert(id)
        }
    }

    mutating func selectAttacker(_ id: String) {
        selectedAttackerIds = [id]
    }

    mutating func selectBlocker(_ id: String) {
        selectedBlockerId = id
    }

    mutating func pairSelectedBlocker(withAttackerId attackerId: String) {
        guard let blockerId = selectedBlockerId else { return }
        let pair = BlockDeclaration(blockerId: blockerId, attackerId: attackerId)
        if !blockerPairs.contains(pair) {
            blockerPairs.append(pair)
        }
        selectedBlockerId = nil
    }

    mutating func clearAttackers() {
        selectedAttackerIds.removeAll()
    }

    mutating func clearBlockers() {
        selectedBlockerId = nil
        blockerPairs.removeAll()
    }

    mutating func resetIfInactive(_ snapshot: GameSnapshot) {
        if !Self.isDeclareAttackers(snapshot) {
            clearAttackers()
        }
        if !Self.isDeclareBlockers(snapshot) {
            clearBlockers()
        }
    }

    func attackerHighlightIds(actions: [LegalAction]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_attackers" }
            .flatMap { Self.attackers(in: $0).map(\.attackerId) })
        ids.formUnion(actions
            .filter { $0.type == "declare_attackers" }
            .compactMap { $0.effectiveCardInstanceId ?? $0.effectiveSourceInstanceId })
        return ids
    }

    func defenderHighlightIds(actions: [LegalAction]) -> Set<String> {
        Set(actions
            .filter { $0.type == "declare_attackers" }
            .flatMap { action in
                var ids = Self.attackers(in: action).compactMap(\.defenderId)
                ids.append(contentsOf: action.validTargetIds ?? [])
                ids.append(contentsOf: action.validPlayerIds ?? [])
                ids.append(contentsOf: action.playerIds ?? [])
                ids.append(contentsOf: action.targetIds ?? [])
                return ids
            })
    }

    func defenderIds(forAttackerId attackerId: String, actions: [LegalAction]) -> Set<String> {
        Set(actions
            .filter { $0.type == "declare_attackers" }
            .flatMap { action -> [String] in
                let attackerIds = Set(Self.attackers(in: action).map(\.attackerId))
                let actionCardId = action.effectiveCardInstanceId ?? action.effectiveSourceInstanceId
                guard attackerIds.contains(attackerId) || actionCardId == attackerId else { return [] }
                var ids = Self.attackers(in: action).compactMap(\.defenderId)
                ids.append(contentsOf: action.validTargetIds ?? [])
                ids.append(contentsOf: action.validPlayerIds ?? [])
                ids.append(contentsOf: action.playerIds ?? [])
                ids.append(contentsOf: action.targetIds ?? [])
                return ids
            })
    }

    func defenderKind(forDefenderId defenderId: String, actions: [LegalAction]) -> String? {
        actions.first { action in
            action.type == "declare_attackers" &&
                Self.attackers(in: action).contains { $0.defenderId == defenderId }
        }?.defenderKind
    }

    func blockerHighlightIds(actions: [LegalAction]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_blockers" }
            .flatMap { Self.blockers(in: $0).map(\.blockerId) })
        ids.formUnion(actions
            .filter { $0.type == "declare_blockers" }
            .compactMap { $0.effectiveCardInstanceId ?? $0.effectiveSourceInstanceId })
        return ids
    }

    func attackingCreatureHighlightIds(actions: [LegalAction], combatGroups: [XmageCombatGroup]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_blockers" }
            .flatMap { Self.blockers(in: $0).compactMap(\.attackerId) })
        ids.formUnion(combatGroups.flatMap { $0.attackers.map(\.instanceId) })
        return ids
    }

    func attackingCreatureIds(forBlockerId blockerId: String, actions: [LegalAction], combatGroups: [XmageCombatGroup]) -> Set<String> {
        var ids = Set(actions
            .filter { $0.type == "declare_blockers" }
            .flatMap { action in
                Self.blockers(in: action)
                    .filter { $0.blockerId == blockerId }
                    .compactMap(\.attackerId)
            })
        if ids.isEmpty {
            ids.formUnion(combatGroups.flatMap { $0.attackers.map(\.instanceId) })
        }
        return ids
    }

    func attackAction(forDefenderId defenderId: String, actions: [LegalAction]) -> LegalAction? {
        guard selectedAttackerIds.count == 1, let attackerId = selectedAttackerIds.first else { return nil }
        return actions.first { action in
            guard action.type == "declare_attackers" else { return false }
            return Self.attackers(in: action).contains { $0.attackerId == attackerId && $0.defenderId == defenderId }
        }
    }

    func attackCommand(gameId: String, playerId: String, defenderId: String, actions: [LegalAction], expectedBridgeRevision: Int?) -> GameCommand? {
        let legalAttackers = attackerHighlightIds(actions: actions)
        guard !selectedAttackerIds.isEmpty, selectedAttackerIds.isSubset(of: legalAttackers) else { return nil }
        return GameCommand(
            type: "declare_attackers",
            gameId: gameId,
            playerId: playerId,
            attackers: selectedAttackerIds.sorted().map { AttackDeclaration(attackerId: $0, defenderId: defenderId) },
            combatComplete: false,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    func pendingBlockActionPayload(playerId: String, gameId: String, expectedBridgeRevision: Int? = nil) -> GameCommand? {
        guard !blockerPairs.isEmpty else { return nil }
        return GameCommand(
            type: "declare_blockers",
            gameId: gameId,
            playerId: playerId,
            blockers: blockerPairs,
            combatComplete: false,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    static func finishAttackCommand(gameId: String, playerId: String, expectedBridgeRevision: Int?) -> GameCommand {
        GameCommand(
            type: "declare_attackers",
            gameId: gameId,
            playerId: playerId,
            attackers: [],
            combatComplete: true,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    static func finishBlockCommand(gameId: String, playerId: String, expectedBridgeRevision: Int?) -> GameCommand {
        GameCommand(
            type: "declare_blockers",
            gameId: gameId,
            playerId: playerId,
            blockers: [],
            combatComplete: true,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    static func isDeclareAttackers(_ snapshot: GameSnapshot) -> Bool {
        snapshot.legalActions?.contains(where: { $0.type == "declare_attackers" }) == true
    }

    static func isDeclareBlockers(_ snapshot: GameSnapshot) -> Bool {
        snapshot.legalActions?.contains(where: { $0.type == "declare_blockers" }) == true
    }

    private static func attackers(in action: LegalAction) -> [AttackDeclaration] {
        if let attackers = action.attackers, !attackers.isEmpty {
            return attackers
        }
        guard case .array(let values)? = action.commandTemplate?["attackers"] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value,
                  let attackerId = object["attackerId"]?.stringValue
            else { return nil }
            return AttackDeclaration(attackerId: attackerId, defenderId: object["defenderId"]?.stringValue)
        }
    }

    private static func blockers(in action: LegalAction) -> [BlockDeclaration] {
        if let blockers = action.blockers, !blockers.isEmpty {
            return blockers
        }
        guard case .array(let values)? = action.commandTemplate?["blockers"] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value,
                  let blockerId = object["blockerId"]?.stringValue
            else { return nil }
            return BlockDeclaration(blockerId: blockerId, attackerId: object["attackerId"]?.stringValue)
        }
    }
}

enum CombatArrowKind: Equatable {
    case attack
    case blockedAttack
    case block
    case previewAttack
    case previewBlock
}

struct CombatArrow: Equatable {
    let kind: CombatArrowKind
    let fromId: String
    let toId: String
    let toKind: String?
}

enum CombatArrowModel {
    static func arrows(from groups: [XmageCombatGroup]) -> [CombatArrow] {
        groups.flatMap { group in
            let attackKind: CombatArrowKind = group.blocked ? .blockedAttack : .attack
            let attacks = group.attackers.map {
                CombatArrow(kind: attackKind, fromId: $0.instanceId, toId: group.defenderId, toKind: group.defenderKind)
            }
            let blocks = group.blockers.flatMap { blocker in
                group.attackers.map { attacker in
                    CombatArrow(kind: .block, fromId: blocker.instanceId, toId: attacker.instanceId, toKind: nil)
                }
            }
            return attacks + blocks
        }
    }

    static func arrows(from groups: [XmageCombatGroup], previewArrows: [CombatArrow]) -> [CombatArrow] {
        arrows(from: groups) + previewArrows
    }
}

struct CombatArrowOverlay: View {
    let snapshot: GameSnapshot
    let groups: [XmageCombatGroup]
    let previewArrows: [CombatArrow]
    let metrics: BattlefieldLayoutMetrics
    let humanBattlefield: [ZoneCard]
    let opponentBattlefield: [ZoneCard]
    var renderedBounds: [String: CGRect] = [:]

    var body: some View {
        let anchors = cardAnchors()
        Canvas { context, _ in
            for arrow in CombatArrowModel.arrows(from: groups, previewArrows: previewArrows) {
                guard let start = anchors[arrow.fromId] else { continue }
                guard let end = anchors[arrow.toId] ?? defenderAnchor(for: arrow.toId, kind: arrow.toKind) else { continue }
                drawArrow(arrow, from: start, to: end, in: &context)
            }
        }
    }

    private func cardAnchors() -> [String: CGPoint] {
        CombatViewportAnchors.resolve(bounds: renderedBounds,
            authorizedIDs: Set((humanBattlefield + opponentBattlefield).map(\.instanceId)),
            viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect,
                        metrics.playerBattlefieldRect, metrics.playerLandsRect],
            laneIndices: CombatViewportAnchors.laneIndices(human: humanBattlefield, opponent: opponentBattlefield)).mapValues(\.point)
    }

    private func defenderAnchor(for defenderId: String, kind: String?) -> CGPoint? {
        CombatPlayerIdentity.defenderAnchor(for: defenderId, kind: kind, metrics: metrics, snapshot: snapshot)
    }

    private func drawArrow(_ arrow: CombatArrow, from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let color: Color
        switch arrow.kind {
        case .attack:
            color = MagicPalette.oxblood
        case .blockedAttack:
            color = .gray
        case .block:
            color = MagicPalette.arcaneBlue
        case .previewAttack:
            color = MagicPalette.warningAmber
        case .previewBlock:
            color = MagicPalette.arcaneBlue
        }
        let isPreview = arrow.kind == .previewAttack || arrow.kind == .previewBlock
        context.stroke(path, with: .color(color.opacity(isPreview ? 0.48 : 0.82)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round, dash: isPreview ? [6, 5] : []))

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 9
        let left = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
        var head = Path()
        head.move(to: end)
        head.addLine(to: left)
        head.move(to: end)
        head.addLine(to: right)
        context.stroke(head, with: .color(color.opacity(isPreview ? 0.56 : 0.92)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round))
    }

    private func nonLandCards(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { !$0.card.isLand }
    }

    private func landCards(_ cards: [ZoneCard]) -> [ZoneCard] {
        cards.filter { $0.card.isLand }
    }
}

enum GameBoardMotion {
    static func largeText(_ preference: DynamicTypeSize) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"] == "large-text" { return true }
        #endif
        return preference.isAccessibilitySize
    }

    static func reduced(_ systemPreference: Bool) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"] == "large-text" { return true }
        #endif
        return systemPreference
    }
}

struct PortraitCardBoundsKey: PreferenceKey {
    // Resolve anchors in the current board layout, never a stored rectangle from
    // the previous orientation or a delayed preference callback.
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum VisibleCombatAnchors {
    static func resolve(bounds: [String: CGRect], authorizedIDs: Set<String>, viewports: [CGRect]) -> [String: CGPoint] {
        bounds.filter { id, rect in
            authorizedIDs.contains(id) && !rect.isEmpty && viewports.contains { $0.contains(rect) }
        }.mapValues { CGPoint(x: $0.midX, y: $0.midY) }
    }
}

struct HandCardBoundsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct PortraitCombatArrowOverlay: View {
    let snapshot: GameSnapshot
    let groups: [XmageCombatGroup]
    let previewArrows: [CombatArrow]
    let metrics: PortraitBattlefieldLayoutMetrics
    let humanBattlefield: [ZoneCard]
    let opponentBattlefield: [ZoneCard]

    var renderedBounds: [String: CGRect] = [:]
    var focusedOpponentID: String?

    var body: some View {
        let anchors = CombatViewportAnchors.resolve(bounds: renderedBounds,
            authorizedIDs: Set((humanBattlefield + opponentBattlefield).map(\.instanceId)),
            viewports: [metrics.opponentBattlefieldRect, metrics.opponentLandsRect, metrics.playerBattlefieldRect, metrics.playerLandsRect],
            laneIndices: CombatViewportAnchors.laneIndices(human: humanBattlefield, opponent: opponentBattlefield)).mapValues(\.point)
        Canvas { context, _ in
            for arrow in CombatArrowModel.arrows(from: groups, previewArrows: previewArrows) {
                guard let start = anchors[arrow.fromId] else { continue }
                guard let end = anchors[arrow.toId] ?? playerAnchor(arrow.toId, kind: arrow.toKind) else { continue }
                drawArrow(arrow, from: start, to: end, in: &context)
            }
        }
    }

    private func playerAnchor(_ id: String, kind: String?) -> CGPoint? {
        guard kind == nil || kind?.lowercased() == "player" else { return nil }
        let rect: CGRect
        // The bottom seat: the viewer, or their stand-in while they watch. On the tavern table
        // the arrow ends at the seat's medallion.
        if CombatPlayerIdentity.ids(for: snapshot.seatID, in: snapshot).contains(id) {
            rect = renderedBounds[TavernSeatAnchor.bottom] ?? metrics.bottomControlsRect
        } else if let focusedOpponentID, CombatPlayerIdentity.ids(for: focusedOpponentID, in: snapshot).contains(id) {
            rect = renderedBounds[TavernSeatAnchor.top] ?? metrics.topHUDRect
        } else { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func drawArrow(_ arrow: CombatArrow, from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let color: Color
        switch arrow.kind {
        case .attack:
            color = MagicPalette.oxblood
        case .blockedAttack:
            color = .gray
        case .block:
            color = MagicPalette.arcaneBlue
        case .previewAttack:
            color = MagicPalette.warningAmber
        case .previewBlock:
            color = MagicPalette.arcaneBlue
        }
        let isPreview = arrow.kind == .previewAttack || arrow.kind == .previewBlock
        context.stroke(path, with: .color(color.opacity(isPreview ? 0.48 : 0.82)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round, dash: isPreview ? [6, 5] : []))

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 9
        let left = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
        var head = Path()
        head.move(to: end)
        head.addLine(to: left)
        head.move(to: end)
        head.addLine(to: right)
        context.stroke(head, with: .color(color.opacity(isPreview ? 0.56 : 0.92)), style: StrokeStyle(lineWidth: isPreview ? 2.0 : 3.0, lineCap: .round))
    }
}

enum CombatPlayerIdentity {
    enum Side { case viewer, opponent }
    enum DefenderKind: String { case player, planeswalker, battle }

    static func ids(for playerID: String, in snapshot: GameSnapshot) -> [String] {
        let engineIDs = snapshot.xmage?.players.filter { $0.playerId == playerID }.compactMap(\.xmagePlayerId) ?? []
        return [playerID] + engineIDs
    }

    static func targetID(for playerID: String, in snapshot: GameSnapshot, candidates: Set<String>) -> String? {
        ids(for: playerID, in: snapshot).first { candidates.contains($0) }
    }

    static func side(for defenderID: String, kind: String?, in snapshot: GameSnapshot) -> Side? {
        // A permanent must use its card anchor, even if its ID resembles a seat ID.
        guard kind == nil || kind.flatMap({ DefenderKind(rawValue: $0.lowercased()) }) == .player else { return nil }
        if ids(for: snapshot.viewerID, in: snapshot).contains(defenderID) { return .viewer }
        if let opponentID = snapshot.opponent?.playerId,
           ids(for: opponentID, in: snapshot).contains(defenderID) { return .opponent }
        // Other seats have no HUD anchor in the current two-sided board projection.
        return nil
    }

    static func defenderAnchor(for defenderID: String, kind: String?, metrics: BattlefieldLayoutMetrics, snapshot: GameSnapshot) -> CGPoint? {
        guard let side = side(for: defenderID, kind: kind, in: snapshot) else { return nil }
        let rect = side == .viewer ? metrics.playerBattlefieldRect : metrics.opponentBattlefieldRect
        return CGPoint(x: metrics.boardColumnRect.minX + 10, y: rect.midY)
    }
}

enum PortraitCombatAnchorResolver {
    static func cardAnchors(metrics: PortraitBattlefieldLayoutMetrics, humanBattlefield: [ZoneCard], opponentBattlefield: [ZoneCard]) -> [String: CGPoint] {
        var anchors: [String: CGPoint] = [:]
        addAnchors(for: opponentBattlefield.filter { !$0.card.isLand }, rect: metrics.opponentBattlefieldRect, cardWidth: metrics.permanentCardWidth, into: &anchors)
        addAnchors(for: opponentBattlefield.filter { $0.card.isLand }, rect: metrics.opponentLandsRect, cardWidth: metrics.landCardWidth, into: &anchors)
        addAnchors(for: humanBattlefield.filter { !$0.card.isLand }, rect: metrics.playerBattlefieldRect, cardWidth: metrics.permanentCardWidth, into: &anchors)
        addAnchors(for: humanBattlefield.filter { $0.card.isLand }, rect: metrics.playerLandsRect, cardWidth: metrics.landCardWidth, into: &anchors)
        return anchors
    }

    static func defenderAnchor(for defenderId: String, kind: String?, metrics: PortraitBattlefieldLayoutMetrics) -> CGPoint {
        // Preserve the legacy helper surface for existing callers and geometry tests.
        if (kind == nil || kind?.lowercased() == "player"), ["human", "ai", "ai-1"].contains(defenderId) {
            let rect = defenderId == "human" ? metrics.bottomHUDRect : metrics.topHUDRect
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        return CGPoint(x: metrics.opponentBattlefieldRect.midX, y: metrics.opponentBattlefieldRect.midY)
    }

    static func defenderAnchor(for defenderId: String, kind: String?, metrics: PortraitBattlefieldLayoutMetrics, snapshot: GameSnapshot) -> CGPoint? {
        guard let side = CombatPlayerIdentity.side(for: defenderId, kind: kind, in: snapshot) else { return nil }
        let rect = side == .viewer ? metrics.bottomHUDRect : metrics.topHUDRect
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func addAnchors(for cards: [ZoneCard], rect: CGRect, cardWidth: CGFloat, into anchors: inout [String: CGPoint]) {
        guard !cards.isEmpty else { return }
        let spacing: CGFloat = 4
        let totalWidth = CGFloat(cards.count) * cardWidth + CGFloat(max(cards.count - 1, 0)) * spacing
        let startX = rect.midX - totalWidth / 2 + cardWidth / 2
        for (index, card) in cards.enumerated() {
            anchors[card.instanceId] = CGPoint(x: startX + CGFloat(index) * (cardWidth + spacing), y: rect.midY)
        }
    }
}
