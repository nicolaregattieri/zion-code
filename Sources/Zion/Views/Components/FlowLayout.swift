import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat
    var maxItemsPerRow: Int = .max

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else { return .zero }
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + spacing * CGFloat(rows.count - 1)
        let width = proposal.width ?? rows.map(\.naturalWidth).max() ?? .zero
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        var subviewIndex = 0
        for row in rows {
            let totalSpacing = spacing * CGFloat(row.count - 1)
            let itemWidth = (bounds.width - totalSpacing) / CGFloat(row.count)
            var x = bounds.minX
            for _ in 0..<row.count {
                let size = CGSize(width: itemWidth, height: row.height)
                subviews[subviewIndex].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += itemWidth + spacing
                subviewIndex += 1
            }
            y += row.height + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let widthAfterAdd = currentRow.naturalWidth + (currentRow.count > 0 ? spacing : 0) + size.width

            let overflowsWidth = maxItemsPerRow == .max && widthAfterAdd > maxWidth
            if currentRow.count > 0 && (overflowsWidth || currentRow.count >= maxItemsPerRow) {
                rows.append(currentRow)
                currentRow = Row()
            }
            currentRow.add(size: size, spacing: spacing)
        }
        if currentRow.count > 0 {
            rows.append(currentRow)
        }
        return rows
    }

    private struct Row {
        var count: Int = 0
        var naturalWidth: CGFloat = 0
        var height: CGFloat = 0

        mutating func add(size: CGSize, spacing: CGFloat) {
            if count > 0 { naturalWidth += spacing }
            naturalWidth += size.width
            height = max(height, size.height)
            count += 1
        }
    }
}
