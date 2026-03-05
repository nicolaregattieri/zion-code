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
                .frame(width: 58, height: 45)
                .offset(y: 8.5)
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
    private static let logoImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "zion-logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        GeometryReader { geo in
            if let logo = Self.logoImage {
                // Reuse the canonical logo texture and crop to the mountain silhouette for exact fidelity.
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: geo.size.width * 1.44, height: geo.size.width * 1.44)
                    .offset(y: geo.size.height * 0.22)
                    .mask(ZionMountainMask())
            } else {
                ZionMountainFallback()
            }
        }
    }
}

private struct ZionMountainMask: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0.0 * w, y: 1.0 * h))
        p.addLine(to: CGPoint(x: 0.14 * w, y: 0.73 * h))
        p.addLine(to: CGPoint(x: 0.28 * w, y: 0.54 * h))
        p.addLine(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
        p.addLine(to: CGPoint(x: 0.72 * w, y: 0.54 * h))
        p.addLine(to: CGPoint(x: 0.86 * w, y: 0.73 * h))
        p.addLine(to: CGPoint(x: 1.00 * w, y: 1.0 * h))
        p.closeSubpath()
        return p
    }
}

private struct ZionMountainFallback: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0.0 * w, y: 1.0 * h))
                    p.addLine(to: CGPoint(x: 0.14 * w, y: 0.73 * h))
                    p.addLine(to: CGPoint(x: 0.28 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
                    p.addLine(to: CGPoint(x: 0.72 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.86 * w, y: 0.73 * h))
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
            }
        }
    }
}
