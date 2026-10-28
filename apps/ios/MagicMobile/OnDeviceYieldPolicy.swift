import Foundation
import MagicMobileOnDevice

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
        /// An opponent's spell or ability on the stack threatens what you control, and you asked to stop for those
        /// (OnDeviceSmartPass.threatensViewer, Settings.stopForThreats): even a skip that passes responses stops.
        var threatToMe = false
    }

    enum StopReason: Equatable {
        case unavailable, turnChanged, controlChanged, stack, decision, interrupted, limit, threat
        var message: String {
            switch self {
            case .unavailable: return String(localized: "Auto-pass stopped. Pass priority manually.")
            case .turnChanged: return String(localized: "Auto-pass stopped. The turn changed.")
            case .controlChanged: return String(localized: "Auto-pass stopped. Player control changed.")
            case .stack: return String(localized: "Auto-pass stopped. Check the stack.")
            case .decision: return String(localized: "Auto-pass stopped. A choice needs your attention.")
            case .interrupted: return String(localized: "Auto-pass stopped. Review the current game state.")
            case .limit: return String(localized: "Auto-pass stopped after its safety limit.")
            case .threat: return String(localized: "Auto-pass stopped. An opponent's spell threatens your permanents.")
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
        else if value.threatToMe && !value.emptyStack { reason = .threat }
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

    static func ordinaryPriority(_ prompt: Prompt, viewer: String) -> Bool {
        !prompt.id.isEmpty && prompt.revision >= 0 && prompt.kind == "SELECT" &&
        prompt.selectMode == "priority" && prompt.allowsBoolean && prompt.manaPlayerID == viewer
    }

    /// Action IDs of the passes the session sends on the player's behalf: smart pass, and the End Turn / Skip yields.
    static let smartPassActionPrefix = "smart-pass-"
    static let yieldPassActionPrefix = "auto-pass-"

    /// A pass the player didn't tap. It answers only ordinary priority, which asks nothing, so the board shows
    /// no "Waiting for the table" pop-up for it (Caleb, 2026-10-14: it flashed on every smart pass).
    static func isAutomaticPass(actionID: String?) -> Bool {
        guard let actionID else { return false }
        return actionID.hasPrefix(smartPassActionPrefix) || actionID.hasPrefix(yieldPassActionPrefix)
    }
}

/// Arena-style smart pass (Caleb, 2026-10-11): when this seat has priority and nothing it could
/// do, or nothing it asked to stop for, the session passes on its behalf. Local scheduling of the
/// same ordinary pass a tap sends; XMage stays the authority for what is playable.
enum OnDeviceSmartPass {
    /// The steps where a player can receive priority, in turn order.
    enum Step: String, CaseIterable, Identifiable {
        case upkeep, draw, main1, beginCombat, declareAttackers, declareBlockers, combatDamage, endCombat, main2, end
        var id: String { rawValue }
        var title: String {
            switch self {
            case .upkeep: return String(localized: "Upkeep")
            case .draw: return String(localized: "Draw")
            case .main1: return String(localized: "Main 1")
            case .beginCombat: return String(localized: "Beginning of combat")
            case .declareAttackers: return String(localized: "Declare attackers")
            case .declareBlockers: return String(localized: "Declare blockers")
            case .combatDamage: return String(localized: "Combat damage")
            case .endCombat: return String(localized: "End of combat")
            case .main2: return String(localized: "Main 2")
            case .end: return String(localized: "End step")
            }
        }

        /// The engine's step name (`PRECOMBAT_MAIN`, `precombat-main`, …); nil for a step that is unknown.
        init?(engine raw: String?) {
            guard let raw else { return nil }
            switch raw.lowercased().replacingOccurrences(of: "_", with: "-") {
            case "upkeep": self = .upkeep
            case "draw": self = .draw
            case "precombat-main", "main1": self = .main1
            case "begin-combat", "combat": self = .beginCombat
            case "declare-attackers": self = .declareAttackers
            case "declare-blockers": self = .declareBlockers
            case "first-combat-damage", "first-strike-damage", "combat-damage": self = .combatDamage
            case "end-combat": self = .endCombat
            case "postcombat-main", "main2": self = .main2
            case "end-turn", "end", "ending", "cleanup": self = .end
            default: return nil
            }
        }
    }

    /// A stop on one step of your turns or of your opponents' turns, stored as "mine.main1" / "theirs.end".
    static func stopKey(_ step: Step, myTurn: Bool) -> String { (myTurn ? "mine." : "theirs.") + step.rawValue }

    static let enabledKey = "magicmobile.smartAutoPass"
    /// Off by default: smart pass lets your own spells and triggers resolve (Arena's default; engine release A).
    static let stopForOwnSpellsKey = "magicmobile.stopForOwnSpells"
    /// On by default (Caleb, 2026-10-21: a board wipe that took his commander went by unread): stop when an opponent's
    /// spell or ability would destroy, exile, bounce or take what you control, even with nothing to answer it.
    static let stopForThreatsKey = "magicmobile.stopForThreats"
    static let stopsKey = "magicmobile.phaseStops"
    /// Your main phases, and your opponents' attacks and end step: where instants usually matter.
    static let defaultStops: Set<String> = [stopKey(.main1, myTurn: true), stopKey(.main2, myTurn: true),
                                            stopKey(.declareAttackers, myTurn: false), stopKey(.end, myTurn: false)]

    struct Settings: Equatable {
        var enabled = true
        var stops = OnDeviceSmartPass.defaultStops
        /// Stop for your own spells and triggers on the stack when you could respond to them.
        var stopForOwnSpells = false
        /// Stop for an opponent's spell or ability that threatens your permanents, response or not.
        var stopForThreats = true

        static func encode(_ stops: Set<String>) -> String { stops.sorted().joined(separator: ",") }
        static func decode(_ raw: String?) -> Set<String> {
            guard let raw else { return OnDeviceSmartPass.defaultStops }
            return Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
        }
        static func load(_ defaults: UserDefaults = .standard) -> Settings {
            Settings(enabled: defaults.object(forKey: OnDeviceSmartPass.enabledKey) as? Bool ?? true,
                     stops: decode(defaults.string(forKey: OnDeviceSmartPass.stopsKey)),
                     stopForOwnSpells: defaults.bool(forKey: OnDeviceSmartPass.stopForOwnSpellsKey),
                     stopForThreats: defaults.object(forKey: OnDeviceSmartPass.stopForThreatsKey) as? Bool ?? true)
        }
    }

    /// What the latest poll says beyond the yield context.
    struct Situation {
        var context: OnDeviceYieldPolicy.Context
        var step: String?
        /// A land, spell or non-mana ability XMage offers this seat right now.
        var hasPlay: Bool
        /// Mana floating in this seat's pool: passing would empty it, so the player decides.
        var manaFloating: Bool
        /// The top of the stack is this seat's own spell or ability (engine `stackControllers`); nil when the engine
        /// doesn't say (older engines), which keeps today's stop.
        var topStackIsMine: Bool? = nil
        /// Some non-mana play could answer the stack or a pending attack (engine `respondsToStack`; a row without
        /// the field counts as a response, so older engines keep today's stops).
        var hasResponse = true
        /// The top of the stack is an opponent's and threatens what you control (`threatensViewer`).
        var threatensMe = false
        /// An activated ability (not a spell, not mana) could answer the stack: Gogo copying your own trigger.
        var hasAbilityResponse = false
    }

    /// The prompt to pass, or nil when the player should decide.
    static func passPrompt(_ value: Situation, settings: Settings) -> OnDeviceYieldPolicy.Prompt? {
        let context = value.context
        guard settings.enabled, context.localHumanEnabled, context.foreground, context.phase == "running",
              context.turn > 0, context.selfAuthority, !context.resyncRequired,
              let active = context.activePlayerID, !active.isEmpty,
              let prompt = context.prompt, !prompt.submitted,
              OnDeviceYieldPolicy.ordinaryPriority(prompt, viewer: context.viewerID), !value.manaFloating else { return nil }
        // An opponent's removal or sweeper waits for you to read it and let it resolve, answer or not.
        if !context.emptyStack && value.threatensMe && settings.stopForThreats && value.topStackIsMine != true { return nil }
        if !value.hasPlay { return prompt }
        // Something on the stack: your own spell or trigger resolves (unless you asked to stop for those);
        // otherwise stop only when you hold a play that actually answers it.
        if !context.emptyStack {
            // Your own trigger still stops when an ability of yours could use it (Caleb, 2026-10-27: Gogo copying Zur's
            // attack trigger never got the chance); a counterspell in hand doesn't stop it.
            if value.topStackIsMine == true && !settings.stopForOwnSpells { return value.hasAbilityResponse ? nil : prompt }
            return value.hasResponse ? nil : prompt
        }
        guard let step = Step(engine: value.step) else { return nil }
        // During an attack, a stop is worth making only with a play that answers it (a trick, a flash blocker).
        if [.declareAttackers, .declareBlockers, .combatDamage].contains(step) && !value.hasResponse { return prompt }
        return settings.stops.contains(stopKey(step, myTurn: active == context.viewerID)) ? nil : prompt
    }

    /// Whether the top of the stack is an opponent's spell or ability that would destroy, exile, bounce, damage or take
    /// what you control: it targets one of your permanents (or you, when it is a spell), or it is an untargeted
    /// sweeper, edict or steal by its rules text. A hint for when to stop and let you read, never a rules decision.
    static func threatensViewer(_ snapshot: GameSnapshot) -> Bool {
        guard let top = snapshot.stackTopFirst.first, let controller = top.controllerId, !snapshot.isViewer(controller),
              let viewer = snapshot.players.first(where: { snapshot.isViewer($0.playerId) }) else { return false }
        let mine = Set(viewer.zones.battlefield.flatMap { [$0.instanceId, $0.id] })
        let targets = Set(top.targetIds ?? [])
        if !targets.isDisjoint(with: mine) { return true }
        let isSpell = (top.objectType ?? "").uppercased() == "SPELL"
        if isSpell && (targets.contains(viewer.playerId) || targets.contains(snapshot.viewerID)) { return true }
        guard targets.isEmpty, !mine.isEmpty else { return false }
        let text = (top.rulesText ?? "").lowercased()
        let sweeps = ["destroy all", "exile all", "destroy each", "exile each", "return all", "all creatures",
                      "each creature", "all nonland permanents", "each nonland permanent", "all other creatures",
                      "sacrifices", "gain control of all", "gains control of all"]
        return sweeps.contains { text.contains($0) }
    }

    /// Whether some non-mana play could answer what is pending (engine `respondsToStack`, missing means yes).
    static func hasResponse(_ gameView: MagicMobileOnDevice.JSONValue?) -> Bool {
        let objects = gameView?["canPlayObjects"]?["objects"]?.object ?? [:]
        for stats in objects.values {
            for (category, rows) in stats.object ?? [:] {
                for row in rows.array ?? [] where !(row["manaAbility"]?.bool ?? (category == "basicManaAbilities")) {
                    if row["respondsToStack"]?.bool != false { return true }
                }
            }
        }
        return false
    }

    /// Whether an activated ability (engine `spellAbility` false, not a mana ability) could answer the stack. Only an
    /// explicit `respondsToStack` counts, so older engines keep passing on your own triggers.
    static func hasAbilityResponse(_ gameView: MagicMobileOnDevice.JSONValue?) -> Bool {
        let objects = gameView?["canPlayObjects"]?["objects"]?.object ?? [:]
        for stats in objects.values {
            for (category, rows) in stats.object ?? [:] {
                for row in rows.array ?? [] where !(row["manaAbility"]?.bool ?? (category == "basicManaAbilities")) {
                    if row["spellAbility"]?.bool == false && row["respondsToStack"]?.bool == true { return true }
                }
            }
        }
        return false
    }

    /// Whether the top stack object is the viewer's own (engine `stackControllers` and `stackOrder`, top first);
    /// nil when the engine doesn't send controllers.
    static func topStackIsMine(_ root: MagicMobileOnDevice.JSONValue?, viewer: String) -> Bool? {
        guard let controllers = root?["stackControllers"]?.object, let top = root?["stackOrder"]?.array?.first?.string,
              let controller = controllers[top]?.string else { return nil }
        return controller == viewer
    }

    /// Reads the engine's own playable list: lands, spells and non-mana abilities count, mana abilities don't.
    static func hasPlay(_ gameView: MagicMobileOnDevice.JSONValue?) -> Bool {
        let objects = gameView?["canPlayObjects"]?["objects"]?.object ?? [:]
        for stats in objects.values {
            for (category, rows) in stats.object ?? [:] {
                for row in rows.array ?? [] where !(row["manaAbility"]?.bool ?? (category == "basicManaAbilities")) {
                    return true
                }
            }
        }
        return false
    }
}
