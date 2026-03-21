import SwiftUI

extension SidebarView {

    var filteredBranchTree: [BranchTreeNode] {
        guard !branchSearchQuery.isEmpty else { return model.branchTree }
        return model.branchTree.compactMap { filterBranchNode($0, query: branchSearchQuery) }
    }

    func filterBranchNode(_ node: BranchTreeNode, query: String) -> BranchTreeNode? {
        // Leaf node: match on title
        if node.children.isEmpty {
            return node.title.localizedCaseInsensitiveContains(query) ? node : nil
        }
        // Group node: keep if any child matches
        let filteredChildren = node.children.compactMap { filterBranchNode($0, query: query) }
        if filteredChildren.isEmpty { return nil }
        return BranchTreeNode(
            id: node.id,
            title: node.title,
            subtitle: node.subtitle,
            branchName: node.branchName,
            children: filteredChildren
        )
    }

    var sidebarBranchExplorer: some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Branches"), icon: "arrow.triangle.branch") {
                Text("\(model.branchInfos.count) \(L10n("refs"))").font(DesignSystem.Typography.label).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "magnifyingglass")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(.secondary)
                TextField(L10n("Filtrar branches..."), text: $branchSearchQuery)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.bodySmall)
                if !branchSearchQuery.isEmpty {
                    Button { branchSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()
            if filteredBranchTree.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: branchSearchQuery.isEmpty ? "arrow.triangle.branch" : "magnifyingglass")
                        .font(DesignSystem.Typography.iconLarge).foregroundStyle(.secondary)
                    Text(branchSearchQuery.isEmpty ? L10n("Sem branches detectadas") : L10n("Nenhuma branch encontrada"))
                        .font(DesignSystem.Typography.sheetTitle)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(selection: $selectedBranchTreeNodeID) {
                    ForEach(filteredBranchTree) { root in
                        OutlineGroup([root], children: \.outlineChildren) { node in
                            branchTreeNodeRow(node).tag(node.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .controlSize(.small)
                .frame(minHeight: 120, maxHeight: 250)
            }
        }
    }

    func branchTreeNodeRow(_ node: BranchTreeNode) -> some View {
        let isMain = ["main", "master", "develop", "dev"].contains(node.title.lowercased())
        let isCurrent = node.branchName == model.currentBranch
        let isFocusLoading = node.branchName == model.branchFocusLoadingBranch && model.isBranchFocusLoading
        return HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            VStack(alignment: .leading, spacing: 2) {
                if node.isGroup { Text(node.title).font(DesignSystem.Typography.sheetTitle) } else {
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        if isFocusLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: isMain ? "shield.fill" : "arrow.triangle.branch")
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(isMain ? DesignSystem.Colors.warning : (isCurrent ? Color.accentColor : Color.secondary))
                        }
                        Text(node.title).font(DesignSystem.Typography.monoLabel).fontWeight(isCurrent || isMain ? .bold : .regular).lineLimit(1).help(node.title)
                        if isCurrent { Text(L10n("current")).font(DesignSystem.Typography.micro).padding(.horizontal, 4).padding(.vertical, 1).background(DesignSystem.Colors.selectionBackground).foregroundStyle(Color.accentColor).clipShape(Capsule()) }
                    }
                }
                if !node.subtitle.isEmpty { Text(node.subtitle).font(DesignSystem.Typography.meta).foregroundStyle(.secondary).lineLimit(1).help(node.subtitle) }
            }
            Spacer()
            if let branch = node.branchName, !isMain, !isCurrent {
                Button {
                    let alert = NSAlert()
                    alert.messageText = L10n("Remover branch local")
                    alert.informativeText = L10n("Deseja remover a branch local %@?", branch)
                    alert.addButton(withTitle: L10n("Remover"))
                    alert.addButton(withTitle: L10n("Cancelar"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        model.deleteLocalBranch(branch, force: false)
                    }
                } label: {
                    Image(systemName: "trash").font(DesignSystem.Typography.meta).foregroundStyle(DesignSystem.Colors.destructiveMuted)
                }
                .buttonStyle(.plain)
                .padding(4)
                .background(DesignSystem.Colors.destructiveBg)
                .clipShape(Circle())
            }
        }
        .padding(.vertical, node.isGroup ? 4 : 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                .fill(isCurrent ? DesignSystem.Colors.selectionBackground : Color.clear)
        )
        .overlay(
            isCurrent ? RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius).stroke(DesignSystem.Colors.selectionBorder, lineWidth: 1) : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { if let branch = node.branchName { selectedBranchTreeNodeID = node.id; model.branchInput = branch } }
        .onTapGesture(count: 2) {
            if let branch = node.branchName, !isFocusLoading {
                selectedBranchTreeNodeID = node.id
                model.branchInput = branch
                model.setBranchFocus(branch)
            }
        }
        .contextMenu {
            if let branch = node.branchName {
                branchContextMenu(branch)
            }
        }
    }

}
