import SwiftUI

struct OpsMaintenanceCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void

    var body: some View {
        GlassCard(spacing: 12, borderTint: DesignSystem.Colors.dangerBorder) {
            CardHeader(L10n("Limpeza"), icon: "leaf.fill", subtitle: L10n("Remover branches locais que ja foram mescladas na main."))

            Button(action: {
                let count = model.mergedBranchesPreview.count
                let message = count == 0
                    ? L10n("prune.merged.confirm.empty")
                    : L10n("prune.merged.confirm.withCount", "\(count)")
                performGitAction(L10n("Prune"), message, true) {
                    model.pruneMergedBranches()
                }
            }) {
                Label(L10n("Prune Merged"), systemImage: "broom.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large)

            Divider().opacity(0.3)

            CardHeader(L10n("Danger Zone"), icon: "exclamationmark.octagon.fill")
                .foregroundStyle(DesignSystem.Colors.destructive)

            Text(L10n("CUIDADO: Operacoes de reset descartam alteracoes."))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.destructiveMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                TextField("HEAD~1", text: $model.resetTargetInput).textFieldStyle(.roundedBorder)
                    .help(L10n("Referencia do commit (ex: HEAD~1, hash, branch)"))
                Button(role: .destructive) {
                    let target = model.resetTargetInput.clean.isEmpty ? "HEAD" : model.resetTargetInput.clean
                    let message = L10n("reset.hard.confirm.withCount", target, "\(model.uncommittedCount)")
                    performGitAction(L10n("Reset --hard"), message, true) { model.hardReset() }
                } label: { Label(L10n("Reset --hard"), systemImage: "trash.fill") }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive)
                    .help(L10n("Descartar TODAS as alteracoes e voltar ao commit informado"))
            }
        }
    }
}
