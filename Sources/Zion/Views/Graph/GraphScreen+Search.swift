import SwiftUI

extension GraphScreen {
    func navigateSelection(direction: Int, proxy: ScrollViewProxy) {
        let commits = model.commits
        guard !commits.isEmpty else { return }
        let hasPending = !model.uncommittedChanges.isEmpty

        // If pending changes is selected, down goes to first commit
        if showingPendingChanges {
            if direction == 1 {
                let first = commits[0]
                showingPendingChanges = false
                withAnimation(DesignSystem.Motion.graph) {
                    model.selectCommit(first.id)
                    proxy.scrollTo(first.id, anchor: .center)
                }
            }
            return
        }

        let currentIndex = commits.firstIndex(where: { $0.id == model.selectedCommitID }) ?? -1
        let nextIndex = currentIndex + direction

        // If at top of commit list and pressing up, jump to pending changes
        if nextIndex < 0 && hasPending {
            showingPendingChanges = true
            model.selectCommit(nil)
            return
        }

        if nextIndex >= 0 && nextIndex < commits.count {
            let nextCommit = commits[nextIndex]
            showingPendingChanges = false
            withAnimation(DesignSystem.Motion.graph) {
                model.selectCommit(nextCommit.id)
                proxy.scrollTo(nextCommit.id, anchor: .center)
            }
        }
    }

    func updateSearchMatches() {
        let query = commitSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            searchMatchIDs = []
            searchMatchIDSet = []
            currentMatchIndex = 0
            aiMatchIDSet = []
            return
        }

        if model.isSemanticSearchActive {
            searchMatchIDs = []
            searchMatchIDSet = []
            currentMatchIndex = 0

            let matches = model.aiHistorySearchResult?.matches ?? []
            if matches.isEmpty {
                aiMatchIDSet = []
            } else {
                aiMatchIDSet = Set(matches.compactMap { matchingCommit(for: $0.hash)?.id })
            }
            return
        }

        var priority1: [String] = []
        var priority2: [String] = []
        var priority3: [String] = []
        priority1.reserveCapacity(model.commits.count)
        priority2.reserveCapacity(model.commits.count)
        priority3.reserveCapacity(model.commits.count)

        for commit in model.commits {
            var hasDecorationExact = false
            var hasDecorationContains = false

            for decoration in commit.decorations {
                let lowercasedDecoration = decoration.lowercased()
                let normalizedDecoration = lowercasedDecoration
                    .replacingOccurrences(of: "head -> ", with: "")
                    .replacingOccurrences(of: "tag: ", with: "")

                if normalizedDecoration == query || normalizedDecoration.hasSuffix("/" + query) {
                    hasDecorationExact = true
                    break
                }

                if !hasDecorationContains && lowercasedDecoration.contains(query) {
                    hasDecorationContains = true
                }
            }

            if hasDecorationExact {
                priority1.append(commit.id)
                continue
            }

            if hasDecorationContains {
                priority2.append(commit.id)
                continue
            }

            let hash = commit.shortHash.lowercased()
            let author = commit.author.lowercased()
            let subject = commit.subject.lowercased()
            if hash.contains(query) || author.contains(query) || subject.contains(query) {
                priority3.append(commit.id)
            }
        }

        searchMatchIDs = priority1 + priority2 + priority3
        searchMatchIDSet = Set(searchMatchIDs)
        if currentMatchIndex >= searchMatchIDs.count { currentMatchIndex = 0 }
        aiMatchIDSet = []

        if searchMatchIDs.isEmpty && !query.isEmpty && !model.isSemanticSearchActive {
            model.searchFullHistory(query: query)
        } else {
            model.clearGitSearch()
        }
    }

    func navigateSearch(direction: Int, proxy: ScrollViewProxy) {
        guard !searchMatchIDs.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + direction + searchMatchIDs.count) % searchMatchIDs.count
        scrollToMatch(id: searchMatchIDs[currentMatchIndex], proxy: proxy)
    }

    func scrollToMatch(id: String, proxy: ScrollViewProxy) {
        withAnimation(DesignSystem.Motion.springInteractive) {
            proxy.scrollTo(id, anchor: .center)
            model.selectCommit(id)
        }
    }

    func scrollToSemanticResults(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(DesignSystem.Motion.springInteractive) {
                proxy.scrollTo(Self.semanticResultsScrollTarget, anchor: .top)
            }
        }
    }

    func matchingCommit(for hash: String) -> Commit? {
        let normalizedHash = hash.lowercased()
        return model.commits.first { commit in
            let shortHash = commit.shortHash.lowercased()
            let fullHash = commit.id.lowercased()
            return shortHash.hasPrefix(normalizedHash)
                || fullHash.hasPrefix(normalizedHash)
                || normalizedHash.hasPrefix(shortHash)
        }
    }

    static let gitSearchResultsScrollTarget = "graph.gitSearchResults.scrollTarget"

    func gitSearchResultsPanel(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: commitGraphColumnWidth)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignSystem.Typography.labelBold)
                        .foregroundStyle(DesignSystem.Colors.brandPrimary)
                    Text(L10n("graph.search.historyTitle"))
                        .font(DesignSystem.Typography.sectionTitle)
                    if !model.gitSearchResults.isEmpty {
                        Text("\(model.gitSearchResults.count) \(L10n("graph.search.historyResults"))")
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(DesignSystem.Colors.brandPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.glassElevated)
                            .clipShape(Capsule())
                    }
                }

                if model.isGitSearching && model.gitSearchResults.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n("graph.search.historyLoading"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                } else if model.gitSearchResults.isEmpty {
                    Text(L10n("graph.ai.noMatches"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.gitSearchResults) { result in
                            Button {
                                model.selectCommit(result.id)
                                model.loadCommitDetails(for: result.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                                        Text(result.shortHash)
                                            .font(DesignSystem.Typography.monoLabelBold)
                                            .foregroundStyle(DesignSystem.Colors.brandPrimary)
                                        Text(result.subject)
                                            .font(DesignSystem.Typography.bodySmallSemibold)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        gitSearchSourceBadge(result.source)
                                    }
                                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                                        Text(result.author)
                                            .font(DesignSystem.Typography.label)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(result.date, style: .date)
                                            .font(DesignSystem.Typography.label)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(DesignSystem.Colors.glassMinimal)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                                        .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .cursorArrow()
                            .contextMenu {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(result.id, forType: .string)
                                } label: {
                                    Label(L10n("Copiar Hash"), systemImage: "doc.on.doc")
                                }
                                Button {
                                    performGitAction(
                                        L10n("Cherry-pick"),
                                        L10n("Deseja aplicar o commit %@ na branch atual?", result.shortHash),
                                        false
                                    ) {
                                        model.cherryPick(commitHash: result.id)
                                    }
                                } label: {
                                    Label(L10n("Cherry-pick"), systemImage: "arrow.triangle.branch")
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.brandPrimary.opacity(0.5), lineWidth: 1)
            )
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func gitSearchSourceBadge(_ source: GitSearchResult.Source) -> some View {
        let label: String = switch source {
        case .message: L10n("graph.search.source.message")
        case .author: L10n("graph.search.source.author")
        case .hash: L10n("graph.search.source.hash")
        case .branch(let name): "\(L10n("graph.search.source.branch")): \(name)"
        case .tag(let name): "\(L10n("graph.search.source.tag")): \(name)"
        }
        Text(label)
            .font(DesignSystem.Typography.monoMetaBold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(DesignSystem.Colors.glassElevated)
            .clipShape(Capsule())
    }

    func aiHistoryResultsPanel(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: commitGraphColumnWidth)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "sparkles")
                        .font(DesignSystem.Typography.labelBold)
                        .foregroundStyle(DesignSystem.Colors.semanticSearch)
                    Text(L10n("graph.ai.answerTitle"))
                        .font(DesignSystem.Typography.sectionTitle)
                    if let count = model.aiHistorySearchResult?.matches.count, count > 0 {
                        Text("\(count) \(L10n("resultados"))")
                            .font(DesignSystem.Typography.monoLabelBold)
                            .foregroundStyle(DesignSystem.Colors.semanticSearch)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.glassElevated)
                            .clipShape(Capsule())
                    }
                }

                if model.isGeneratingAIMessage && model.aiHistorySearchResult == nil {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n("graph.ai.loading"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                } else if let result = model.aiHistorySearchResult {
                    Text(result.answer)
                        .font(DesignSystem.Typography.bodySemibold)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if result.matches.isEmpty {
                        Text(L10n("graph.ai.noMatches"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(result.matches) { match in
                                if let commit = matchingCommit(for: match.hash) {
                                    Button {
                                        scrollToMatch(id: commit.id, proxy: proxy)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                                                Text(commit.shortHash)
                                                    .font(DesignSystem.Typography.monoLabelBold)
                                                    .foregroundStyle(DesignSystem.Colors.semanticSearch)
                                                Text(commit.subject)
                                                    .font(DesignSystem.Typography.bodySmallSemibold)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Image(systemName: "arrow.up.forward.square")
                                                    .font(DesignSystem.Typography.label)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(match.reason)
                                                .font(DesignSystem.Typography.label)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(DesignSystem.Colors.glassMinimal)
                                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                                                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .cursorArrow()
                                    .help(L10n("graph.ai.openCommit", commit.shortHash))
                                    .accessibilityLabel(L10n("graph.ai.openCommit", commit.shortHash))
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.semanticSearch, lineWidth: 1)
            )
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
