import Foundation

/// A receipt is evidence for one exact request and installed engine, not a flag
/// attached permanently to a mutable deck record.
struct DeckStudioValidationReceipt: Equatable, Sendable {
    struct Issue: Equatable, Sendable, Identifiable {
        let index: Int
        let type: String
        let group: String?
        let message: String
        let cardName: String?
        var id: Int { index }
    }
    let request: Data
    let upstream: String
    let catalogue: String
    let appBuild: String
    let checkedAt: Date
    let valid: Bool
    let issues: [Issue]
    let summary: String
    static func success(result: Data, request: Data, upstream: String, catalogue: String, appBuild: String, now: Date = Date()) throws -> Self {
        guard let value = DeckStudioJSON.object(result), DeckStudioJSON.boolean(value["valid"]) == true,
              value["validator"] as? String == "Commander", value["upstream"] as? String == upstream,
              value["catalogueHash"] as? String == catalogue, let errors = value["issues"] as? [Any], errors.isEmpty else { throw Failure.invalidReceipt }
        return Self(request: request, upstream: upstream, catalogue: catalogue, appBuild: appBuild,
                    checkedAt: now, valid: true, issues: [], summary: "Passed the installed XMage Commander validator")
    }
    static func rejection(details: Data, message: String, request: Data, upstream: String, catalogue: String, appBuild: String, now: Date = Date()) throws -> Self {
        guard let value = DeckStudioJSON.object(details), value["validator"] as? String == "Commander",
              let rows = value["issues"] as? [[String: Any]], !rows.isEmpty, rows.count <= 2000 else { throw Failure.invalidReceipt }
        let issues = try rows.enumerated().map { index, row -> Issue in
            guard let type = row["type"] as? String, let text = row["message"] as? String,
                  type.utf8.count <= 128, text.utf8.count <= 16_384 else { throw Failure.invalidReceipt }
            let group = row["group"] as? String, name = row["cardName"] as? String
            guard (group?.utf8.count ?? 0) <= 2048, (name?.utf8.count ?? 0) <= 2048 else { throw Failure.invalidReceipt }
            return Issue(index: index, type: type, group: group, message: text, cardName: name)
        }
        return Self(request: request, upstream: upstream, catalogue: catalogue, appBuild: appBuild,
                    checkedAt: now, valid: false, issues: issues, summary: message)
    }
    func matches(request: Data, upstream: String, catalogue: String, appBuild: String) -> Bool {
        self.request == request && self.upstream == upstream && self.catalogue == catalogue && self.appBuild == appBuild
    }
    enum Failure: LocalizedError {
        case invalidReceipt
        var errorDescription: String? { "XMage returned an unrecognized validation result. The draft is unchanged and has not been marked legal." }
    }
}
