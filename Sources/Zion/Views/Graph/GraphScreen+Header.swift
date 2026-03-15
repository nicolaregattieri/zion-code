import SwiftUI

extension GraphScreen {
    func header(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Zion Tree")).font(DesignSystem.Typography.screenTitle)
                Text(L10n("Navegue e salte entre as pontas das branches.")).foregroundStyle(.secondary).font(DesignSystem.Typography.subtitle)
            }
            Spacer()

            // FIXED LOADING INDICATOR - No layout shift
            ZStack {
                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(width: 24, height: 24)

            jumpBar
            searchBar(proxy: proxy).frame(minWidth: 250, idealWidth: 350, maxWidth: 400)
        }
    }

    @ViewBuilder
    var jumpBar: some View {
        let hasMain = findBranchName(matches: ["main", "master", "trunk"]) != nil
        let hasDev = findBranchName(matches: ["develop", "development", "dev"]) != nil

        if hasMain || hasDev {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                if let mainName = findBranchName(matches: ["main", "master", "trunk"]) {
                    jumpButton(icon: "shield.fill", color: DesignSystem.Colors.warning, label: mainName) { commitSearchQuery = mainName }
                }
                if let devName = findBranchName(matches: ["develop", "development", "dev"]) {
                    jumpButton(icon: "flag.fill", color: DesignSystem.Colors.brandPrimary, label: devName) { commitSearchQuery = devName }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.glassElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous))
        }
    }

    func actionButtonSmall(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: icon).font(DesignSystem.Typography.labelBold)
                Text(L10n(title)).font(DesignSystem.Typography.labelSemibold)
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    func jumpButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(DesignSystem.Typography.bodyLargeBold).foregroundStyle(.white).frame(width: 32, height: 32).background(color.gradient).clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
        }.buttonStyle(.plain).cursorArrow().help(L10n("Saltar para") + " \(label)")
        .accessibilityLabel(L10n("Saltar para") + " \(label)")
    }

    func findBranchName(matches: [String]) -> String? {
        let allRefs = model.branchInfos.map { $0.name.lowercased() }
        for match in matches {
            if allRefs.contains(where: { $0 == match || $0.hasSuffix("/" + match) }) {
                return match
            }
        }
        return nil
    }

    func searchBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: model.isSemanticSearchActive ? "sparkles" : "magnifyingglass")
                    .foregroundStyle(model.isSemanticSearchActive ? DesignSystem.Colors.semanticSearch : .secondary)
                TextField(model.isSemanticSearchActive ? L10n("graph.search.aiPlaceholder") : L10n("Busca (Cmd+F)"), text: $commitSearchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if model.isSemanticSearchActive && !commitSearchQuery.isEmpty {
                            model.semanticSearchCommits(query: commitSearchQuery)
                        }
                    }
                if !commitSearchQuery.isEmpty {
                    if !model.isSemanticSearchActive && !searchMatchIDs.isEmpty {
                        Text("\(currentMatchIndex + 1)/\(searchMatchIDs.count)")
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(.secondary)
                    } else if let aiResult = model.aiHistorySearchResult, !aiResult.matches.isEmpty {
                        Text("\(aiResult.matches.count) \(L10n("resultados"))")
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(DesignSystem.Colors.semanticSearch)
                    }

                    Button {
                        commitSearchQuery = ""
                        searchMatchIDs = []
                        searchMatchIDSet = []
                        aiMatchIDSet = []
                        currentMatchIndex = 0
                        model.resetSemanticSearchResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .cursorArrow()
                    .help(L10n("Limpar busca"))
                    .accessibilityLabel(L10n("Limpar busca"))
                }
                if model.isAIConfigured {
                    Button {
                        model.isSemanticSearchActive.toggle()
                        if !model.isSemanticSearchActive {
                            model.clearSemanticSearch()
                        } else {
                            model.resetSemanticSearchResults()
                        }
                        updateSearchMatches()
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                            Image(systemName: "sparkles")
                                .font(DesignSystem.Typography.labelBold)
                            Text(L10n("graph.search.aiMode"))
                                .font(DesignSystem.Typography.labelSemibold)
                        }
                        .foregroundStyle(model.isSemanticSearchActive ? DesignSystem.Colors.brandWhite : DesignSystem.Colors.semanticSearch)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.isSemanticSearchActive ? DesignSystem.Colors.semanticSearch : DesignSystem.Colors.glassElevated)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    model.isSemanticSearchActive ? DesignSystem.Colors.semanticSearch : DesignSystem.Colors.glassBorderDark,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .cursorArrow()
                    .help(L10n("graph.search.aiMode.help"))
                    .accessibilityLabel(L10n("graph.search.aiMode.help"))
                }
                if model.isSemanticSearchActive && model.isGeneratingAIMessage {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.glassOverlay)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .stroke(
                        model.isSemanticSearchActive ? DesignSystem.Colors.semanticSearch : DesignSystem.Colors.glassBorderDark,
                        lineWidth: 1
                    )
            )

            if !model.isSemanticSearchActive {
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Button(action: { navigateSearch(direction: -1, proxy: proxy) }) { Image(systemName: "chevron.up") }
                        .disabled(searchMatchIDs.isEmpty)
                        .help(L10n("Resultado anterior"))
                        .accessibilityLabel(L10n("Resultado anterior"))
                    Button(action: { navigateSearch(direction: 1, proxy: proxy) }) { Image(systemName: "chevron.down") }
                        .disabled(searchMatchIDs.isEmpty)
                        .help(L10n("Proximo resultado"))
                        .accessibilityLabel(L10n("Proximo resultado"))
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
