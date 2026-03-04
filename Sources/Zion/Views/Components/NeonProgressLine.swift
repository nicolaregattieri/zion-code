import SwiftUI

struct NeonProgressLine: View {
    enum Mode {
        case shimmer
        case pulse
        case `static`
    }

    var gradient: LinearGradient = DesignSystem.ZionMode.neonGradient
    var mode: Mode = .shimmer
    var height: CGFloat = DesignSystem.ZionMode.neonLineHeight

    @Environment(\.zionModeEnabled) private var zionModeEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shimmerPhase: CGFloat = 0
    @State private var pulseOpacity: Double = 0.4
    @State private var pulseGradientShift: CGFloat = 0

    private var activeGradient: LinearGradient {
        zionModeEnabled ? gradient : DesignSystem.Colors.brandGradient
    }

    private var glowColor: SwiftUI.Color {
        zionModeEnabled ? DesignSystem.ZionMode.neonMagenta : DesignSystem.Colors.brandPrimary
    }

    var body: some View {
        gradientBar
            .frame(height: height)
            .clipShape(Capsule())
            .shadow(
                color: glowColor.opacity(DesignSystem.ZionMode.neonGlowOpacity),
                radius: DesignSystem.ZionMode.neonGlowBlur,
                y: 1
            )
            .onAppear { startAnimation() }
    }

    @ViewBuilder
    private var gradientBar: some View {
        let effectiveMode = reduceMotion ? .static : mode

        switch effectiveMode {
        case .shimmer:
            activeGradient
                .overlay(shimmerOverlay)

        case .pulse:
            LinearGradient(
                colors: [
                    DesignSystem.ZionMode.neonGold,
                    DesignSystem.ZionMode.neonMagenta
                ],
                startPoint: UnitPoint(x: pulseGradientShift, y: 0.5),
                endPoint: UnitPoint(x: 1.0 + pulseGradientShift, y: 0.5)
            )
            .opacity(pulseOpacity)

        case .static:
            activeGradient
                .opacity(DesignSystem.Opacity.visible)
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let bandWidth = geo.size.width * 0.3
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: bandWidth)
                .offset(x: shimmerPhase * (geo.size.width + bandWidth) - bandWidth)
        }
        .clipped()
    }

    private func startAnimation() {
        guard !reduceMotion else { return }

        switch mode {
        case .shimmer:
            shimmerPhase = 0
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }

        case .pulse:
            pulseOpacity = 0.4
            pulseGradientShift = 0
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.9
            }
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: true)) {
                pulseGradientShift = 0.5
            }

        case .static:
            break
        }
    }
}
