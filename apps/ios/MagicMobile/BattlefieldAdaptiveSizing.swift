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

/// Which cards a horizontally scrolled battlefield lane hides at each edge. BattlefieldRow draws
/// a soft fade where content is clipped and a "+N" marker for cards entirely out of view.
/// Pure geometry, ported to Android as BattlefieldRowOverflow (BoardLayout.kt).
struct BattlefieldRowOverflow: Equatable {
    /// Cards whose slot lies entirely before (left of) or after (right of) the viewport.
    var hiddenLeading = 0
    var hiddenTrailing = 0
    /// Some slot extends past that edge, fully or in part.
    var clipsLeading = false
    var clipsTrailing = false

    static let none = BattlefieldRowOverflow()
    /// BattlefieldRow pads each row by 8 points and separates slots by 4.
    static let rowPadding: CGFloat = 8
    static let slotSpacing: CGFloat = 4
    /// Sub-point slivers from rounding never count as clipped or visible.
    static let tolerance: CGFloat = 0.5

    /// One row of slots laid out left to right from `leadingInset` in content coordinates, scrolled by
    /// `contentOffset`. `cardsPerSlot` is how many cards each slot shows (a collapsed group or an
    /// attachment stack counts all of its cards); a missing entry counts one.
    static func measure(contentOffset: CGFloat, viewportWidth: CGFloat, slotWidths: [CGFloat], spacing: CGFloat,
                        leadingInset: CGFloat = 0, cardsPerSlot: [Int] = []) -> BattlefieldRowOverflow {
        guard !slotWidths.isEmpty, contentOffset.isFinite, viewportWidth.isFinite, viewportWidth > 0 else { return .none }
        let gap = spacing.isFinite ? max(0, spacing) : 0
        var result = BattlefieldRowOverflow()
        var minX = (leadingInset.isFinite ? leadingInset : 0) - contentOffset
        for (index, rawWidth) in slotWidths.enumerated() {
            let maxX = minX + (rawWidth.isFinite ? max(0, rawWidth) : 0)
            let cards = index < cardsPerSlot.count ? max(0, cardsPerSlot[index]) : 1
            let pastLeading = minX < -tolerance, pastTrailing = maxX > viewportWidth + tolerance
            if pastLeading { result.clipsLeading = true }
            if pastTrailing { result.clipsTrailing = true }
            if pastLeading && maxX <= tolerance { result.hiddenLeading += cards }
            else if pastTrailing && minX >= viewportWidth - tolerance { result.hiddenTrailing += cards }
            minX = maxX + gap
        }
        return result
    }

    /// A BattlefieldRow scroller: its rows share one offset, start at the row padding and use one
    /// card width. Hidden cards add up across the rows.
    static func lane(contentOffset: CGFloat, viewportWidth: CGFloat, cardWidth: CGFloat,
                     cardsPerSlotByRow: [[Int]]) -> BattlefieldRowOverflow {
        cardsPerSlotByRow.reduce(.none) { total, row in
            total + measure(contentOffset: contentOffset, viewportWidth: viewportWidth,
                            slotWidths: Array(repeating: cardWidth, count: row.count), spacing: slotSpacing,
                            leadingInset: rowPadding, cardsPerSlot: row)
        }
    }

    static func + (lhs: BattlefieldRowOverflow, rhs: BattlefieldRowOverflow) -> BattlefieldRowOverflow {
        BattlefieldRowOverflow(hiddenLeading: lhs.hiddenLeading + rhs.hiddenLeading,
                               hiddenTrailing: lhs.hiddenTrailing + rhs.hiddenTrailing,
                               clipsLeading: lhs.clipsLeading || rhs.clipsLeading,
                               clipsTrailing: lhs.clipsTrailing || rhs.clipsTrailing)
    }
}
