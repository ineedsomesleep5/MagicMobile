import Foundation
import Combine
import CryptoKit

/// A stored XMage check applies to one deck, one exact playing request and one
/// installed engine, catalogue and app build. Any other combination is a cache miss.
/// Android's DeckStudioReceiptStore.kt uses the same key and the same cap.
struct DeckStudioCheckKey: Codable, Hashable, Sendable {
    let deckID: String
    let requestSHA256: String
    let upstream: String
    let catalogue: String
    let appBuild: String

    init(deckID: String, request: Data, upstream: String, catalogue: String, appBuild: String) {
        self.deckID = deckID
        requestSHA256 = SHA256.hash(data: request).map { String(format: "%02x", $0) }.joined()
        self.upstream = upstream; self.catalogue = catalogue; self.appBuild = appBuild
    }

    /// Results from another engine, catalogue or build can never match again.
    func sameInstall(as other: DeckStudioCheckKey) -> Bool {
        upstream == other.upstream && catalogue == other.catalogue && appBuild == other.appBuild
    }

    fileprivate var bounded: Bool {
        [deckID, upstream, catalogue, appBuild].allSatisfy { !$0.isEmpty && $0.utf8.count <= 512 }
            && requestSHA256.count == 64
    }
}

/// The outcome of one XMage Commander check, kept so the deck is not checked again
/// until its playing cards, the engine, the catalogue or the app build change.
struct DeckStudioStoredCheck: Codable, Equatable, Sendable {
    struct Issue: Codable, Equatable, Sendable, Identifiable {
        let index: Int
        let type: String
        let group: String?
        let message: String
        let cardName: String?
        var id: Int { index }
    }
    struct IssueGroup: Equatable, Identifiable {
        let title: String
        let issues: [Issue]
        var id: String { title }
    }
    /// Shown issues are bounded; `issueCount` keeps XMage's full count.
    static let maximumIssues = 100

    let key: DeckStudioCheckKey
    let checkedAt: Date
    let valid: Bool
    let summary: String
    let issueCount: Int
    let issues: [Issue]

    init(key: DeckStudioCheckKey, checkedAt: Date, valid: Bool, summary: String, issues: [Issue], issueCount: Int? = nil) {
        self.key = key; self.checkedAt = checkedAt; self.valid = valid; self.summary = summary
        self.issues = Array(issues.prefix(Self.maximumIssues))
        self.issueCount = max(issueCount ?? issues.count, self.issues.count)
    }

    init(deckID: String, receipt: DeckStudioValidationReceipt) {
        self.init(key: DeckStudioCheckKey(deckID: deckID, request: receipt.request, upstream: receipt.upstream,
                                          catalogue: receipt.catalogue, appBuild: receipt.appBuild),
                  checkedAt: receipt.checkedAt, valid: receipt.valid, summary: receipt.summary,
                  issues: receipt.issues.map { Issue(index: $0.index, type: $0.type, group: $0.group,
                                                     message: $0.message, cardName: $0.cardName) })
    }

    /// Cards XMage named, in first-seen order, so Fix deck can find their rows.
    var cardNames: [String] {
        var seen = Set<String>()
        return issues.compactMap { issue in
            guard let name = issue.cardName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  seen.insert(name).inserted else { return nil }
            return name
        }
    }

    /// Issues grouped the way XMage groups them, in the order XMage reported each group.
    var groups: [IssueGroup] {
        var order: [String] = []
        var members: [String: [Issue]] = [:]
        for issue in issues {
            let title = Self.groupTitle(issue)
            if members[title] == nil { order.append(title) }
            members[title, default: []].append(issue)
        }
        return order.map { IssueGroup(title: $0, issues: members[$0] ?? []) }
    }

    private static func groupTitle(_ issue: Issue) -> String {
        if let group = issue.group?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty { return group }
        let words = issue.type.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.isEmpty ? "Commander rules" : words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The same result as a validation receipt, only for the exact request it was made for.
    func receipt(request: Data) -> DeckStudioValidationReceipt? {
        guard DeckStudioCheckKey(deckID: key.deckID, request: request, upstream: key.upstream,
                                 catalogue: key.catalogue, appBuild: key.appBuild) == key else { return nil }
        return DeckStudioValidationReceipt(request: request, upstream: key.upstream, catalogue: key.catalogue,
            appBuild: key.appBuild, checkedAt: checkedAt, valid: valid,
            issues: issues.map { .init(index: $0.index, type: $0.type, group: $0.group, message: $0.message, cardName: $0.cardName) },
            summary: summary)
    }

    fileprivate var bounded: Bool {
        key.bounded && summary.utf8.count <= 16_384 && issues.count <= Self.maximumIssues
            && issueCount >= issues.count && issueCount <= 2000 && valid == issues.isEmpty
            && issues.allSatisfy { $0.type.utf8.count <= 128 && $0.message.utf8.count <= 16_384
                && ($0.group?.utf8.count ?? 0) <= 2048 && ($0.cardName?.utf8.count ?? 0) <= 2048 }
    }
}

/// What a deck tile, the Now playing strip and the setup screen say about a deck.
enum DeckStudioPlayStatus: Equatable, Sendable {
    case ready, needsFixes, notChecked

    var label: String {
        switch self {
        case .ready: return DeckStudioPlayText.ready
        case .needsFixes: return DeckStudioPlayText.needsFixes
        case .notChecked: return DeckStudioPlayText.notChecked
        }
    }

    /// The status line under the deck on the game setup screen.
    var setupLine: String {
        switch self {
        case .ready: return DeckStudioPlayText.setupReady
        case .needsFixes: return DeckStudioPlayText.setupNeedsFixes
        case .notChecked: return DeckStudioPlayText.setupNotChecked
        }
    }
}

/// Device-local check results, newest first. It is a cache: a missing, unreadable or
/// stale file only means decks show "Not checked" until they are checked again.
/// Android's DeckStudioReceiptStore.kt keeps the same caps: the newest 200 results,
/// at most five per deck, and a file of at most 2 MiB.
@MainActor
final class DeckStudioReceiptStore: ObservableObject {
    static let shared = DeckStudioReceiptStore()
    static let maximumResults = 200
    static let maximumPerDeck = 5
    static let maximumBytes = 2 * 1024 * 1024
    private struct Payload: Codable { let schema: Int; let checks: [DeckStudioStoredCheck] }

    @Published private(set) var checks: [DeckStudioStoredCheck] = []
    private let url: URL?

    init(url: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("MagicMobile-DeckChecks", isDirectory: true).appendingPathComponent("checks-v1.json")) {
        self.url = url
        checks = Self.read(url)
    }

    func check(for key: DeckStudioCheckKey) -> DeckStudioStoredCheck? { checks.first { $0.key == key } }

    /// Never "Ready" from a result that does not match every part of the key.
    func status(for key: DeckStudioCheckKey?) -> DeckStudioPlayStatus {
        guard let key, let check = check(for: key) else { return .notChecked }
        return check.valid ? .ready : .needsFixes
    }

    /// Keeps the newest result per key, at most five per deck and 200 in all, newest
    /// first, and drops results from other installs. When the file would pass its size
    /// cap, the oldest results go. The in-memory result stays usable when the file
    /// cannot be written.
    @discardableResult func record(_ check: DeckStudioStoredCheck) -> Bool {
        guard check.bounded else { return false }
        let others = Self.newestFirst(checks.filter { $0.key != check.key && $0.key.sameInstall(as: check.key) })
        let sameDeck = others.filter { $0.key.deckID == check.key.deckID }.prefix(Self.maximumPerDeck - 1)
        var next = Array(Self.newestFirst([check] + others.filter { $0.key.deckID != check.key.deckID } + sameDeck).prefix(Self.maximumResults))
        var data = try? Self.encode(next)
        while let current = data, current.count > Self.maximumBytes, next.count > 1 {
            next.removeLast(); data = try? Self.encode(next)
        }
        checks = next
        return write(data)
    }

    /// A deleted deck's results go with it.
    func forget(deckID: String) {
        guard checks.contains(where: { $0.key.deckID == deckID }) else { return }
        checks.removeAll { $0.key.deckID == deckID }
        write(try? Self.encode(checks))
    }

    /// Newest first; results checked at the same moment keep their order.
    private static func newestFirst(_ values: [DeckStudioStoredCheck]) -> [DeckStudioStoredCheck] {
        values.enumerated().sorted { left, right in
            left.element.checkedAt != right.element.checkedAt ? left.element.checkedAt > right.element.checkedAt : left.offset < right.offset
        }.map(\.element)
    }

    private static func encode(_ checks: [DeckStudioStoredCheck]) throws -> Data {
        try JSONEncoder().encode(Payload(schema: 1, checks: checks))
    }

    private static func read(_ url: URL?) -> [DeckStudioStoredCheck] {
        guard let url, let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: url), data.count <= maximumBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schema == 1, payload.checks.count <= maximumResults,
              payload.checks.allSatisfy(\.bounded),
              Set(payload.checks.map(\.key)).count == payload.checks.count else { return [] }
        return payload.checks
    }

    @discardableResult private func write(_ data: Data?) -> Bool {
        guard let url, let data else { return false }
        do {
            guard data.count <= Self.maximumBytes else { return false }
            var directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
}
