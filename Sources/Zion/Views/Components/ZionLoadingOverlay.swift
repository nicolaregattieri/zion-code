import SwiftUI

struct ZionLoadingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(DesignSystem.Colors.glassInset)

            VStack(spacing: DesignSystem.Spacing.smallCornerRadius) {
                zionLoader

                Text(L10n("switch.overlay.loading"))
                    .font(DesignSystem.Typography.bodyMedium)
                    .foregroundStyle(DesignSystem.Colors.brandWhite.opacity(0.78))
            }
            .padding(.horizontal, DesignSystem.Spacing.cardPadding)
            .padding(.vertical, DesignSystem.Spacing.smallCornerRadius)
            .shadow(color: DesignSystem.Colors.shadowDark, radius: 8, y: 2)
        }
        .transition(DesignSystem.Motion.fade)
    }

    private var zionLoader: some View {
        ZStack {
            ZionTriangle()
                .stroke(
                    DesignSystem.Colors.glassBorderDark,
                    style: StrokeStyle(lineWidth: 2.25, lineJoin: .round)
                )
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            ZionTriangle()
                .stroke(
                    DesignSystem.Colors.brandWhite.opacity(0.92),
                    style: StrokeStyle(
                        lineWidth: 2.25,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .opacity(0.24)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            triangleLaserOrbit
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            ZionMountainFaceted()
                .frame(width: 56, height: 44)
                .offset(y: 9)
                .accessibilityHidden(true)
        }
        .frame(width: 72, height: 72)
        .drawingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n("switch.overlay.loading"))
    }

    @ViewBuilder
    private var triangleLaserOrbit: some View {
        if reduceMotion {
            ZionTriangle()
                .trim(from: 0.02, to: 0.17)
                .stroke(
                    DesignSystem.Colors.brandWhite.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2.45, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: DesignSystem.Colors.brandWhite.opacity(0.25), radius: 2, y: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let phase = orbitPhase(for: context.date)
                ZStack {
                    triangleLaserSegment(start: phase, length: 0.16)
                    triangleLaserSegment(start: phase - 1, length: 0.16)
                }
            }
        }
    }

    private func orbitPhase(for date: Date) -> CGFloat {
        let cycle: TimeInterval = 1.1
        let t = date.timeIntervalSinceReferenceDate
        let normalized = (t.remainder(dividingBy: cycle) + cycle).remainder(dividingBy: cycle) / cycle
        return CGFloat(normalized)
    }

    @ViewBuilder
    private func triangleLaserSegment(start: CGFloat, length: CGFloat) -> some View {
        let from = max(0, start)
        let to = min(1, start + length)
        if to > from {
            ZionTriangle()
                .trim(from: from, to: to)
                .stroke(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.brandWhite.opacity(0.02),
                            DesignSystem.Colors.brandWhite.opacity(0.45),
                            DesignSystem.Colors.brandWhite.opacity(1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.55, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: DesignSystem.Colors.brandWhite.opacity(0.6), radius: 3, y: 0)
        }
    }
}

private struct ZionTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let sqrt3 = CGFloat(3.0.squareRoot())
        let side = min(rect.width, rect.height * 2 / sqrt3)
        let triangleHeight = side * sqrt3 / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let top = CGPoint(x: center.x, y: center.y - triangleHeight / 2)
        let left = CGPoint(x: center.x - side / 2, y: center.y + triangleHeight / 2)
        let right = CGPoint(x: center.x + side / 2, y: center.y + triangleHeight / 2)

        var p = Path()
        p.move(to: top)
        p.addLine(to: right)
        p.addLine(to: left)
        p.closeSubpath()
        return p
    }
}

private struct ZionMountainFaceted: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Base silhouette
                Path { p in
                    p.move(to: CGPoint(x: 0.0 * w, y: 1.0 * h))
                    p.addLine(to: CGPoint(x: 0.13 * w, y: 0.74 * h))
                    p.addLine(to: CGPoint(x: 0.27 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
                    p.addLine(to: CGPoint(x: 0.73 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.87 * w, y: 0.74 * h))
                    p.addLine(to: CGPoint(x: 1.00 * w, y: 1.0 * h))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.brandWhite.opacity(0.88),
                            DesignSystem.Colors.brandLight.opacity(0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Top strong triangle
                Path { p in
                    p.move(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
                    p.addLine(to: CGPoint(x: 0.63 * w, y: 0.49 * h))
                    p.addLine(to: CGPoint(x: 0.37 * w, y: 0.49 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.93))

                // Center lozenge facet
                Path { p in
                    p.move(to: CGPoint(x: 0.37 * w, y: 0.49 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.69 * h))
                    p.addLine(to: CGPoint(x: 0.63 * w, y: 0.49 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.42 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.55))

                // Left shoulder triangle
                Path { p in
                    p.move(to: CGPoint(x: 0.27 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.37 * w, y: 0.49 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.69 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.66))

                // Right shoulder triangle
                Path { p in
                    p.move(to: CGPoint(x: 0.73 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.63 * w, y: 0.49 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.69 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.60))

                // Side lozenges
                Path { p in
                    p.move(to: CGPoint(x: 0.13 * w, y: 0.74 * h))
                    p.addLine(to: CGPoint(x: 0.27 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.23 * w, y: 0.76 * h))
                    p.addLine(to: CGPoint(x: 0.09 * w, y: 0.90 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.78))

                Path { p in
                    p.move(to: CGPoint(x: 0.87 * w, y: 0.74 * h))
                    p.addLine(to: CGPoint(x: 0.73 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.77 * w, y: 0.76 * h))
                    p.addLine(to: CGPoint(x: 0.91 * w, y: 0.90 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.74))

                // Lower base plate
                Path { p in
                    p.move(to: CGPoint(x: 0.04 * w, y: 0.94 * h))
                    p.addLine(to: CGPoint(x: 0.96 * w, y: 0.94 * h))
                    p.addLine(to: CGPoint(x: 0.90 * w, y: 1.00 * h))
                    p.addLine(to: CGPoint(x: 0.10 * w, y: 1.00 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.30))

                // Facet lines to approximate logo geometry
                Path { p in
                    p.move(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.69 * h))
                    p.move(to: CGPoint(x: 0.27 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.73 * w, y: 0.54 * h))
                    p.move(to: CGPoint(x: 0.37 * w, y: 0.49 * h))
                    p.addLine(to: CGPoint(x: 0.27 * w, y: 0.54 * h))
                    p.move(to: CGPoint(x: 0.63 * w, y: 0.49 * h))
                    p.addLine(to: CGPoint(x: 0.73 * w, y: 0.54 * h))
                    p.move(to: CGPoint(x: 0.13 * w, y: 0.74 * h))
                    p.addLine(to: CGPoint(x: 0.23 * w, y: 0.76 * h))
                    p.addLine(to: CGPoint(x: 0.27 * w, y: 0.54 * h))
                    p.move(to: CGPoint(x: 0.87 * w, y: 0.74 * h))
                    p.addLine(to: CGPoint(x: 0.77 * w, y: 0.76 * h))
                    p.addLine(to: CGPoint(x: 0.73 * w, y: 0.54 * h))
                }
                .stroke(DesignSystem.Colors.brandWhite.opacity(0.30), lineWidth: 1)
            }
        }
    }
}
