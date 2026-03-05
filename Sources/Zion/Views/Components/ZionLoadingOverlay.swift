import SwiftUI

struct ZionLoadingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var laserRotation: Double = 0

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
        .onAppear {
            guard !reduceMotion else { return }
            laserRotation = 0
            withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                laserRotation = 360
            }
        }
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
            EmptyView()
        } else {
            ZionTriangle()
                .trim(from: 0.02, to: 0.17)
                .stroke(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.brandWhite.opacity(0.06),
                            DesignSystem.Colors.brandWhite.opacity(0.52),
                            DesignSystem.Colors.brandWhite.opacity(1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.55, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: DesignSystem.Colors.brandWhite.opacity(0.58), radius: 3, y: 0)
                .rotationEffect(.degrees(laserRotation))
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

                // Lower base plate
                Path { p in
                    p.move(to: CGPoint(x: 0.04 * w, y: 0.94 * h))
                    p.addLine(to: CGPoint(x: 0.96 * w, y: 0.94 * h))
                    p.addLine(to: CGPoint(x: 0.90 * w, y: 1.00 * h))
                    p.addLine(to: CGPoint(x: 0.10 * w, y: 1.00 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.30))

                // Top facets
                Path { p in
                    p.move(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
                    p.addLine(to: CGPoint(x: 0.56 * w, y: 0.48 * h))
                    p.addLine(to: CGPoint(x: 0.72 * w, y: 0.54 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.58))

                Path { p in
                    p.move(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
                    p.addLine(to: CGPoint(x: 0.44 * w, y: 0.48 * h))
                    p.addLine(to: CGPoint(x: 0.28 * w, y: 0.54 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.64))

                Path { p in
                    p.move(to: CGPoint(x: 0.44 * w, y: 0.48 * h))
                    p.addLine(to: CGPoint(x: 0.56 * w, y: 0.48 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.70 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.46))

                // Side facets
                Path { p in
                    p.move(to: CGPoint(x: 0.72 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.84 * w, y: 0.78 * h))
                    p.addLine(to: CGPoint(x: 1.00 * w, y: 1.00 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.70))

                Path { p in
                    p.move(to: CGPoint(x: 0.28 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.16 * w, y: 0.78 * h))
                    p.addLine(to: CGPoint(x: 0.00 * w, y: 1.00 * h))
                    p.closeSubpath()
                }
                .fill(DesignSystem.Colors.brandWhite.opacity(0.74))

                // Facet lines to approximate logo geometry
                Path { p in
                    p.move(to: CGPoint(x: 0.50 * w, y: 0.02 * h))
                    p.addLine(to: CGPoint(x: 0.50 * w, y: 0.70 * h))
                    p.move(to: CGPoint(x: 0.28 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.72 * w, y: 0.54 * h))
                    p.move(to: CGPoint(x: 0.44 * w, y: 0.48 * h))
                    p.addLine(to: CGPoint(x: 0.28 * w, y: 0.54 * h))
                    p.move(to: CGPoint(x: 0.56 * w, y: 0.48 * h))
                    p.addLine(to: CGPoint(x: 0.72 * w, y: 0.54 * h))
                    p.move(to: CGPoint(x: 0.72 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.84 * w, y: 0.78 * h))
                    p.move(to: CGPoint(x: 0.28 * w, y: 0.54 * h))
                    p.addLine(to: CGPoint(x: 0.16 * w, y: 0.78 * h))
                }
                .stroke(DesignSystem.Colors.brandWhite.opacity(0.30), lineWidth: 1)
            }
        }
    }
}
