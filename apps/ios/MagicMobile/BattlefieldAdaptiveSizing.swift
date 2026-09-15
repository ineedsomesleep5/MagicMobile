import Foundation

/// Landscape presentation only; callers retain scrolling and long-press inspection.
enum BattlefieldAdaptiveSizing {
    /// Supply one flag per rendered slot (one for a collapsed group, all when expanded).
    /// Row width includes 16 points total horizontal padding and 4-point inter-slot gaps.
    /// At the readable floor, overflow is intentional and must remain scrollable.
    static func cardWidth(
        availableRowWidth: CGFloat,
        maxCardWidth: CGFloat,
        heightRatio: CGFloat,
        tappedSlots: [Bool]
    ) -> CGFloat {
        guard maxCardWidth.isFinite, maxCardWidth > 0 else { return 0 }
        guard !tappedSlots.isEmpty else { return maxCardWidth }
        let minimum = min(44, maxCardWidth)
        let available = availableRowWidth.isFinite ? max(0, availableRowWidth) : 0
        let ratio = heightRatio.isFinite && heightRatio > 0 ? heightRatio : 1
        let footprint = tappedSlots.reduce(CGFloat.zero) { $0 + ($1 ? ratio : 1) }
        let gaps = CGFloat(tappedSlots.count - 1) * 4
        let fittingWidth = max(0, available - 16 - gaps) / footprint
        return max(minimum, min(maxCardWidth, fittingWidth))
    }
}
