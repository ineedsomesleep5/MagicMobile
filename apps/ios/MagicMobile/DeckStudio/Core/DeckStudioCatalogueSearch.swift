import Foundation

/// The existing catalogue supports exact-identity filters. Search each permitted
/// identity before limiting results, so off-color cards cannot hide later matches.
/// At most 32 searches; all filtering runs off the UI actor in the search screen.
enum DeckStudioCatalogueSearch {
    static func cards(in catalogue: NativeDeckMetadataCatalogue, query: String = "", type: String = "",
                      allowedIdentity: [String]? = nil, limit: Int = 80) -> [NativeDeckMetadataCatalogue.Card] {
        guard limit > 0 else { return [] }
        let cap = min(limit, 2000)
        var filter = NativeDeckMetadataCatalogue.SearchFilter()
        filter.query = query; filter.type = type
        guard let allowedIdentity else { return catalogue.search(filter, limit: cap) }
        let identity = Array(Set(allowedIdentity)).sorted()
        guard identity.count <= 5, Set(identity).isSubset(of: ["W", "U", "B", "R", "G"]) else { return [] }
        var results: [NativeDeckMetadataCatalogue.Card] = []
        for mask in 0..<(1 << identity.count) {
            filter.colorIdentity = Set(identity.indices.filter { mask & (1 << $0) != 0 }.map { identity[$0] })
            results.append(contentsOf: catalogue.search(filter, limit: cap))
        }
        // Exact identity buckets are disjoint. A card after cap in its own bucket
        // cannot belong to the first cap of their combined alphabetical ordering.
        return Array(results.sorted { $0.name < $1.name }.prefix(cap))
    }
}
