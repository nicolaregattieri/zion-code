import SwiftUI

struct LaneGraphView: View {
    let commit: Commit
    let laneCount: Int
    let isSelected: Bool
    let isHead: Bool
    let height: CGFloat
    
    private let leadingPadding: CGFloat = 10
    private let trailingPadding: CGFloat = 12
    private let laneSpacing: CGFloat = 20
    private let minimumWidth: CGFloat = 56

    var body: some View {
        Canvas { context, size in
            let centerY = size.height * 0.50
            let laneColorByLane = Dictionary(uniqueKeysWithValues: commit.laneColors.map { ($0.lane, $0.colorKey) })

            let incomingLanes = Set(commit.incomingLanes)
            let outgoingLanes = Set(commit.outgoingLanes)
            let allActiveLanes = incomingLanes.union(outgoingLanes).union([commit.lane])

            // Lanes newly created by cross-lane edges (merge targets with no incoming line).
            // The Bezier curve already handles the visual connection, so the vertical
            // outgoing stub would create a visible spike — skip it.
            let newEdgeTargetLanes: Set<Int> = {
                let targets = Set(commit.outgoingEdges.filter { $0.from != $0.to }.map(\.to))
                return targets.subtracting(incomingLanes)
            }()

            for lane in allActiveLanes {
                let colorKey = laneColorByLane[lane] ?? lane
                let laneColor = color(forKey: colorKey)
                let x = laneX(lane)

                let hasIncoming = incomingLanes.contains(lane)
                let hasOutgoing = outgoingLanes.contains(lane)
                let isCommitLane = (lane == commit.lane)

                if hasIncoming {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: centerY))
                    context.stroke(path, with: .color(laneColor.opacity(isCommitLane ? 1.0 : 0.4)), style: StrokeStyle(lineWidth: isCommitLane ? 2.5 : 1.4, lineCap: .butt))
                }

                if hasOutgoing && !newEdgeTargetLanes.contains(lane) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: centerY))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(laneColor.opacity(isCommitLane ? 1.0 : 0.4)), style: StrokeStyle(lineWidth: isCommitLane ? 2.5 : 1.4, lineCap: .butt))
                }
            }

            for edge in commit.outgoingEdges where edge.from != edge.to {
                let startX = laneX(edge.from)
                let endX = laneX(edge.to)
                let laneDist = abs(endX - startX)
                let arcHeight = min(laneDist * 1.2, (size.height - centerY) * 0.6)
                let arcTop = centerY + 4
                let arcBottom = arcTop + arcHeight
                let arcMidY = (arcTop + arcBottom) / 2

                var edgePath = Path()
                edgePath.move(to: CGPoint(x: startX, y: centerY))
                edgePath.addLine(to: CGPoint(x: startX, y: arcTop))
                edgePath.addCurve(
                    to: CGPoint(x: endX, y: arcBottom),
                    control1: CGPoint(x: startX, y: arcMidY),
                    control2: CGPoint(x: endX, y: arcMidY)
                )
                edgePath.addLine(to: CGPoint(x: endX, y: size.height))
                context.stroke(edgePath, with: .color(color(forKey: edge.colorKey).opacity(0.8)),
                               style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
            }

            let x = laneX(commit.lane)
            let nodeColor = color(forKey: laneColorByLane[commit.lane] ?? commit.nodeColorKey)
            
            if isHead {
                let outerRect = CGRect(x: x - 9, y: centerY - 9, width: 18, height: 18)
                let midRect = CGRect(x: x - 6, y: centerY - 6, width: 12, height: 12)
                let innerRect = CGRect(x: x - 3, y: centerY - 3, width: 6, height: 6)
                context.stroke(Path(ellipseIn: outerRect), with: .color(nodeColor.opacity(0.4)), lineWidth: 1)
                context.stroke(Path(ellipseIn: midRect), with: .color(nodeColor), lineWidth: 2.5)
                context.fill(Path(ellipseIn: innerRect), with: .color(nodeColor))
            } else {
                let nodeRect = CGRect(x: x - 6.5, y: centerY - 6.5, width: 13, height: 13)
                context.fill(Path(ellipseIn: nodeRect), with: .color(nodeColor))
                context.stroke(Path(ellipseIn: nodeRect), with: .color(.white.opacity(0.8)), lineWidth: 1.8)
            }
        }
        .frame(width: graphWidth, height: height)
    }

    private var graphWidth: CGFloat {
        let span = CGFloat(max(laneCount - 1, 0)) * laneSpacing
        return max(leadingPadding + trailingPadding + span, minimumWidth)
    }

    private func laneX(_ lane: Int) -> CGFloat {
        let maxLaneIndex = max(laneCount - 1, 0)
        let rightAlignedOffset = CGFloat(maxLaneIndex - lane) * laneSpacing
        return graphWidth - trailingPadding - rightAlignedOffset
    }

    private func color(forKey key: Int) -> Color { DesignSystem.Colors.laneColor(forKey: key) }
}
