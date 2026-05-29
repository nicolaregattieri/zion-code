import SwiftUI

// MARK: - UsageSettingsSection
// Monthly breakdown of provider × model spend + soft-cap toggle/stepper.
// Reads from SpendLedger.shared each time the view appears.

struct UsageSettingsSection: View {

    @AppStorage("chat.spend.softCapUSD") private var softCapUSD: Int = 0  // 0 = no cap
    @State private var rows: [ProviderSpendRow] = []

    private var isSoftCapEnabled: Bool {
        softCapUSD > 0
    }

    var body: some View {
        Section(L10n("chat.spend.usage.section.title")) {
            Text(L10n("chat.spend.usage.honestyBanner"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.warning)

            Toggle(L10n("chat.spend.usage.softCap"), isOn: Binding(
                get: { isSoftCapEnabled },
                set: { enabled in
                    softCapUSD = enabled ? Constants.Limits.spendSoftCapDefaultUSD : 0
                }
            ))

            if isSoftCapEnabled {
                Stepper(
                    value: $softCapUSD,
                    in: Constants.Limits.spendSoftCapStepUSD...Constants.Limits.spendSoftCapMaxUSD,
                    step: Constants.Limits.spendSoftCapStepUSD
                ) {
                    HStack {
                        Text(L10n("chat.spend.usage.softCap.amount"))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("$\(softCapUSD)")
                            .font(DesignSystem.Typography.bodySemibold)
                            .monospacedDigit()
                    }
                }
            }

            if rows.isEmpty {
                Text(L10n("chat.spend.usage.empty"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Text(providerLabel(for: row.provider))
                            .font(DesignSystem.Typography.body)
                        Text("·")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.tertiary)
                        Text(row.model)
                            .font(DesignSystem.Typography.monoLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("$\(String(format: "%.3f", row.usdCost))")
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Text(L10n("chat.spend.usage.resetsFooter"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
        }
        .task { await reload() }
    }

    /// Map the raw provider string stored in `ProviderSpendRow` to the
    /// user-facing label from `AIProvider`. Falls back to the raw value when
    /// the ledger holds a provider tag that does not match any known enum
    /// case (older rows, etc.).
    private func providerLabel(for raw: String) -> String {
        AIProvider(rawValue: raw)?.label ?? raw
    }

    private func reload() async {
        rows = (try? await SpendLedger.shared.monthlyTotals(forMonth: Date())) ?? []
    }
}
