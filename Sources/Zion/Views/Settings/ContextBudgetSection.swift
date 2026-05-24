import SwiftUI

// MARK: - ContextBudgetSection
// Embedded by ZionTalksSettingsTab inside its Form, after SmartContextSettingsSection.
// Returns a Section — do NOT wrap in Form.
// MARK: - TODO(T11): L10n — new keys below need locale entries

struct ContextBudgetSection: View {
    @AppStorage("chat.contextBudget.responseReserve") private var responseReserve: Int = 16_000

    var body: some View {
        Section(L10n("chat.contextBudget.section.title")) {
            Stepper(value: $responseReserve, in: 4_000...64_000, step: 1_000) {
                HStack {
                    Text(L10n("chat.contextBudget.responseReserve"))
                    Spacer()
                    Text("\(responseReserve) tok")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Text(L10n("chat.contextBudget.responseReserve.hint"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
            // Stats footer (window utilization, last compaction timestamp) — T12 polish pass.
        }
    }
}
