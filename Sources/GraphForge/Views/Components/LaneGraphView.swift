import SwiftUI

struct LaneGraphView: View {
    let commit: Commit
    let laneCount: Int
    let isSelected: Bool
    let isHead: Bool
    let height: CGFloat
    
    private let safePadding: CGFloat = 14
    private let laneSpacing: CGFloat = 20
    private let colorPalette: [Color] = [
        .blue, .pink, .green, .orange, .teal, .purple, .red, .mint, .indigo, .yellow, .cyan, .brown
    ]

    var body: some View {
        Canvas { context, size in
            let centerY = size.height * 0.50
            let laneColorByLane = Dictionary(uniqueKeysWithValues: commit.laneColors.map { ($0.lane, $0.colorKey) })

            let incomingLanes = Set(commit.incomingLanes)
            let outgoingLanes = Set(commit.outgoingLanes)
            let allActiveLanes = incomingLanes.union(outgoingLanes).union([commit.lane])
            
            for lane in allActiveLanes {
                let colorKey = laneColorByLane[lane] ?? lane
                let laneColor = color(forKey: colorKey)
                let x = laneX(lane) + safePadding
                
                let hasIncoming = incomingLanes.contains(lane)
                let hasOutgoing = outgoingLanes.contains(lane)
                let isCommitLane = (lane == commit.lane)
                
                if hasIncoming {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: centerY))
                    context.stroke(path, with: .color(laneColor.opacity(isCommitLane ? 1.0 : 0.4)), style: StrokeStyle(lineWidth: isCommitLane ? 2.5 : 1.4, lineCap: .butt))
                }
                
                if hasOutgoing {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: centerY))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(laneColor.opacity(isCommitLane ? 1.0 : 0.4)), style: StrokeStyle(lineWidth: isCommitLane ? 2.5 : 1.4, lineCap: .butt))
                }
            }

            for edge in commit.outgoingEdges where edge.from != edge.to {
                let startX = laneX(edge.from) + safePadding
                let endX = laneX(edge.to) + safePadding
                var edgePath = Path()
                edgePath.move(to: CGPoint(x: startX, y: centerY))
                edgePath.addCurve(to: CGPoint(x: endX, y: size.height), control1: CGPoint(x: startX, y: centerY + 18), control2: CGPoint(x: endX, y: centerY + 10))
                context.stroke(edgePath, with: .color(color(forKey: edge.colorKey).opacity(0.8)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
            }

            let x = laneX(commit.lane) + safePadding
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
        .frame(width: max(CGFloat(max(laneCount, 1)) * laneSpacing + (safePadding * 2), 84), height: height)
    }

    private func laneX(_ lane: Int) -> CGFloat { CGFloat(lane) * laneSpacing + 4 }
    private func color(forKey key: Int) -> Color {
        if key < colorPalette.count { return colorPalette[key] }
        let hue = Double((key * 137) % 360) / 360.0
        return Color(hue: hue, saturation: 0.80, brightness: 0.95)
    }
}
