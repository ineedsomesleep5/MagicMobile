import Foundation

/// Optional local authoring data; never part of the deck sent to XMage or a web service.
struct DeckStudioOrganization: Codable, Equatable, Sendable {
    var tags: [String] = []
    var notes = ""
    var importAnnotations: [String] = []
    var importedFrom: String?
    var importReceiptFile: String?
    var importAnnotationCount: Int?
    static let maximumBytes = 512 * 1024

    func validated() throws -> Self {
        guard tags.count <= 24, notes.utf8.count <= 16_384,
              importAnnotations.count <= 2000,
              importAnnotations.allSatisfy({ $0.utf8.count <= 8192 && !$0.contains("\0") }),
              (importedFrom?.utf8.count ?? 0) <= 2048,
              importAnnotationCount.map({ (0...2_000_000).contains($0) && $0 >= importAnnotations.count }) ?? true,
              importReceiptFile.map(Self.validReceiptFile) ?? true,
              !notes.contains("\0"), !(importedFrom?.contains("\0") ?? false) else { throw Failure.invalid }
        var checked = self
        var seen = Set<String>()
        checked.tags = try tags.compactMap { raw in
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, tag.utf8.count <= 80,
                  !tag.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Failure.invalid }
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return seen.insert(key).inserted ? tag : nil
        }
        return checked
    }
    static func validReceiptFile(_ name: String) -> Bool {
        name.hasSuffix(".json") && name.count == 41 && UUID(uuidString: String(name.dropLast(5))) != nil
    }
    /// Only an app-created UUID filename can resolve within the owned receipt directory.
    var receiptURL: URL? {
        guard let name = importReceiptFile, Self.validReceiptFile(name),
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("MagicMobile/DeckStudio/ImportReceipts", isDirectory: true).appendingPathComponent(name)
    }
    enum Failure: LocalizedError {
        case invalid, corrupt, conflict, unavailable
        var errorDescription: String? {
            switch self {
            case .invalid: return "Use up to 24 tags (80 bytes each), 16 KiB of notes, and a bounded import receipt. Existing data is unchanged."
            case .corrupt: return "Saved deck details could not be read safely. The original file is preserved; card editing still works."
            case .conflict: return "Deck details changed elsewhere. Close and reopen Details before saving; the newer version was preserved."
            case .unavailable: return "Local deck-detail storage is unavailable. Your deck cards are unchanged."
            }
        }
    }
}

/// Content revision is separate from DeckLibraryRecord's card-list revision.
/// Independent windows cannot silently overwrite each other's notes or tags.
actor DeckStudioOrganizationStore {
    static let shared = DeckStudioOrganizationStore()
    struct Snapshot: Equatable, Sendable {
        let value: DeckStudioOrganization
        let revision: Int
    }
    private struct Envelope: Codable {
        let schema: Int
        let recordID: String
        let revision: Int
        let value: DeckStudioOrganization
    }
    private let directory: URL?
    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("MagicMobile-DeckDetails", isDirectory: true)) { self.directory = directory }

    func load(recordID: String) throws -> Snapshot {
        let file = try url(recordID)
        guard FileManager.default.fileExists(atPath: file.path) else { return Snapshot(value: .init(), revision: 0) }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= DeckStudioOrganization.maximumBytes else { throw DeckStudioOrganization.Failure.corrupt }
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= DeckStudioOrganization.maximumBytes else { throw DeckStudioOrganization.Failure.corrupt }
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            guard envelope.schema == 1, envelope.recordID == recordID, (1...1_000_000_000).contains(envelope.revision),
                  try envelope.value.validated() == envelope.value else { throw DeckStudioOrganization.Failure.corrupt }
            return Snapshot(value: envelope.value, revision: envelope.revision)
        } catch { throw DeckStudioOrganization.Failure.corrupt }
    }
    @discardableResult func save(_ value: DeckStudioOrganization, recordID: String, expectedRevision: Int) throws -> Snapshot {
        let existing = try load(recordID: recordID)
        guard existing.revision == expectedRevision, expectedRevision < 1_000_000_000 else { throw DeckStudioOrganization.Failure.conflict }
        let value = try value.validated()
        let snapshot = Snapshot(value: value, revision: existing.revision + 1)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(schema: 1, recordID: recordID, revision: snapshot.revision, value: value))
        guard data.count <= DeckStudioOrganization.maximumBytes else { throw DeckStudioOrganization.Failure.invalid }
        let file = try url(recordID)
        var folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS) || os(macOS)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        #endif
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        return snapshot
    }
    func retainImport(recordID: String, annotations: [String], source: String?, receiptFile: String? = nil) throws {
        let old = try load(recordID: recordID)
        var value = old.value
        // A large import remains fully preserved in its existing bounded receipt,
        // not stuffed into the small searchable tag/notes record or silently truncated.
        let small = annotations.count <= 2000 && annotations.allSatisfy { $0.utf8.count <= 8192 } &&
            annotations.reduce(0, { $0 + $1.utf8.count }) <= 128 * 1024
        if !small && receiptFile == nil { throw DeckStudioOrganization.Failure.invalid }
        let inline = small ? annotations : []
        if value.importReceiptFile != nil || value.importAnnotationCount != nil || !value.importAnnotations.isEmpty || value.importedFrom != nil {
            guard value.importReceiptFile == receiptFile, value.importAnnotations == inline,
                  (value.importAnnotationCount ?? value.importAnnotations.count) == annotations.count,
                  value.importedFrom == source else { throw DeckStudioOrganization.Failure.conflict }
            return
        }
        value.importAnnotations = inline; value.importedFrom = source
        value.importReceiptFile = receiptFile; value.importAnnotationCount = annotations.count
        _ = try save(value, recordID: recordID, expectedRevision: old.revision)
    }
    func duplicate(from: String, to: String) throws {
        let original = try load(recordID: from)
        guard original.revision > 0 else { return }
        _ = try save(original.value, recordID: to, expectedRevision: 0)
    }
    func delete(recordID: String) throws {
        let file = try url(recordID)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    func tagIndex(recordIDs: [String]) -> [String: [String]] {
        // Nonessential index failures do not hide cards or mutate unreadable files.
        var result: [String: [String]] = [:]
        for id in recordIDs.prefix(4000) {
            if let snapshot = try? load(recordID: id) { result[id] = snapshot.value.tags }
        }
        return result
    }
    private func url(_ id: String) throws -> URL {
        guard let directory, !id.isEmpty, id.utf8.count <= 256,
              !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw DeckStudioOrganization.Failure.unavailable }
        // ID never becomes a path. Full stored-ID validation rejects hash collisions.
        var hash: UInt64 = 14695981039346656037
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return directory.appendingPathComponent("details-\(String(hash, radix: 16)).json")
    }
}
