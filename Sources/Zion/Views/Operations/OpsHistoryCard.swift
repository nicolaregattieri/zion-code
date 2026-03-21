import SwiftUI

struct OpsHistoryCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void

    var body: some View {
        GlassCard(spacing: 10, expanding: true) {
            CardHeader(L10n("Reescrita"), icon: "arrow.triangle.branch", subtitle: L10n("Rebase e cherry-pick"))
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                TextField(L10n("rebase target"), text: $model.rebaseTargetInput).textFieldStyle(.roundedBorder)
                    .help(L10n("Nome da branch ou commit onde rebasear (ex: main, origin/main)"))
                Button(L10n("Rebase")) { performGitAction(L10n("Rebase"), L10n("Rebasear a branch atual no target informado?"), true) { model.rebaseOntoTarget() } }.buttonStyle(.bordered).tint(DesignSystem.Colors.warning)
                    .help(L10n("Replay seus commits em cima da branch informada"))
            }
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                TextField(L10n("cherry-pick hash"), text: $model.cherryPickInput).textFieldStyle(.roundedBorder)
                    .help(L10n("Hash do commit a aplicar (ex: a1b2c3d)"))
                Button(L10n("Cherry-pick")) { performGitAction(L10n("Cherry-pick"), L10n("Aplicar o commit informado na branch atual?"), false) { model.cherryPick() } }.buttonStyle(.borderedProminent).tint(DesignSystem.Colors.actionPrimary)
                    .help(L10n("Copiar um commit de outra branch para a branch atual"))
            }
        }
    }
}
