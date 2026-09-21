import Foundation

/// Retains the source so clearing an old setup error cannot surface an older
/// session error as a new failure during the next user-authorized attempt.
struct CardChoiceCommandFailure: Equatable {
    enum Source: Equatable { case legacy, setup, session }
    let message: String
    let source: Source

    init?(_ message: String?, source: Source) {
        guard let message else { return nil }
        self.message = message
        self.source = source
    }

    static func isNewFailure(from old: Self?, to new: Self?) -> Bool {
        guard let new, new != old else { return false }
        return !(old?.source == .setup && new.source == .session)
    }
}

/// A visual draft delivered as individual, freshly authorized native answers.
struct CardChoicePlan {
    enum Kind: Equatable { case selection, scry, topOrder, bottomOrder }
    let gameID: String
    let playerID: String
    let turn: Int
    let activePlayerID: String?
    let phase: String
    let step: String?
    let kind: Kind
    let universe: Set<String>
    let selected: [String] // Bottom first for scry.
    let top: [String] // Desired top first.
    let context: String
    let minimumSelection: Int?
    let maximumSelection: Int?
    private(set) var stopped = false
    private(set) var lastPrompt: String?
    private var expectedChosen: Set<String>?
    private var remainingOrder: [String]?
    private var orderKind: Kind?
    private var orderContext: String?
    private var doneSent = false

    static func kind(for prompt: PromptEnvelopeV2) -> Kind {
        let text = prompt.message.lowercased()
        if text.contains("card order to put"), text.contains("top of your library"),
           text.contains("last one chosen will be topmost") { return .topOrder }
        if text.contains("card order to put"), text.contains("bottom of your library"),
           text.contains("last one chosen will be bottommost") { return .bottomOrder }
        if text.contains("(scry)"), text.contains("bottom of your library") { return .scry }
        return .selection
    }

    static func context(_ prompt: PromptEnvelopeV2) -> String {
        prompt.message.replacingOccurrences(of: #"\s*\(selected \d+ of \d+(?:, min \d+)?\)"#,
                                            with: "", options: .regularExpression)
    }

    static func supportsDraft(_ prompt: PromptEnvelopeV2) -> Bool {
        let kind = kind(for: prompt)
        return prompt.responseCommand?.type == "choose_target" &&
            ((kind != .selection && kind != .scry) ||
             (prompt.options?["chosenTargets"]?.stringArrayValue != nil &&
              (kind == .scry || selectionBounds(prompt.message) != nil))) &&
            (prompt.cards?.filter(\.isPromptSelectable).isEmpty == false) &&
            (prompt.targets ?? []).isEmpty
    }

    static func toggled(_ ids: [String], id: String) -> [String] {
        if let index = ids.firstIndex(of: id) {
            var next = ids
            next.remove(at: index)
            return next
        }
        return ids + [id]
    }

    static func selectionBounds(_ message: String) -> (Int, Int)? {
        let pattern = #"(?:selected\s+)\d+\s+of\s+(\d+)(?:,\s*min\s+(\d+))?"#
        guard let match = message.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let part = String(message[match])
        let numbers = part.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        // TargetImpl omits ", min 0" while retaining "of <max>".
        return (numbers.count >= 3 ? numbers[2] : 0, numbers[1])
    }

    init(snapshot: GameSnapshot, prompt: PromptEnvelopeV2, selected: [String], top: [String] = []) {
        gameID = snapshot.id; playerID = prompt.playerId; turn = snapshot.turn
        activePlayerID = snapshot.activePlayerId; phase = snapshot.phase; step = snapshot.step
        kind = Self.kind(for: prompt)
        universe = Set((prompt.cards ?? []).filter(\.isPromptSelectable).map(\.id))
        self.selected = selected; self.top = top
        context = Self.context(prompt)
        let bounds = Self.selectionBounds(prompt.message)
        minimumSelection = bounds?.0
        maximumSelection = bounds?.1
    }

    mutating func cancel() { stopped = true }

    /// A cleared pending submission with the same prompt has not authorized another reply.
    func submittedPromptIsUnchanged(in snapshot: GameSnapshot) -> Bool {
        guard let lastPrompt, let prompt = snapshot.promptEnvelopeV2 else { return false }
        return lastPrompt == "\(prompt.id):\(prompt.messageId)"
    }

    /// Nil means wait, finish, or return an unexpected prompt to manual control.
    mutating func next(in snapshot: GameSnapshot, pending: Bool) -> GameCommand? {
        guard !stopped else { return nil }
        guard snapshot.id == gameID, snapshot.turn == turn, snapshot.phase == phase,
              (activePlayerID == nil || snapshot.activePlayerId == activePlayerID),
              (step == nil || snapshot.step == step),
              !snapshot.isCompleted else { stopped = true; return nil }
        guard !pending, let prompt = snapshot.promptEnvelopeV2 else { return nil }
        let key = "\(prompt.id):\(prompt.messageId)"
        guard key != lastPrompt else { return nil }
        guard prompt.playerId == playerID, prompt.responseCommand?.type == "choose_target",
              snapshot.isViewer(playerID), (prompt.targets ?? []).isEmpty else { stopped = true; return nil }
        let currentKind = Self.kind(for: prompt)
        let candidates = Set((prompt.cards ?? []).filter(\.isPromptSelectable).map(\.id))
        guard !candidates.isEmpty, candidates.isSubset(of: universe),
              Set(selected).count == selected.count, Set(top).count == top.count,
              Set(selected).isSubset(of: universe), Set(top).isSubset(of: universe) else { stopped = true; return nil }
        if kind == .scry {
            guard Set(selected).isDisjoint(with: Set(top)),
                  Set(selected).union(top) == universe else { stopped = true; return nil }
        }

        if currentKind == .topOrder || currentKind == .bottomOrder {
            let desired: [String]
            if kind == .scry {
                guard doneSent || expectedChosen == Set(selected) else { stopped = true; return nil }
                desired = currentKind == .topOrder ? top : selected
                guard (currentKind == .bottomOrder && (orderKind == nil || orderKind == .bottomOrder)) ||
                      (currentKind == .topOrder && (orderKind == .topOrder || orderKind == .bottomOrder ||
                        (orderKind == nil && selected.count <= 1))) else {
                    stopped = true; return nil
                }
            } else if kind == currentKind { desired = selected }
            else { stopped = true; return nil }
            if orderKind != currentKind {
                guard (remainingOrder?.count ?? 0) <= 1,
                      candidates == Set(desired) else { stopped = true; return nil }
                orderKind = currentKind
                orderContext = Self.context(prompt)
                remainingOrder = currentKind == .topOrder ? Array(desired.reversed()) : desired
            }
            guard orderContext == Self.context(prompt) else { stopped = true; return nil }
            guard let remaining = remainingOrder, let id = remaining.first,
                  candidates == Set(remaining) else { stopped = true; return nil }
            guard let command = Self.command(prompt, gameID: gameID, id: id) else { stopped = true; return nil }
            remainingOrder = Array(remaining.dropFirst())
            lastPrompt = key
            return command
        }

        guard (kind == .selection || kind == .scry), orderKind == nil, !doneSent,
              currentKind == kind, Self.context(prompt) == context,
              (kind == .scry
               ? (maximumSelection == nil ||
                  (Self.selectionBounds(prompt.message)?.0 == minimumSelection &&
                   Self.selectionBounds(prompt.message)?.1 == maximumSelection))
               : (Self.selectionBounds(prompt.message)?.0 == minimumSelection &&
                  Self.selectionBounds(prompt.message)?.1 == maximumSelection)),
              let chosenArray = prompt.options?["chosenTargets"]?.stringArrayValue,
              Set(chosenArray).count == chosenArray.count else { stopped = true; return nil }
        let chosen = Set(chosenArray)
        guard chosen.isSubset(of: universe), expectedChosen == nil || expectedChosen == chosen else { stopped = true; return nil }
        let removal = chosen.subtracting(selected).sorted().first
        let addition = selected.first { !chosen.contains($0) }
        if let id = removal ?? addition {
            guard candidates.contains(id), let command = Self.command(prompt, gameID: gameID, id: id) else { stopped = true; return nil }
            var expected = chosen
            if expected.contains(id) { expected.remove(id) } else { expected.insert(id) }
            expectedChosen = expected; lastPrompt = key
            return command
        }
        // False is Done only when the engine explicitly labels it Done.
        if kind == .selection {
            guard let minimumSelection, let maximumSelection,
                  selected.count >= minimumSelection, selected.count <= maximumSelection else {
                stopped = true; return nil
            }
        }
        guard (snapshot.legalActions ?? []).contains(where: {
            $0.promptId == prompt.id && $0.messageId == prompt.messageId && $0.type == "answer_yes_no" &&
                $0.confirmed == false && $0.label.lowercased() == "done"
        }) else { stopped = true; return nil }
        doneSent = true; lastPrompt = key
        return GameCommand(type: "answer_yes_no", gameId: gameID, playerId: playerID,
                           promptId: prompt.id, messageId: prompt.messageId, confirmed: false)
    }

    private static func command(_ prompt: PromptEnvelopeV2, gameID: String, id: String) -> GameCommand? {
        PromptCommandBuilder.command(gameId: gameID, promptEnvelope: prompt,
            type: "choose_target", promptId: prompt.id, playerId: prompt.playerId, ids: [id])
    }
}
