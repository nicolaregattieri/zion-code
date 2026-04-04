import SwiftUI

struct LiquidBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.zionModeEnabled) private var zionMode
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var phase: Bool = false
    @State private var isAnimating: Bool = false

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                if zionMode {
                    // Zion Mode: deep purple base with neon orbs
                    DesignSystem.ZionMode.neonBaseDark.ignoresSafeArea()
                    Circle()
                        .fill(DesignSystem.ZionMode.neonMagenta.opacity(phase ? 0.20 : 0.16))
                        .frame(width: 600).blur(radius: 100)
                        .offset(x: phase ? -310 : -370, y: phase ? -200 : -240)
                    Circle()
                        .fill(DesignSystem.ZionMode.neonCyan.opacity(phase ? 0.15 : 0.11))
                        .frame(width: 500).blur(radius: 90)
                        .offset(x: phase ? 310 : 260, y: phase ? -260 : -300)
                    Circle()
                        .fill(DesignSystem.ZionMode.neonGold.opacity(phase ? 0.08 : 0.05))
                        .frame(width: 350).blur(radius: 70)
                        .offset(x: phase ? 280 : 320, y: phase ? 220 : 260)
                } else {
                    Color(red: 0.05, green: 0.02, blue: 0.10).ignoresSafeArea()
                    Circle()
                        .fill(DesignSystem.Colors.brandPrimary.opacity(phase ? 0.17 : 0.14))
                        .frame(width: 520).blur(radius: 80)
                        .offset(x: phase ? -310 : -370, y: phase ? -200 : -240)
                    Circle()
                        .fill(DesignSystem.Colors.brandInk.opacity(0.12))
                        .frame(width: 420).blur(radius: 70)
                        .offset(x: phase ? 310 : 260, y: phase ? -260 : -300)
                }
            } else {
                Color(red: 0.96, green: 0.94, blue: 1.00).ignoresSafeArea()
                Circle()
                    .fill(DesignSystem.Colors.brandPrimary.opacity(phase ? 0.12 : 0.09))
                    .frame(width: 520).blur(radius: 80)
                    .offset(x: phase ? -310 : -370, y: phase ? -200 : -240)
            }
        }
        .drawingGroup()
        .onAppear { startAnimation() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onChange(of: controlActiveState) { _, newState in
            if newState == .key {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    private func startAnimation() {
        guard !isAnimating else { return }
        guard scenePhase == .active, controlActiveState == .key else { return }
        isAnimating = true
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
            phase.toggle()
        }
    }

    private func stopAnimation() {
        isAnimating = false
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = false
        }
    }
}
