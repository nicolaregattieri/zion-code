import SwiftUI

/// One-time banner offering to start the local LLM server for Smart Auto.
///
/// Shown when ALL of these are true:
///   - The user has Auto mode selected.
///   - A `LocalLLMConfig` exists (engine != .custom).
///   - The local server is NOT currently reachable.
///   - The user has not opted out (`LocalAutoStartPolicy.current() == .ask`).
///
/// Four buttons:
///   - **Start once** — spawn now; policy stays `.ask`.
///   - **Always start** — spawn now; policy → `.always`.
///   - **Not now** — dismiss for the session.
///   - **Never ask** — policy → `.never`, never show again.
///
/// Zion NEVER auto-spawns the local server. Every spawn is gated by a click here
/// or by the user's pre-recorded `.always` choice.
struct LocalAutoStartBanner: View {

    let modelName: String
    let onStartOnce: () -> Void
    let onStartAlways: () -> Void
    let onDismiss: () -> Void
    let onNever: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "bolt.fill")
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundStyle(.yellow)
                Text(L10n("chat.local.autostart.banner.title"))
                    .font(DesignSystem.Typography.bodySemibold)
            }
            Text(String(format: L10n("chat.local.autostart.banner.subtitle"), modelName))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            HStack(spacing: DesignSystem.Spacing.compact) {
                Button(L10n("chat.local.autostart.banner.startOnce"), action: onStartOnce)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L10n("chat.local.autostart.banner.startAlways"), action: onStartAlways)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button(L10n("chat.local.autostart.banner.notNow"), action: onDismiss)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Button(L10n("chat.local.autostart.banner.never"), action: onNever)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.red)
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 0.5)
        )
    }
}
