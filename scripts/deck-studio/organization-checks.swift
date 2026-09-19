import Foundation
@main struct OrganizationChecks {
    static var count = 0
    static func check(_ value: Bool, _ label: String) { count += 1; if !value { fatalError(label) } }
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("studio-details-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeckStudioOrganizationStore(directory: directory)
        let empty = try await store.load(recordID: "deck")
        check(empty.revision == 0 && empty.value.tags.isEmpty, "empty optional metadata")
        let input = DeckStudioOrganization(tags: [" Treasure ", "treasure", "Artifacts"], notes: "Keep enough early ramp.\nReview the curve.")
        let first = try await store.save(input, recordID: "deck", expectedRevision: 0)
        check(first.value.tags == ["Treasure", "Artifacts"] && first.revision == 1, "tags normalized without changing notes")
        check(first.value.notes == input.notes, "notes retained verbatim")
        let reload = DeckStudioOrganizationStore(directory: directory)
        check(try await reload.load(recordID: "deck") == first, "durable roundtrip")
        do { _ = try await store.save(.init(), recordID: "deck", expectedRevision: 0); check(false, "stale expected") }
        catch { check(true, "stale metadata rejected") }
        check(try await store.load(recordID: "deck") == first, "stale write preserved existing details")
        try await store.retainImport(recordID: "deck", annotations: ["1 Sol Ring (CMM) 410 [Ramp]", "Unknown annotation retained"], source: "https://archidekt.com/decks/123")
        let receipt = try await store.load(recordID: "deck")
        check(receipt.value.importAnnotations.count == 2 && receipt.value.notes == input.notes, "import preserves local notes and full annotations")
        try await store.retainImport(recordID: "deck", annotations: receipt.value.importAnnotations, source: receipt.value.importedFrom)
        check(try await store.load(recordID: "deck") == receipt, "idempotent import receipt")
        do { try await store.retainImport(recordID: "deck", annotations: ["Different receipt"], source: nil); check(false, "conflict expected") }
        catch { check(true, "different receipt not silently merged") }
        try await store.duplicate(from: "deck", to: "copy")
        check(try await store.load(recordID: "copy").value == receipt.value, "duplicate preserves authoring metadata")
        let tags = await store.tagIndex(recordIDs: ["deck", "copy", "missing"])
        check(tags["deck"] == ["Treasure", "Artifacts"] && tags["missing"] == [], "searchable local tags")
        for value in [DeckStudioOrganization(tags: ["" ]), .init(tags: Array(repeating: "x", count: 25)), .init(tags: ["bad\nname"]), .init(notes: String(repeating: "x", count: 16385))] {
            do { _ = try await store.save(value, recordID: "deck", expectedRevision: receipt.revision); check(false, "invalid details expected") }
            catch { check(true, "invalid details bounded") }
        }
        check(try await store.load(recordID: "deck") == receipt, "rejected details are atomic")
        _ = try await store.save(.init(tags: ["Safe"]), recordID: "../../outside", expectedRevision: 0)
        check(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 3, "opaque IDs stay within owned directory")
        try await store.delete(recordID: "copy")
        check(try await store.load(recordID: "copy").revision == 0, "delete details explicit")
        check(try await store.load(recordID: "deck") == receipt, "delete never affects another deck")
        let huge = [String(repeating: "x", count: 150_000)]
        let receiptName = UUID().uuidString + ".json"
        try await store.retainImport(recordID: "large", annotations: huge, source: nil, receiptFile: receiptName)
        let large = try await store.load(recordID: "large")
        check(large.value.importAnnotations.isEmpty && large.value.importAnnotationCount == 1 && large.value.importReceiptFile == receiptName, "large receipt linked without truncation")
        check(large.value.receiptURL?.lastPathComponent == receiptName, "receipt resolves only owned filename")
        do { try await store.retainImport(recordID: "bad-receipt", annotations: [], source: nil, receiptFile: "../secret.json"); check(false, "unsafe receipt rejected") }
        catch { check(true, "receipt cannot escape directory") }
        do { try await store.retainImport(recordID: "large-unlinked", annotations: huge, source: nil); check(false, "large unlinked cannot lose data") }
        catch { check(true, "oversized annotations require durable receipt link") }
        try await store.retainImport(recordID: "large", annotations: huge, source: nil, receiptFile: receiptName)
        check(try await store.load(recordID: "large") == large, "large import retry idempotent")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let file = try files.first { try JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: Any] != nil && String(decoding: Data(contentsOf: $0), as: UTF8.self).contains("\"recordID\":\"deck\"") }!
        let corrupted = Data("preserve me".utf8); try corrupted.write(to: file)
        do { _ = try await store.save(.init(), recordID: "deck", expectedRevision: 2); check(false, "corrupt expected") }
        catch { check(true, "corruption fails closed") }
        check(try Data(contentsOf: file) == corrupted, "corrupt receipt not overwritten")
        print("PASS: \(count) local organization/receipt storage assertions; no network or engine calls.")
    }
}
