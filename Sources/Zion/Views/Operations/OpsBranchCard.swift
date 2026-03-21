import SwiftUI

struct OpsBranchCard: View {
    @Bindable var model: RepositoryViewModel
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    let branchContextMenu: (String) -> AnyView

    var body: some View {
        GlassCard(spacing: 12, expanding: true) {
            CardHeader(L10n("Branches"), icon: "arrow.triangle.branch", subtitle: L10n("Checkout e integracao"))

            VStack(spacing: 10) {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n("Selecionar branch ou hash..."), text: $model.branchInput)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.monoBody)
                }
                .padding(8).background(DesignSystem.Colors.glassInset).clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))

                HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                    Button(action: {
                        performGitAction(L10n("Checkout"), L10n("Fazer checkout da referencia informada?"), false) {
                            model.checkoutBranch()
                        }
                    }) {
                        Label(L10n("Checkout"), systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).tint(DesignSystem.Colors.actionPrimary)

                    Button(action: {
                        performGitAction(L10n("Merge into Current"), L10n("Fazer merge da branch informada na atual?"), false) {
                            model.mergeBranch()
                        }
                    }) {
                        Label(L10n("Merge into Current"), systemImage: "arrow.merge").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large)
                }
            }

            branchListView
        }
    }

    private var branchListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n("Branches locais/remotas")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
            if model.branchInfos.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(DesignSystem.Typography.sheetTitle).foregroundStyle(.secondary)
                    Text(L10n("Nenhuma branch encontrada")).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                    Text(L10n("branches.emptyHint")).font(DesignSystem.Typography.meta).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius).stroke(DesignSystem.Colors.glassStroke, lineWidth: 1))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.branchInfos) { branch in
                            Button {
                                model.branchInput = branch.name
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        if branch.name == model.currentBranch {
                                            Image(systemName: "checkmark.circle.fill").font(DesignSystem.Typography.meta).foregroundStyle(DesignSystem.Colors.success)
                                        }
                                        Text(branch.name).font(DesignSystem.Typography.monoLabel)
                                            .fontWeight(branch.name == model.currentBranch ? .bold : .regular)
                                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                        if branch.isRemote { Image(systemName: "icloud").font(DesignSystem.Typography.meta).foregroundStyle(.secondary) }
                                    }
                                    Text(L10n("ops.branch.head", branch.shortHead)).font(DesignSystem.Typography.meta).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onTapGesture(count: 2) {
                                performGitAction(L10n("Checkout branch"), L10n("Fazer checkout da branch %@?", branch.name), false) {
                                    model.checkout(reference: branch.name)
                                }
                            }
                            .contextMenu { branchContextMenu(branch.name) }
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius).stroke(DesignSystem.Colors.glassStroke, lineWidth: 1))
            }
        }
    }
}
