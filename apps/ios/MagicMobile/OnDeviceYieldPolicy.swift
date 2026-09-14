import Foundation

/// Local scheduling only. Every pass still requires an ordinary engine prompt.
/// No F-key/skip commands, inferred choices, network authority, or rules simulation.
struct OnDeviceYieldPolicy {
    enum Mode {
        case safeEndTurn, endTurnSkippingResponses, untilMyTurn
        var duration: TimeInterval {
            switch self {
            case .safeEndTurn: return 60
            case .endTurnSkippingResponses: return 120
            case .untilMyTurn: return 180
            }
        }
        var passLimit: Int { self == .safeEndTurn ? 64 : 256 }
        var status: String {
            switch self {
            case .safeEndTurn: return String(localized: "Auto-passing routine priority this turn. Stop at any time.")
            case .endTurnSkippingResponses: return String(localized: "Skipping responses this turn, including the stack. Stops for choices or after 120 seconds / 256 passes.")
            case .untilMyTurn: return String(localized: "Skipping responses until your next turn, including the stack. Stops for choices or after 180 seconds / 256 passes.")
            }
        }
    }
    struct Prompt: Equatable {
        var id: String
        var revision: Int64
        var kind: String
        var selectMode: String?
        var allowsBoolean: Bool
        var submitted: Bool
        var manaPlayerID: String?
    }

    struct Context {
        var matchID: String
        var seatID: String
        var viewerID: String
        var activePlayerID: String?
        var turn: Int64
        var phase: String
        var localHumanEnabled: Bool
        var foreground: Bool
        var emptyStack: Bool
        var selfAuthority: Bool
        var resyncRequired: Bool
        var prompt: Prompt?
    }

    enum StopReason: Equatable {
        case unavailable, turnChanged, controlChanged, stack, decision, interrupted, limit
        var message: String {
            switch self {
            case .unavailable: return String(localized: "Auto-pass stopped. Pass priority manually.")
            case .turnChanged: return String(localized: "Auto-pass stopped. The turn changed.")
            case .controlChanged: return String(localized: "Auto-pass stopped. Player control changed.")
            case .stack: return String(localized: "Auto-pass stopped. Check the stack.")
            case .decision: return String(localized: "Auto-pass stopped. A choice needs your attention.")
            case .interrupted: return String(localized: "Auto-pass stopped. Review the current game state.")
            case .limit: return String(localized: "Auto-pass stopped after its safety limit.")
            }
        }
    }

    enum Decision: Equatable { case wait, pass(Prompt), stop(StopReason) }
    private var anchor: Context?
    private var mode: Mode = .safeEndTurn
    private var expiresAt: TimeInterval = 0
    private var attempted: Set<String> = []
    private var latestRevision: Int64 = -1
    var isActive: Bool { anchor != nil }

    static func canStart(_ value: Context, mode: Mode = .safeEndTurn) -> Bool {
        guard value.localHumanEnabled, value.foreground, value.phase == "running", value.turn > 0,
              let active = value.activePlayerID, !active.isEmpty, value.selfAuthority,
              !value.resyncRequired else { return false }
        guard mode == .untilMyTurn || active == value.viewerID,
              mode != .safeEndTurn || value.emptyStack else { return false }
        // Waiting on an opponent is safe to arm; it does not authorize an answer.
        guard let prompt = value.prompt else { return mode == .untilMyTurn }
        guard !prompt.submitted else { return false }
        return ordinaryPriority(prompt, viewer: value.viewerID)
    }

    mutating func start(_ value: Context, now: TimeInterval, mode: Mode = .safeEndTurn) -> Bool {
        guard Self.canStart(value, mode: mode) else { return false }
        self.mode = mode
        anchor = value; expiresAt = now + mode.duration; attempted.removeAll(); latestRevision = -1
        return true
    }

    mutating func stop() { anchor = nil; attempted.removeAll(); latestRevision = -1 }

    mutating func evaluate(_ value: Context, now: TimeInterval) -> Decision {
        guard let anchor else { return .wait }
        let turnBoundary = mode == .untilMyTurn
            ? (value.activePlayerID == value.viewerID && (value.turn != anchor.turn || anchor.activePlayerID != anchor.viewerID))
            : (value.turn != anchor.turn || value.activePlayerID != anchor.activePlayerID)
        let reason: StopReason?
        if !value.localHumanEnabled || value.phase != "running" { reason = .unavailable }
        else if !value.foreground || value.resyncRequired { reason = .interrupted }
        else if value.matchID != anchor.matchID || value.seatID != anchor.seatID || value.viewerID != anchor.viewerID || !value.selfAuthority { reason = .controlChanged }
        else if value.turn < anchor.turn || value.activePlayerID == nil || value.activePlayerID == "" { reason = .interrupted }
        else if turnBoundary { reason = .turnChanged }
        else if mode == .safeEndTurn && !value.emptyStack { reason = .stack }
        else if now >= expiresAt || attempted.count >= mode.passLimit { reason = .limit }
        else if let prompt = value.prompt, prompt.manaPlayerID != value.viewerID && prompt.kind == "SELECT" && prompt.selectMode == "priority" { reason = .controlChanged }
        else if let prompt = value.prompt, !Self.ordinaryPriority(prompt, viewer: value.viewerID) { reason = .decision }
        else { reason = nil }
        if let reason { stop(); return .stop(reason) }
        guard let prompt = value.prompt, !prompt.submitted,
              !attempted.contains(prompt.id), prompt.revision > latestRevision else { return .wait }
        return .pass(prompt)
    }

    /// Reserve before dispatch, including uncertain/failed responses. Never auto-retry.
    mutating func recordPass(_ prompt: Prompt) {
        guard isActive, attempted.count < mode.passLimit else { return }
        attempted.insert(prompt.id); latestRevision = max(latestRevision, prompt.revision)
    }

    private static func ordinaryPriority(_ prompt: Prompt, viewer: String) -> Bool {
        !prompt.id.isEmpty && prompt.revision >= 0 && prompt.kind == "SELECT" &&
        prompt.selectMode == "priority" && prompt.allowsBoolean && prompt.manaPlayerID == viewer
    }
}
