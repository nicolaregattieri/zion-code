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
        Circle()
            .fill(model.isStreaming ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(DesignSystem.Colors.glassOverlay, lineWidth: 0.5)
            )
    }

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
