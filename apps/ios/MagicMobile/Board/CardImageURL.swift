import SwiftUI
import PhotosUI
import UIKit

enum CardImageCacheVariant {
    case board
    case inspection

    var cacheDirectoryName: String {
        switch self {
        case .board: return "MagicMobileCardImages"
        case .inspection: return "MagicMobileInspectionImages"
        }
    }
}

/// Card image locations: forced placeholders, the card back, DEBUG design-preview art, or an
/// image an earlier build saved on this phone. There is no server fallback; the shipped board
/// loads artwork through NativeCardArtworkView.
enum CardImageURL {
    private static var shouldForcePlaceholders: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MAGICMOBILE_FORCE_CARD_PLACEHOLDERS"] == "true"
        #else
        false
        #endif
    }

    static func image(_ name: String, variant: CardImageCacheVariant, forcePlaceholder: Bool = shouldForcePlaceholders) -> URL? {
        if forcePlaceholder {
            return nil
        }
        if name == "Hidden card" {
            return URL(string: "https://gatherer.wizards.com/Images/CardBack.jpg")
        }
        #if DEBUG
        // Explicit design-preview assets only; never a production image or engine fallback.
        if ProcessInfo.processInfo.environment["MAGICMOBILE_DESIGN_PREVIEW"] != nil,
           name != "Unknown Preview Card" {
            var preview = URLComponents(string: "https://api.scryfall.com/cards/named")!
            preview.queryItems = [URLQueryItem(name: "exact", value: name), URLQueryItem(name: "format", value: "image"), URLQueryItem(name: "version", value: "normal")]
            return preview.url
        }
        #endif
        // Art saved on this phone by earlier builds stays usable offline; nothing is fetched here.
        let localURL = cacheURL(for: name, variant: variant)
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }

    static func symbol(_ symbol: String) -> URL? {
        let localURL = symbolCacheURL(for: symbol)
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }

    static func bundledSymbolAssetName(for symbol: String) -> String? {
        switch cleanedSymbolCode(symbol) {
        case "w": return "mana-w"
        case "u": return "mana-u"
        case "b": return "mana-b"
        case "r": return "mana-r"
        case "g": return "mana-g"
        case "c": return "mana-c"
        default: return nil
        }
    }

    static func xmageIconAssetName(for iconType: String) -> String? {
        XmageCardIcon.assetName(for: iconType)
    }

    private static func cacheDirectory(for variant: CardImageCacheVariant) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(variant.cacheDirectoryName, isDirectory: true)
    }

    private static var symbolCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MagicMobileSymbols", isDirectory: true)
    }

    private static func cacheURL(for name: String, variant: CardImageCacheVariant) -> URL {
        cacheDirectory(for: variant).appendingPathComponent(fileName(for: name))
    }

    private static func symbolCacheURL(for symbol: String) -> URL {
        symbolCacheDirectory.appendingPathComponent(symbolFileName(for: symbol))
    }

    private static func fileName(for name: String) -> String {
        let slug = name
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "\(slug.isEmpty ? "card" : slug).jpg"
    }

    private static func symbolFileName(for symbol: String) -> String {
        let cleaned = cleanedSymbolCode(symbol)
        let slug = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(slug.isEmpty ? "symbol" : slug).png"
    }

    private static func cleanedSymbolCode(_ symbol: String) -> String {
        symbol
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "∞", with: "infinity")
            .lowercased()
    }
}

extension String {
    var phaseTitle: String {
        split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var compactPhaseTitle: String {
        switch lowercased() {
        case "beginning", "untap", "upkeep", "draw":
            return capitalized
        case "precombat-main":
            return "Main 1"
        case "postcombat-main":
            return "Main 2"
        case "combat", "begin-combat":
            return "Combat"
        case "declare-attackers":
            return "Attackers"
        case "declare-blockers":
            return "Blockers"
        case "first-strike-damage":
            return "First Damage"
        case "combat-damage":
            return "Damage"
        case "end-combat":
            return "End Combat"
        case "ending", "end", "cleanup":
            return capitalized
        default:
            return phaseTitle
        }
    }

    var arenaPhaseTitle: String {
        switch lowercased().replacingOccurrences(of: "_", with: "-") {
        case "beginning":
            return "BEGIN"
        case "untap":
            return "UNTAP"
        case "upkeep":
            return "UPKEEP"
        case "draw":
            return "DRAW"
        case "precombat-main":
            return "MAIN 1"
        case "postcombat-main":
            return "MAIN 2"
        case "combat", "begin-combat":
            return "COMBAT"
        case "declare-attackers":
            return "ATTACK"
        case "declare-blockers":
            return "BLOCK"
        case "first-combat-damage", "first-strike-damage", "combat-damage":
            return "DAMAGE"
        case "end-combat":
            return "END C"
        case "ending", "end", "end-turn":
            return "END"
        case "cleanup":
            return "CLEANUP"
        default:
            return EngineDisplayText.phaseLabel(self)
        }
    }
}



extension LegalAction {
    var displayLabel: String {
        if type == "choose_ability" || type == "activate_ability" {
            return compactPromptTitle
        }
        if let shortLabel, !shortLabel.isEmpty {
            return shortLabel
        }
        switch type {
        case "pass_priority":
            return "Pass Priority"
        case "pass_until_response":
            return "Pass Until Response"
        case "resolve_stack", "pass_until_stack_resolved":
            return "Resolve Stack"
        case "end_turn":
            return "End Turn"
        case "pass_until_end_of_turn":
            return "Yield Until End Step"
        case "yield_until_next_turn", "pass_until_next_turn":
            return "Yield Until Next Turn"
        case "play_land":
            return "Play"
        case "cast_spell":
            return "Cast"
        case "activate_ability":
            return "Ability"
        case "make_mana":
            return "Mana"
        default:
            return label
        }
    }

    var actionDetail: String? {
        if type == "cast_spell" {
            if let manaCost, !manaCost.isEmpty {
                return requiresPayment == true ? "\(manaCost) · XMage will ask for payment" : manaCost
            }
            if requiresPayment == true {
                return "XMage will ask for payment"
            }
        }
        if type == "make_mana", let producedMana, !producedMana.isEmpty {
            return producedMana.map { "{\($0)}" }.joined(separator: " ")
        }
        if let zoneContext, !zoneContext.isEmpty {
            return zoneContext
        }
        if let sourceZone, !sourceZone.isEmpty {
            return sourceZone
        }
        let count = validTargetIds?.count ?? targetIds?.count ?? 0
        return count > 0 ? "\(count) choices" : nil
    }

    var actionPriority: Int {
        if isPrimary == true { return 0 }
        switch type {
        case "keep_hand", "resolve_choice", "play_land", "cast_spell":
            return 1
        case "choose_target", "choose_card", "choose_mode", "choose_ability", "choose_amount", "play_mana":
            return 2
        case "make_mana", "activate_ability", "pay_cost":
            return 3
        case "pass_priority":
            return 4
        case "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase":
            return 5
        case "concede":
            return 9
        default:
            return 6
        }
    }

    var systemImage: String {
        switch type {
        case "keep_hand":
            return "hand.thumbsup.fill"
        case "mulligan":
            return "arrow.counterclockwise"
        case "play_land":
            return "leaf.fill"
        case "cast_spell":
            return "sparkles"
        case "activate_ability", "choose_ability":
            return "bolt.fill"
        case "make_mana", "play_mana", "play_x_mana":
            return "circle.hexagongrid.fill"
        case "choose_target":
            return "scope"
        case "choose_card", "search_select":
            return "rectangle.stack.fill"
        case "choose_mode":
            return "square.stack.3d.up"
        case "choose_amount", "choose_multi_amount":
            return "number"
        case "order_triggers":
            return "arrow.up.arrow.down"
        case "commander_replacement":
            return "crown.fill"
        case "pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase":
            return "forward.fill"
        case "concede":
            return "flag.fill"
        default:
            return "circle.fill"
        }
    }
}
