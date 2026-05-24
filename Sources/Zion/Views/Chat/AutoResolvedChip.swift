import SwiftUI

// MARK: - AutoResolvedChip
// Shown in the composer area only when the selected provider is .auto AND the
// orchestrator has resolved a concrete provider for the latest send.
// Tells the user "Auto → Claude" so the routing is transparent.

struct AutoResolvedChip: View {

    @Bindable var chat: ChatService
    @AppStorage(UserDefaultsKeys.AI.provider) private var providerRaw: String = AIProvider.none.rawValue

    private var isAuto: Bool {
        (AIProvider(rawValue: providerRaw) ?? .none) == .auto
    }

    var body: some View {
        if isAuto, let resolved = chat.resolvedProvider {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "arrow.triangle.branch")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.ai)
                Text(L10n("chat.auto.resolvedChip", resolved.label)) // MARK: - TODO(P14:T10): L10n
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(Capsule().fill(DesignSystem.Colors.glassSubtle))
        }
    }
}
