import SwiftUI

// MARK: - SpendMeterPill
// Header pill showing monthly spend across all configured providers.
// API providers show $X.XX; subscription providers (Claude CLI / Codex CLI) show a badge;
// local providers (Ollama / MLX) show $0; empty ledger shows a "no spend yet" hint.

struct SpendMeterPill: View {

    @State private var displayMode: DisplayMode = .empty

    enum DisplayMode: Equatable {
        case api(Double)         // monthly USD aggregate across API providers
        case subscription
        case local
        case empty
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            switch displayMode {
            case .api(let total):
                Text("$\(String(format: "%.2f", total))")
                    .font(DesignSystem.Typography.monoLabelBold)
                Text(L10n("chat.spend.pill.month")) // MARK: - TODO(P14:T10): L10n
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            case .subscription:
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(DesignSystem.Colors.success)
                Text(L10n("chat.spend.pill.subscription")) // MARK: - TODO(P14:T10): L10n
                    .font(DesignSystem.Typography.metaSemibold)
            case .local:
                Image(systemName: "desktopcomputer")
                Text(L10n("chat.spend.pill.local")) // MARK: - TODO(P14:T10): L10n
                    .font(DesignSystem.Typography.metaSemibold)
            case .empty:
                Text(L10n("chat.spend.pill.empty")) // MARK: - TODO(P14:T10): L10n
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, DesignSystem.Spacing.micro)
        .background(Capsule().fill(DesignSystem.Colors.glassSubtle))
        .task { await reload() }
    }

    private func reload() async {
        guard let rows = try? await SpendLedger.shared.monthlyTotals(forMonth: Date()) else {
            displayMode = .empty
            return
        }
        let apiTotal = rows.filter { $0.billingMode == .api }.reduce(0.0) { $0 + $1.usdCost }
        if apiTotal > 0 {
            displayMode = .api(apiTotal)
        } else if rows.contains(where: { $0.billingMode == .subscription }) {
            displayMode = .subscription
        } else if rows.contains(where: { $0.billingMode == .local }) {
            displayMode = .local
        } else {
            displayMode = .empty
        }
    }
}
