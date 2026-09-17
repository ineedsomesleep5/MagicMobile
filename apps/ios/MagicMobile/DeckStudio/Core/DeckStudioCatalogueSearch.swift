import Foundation

/// Apply type, mana, set and identity filters before limiting results. Exact
/// identity buckets are disjoint, so off-color entries cannot hide later matches.
enum DeckStudioCatalogueSearch {
    static func cards(in catalogue: NativeDeckMetadataCatalogue, query: String = "", type: String = "",
                      allowedIdentity: [String]? = nil, setCode: String = "", minimumManaValue: Double? = nil,
                      maximumManaValue: Double? = nil, limit: Int = 80) -> [NativeDeckMetadataCatalogue.Card] {
        guard limit > 0, minimumManaValue.map({ $0.isFinite && $0 >= 0 }) ?? true,
              maximumManaValue.map({ $0.isFinite && $0 >= 0 }) ?? true,
              minimumManaValue == nil || maximumManaValue == nil || minimumManaValue! <= maximumManaValue! else { return [] }
        let cap = min(limit, 2000)
        var filter = NativeDeckMetadataCatalogue.SearchFilter()
        filter.query = query; filter.type = type; filter.setCode = setCode
        filter.minimumManaValue = minimumManaValue; filter.maximumManaValue = maximumManaValue
        guard let allowedIdentity else { return catalogue.search(filter, limit: cap) }
        let identity = Array(Set(allowedIdentity)).sorted()
        guard identity.count <= 5, Set(identity).isSubset(of: ["W", "U", "B", "R", "G"]) else { return [] }
        var results: [NativeDeckMetadataCatalogue.Card] = []
        for mask in 0..<(1 << identity.count) {
            filter.colorIdentity = Set(identity.indices.filter { mask & (1 << $0) != 0 }.map { identity[$0] })
            results.append(contentsOf: catalogue.search(filter, limit: cap))
        }
        return Array(NativeDeckMetadataCatalogue.ranked(results, query: query).prefix(cap))
    }
}
