import SwiftUI

/// Compact CPU + Memory pill rendered in the macOS title-bar toolbar.
/// Opt-in via the `topbar.systemMonitor.enabled` UserDefaults flag (default
/// off). The pill auto-tints amber / red as load increases so the user gets a
/// peripheral hint without having to read the digits.
struct TopBarSystemMonitorPill: View {

    @State private var monitor = SystemMonitor()

    var body: some View {
        HStack(spacing: 6) {
            metric(label: "CPU", value: monitor.cpuLoad)
            Text("·").foregroundStyle(.tertiary)
            metric(label: "RAM", value: monitor.memoryPressure)
        }
        .padding(.horizontal, DesignSystem.Spacing.toolbarItemGap)
        .fixedSize()
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .help(L10n("topbar.systemMonitor.help"))
    }

    @ViewBuilder
    private func metric(label: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(.secondary)
            Text("\(Int(value * 100))%")
                .font(DesignSystem.Typography.meta.monospacedDigit())
                .foregroundStyle(loadColor(value))
        }
    }

    private func loadColor(_ value: Double) -> Color {
        switch value {
        case ..<0.6:  return .primary
        case ..<0.85: return DesignSystem.Colors.warning
        default:      return DesignSystem.Colors.destructive
        }
    }
}
