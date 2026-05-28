import SwiftUI

/// Phase 6 — per-message auto-context controls. Lives separately from
/// `RAGSettingsSection` (which owns infra: hybrid toggle, reindex,
/// Qodo). This section owns BEHAVIOR: whether the chat surface
/// silently pre-fetches context before each message and how much
/// budget that injection may consume.
struct ChatContextSettingsSection: View {

    @AppStorage("chat.context.autoEnabled") private var autoEnabled: Bool = true
    @AppStorage("chat.context.budgetTokens") private var budgetTokens: Int = Constants.RAG.autoBudgetTokensCheap

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            Text(L10n("chat.context.settings.section.title"))
                .font(DesignSystem.Typography.sheetTitle)

            Toggle(L10n("chat.context.settings.autoToggle"), isOn: $autoEnabled)
                .tint(DesignSystem.Colors.ai)

            Text(L10n("chat.context.settings.autoHelp"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)

            if autoEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("chat.context.settings.budgetLabel"))
                        .font(DesignSystem.Typography.label)
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(budgetTokens) },
                                set: { budgetTokens = Int($0) }
                            ),
                            in: 500...4000,
                            step: 250
                        )
                        Text(String(format: L10n("chat.context.settings.budgetUnit"), budgetTokens))
                            .font(DesignSystem.Typography.monoLabel)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
    }
}
