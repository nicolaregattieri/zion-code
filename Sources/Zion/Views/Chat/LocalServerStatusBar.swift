import SwiftUI

/// Live status bar shown above the Zion Talks composer when a local LLM
/// server is running (or known to be reachable). Surfaces:
///   - active model id (from `LocalLLMConfig`)
///   - system memory pressure %
///   - server RSS in GB when known
///   - a one-click "Disconnect" button that calls `LocalServerLauncher.stop`.
///
/// Zion NEVER auto-disconnects. The user is the only authority over local-server
/// lifetime; this view just gives them the affordance to do it in one click,
/// even mid-stream.
struct LocalServerStatusBar: View {

    let model: LocalServerStatusBar.Model
    let onDisconnect: () -> Void

    struct Model: Equatable {
        var modelName: String
        var systemPressure: Double       // 0...1
        var totalBytes: UInt64
        var usedBytes: UInt64
        var serverRSSBytes: UInt64?
        var isStreaming: Bool
        /// Label of the provider that handled the last turn, when it was NOT
        /// the local server (e.g. "Claude CLI"). The user reported confusion
        /// (Image #32): memory bar shows RSS while the chat chip shows Claude
        /// — they assume local was used. Surfacing "Idle · Last turn: Claude
        /// CLI" makes it explicit that the server is warm but unused this
        /// turn. Nil = local handled the last turn (or no turn happened yet).
        var idleLastProviderLabel: String?
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.modelName)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.primary)
                    if let rss = model.serverRSSBytes {
                        Text("· \(MemoryMonitor.formatBytes(rss))")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let lastProvider = model.idleLastProviderLabel, !model.isStreaming {
                        Text("· " + String(format: L10n("chat.local.status.idleLastTurn"), lastProvider))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .help(L10n("chat.local.status.idleLastTurn.help"))
                    }
                }
                HStack(spacing: 6) {
                    Text(L10n("chat.local.status.systemPressure"))
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(.secondary)
                    Text("\(Int(model.systemPressure * 100))%")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(pressureColor)
                        .monospacedDigit()
                    Text("· \(MemoryMonitor.formatBytes(model.usedBytes)) / \(MemoryMonitor.formatBytes(model.totalBytes))")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .help(L10n("chat.local.status.memory.help"))
            }

            Spacer(minLength: 8)

            disconnectButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 0.5)
        )
    }

    private var statusDot: some View {
        // The status bar is only mounted when a local server is reachable, so
        // the dot is always the "connected" color (green). Streaming animates
        // the dot via a subtle pulse; idle stays solid green. Previously the
        // dot was grey when not streaming, which read as "disconnected" even
        // though the Disconnect button next to it implied the opposite.
        Circle()
            .fill(DesignSystem.Colors.success)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(DesignSystem.Colors.glassOverlay, lineWidth: 0.5)
            )
            .modifier(PulsingIfStreaming(isStreaming: model.isStreaming))
    }
}

private struct PulsingIfStreaming: ViewModifier {
    let isStreaming: Bool
    @State private var phase: Double = 1.0

    func body(content: Content) -> some View {
        if isStreaming {
            content
                .scaleEffect(phase)
                .opacity(2 - phase)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: phase
                )
                .onAppear { phase = 1.35 }
                .onDisappear { phase = 1.0 }
        } else {
            content
        }
    }
}

private extension LocalServerStatusBar {

    private var pressureColor: Color {
        switch model.systemPressure {
        case ..<0.6:  return .secondary
        case ..<0.85: return DesignSystem.Colors.warning
        default:      return DesignSystem.Colors.destructive
        }
    }

    private var disconnectButton: some View {
        Button(action: onDisconnect) {
            HStack(spacing: 4) {
                Image(systemName: "power")
                Text(L10n("chat.local.status.disconnect"))
            }
            .font(DesignSystem.Typography.label)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.destructive.opacity(0.15))
            )
            .foregroundStyle(DesignSystem.Colors.destructive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.local.status.disconnect.help"))
    }
}

#if DEBUG
struct LocalServerStatusBar_Previews: PreviewProvider {
    static var previews: some View {
        LocalServerStatusBar(
            model: .init(
                modelName: "qwen3-coder:30b",
                systemPressure: 0.72,
                totalBytes: 64 * 1024 * 1024 * 1024,
                usedBytes: 46 * 1024 * 1024 * 1024,
                serverRSSBytes: 18 * 1024 * 1024 * 1024,
                isStreaming: true
            ),
            onDisconnect: {}
        )
        .padding()
        .frame(width: 480)
    }
}
#endif
