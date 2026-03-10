import SwiftUI

struct GraphScreen: View {
    @Bindable var model: RepositoryViewModel
    @Binding var commitSearchQuery: String
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    let commitContextMenu: (Commit) -> AnyView
    let branchContextMenu: (String) -> AnyView
    let tagContextMenu: (String) -> AnyView
    
    @State private var currentMatchIndex: Int = 0
    @State private var searchMatchIDs: [String] = []
    @State private var searchMatchIDSet: Set<String> = []
    @State private var aiMatchIDSet: Set<String> = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isShowingQuickCommit: Bool = false
    @State private var quickCommitIncludesAllChanges: Bool = false
    @State private var isShowingCreateBranchFromPending: Bool = false
    @State private var pendingBranchNameInput: String = ""
    @State private var isShowingQuickStash: Bool = false
    @State private var isShowingStashList: Bool = false
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isCommitMessageFocused: Bool
    
    @State private var showingPendingChanges: Bool = false
    @State private var splitRatio: CGFloat = 0.7
    @State private var inlineSplitRatio: CGFloat = 0.35
    @State private var hoveredInlineFilePath: String?
    @FocusState private var isGraphFocused: Bool

    private var commitRowMinWidth: CGFloat {
        let laneWidth = CGFloat(max(model.maxLaneCount, 1)) * 20
        return max(DesignSystem.Layout.commitRowFloor, laneWidth + DesignSystem.Layout.commitRowLaneOffset)
    }

    private var commitGraphColumnWidth: CGFloat {
        let span = CGFloat(max(model.maxLaneCount - 1, 0)) * 20
        return max(10 + 12 + span, 56)
    }

    private var commitRowMaxWidth: CGFloat {
        DesignSystem.Layout.centeredContentMaxWidth
    }

    private func commitRowWidth(for containerWidth: CGFloat) -> CGFloat {
        let available = max(containerWidth - 18, 0)
        return min(max(available, commitRowMinWidth), commitRowMaxWidth)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 14) {
                header(proxy: proxy)
                if !model.worktrees.isEmpty {
                    worktreeQuickSwitchBar
                }

                DraggableSplitView(
                    axis: .horizontal,
                    ratio: $splitRatio,
                    minLeading: DesignSystem.Layout.commitListMinWidth,
                    minTrailing: DesignSystem.Layout.commitDetailMinWidth
                ) {
                    commitListPane(proxy: proxy)
                        .focusable()
                        .focused($isGraphFocused)
                        .focusEffectDisabled()
                        .onMoveCommand { direction in
                            switch direction {
                            case .up: navigateSelection(direction: -1, proxy: proxy)
                            case .down: navigateSelection(direction: 1, proxy: proxy)
                            default: break
                            }
                        }
                        .onExitCommand { model.selectCommit(nil); showingPendingChanges = false }
                        .padding(.trailing, 6)
                } trailing: {
                    commitDetailsPane
                        .animation(nil, value: showingPendingChanges)
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .onAppear {
                updateSearchMatches()
            }
            .onChange(of: model.shouldClosePopovers) { _, shouldClose in
                if shouldClose {
                    isShowingQuickCommit = false
                    isShowingQuickStash = false
                    isShowingStashList = false
                    model.shouldClosePopovers = false
                }
            }
            .onChange(of: commitSearchQuery) { _, _ in
                if model.isSemanticSearchActive {
                    model.resetSemanticSearchResults()
                }
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    updateSearchMatches()
                    if !searchMatchIDs.isEmpty {
                        scrollToMatch(id: searchMatchIDs[0], proxy: proxy)
                    }
                }
            }
            .onChange(of: model.aiHistorySearchResult) { _, newValue in
                updateSearchMatches()
                guard model.isSemanticSearchActive,
                      let firstHash = newValue?.matches.first?.hash,
                      let commit = matchingCommit(for: firstHash) else { return }
                scrollToMatch(id: commit.id, proxy: proxy)
            }
            .onChange(of: model.uncommittedChanges) { _, changes in
                if changes.isEmpty, showingPendingChanges {
                    showingPendingChanges = false
                    model.selectChangeFile(nil)
                }
            }
            .background {
                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0)
            }
        }
    }

    private var worktreeQuickSwitchBar: some View {
        let hasAdditionalWorktrees = model.worktrees.contains { !$0.isMainWorktree }
        return GlassCard(spacing: 8) {
            CardHeader(L10n("Worktrees"), icon: "square.split.2x2") {
                Text("\(model.worktrees.count)")
                    .font(DesignSystem.Typography.monoLabelBold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                    ForEach(model.worktrees) { worktree in
                        WorktreePill(
                            branch: worktree.branch,
                            isMainWorktree: worktree.isMainWorktree,
                            showRootBadge: hasAdditionalWorktrees,
                            dirtyCount: worktree.uncommittedCount,
                            hasConflicts: worktree.hasConflicts,
                            isCurrent: worktree.isCurrent
                        ) {
                            showingPendingChanges = worktree.uncommittedCount > 0
                            if showingPendingChanges {
                                model.selectCommit(nil)
                            }
                            model.openWorktreeInZion(
                                worktree,
                                navigateToCode: false,
                                sectionAfterOpen: .graph
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    private func header(proxy: ScrollViewProxy) -> some View {
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
    private var jumpBar: some View {
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

    private func actionButtonSmall(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
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

    private func jumpButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(DesignSystem.Typography.bodyLargeBold).foregroundStyle(.white).frame(width: 32, height: 32).background(color.gradient).clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
        }.buttonStyle(.plain).cursorArrow().help(L10n("Saltar para") + " \(label)")
        .accessibilityLabel(L10n("Saltar para") + " \(label)")
    }

    private func findBranchName(matches: [String]) -> String? {
        let allRefs = model.branchInfos.map { $0.name.lowercased() }
        for match in matches {
            if allRefs.contains(where: { $0 == match || $0.hasSuffix("/" + match) }) {
                return match
            }
        }
        return nil
    }

    
    private func searchBar(proxy: ScrollViewProxy) -> some View {
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
    
    private func commitListPane(proxy: ScrollViewProxy) -> some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Commits"), icon: "list.bullet") {
                Text("\(model.commits.count) \(L10n("itens"))").font(DesignSystem.Typography.label).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()
            GeometryReader { geometry in
                let rowWidth = commitRowWidth(for: geometry.size.width)

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    let remoteNames = model.remotes.map(\.name)
                    let hasAdditionalWorktrees = model.worktrees.contains { !$0.isMainWorktree }
                    let worktreeBranchNames = Set(
                        model.worktrees
                            .filter { !$0.isMainWorktree && !$0.isCurrent && !$0.branch.isEmpty }
                            .map(\.branch)
                    )
                    let rootWorktreeBranchNames: Set<String> = hasAdditionalWorktrees
                        ? Set(
                            model.worktrees
                                .filter { $0.isMainWorktree && !$0.branch.isEmpty }
                                .map(\.branch)
                        )
                        : []
                    LazyVStack(spacing: 0) {
                        if model.isSemanticSearchActive, (model.isGeneratingAIMessage || model.aiHistorySearchResult != nil) {
                            aiHistoryResultsPanel(proxy: proxy)
                                .padding(.top, 8)
                                .frame(width: rowWidth, alignment: .leading)
                        }

                        // PENDING CHANGES - TOP OF THE LIST
                        if !model.uncommittedChanges.isEmpty {
                            pendingChangesRow
                                .padding(.top, 8)
                                .frame(width: rowWidth, alignment: .leading)
                        }

                        ForEach(model.commits) { commit in
                            CommitRowView(
                                commit: commit,
                                isSelected: model.selectedCommitID == commit.id,
                                isSearchMatch: searchMatchIDSet.contains(commit.id) || aiMatchIDSet.contains(commit.id),
                                searchQuery: commitSearchQuery,
                                laneCount: model.maxLaneCount,
                                currentBranch: model.currentBranch,
                                isAIConfigured: model.isAIConfigured,
                                isReviewingThisCommit: model.reviewingCommitID == commit.id,
                                onCheckout: { branch in
                                    let isRemote = model.isRemoteRefName(branch)
                                    if isRemote {
                                        let title = L10n("Checkout & Pull")
                                        var localName = branch
                                        for remote in model.remotes {
                                            if branch.hasPrefix("\(remote.name)/") {
                                                localName = String(branch.dropFirst(remote.name.count + 1))
                                                break
                                            }
                                        }
                                        let message = L10n("Deseja fazer checkout de %@ e puxar as alterações?", localName)
                                        performGitAction(title, message, false) {
                                            model.checkoutAndPull(reference: branch)
                                        }
                                    } else {
                                        model.checkout(reference: branch)
                                    }
                                },
                                onReviewCommit: { commitID in
                                    model.reviewCommitChanges(commitID: commitID)
                                },
                                onSelect: {
                                    showingPendingChanges = false
                                    withAnimation(DesignSystem.Motion.graph) {
                                        model.selectCommit(commit.id)
                                    }
                                },
                                contextMenu: commitContextMenu(commit),
                                branchContextMenu: branchContextMenu,
                                tagContextMenu: tagContextMenu,
                                remotes: remoteNames,
                                worktreeBranches: worktreeBranchNames,
                                rootWorktreeBranches: rootWorktreeBranchNames,
                                bisectRole: model.bisectRole(for: commit.id),
                                avatarImage: model.avatarImage(for: commit.email)
                            )
                            .frame(width: rowWidth, alignment: .leading)
                            .id(commit.id)
                            .overlay(alignment: .trailing) {
                                if !searchMatchIDs.isEmpty && searchMatchIDs[currentMatchIndex] == commit.id {
                                    Image(systemName: "arrow.left").foregroundStyle(DesignSystem.Colors.searchHighlight).padding(.trailing, 32)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(minWidth: rowWidth, alignment: .leading)
                }
            }
            if model.hasMoreCommits { loadMoreButton }
        }
    }
    
    private var pendingChangesRow: some View {
        HStack(spacing: 0) {
            PendingChangesLaneView(height: 102, width: commitGraphColumnWidth)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                    .fill(showingPendingChanges ? DesignSystem.Colors.statusOrangeBg : DesignSystem.Colors.warning.opacity(0.05))
                    .frame(height: 86)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius, style: .continuous)
                            .stroke(showingPendingChanges ? DesignSystem.Colors.warning.opacity(0.5) : DesignSystem.Colors.warning.opacity(0.2), lineWidth: 1.5)
                    )

                HStack(spacing: 12) {
                    Image(systemName: "pencil.circle.fill").font(DesignSystem.Typography.iconLarge).foregroundStyle(DesignSystem.Colors.warning.opacity(0.8))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n("Alteracoes Pendentes")).font(DesignSystem.Typography.sectionTitle).foregroundStyle(.primary.opacity(0.9))
                        Text("\(model.uncommittedCount) \(L10n("arquivos modificados"))").font(DesignSystem.Typography.label).foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Button {
                            quickCommitIncludesAllChanges = false
                            isShowingQuickCommit = true
                        } label: {
                            Label(L10n("Commit"), systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.actionPrimary)
                        .controlSize(.small)
                        .sheet(isPresented: $isShowingQuickCommit) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L10n("Criar Commit Rapido")).font(.title3.bold())

                                HStack(spacing: 8) {
                                    quickCommitScopeChip(
                                        title: L10n("Staged"),
                                        icon: "checkmark.circle.fill",
                                        isSelected: !quickCommitIncludesAllChanges
                                    ) {
                                        quickCommitIncludesAllChanges = false
                                    }
                                    quickCommitScopeChip(
                                        title: L10n("Stage All"),
                                        icon: "plus.circle.fill",
                                        isSelected: quickCommitIncludesAllChanges
                                    ) {
                                        quickCommitIncludesAllChanges = true
                                    }
                                    Spacer()
                                }
                                Text(
                                    quickCommitIncludesAllChanges
                                        ? L10n("commit.mode.allChanges.hint")
                                        : L10n("commit.mode.stagedOnly.hint")
                                )
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)

                                HStack(alignment: .bottom, spacing: 8) {
                                    ZStack(alignment: .topLeading) {
                                        TextEditor(text: $model.commitMessageInput)
                                            .font(DesignSystem.Typography.monoBody)
                                            .lineSpacing(4)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(DesignSystem.Colors.glassInset)
                                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                                                    .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                                            )
                                            .frame(minHeight: 180, maxHeight: 220)

                                        if model.commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text(L10n("Mensagem do commit..."))
                                                .font(DesignSystem.Typography.monoBody)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .allowsHitTesting(false)
                                        }
                                    }

                                    Button {
                                        model.suggestCommitMessage()
                                    } label: {
                                        if model.isGeneratingAIMessage {
                                            ProgressView().controlSize(.small).frame(width: 12, height: 12)
                                        } else {
                                            Image(systemName: "sparkles").font(DesignSystem.Typography.body)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(DesignSystem.Colors.ai)
                                    .disabled(model.isGeneratingAIMessage)
                                    .help(model.isAIConfigured ? L10n("Gerar mensagem com IA") : L10n("Sugerir mensagem de commit"))
                                    .accessibilityLabel(L10n("Gerar mensagem com IA"))
                                    .onChange(of: model.suggestedCommitMessage) { _, newValue in
                                        if !newValue.isEmpty {
                                            model.commitMessageInput = newValue
                                        }
                                    }
                                }

                                if model.aiQuotaExceeded {
                                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(DesignSystem.Typography.label)
                                        Text(L10n("Cota da API excedida. Usando sugestao local."))
                                            .font(DesignSystem.Typography.labelMedium)
                                    }
                                    .foregroundStyle(DesignSystem.Colors.warning)
                                    .padding(.top, -8)
                                }

                                HStack {
                                    Button(L10n("Cancelar")) {
                                        quickCommitIncludesAllChanges = false
                                        isShowingQuickCommit = false
                                    }
                                        .buttonStyle(.bordered)
                                        .keyboardShortcut(.escape, modifiers: [])

                                    Spacer()

                                    Button(L10n("Commit")) {
                                        model.commit(
                                            message: model.commitMessageInput,
                                            scope: quickCommitIncludesAllChanges ? .allChanges : .stagedOnly
                                        )
                                        quickCommitIncludesAllChanges = false
                                        isShowingQuickCommit = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                    .disabled(
                                        model.commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                        (!quickCommitIncludesAllChanges && !model.hasStagedChanges)
                                    )
                                    .keyboardShortcut(.return, modifiers: [.command])
                                }
                            }
                            .padding(24)
                            .frame(width: 560)
                            .frame(minHeight: 360)
                        }

                        Button {
                            isShowingCreateBranchFromPending = true
                        } label: {
                            Label(L10n("pending.createBranchHere"), systemImage: "arrow.triangle.branch")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .sheet(isPresented: $isShowingCreateBranchFromPending) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L10n("pending.createBranchHere"))
                                    .font(.title3.bold())
                                Text(L10n("pending.createBranchHere.subtitle"))
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.secondary)

                                TextField(L10n("pending.createBranch.placeholder"), text: $pendingBranchNameInput)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        createBranchFromPending()
                                    }

                                HStack {
                                    Button(L10n("Cancelar")) {
                                        isShowingCreateBranchFromPending = false
                                    }
                                    .buttonStyle(.bordered)
                                    .keyboardShortcut(.escape, modifiers: [])

                                    Spacer()

                                    Button(L10n("Criar branch")) {
                                        createBranchFromPending()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                    .disabled(pendingBranchNameInput.clean.isEmpty)
                                    .keyboardShortcut(.return, modifiers: [])
                                }
                            }
                            .padding(24)
                            .frame(width: 420)
                        }

                        Menu {
                            pendingTransferMenuItems()
                        } label: {
                            Label(L10n("pending.copyChanges"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // STASH MENU - COMBINED
                        Menu {
                            Button(role: .destructive) {
                                performGitAction(
                                    L10n("Descartar Mudanças"),
                                    L10n("discardAll.confirm.current"),
                                    true
                                ) {
                                    model.discardAllChanges()
                                    showingPendingChanges = true
                                    model.selectCommit(nil)
                                }
                            } label: {
                                Label(L10n("Descartar"), systemImage: "trash.slash.fill")
                            }

                            Divider()

                            Button {
                                isShowingQuickStash = true
                            } label: {
                                Label(L10n("Criar Novo Stash"), systemImage: "plus.square.fill")
                            }

                            if !model.stashes.isEmpty {
                                Divider()
                                Button {
                                    isShowingStashList = true
                                } label: {
                                    Label(L10n("Gerenciar Stashes..."), systemImage: "list.bullet.rectangle.stack")
                                }
                            }
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                                Image(systemName: "archivebox.fill")
                                Text(L10n("Stash"))
                                if !model.stashes.isEmpty {
                                    Text("\(model.stashes.count)")
                                        .font(DesignSystem.Typography.metaBold)
                                        .padding(.horizontal, 4)
                                        .background(DesignSystem.Colors.info.opacity(0.5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .sheet(isPresented: $isShowingQuickStash) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L10n("Salvar no Stash")).font(.title3.bold())
                                TextField(L10n("Mensagem do stash (opcional)"), text: $model.stashMessageInput)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        model.createStash(message: model.stashMessageInput)
                                        model.stashMessageInput = ""
                                        isShowingQuickStash = false
                                    }

                                HStack {
                                    Button(L10n("Cancelar")) { isShowingQuickStash = false }
                                        .buttonStyle(.bordered)
                                        .keyboardShortcut(.escape, modifiers: [])
                                    Spacer()
                                    Button(L10n("Salvar")) {
                                        model.createStash(message: model.stashMessageInput)
                                        model.stashMessageInput = ""
                                        isShowingQuickStash = false
                                    }.buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.actionPrimary)
                                    .keyboardShortcut(.return, modifiers: [])
                                }
                            }
                            .padding(24).frame(width: 400)
                        }
                        .sheet(isPresented: $isShowingStashList) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text(L10n("Stashes Recentes")).font(.title3.bold())
                                    Spacer()
                                    Button(L10n("Fechar")) { isShowingStashList = false }.buttonStyle(.bordered).keyboardShortcut(.escape, modifiers: [])
                                }

                                ScrollView {
                                    VStack(spacing: 10) {
                                        ForEach(model.stashes, id: \.self) { stash in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(stash).font(DesignSystem.Typography.monoBody).lineLimit(2)
                                                }
                                                Spacer()
                                                HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                                                    Button(L10n("Apply")) { model.selectedStash = stash; model.applySelectedStash(); isShowingStashList = false }.buttonStyle(.bordered).controlSize(.small)
                                                    Button(L10n("Pop")) { model.selectedStash = stash; model.popSelectedStash(); isShowingStashList = false }.buttonStyle(.bordered).controlSize(.small)
                                                    Button { model.selectedStash = stash; model.dropSelectedStash() } label: { Image(systemName: "trash") }.buttonStyle(.bordered).tint(DesignSystem.Colors.destructive).controlSize(.small).accessibilityLabel(L10n("Drop Stash"))
                                                }
                                            }
                                            .padding(10).background(DesignSystem.Colors.glassSubtle).cornerRadius(DesignSystem.Spacing.elementCornerRadius)
                                        }
                                    }
                                }.frame(maxHeight: 400)
                            }
                            .padding(24).frame(width: 550)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 102)
        .contentShape(Rectangle())
        .onTapGesture {
            showingPendingChanges = true
            model.selectCommit(nil)
        }
        .contextMenu {
            Button {
                isShowingCreateBranchFromPending = true
            } label: {
                Label(L10n("pending.createBranchHere"), systemImage: "arrow.triangle.branch")
            }

            Divider()

            pendingTransferMenuItems()

            Divider()

            Button(role: .destructive) {
                performGitAction(
                    L10n("Descartar Mudanças"),
                    L10n("discardAll.confirm.current"),
                    true
                ) {
                    model.discardAllChanges()
                    showingPendingChanges = true
                    model.selectCommit(nil)
                }
            } label: {
                Label(L10n("Descartar"), systemImage: "trash.slash.fill")
            }
        }
    }

    private var nonCurrentWorktrees: [WorktreeItem] {
        model.worktrees.filter { !$0.isCurrent }
    }

    private func createBranchFromPending() {
        let branchName = pendingBranchNameInput.clean
        guard !branchName.isEmpty else { return }
        model.createBranch(named: branchName, from: "HEAD", andCheckout: true)
        pendingBranchNameInput = ""
        isShowingCreateBranchFromPending = false
        showingPendingChanges = true
        model.selectCommit(nil)
    }

    @ViewBuilder
    private func pendingTransferMenuItems() -> some View {
        if nonCurrentWorktrees.isEmpty {
            Button(L10n("pending.transfer.noWorktrees")) {}
                .disabled(true)
        } else {
            Menu(L10n("pending.transfer.copy")) {
                ForEach(nonCurrentWorktrees) { worktree in
                    Button(worktree.branch.isEmpty ? URL(fileURLWithPath: worktree.path).lastPathComponent : worktree.branch) {
                        transferPendingChanges(to: worktree, keepInCurrentWorktree: true)
                    }
                }
            }

            Divider()

            Menu(L10n("pending.transfer.move")) {
                ForEach(nonCurrentWorktrees) { worktree in
                    Button(worktree.branch.isEmpty ? URL(fileURLWithPath: worktree.path).lastPathComponent : worktree.branch) {
                        transferPendingChanges(to: worktree, keepInCurrentWorktree: false)
                    }
                }
            }
        }
    }

    private func transferPendingChanges(to worktree: WorktreeItem, keepInCurrentWorktree: Bool) {
        let performTransfer = {
            model.transferPendingChanges(toWorktree: worktree, keepInCurrentWorktree: keepInCurrentWorktree)
            showingPendingChanges = true
            model.selectCommit(nil)
        }

        if keepInCurrentWorktree {
            performTransfer()
            return
        }

        let targetName = worktree.branch.isEmpty ? URL(fileURLWithPath: worktree.path).lastPathComponent : worktree.branch
        performGitAction(
            L10n("pending.transfer.move.short"),
            L10n("pending.transfer.move.confirm", targetName),
            true
        ) {
            performTransfer()
        }
    }

    private func navigateSelection(direction: Int, proxy: ScrollViewProxy) {
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

    private func updateSearchMatches() {
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
    }
    
    private func navigateSearch(direction: Int, proxy: ScrollViewProxy) {
        guard !searchMatchIDs.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + direction + searchMatchIDs.count) % searchMatchIDs.count
        scrollToMatch(id: searchMatchIDs[currentMatchIndex], proxy: proxy)
    }
    
    private func scrollToMatch(id: String, proxy: ScrollViewProxy) {
        withAnimation(DesignSystem.Motion.springInteractive) {
            proxy.scrollTo(id, anchor: .center)
            model.selectCommit(id)
        }
    }

    private func matchingCommit(for hash: String) -> Commit? {
        let normalizedHash = hash.lowercased()
        return model.commits.first { commit in
            let shortHash = commit.shortHash.lowercased()
            let fullHash = commit.id.lowercased()
            return shortHash.hasPrefix(normalizedHash)
                || fullHash.hasPrefix(normalizedHash)
                || normalizedHash.hasPrefix(shortHash)
        }
    }

    private func aiHistoryResultsPanel(proxy: ScrollViewProxy) -> some View {
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
    
    private var loadMoreButton: some View {
        Group {
            Divider()
            HStack {
                Spacer()
                Button { model.loadMoreCommits() } label: { Label(L10n("Carregar mais"), systemImage: "arrow.down.circle") }.buttonStyle(.bordered).disabled(model.isBusy)
                Spacer()
            }.padding(10)
        }
    }
    
    @ViewBuilder
    private var commitDetailsPane: some View {
        if showingPendingChanges {
            inlineChangesPane
        } else if let selectedCommitID = model.selectedCommitID {
            GlassCard(spacing: 0) {
                CardHeader(L10n("Detalhes"), icon: "doc.text.magnifyingglass") {
                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        if model.isAIConfigured {
                            Button {
                                model.reviewCommitChanges(commitID: selectedCommitID)
                            } label: {
                                if model.reviewingCommitID == selectedCommitID {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(DesignSystem.Typography.labelBold)
                                }
                            }
                            .buttonStyle(.plain)
                            .cursorArrow()
                            .foregroundStyle(DesignSystem.Colors.ai)
                            .help(L10n("graph.commit.review"))
                            .accessibilityLabel(L10n("graph.commit.review"))
                        }

                        if model.cachedReviewFindings(for: selectedCommitID) != nil {
                            Text(L10n("graph.commit.review.cached"))
                                .font(DesignSystem.Typography.metaBold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.glassSubtle)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                                )
                                .foregroundStyle(.secondary)
                        }

                        Text(String(selectedCommitID.prefix(8)))
                            .font(DesignSystem.Typography.monoLabel)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

                if model.isAIConfigured {
                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        detailTabButton(
                            title: L10n("graph.commit.review.tab.details"),
                            isSelected: model.selectedCommitDetailTab == .details
                        ) {
                            model.selectedCommitDetailTab = .details
                        }

                        detailTabButton(
                            title: L10n("graph.commit.review.tab.ai"),
                            isSelected: model.selectedCommitDetailTab == .aiReview
                        ) {
                            model.selectedCommitDetailTab = .aiReview
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                Divider()

                ScrollView {
                    CommitDetailContent(rawDetails: model.commitDetails, model: model, commitID: selectedCommitID)
                        .padding(12)
                }
            }
        } else {
            GlassCard(spacing: 0) {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.left.circle")
                        .font(DesignSystem.Typography.heroIcon)
                        .foregroundStyle(.tertiary)
                    Text(L10n("Selecione um commit para ver detalhes"))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
        }
    }

    private func detailTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.labelSemibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                        .fill(isSelected ? DesignSystem.Colors.selectionBackground : DesignSystem.Colors.glassSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                        .stroke(isSelected ? DesignSystem.Colors.selectionBorder : DesignSystem.Colors.glassBorderDark, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .cursorArrow()
    }

    // MARK: - Inline Changes Pane (replaces detail when pending changes selected)

    private var inlineChangesPane: some View {
        DraggableSplitView(
            axis: .vertical,
            ratio: $inlineSplitRatio,
            minLeading: DesignSystem.Layout.graphInlineSplitMinLeading,
            minTrailing: DesignSystem.Layout.graphInlineSplitMinTrailing
        ) {
            inlineFileList
                .padding(.bottom, 6)
        } trailing: {
            inlineDiffViewer
                .padding(.top, 6)
        }
    }

    private var inlineFileList: some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Changes"), icon: "pencil.circle", subtitle: "\(model.uncommittedCount) \(L10n("arquivos modificados"))") {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Button {
                        model.stageAllFiles()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help(L10n("Stage All"))
                    .accessibilityLabel(L10n("Stage All"))
                    .disabled(model.uncommittedChanges.isEmpty)

                    Button {
                        model.unstageAllFiles()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help(L10n("Unstage All"))
                    .accessibilityLabel(L10n("Unstage All"))
                    .disabled(!model.hasStagedChanges)

                    if model.isAIConfigured && !model.uncommittedChanges.isEmpty {
                        Button { model.summarizePendingChanges() } label: {
                            if model.isLoadingPendingChangesSummary && !model.hasVisiblePendingChangesSummary {
                                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(L10n("Resumo IA das mudancas"))
                                }
                                .font(DesignSystem.Typography.bodySmallSemibold)
                            } else {
                                Label(L10n("Resumo IA das mudancas"), systemImage: "sparkles")
                                    .font(DesignSystem.Typography.bodySmallSemibold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(DesignSystem.Colors.ai)
                        .help(L10n("Resumo IA das mudancas"))
                        .accessibilityLabel(L10n("Resumo IA das mudancas"))
                        .disabled(model.isLoadingPendingChangesSummary)
                    }
                    Button { model.refreshRepository() } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain).cursorArrow().help(L10n("Atualizar")).accessibilityLabel(L10n("Atualizar"))
                }
            }
            .padding(12)

            if !model.uncommittedChanges.isEmpty {
                inlineChangesSummaryBar
            }

            if showPendingChangesSummaryCard {
                pendingChangesSummaryCard
            }

            Divider()
            if model.uncommittedChanges.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(DesignSystem.Typography.largeIcon).foregroundStyle(DesignSystem.Colors.success.opacity(0.6))
                    Text(L10n("Tudo limpo!")).font(DesignSystem.Typography.sheetTitle)
                    Text(L10n("Nenhuma alteração pendente no momento.")).font(DesignSystem.Typography.label).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.uncommittedChanges, id: \.self) { line in
                            inlineFileRow(line: line)
                        }
                    }.padding(8)
                }
            }
        }
    }

    private func inlineFileRow(line: String) -> some View {
        let (indexStatus, workTreeStatus, file) = parseInlineGitStatus(line)
        let isSelected = model.selectedChangeFile == file
        let isHovered = hoveredInlineFilePath == file
        return Button {
            model.selectChangeFile(file)
        } label: {
            HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                inlineStatusIcon(index: indexStatus, worktree: workTreeStatus).font(DesignSystem.Typography.bodyLarge)
                Text(file).font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if indexStatus != " " && indexStatus != "?" {
                    Circle().fill(DesignSystem.Colors.fileStaged).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                    .fill(isSelected ? DesignSystem.Colors.selectionBackground : (isHovered ? DesignSystem.Colors.glassHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                    .stroke(isSelected ? DesignSystem.Colors.selectionBorder : (isHovered ? DesignSystem.Colors.glassBorderDark : Color.clear), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .onHover { hovering in
            hoveredInlineFilePath = hovering ? file : nil
        }
        .onTapGesture(count: 2) {
            model.openFileInEditor(relativePath: file)
        }
        .contextMenu {
            Button {
                model.stageFile(file)
            } label: {
                Label(L10n("Stage"), systemImage: "plus.circle")
            }
            .disabled(indexStatus != " " && indexStatus != "?")
            Button {
                model.unstageFile(file)
            } label: {
                Label(L10n("Unstage"), systemImage: "minus.circle")
            }
            .disabled(indexStatus == " " || indexStatus == "?")
            Divider()
            Button {
                model.openFileInEditor(relativePath: file)
            } label: {
                Label(L10n("Abrir no Editor"), systemImage: "pencil.and.outline")
            }
            Divider()
            Button(role: .destructive) {
                model.discardChanges(in: file)
            } label: {
                Label(L10n("Descartar Mudanças"), systemImage: "trash")
            }
        }
    }

    private var inlineDiffViewer: some View {
        GlassCard(spacing: 0) {
            if let file = model.selectedChangeFile {
                let isStaged = model.statusEntry(for: file)?.isStaged ?? false
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(file).font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                    Spacer()
                    Button { model.unstageFile(file) } label: {
                        Label(L10n("Unstage"), systemImage: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isStaged)
                    Button { model.stageFile(file) } label: {
                        Label(L10n("Stage"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isStaged)
                }.padding(12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.currentFileDiffLines.enumerated()), id: \.offset) { _, line in
                            inlineDiffLine(line)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.background(DesignSystem.Colors.glassInset)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(DesignSystem.Typography.emptyStateIcon).foregroundStyle(.tertiary)
                    Text(L10n("Selecione um arquivo para ver as mudanças.")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func inlineDiffLine(_ line: String) -> some View {
        let backgroundColor: Color
        let textColor: Color
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            backgroundColor = DesignSystem.Colors.diffAdditionBgRaw; textColor = DesignSystem.Colors.diffAddition
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            backgroundColor = DesignSystem.Colors.diffDeletionBgRaw; textColor = DesignSystem.Colors.diffDeletion
        } else if line.hasPrefix("@@") {
            backgroundColor = DesignSystem.Colors.diffHunkHeaderBg; textColor = DesignSystem.Colors.diffHunkHeader
        } else {
            backgroundColor = Color.clear; textColor = .primary.opacity(0.8)
        }
        return Text(line).font(DesignSystem.Typography.monoBody).padding(.horizontal, 8).padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading).background(backgroundColor).foregroundStyle(textColor)
    }

    private func parseInlineGitStatus(_ line: String) -> (String, String, String) {
        guard let entry = RepositoryViewModel.parsePorcelainStatusLine(line) else {
            return (" ", " ", line.trimmingCharacters(in: .whitespaces))
        }
        return (entry.indexStatus, entry.worktreeStatus, entry.path)
    }

    private var showPendingChangesSummaryCard: Bool {
        model.isAIConfigured
            && !model.uncommittedChanges.isEmpty
            && (model.isLoadingPendingChangesSummary || model.hasVisiblePendingChangesSummary)
    }

    private var pendingChangesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.iconTextGap) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "sparkles")
                        .font(DesignSystem.Typography.bodySemibold)
                        .foregroundStyle(DesignSystem.Colors.ai)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n("map.ai.summary.title"))
                            .font(DesignSystem.Typography.bodySemibold)
                            .foregroundStyle(.primary)
                        if model.isLoadingPendingChangesSummary {
                            Text(L10n("Analisando mudancas..."))
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if model.isLoadingPendingChangesSummary {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    model.dismissPendingChangesSummary()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .cursorArrow()
                .help(L10n("Fechar"))
                .accessibilityLabel(L10n("accessibility.dismiss"))
            }

            if model.hasVisiblePendingChangesSummary {
                Text(model.aiPendingChangesSummary)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Button {
                    model.commitMessageInput = model.aiPendingChangesSummary
                } label: {
                    Label(L10n("Usar como mensagem de commit"), systemImage: "text.insert")
                        .font(DesignSystem.Typography.bodySmallSemibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.hasVisiblePendingChangesSummary)

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .fill(DesignSystem.Colors.glassSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.mediumCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var inlineChangesSummaryBar: some View {
        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            summaryChip(
                title: L10n("changes.summary.staged"),
                count: model.stagedChangesCount,
                color: DesignSystem.Colors.fileStaged,
                icon: "checkmark.circle.fill"
            )
            summaryChip(
                title: L10n("changes.summary.pending"),
                count: model.unstagedChangesCount,
                color: DesignSystem.Colors.warning,
                icon: "pencil.circle.fill"
            )
            if model.untrackedChangesCount > 0 {
                summaryChip(
                    title: L10n("changes.summary.untracked"),
                    count: model.untrackedChangesCount,
                    color: .secondary,
                    icon: "plus.circle"
                )
            }
            Spacer()
            if model.stagedChangesCount == 0 {
                Label(L10n("changes.summary.stageHint"), systemImage: "info.circle")
                    .font(DesignSystem.Typography.metaSemibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func summaryChip(title: String, count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
            Image(systemName: icon)
            Text("\(title) \(count)")
        }
        .font(DesignSystem.Typography.metaSemibold)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func quickCommitScopeChip(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: icon)
                Text(title)
            }
            .font(DesignSystem.Typography.labelSemibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .fill(isSelected ? DesignSystem.Colors.selectionBackground : DesignSystem.Colors.glassSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .stroke(isSelected ? DesignSystem.Colors.selectionBorder : DesignSystem.Colors.glassBorderDark, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .cursorArrow()
    }

    @ViewBuilder
    private func inlineStatusIcon(index: String, worktree: String) -> some View {
        if index != " " && index != "?" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignSystem.Colors.fileStaged)
        } else {
            switch worktree {
            case "?": Image(systemName: "plus.circle").foregroundStyle(.secondary)
            case "M": Image(systemName: "pencil.circle").foregroundStyle(DesignSystem.Colors.fileModified)
            case "D": Image(systemName: "minus.circle").foregroundStyle(DesignSystem.Colors.fileDeleted)
            default: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
    }
}

private struct PendingChangesLaneView: View {
    let height: CGFloat
    let width: CGFloat

    private let trailingPadding: CGFloat = 12
    private let markerDiameter: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(
                x: max(size.width - trailingPadding - markerDiameter, 0),
                y: (size.height - markerDiameter) / 2,
                width: markerDiameter,
                height: markerDiameter
            )

            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.white.opacity(0.7)),
                style: StrokeStyle(lineWidth: 2)
            )
        }
        .frame(width: width, height: height)
    }
}

private struct WorktreePill: View {
    let branch: String
    let isMainWorktree: Bool
    let showRootBadge: Bool
    let dirtyCount: Int
    let hasConflicts: Bool
    let isCurrent: Bool
    let action: () -> Void

    private var isMainLine: Bool {
        let normalized = branch.lowercased()
        return normalized == "main" || normalized == "master"
    }

    private var currentAccent: Color {
        isMainLine ? DesignSystem.Colors.success : DesignSystem.Colors.commitSplit
    }

    private var borderColor: Color {
        if hasConflicts { return DesignSystem.Colors.destructive.opacity(0.8) }
        if dirtyCount > 0 { return DesignSystem.Colors.warning.opacity(0.8) }
        if isCurrent { return currentAccent.opacity(0.95) }
        return DesignSystem.Colors.glassBorderDark
    }

    private var backgroundColor: Color {
        if isCurrent {
            return isMainLine ? DesignSystem.Colors.statusGreenBg : DesignSystem.Colors.selectionBackground
        }
        return DesignSystem.Colors.glassSubtle
    }

    private var statusColor: Color {
        if hasConflicts { return DesignSystem.Colors.destructive }
        if dirtyCount > 0 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.success
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Text("⊞")
                    .font(.system(size: 11, weight: isCurrent ? .bold : .semibold))
                Text(branch)
                    .font(.system(size: 11, weight: isCurrent ? .bold : .semibold, design: .monospaced))
                    .lineLimit(1)
                if isMainWorktree && showRootBadge {
                    Text(L10n("worktree.main.badge"))
                        .font(DesignSystem.Typography.monoMetaBold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.success.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
                        .foregroundStyle(DesignSystem.Colors.success)
                }
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text("\(dirtyCount)")
                    .font(DesignSystem.Typography.monoLabelBold)
                if hasConflicts {
                    Text("⚠")
                        .font(DesignSystem.Typography.labelBold)
                }
                if isCurrent {
                    Text("*")
                        .font(DesignSystem.Typography.monoLabelBold)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isCurrent ? 1.8 : 1)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: isCurrent ? currentAccent.opacity(0.24) : .clear, radius: 8, y: 2)
        .help(isMainWorktree && showRootBadge ? L10n("worktree.main.hint") : "")
    }
}
