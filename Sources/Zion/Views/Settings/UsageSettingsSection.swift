import SwiftUI

// MARK: - UsageSettingsSection
// Monthly breakdown of provider × model spend + soft-cap stepper.
// Reads from SpendLedger.shared each time the view appears.

struct UsageSettingsSection: View {

    @AppStorage("chat.spend.softCapUSD") private var softCapUSD: Int = 0  // 0 = no cap
    @State private var rows: [ProviderSpendRow] = []

    var body: some View {
        Section(L10n("chat.spend.usage.section.title")) {
            Text(L10n("chat.spend.usage.honestyBanner"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.warning)

            Stepper(value: $softCapUSD, in: 0...500, step: 5) {
                HStack {
                    Text(L10n("chat.spend.usage.softCap"))
                    Spacer()
                    Text(softCapUSD == 0 ? L10n("chat.spend.usage.softCap.off") : "$\(softCapUSD)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if rows.isEmpty {
                Text(L10n("chat.spend.usage.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text("\(row.provider) · \(row.model)")
                            .font(DesignSystem.Typography.monoLabel)
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

    private func reload() async {
        rows = (try? await SpendLedger.shared.monthlyTotals(forMonth: Date())) ?? []
    }
}
