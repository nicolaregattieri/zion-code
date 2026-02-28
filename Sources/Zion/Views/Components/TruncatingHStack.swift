import SwiftUI

/// A horizontal layout that places children left-to-right and truncates when space runs out.
///
/// The **last child** is treated as the overflow indicator. It is only displayed when one or more
/// earlier children cannot fit. The number of hidden children is reported through `overflowCount`.
///
/// Usage:
/// ```swift
/// TruncatingHStack(spacing: 10, overflowCount: $overflow) {
///     ForEach(items) { item in ItemView(item) }
///     OverflowPill(count: overflow)  // last child = overflow indicator
/// }
/// ```
struct TruncatingHStack: Layout {
    var spacing: CGFloat = 8
    @Binding var overflowCount: Int

    struct CacheData {
        var overflow: Int = 0
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        // The last subview is the overflow indicator
        let contentSubviews = subviews.dropLast()
        let overflowSize = sizes.last!

        // Try fitting all content subviews (no overflow indicator)
        var usedWidth: CGFloat = 0
        var allFit = true
        for (index, size) in sizes.dropLast().enumerated() {
            let gap = index > 0 ? spacing : 0
            if usedWidth + gap + size.width > maxWidth {
                allFit = false
                break
            }
            usedWidth += gap + size.width
        }

        if allFit {
            cache.overflow = 0
            let height = sizes.dropLast().map(\.height).max() ?? 0
            return CGSize(width: usedWidth, height: height)
        }

        // Not all fit — figure out how many fit alongside the overflow indicator
        usedWidth = 0
        var visibleCount = 0
        let reservedForOverflow = overflowSize.width

        for (index, size) in sizes.dropLast().enumerated() {
            let gap = index > 0 ? spacing : 0
            let neededWithOverflow = usedWidth + gap + size.width + spacing + reservedForOverflow
            if neededWithOverflow > maxWidth {
                break
            }
            usedWidth += gap + size.width
            visibleCount += 1
        }

        // At minimum show the overflow pill even if zero content items fit
        let totalWidth: CGFloat
        if visibleCount > 0 {
            totalWidth = usedWidth + spacing + reservedForOverflow
        } else {
            totalWidth = reservedForOverflow
        }

        cache.overflow = contentSubviews.count - visibleCount

        let allHeights = sizes.dropLast().prefix(visibleCount).map(\.height) + [overflowSize.height]
        let height = allHeights.max() ?? 0

        return CGSize(width: totalWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        guard !subviews.isEmpty else { return }

        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentSubviews = Array(subviews.dropLast())
        let overflowSubview = subviews.last!
        let overflowSize = sizes.last!

        // First pass: determine how many content items fit
        let maxWidth = bounds.width
        var usedWidth: CGFloat = 0
        var allFit = true

        for (index, size) in sizes.dropLast().enumerated() {
            let gap = index > 0 ? spacing : 0
            if usedWidth + gap + size.width > maxWidth {
                allFit = false
                break
            }
            usedWidth += gap + size.width
        }

        if allFit {
            // Place all content subviews, hide overflow indicator
            var x = bounds.minX
            for (index, subview) in contentSubviews.enumerated() {
                let size = sizes[index]
                subview.place(
                    at: CGPoint(x: x, y: bounds.midY - size.height / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }

            // Hide overflow indicator off-screen
            overflowSubview.place(
                at: CGPoint(x: -10000, y: bounds.midY),
                proposal: .zero
            )

            // Update binding on next run loop to avoid modifying state during layout
            let newOverflow = 0
            if cache.overflow != newOverflow {
                cache.overflow = newOverflow
                DispatchQueue.main.async { [self] in
                    self.overflowCount = newOverflow
                }
            }
            return
        }

        // Not all fit — place as many as possible + overflow indicator
        usedWidth = 0
        var visibleCount = 0
        let reservedForOverflow = overflowSize.width

        for (index, size) in sizes.dropLast().enumerated() {
            let gap = index > 0 ? spacing : 0
            let neededWithOverflow = usedWidth + gap + size.width + spacing + reservedForOverflow
            if neededWithOverflow > maxWidth {
                break
            }
            usedWidth += gap + size.width
            visibleCount += 1
        }

        // Place visible content subviews
        var x = bounds.minX
        for index in 0..<visibleCount {
            let size = sizes[index]
            contentSubviews[index].place(
                at: CGPoint(x: x, y: bounds.midY - size.height / 2),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
        }

        // Hide remaining content subviews off-screen
        for index in visibleCount..<contentSubviews.count {
            contentSubviews[index].place(
                at: CGPoint(x: -10000, y: bounds.midY),
                proposal: .zero
            )
        }

        // Place overflow indicator
        overflowSubview.place(
            at: CGPoint(x: x, y: bounds.midY - overflowSize.height / 2),
            proposal: ProposedViewSize(overflowSize)
        )

        let newOverflow = contentSubviews.count - visibleCount
        if cache.overflow != newOverflow {
            cache.overflow = newOverflow
            DispatchQueue.main.async { [self] in
                self.overflowCount = newOverflow
            }
        }
    }
}
