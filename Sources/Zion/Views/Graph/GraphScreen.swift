import SwiftUI
import AppKit

struct GraphScreen: View {
    static let semanticResultsScrollTarget = "graph.semanticResults.scrollTarget"

    @Bindable var model: RepositoryViewModel
    @Binding var commitSearchQuery: String
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    let commitContextMenu: (Commit) -> AnyView
    let branchContextMenu: (String) -> AnyView
    let tagContextMenu: (String) -> AnyView

    @EnvironmentObject private var shortcutRegistry: ShortcutRegistry
    @State var currentMatchIndex: Int = 0
    @State var searchMatchIDs: [String] = []
    @State var searchMatchIDSet: Set<String> = []
    @State var aiMatchIDSet: Set<String> = []
    @State var searchDebounceTask: Task<Void, Never>?
    @State var isShowingQuickCommit: Bool = false
    @State var quickCommitIncludesAllChanges: Bool = false
    @State var isShowingCreateBranchFromPending: Bool = false
    @State var pendingBranchNameInput: String = ""
    @State var isShowingQuickStash: Bool = false
    @State var isShowingStashList: Bool = false
    @FocusState var isSearchFocused: Bool
    @FocusState var isCommitMessageFocused: Bool

    @State var showingPendingChanges: Bool = false
    @State var hoveredInlineFilePath: String?
    @FocusState var isGraphFocused: Bool

    /// Hoisted out of the per-row `LazyVStack` body so `UserDefaults.bool(forKey:)`
    /// is read once per render of GraphScreen instead of once per visible commit
    /// row. SwiftUI re-renders the LazyVStack on every selection change.
    @AppStorage(UserDefaultsKeys.General.graphAuthorAvatarsEnabled)
    private var graphAuthorAvatarsEnabled: Bool = false

    /// GraphScreen stays mounted under other workspace tabs (ZStack-overlay).
    /// Gate avatar prefetch on this so we don't fire off Gravatar downloads
    /// for commits the user isn't looking at.
    @Environment(\.zionActiveSection) private var activeSection: AppSection?

    var commitRowMinWidth: CGFloat {
        let rawLaneWidth = CGFloat(max(model.maxLaneCount, 1)) * 20
        let cappedLaneWidth = min(rawLaneWidth, DesignSystem.Layout.graphColumnMaxWidth)
        return max(DesignSystem.Layout.commitRowFloor, cappedLaneWidth + DesignSystem.Layout.commitRowLaneOffset)
    }

    var commitGraphColumnWidth: CGFloat {
        let span = CGFloat(max(model.maxLaneCount - 1, 0)) * 20
        let uncapped = max(10 + 12 + span, 56)
        return min(uncapped, DesignSystem.Layout.graphColumnMaxWidth)
    }

    private var commitRowMaxWidth: CGFloat {
        DesignSystem.Layout.centeredContentMaxWidth
    }

    func commitRowWidth(for containerWidth: CGFloat) -> CGFloat {
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

                ZStack {
                    DraggableSplitView(
                        axis: .horizontal,
                        ratio: $model.graphSplitRatio,
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

                    if model.isRepositorySwitchRefreshingInBackground {
                        ZionLoadingOverlay()
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.cardCornerRadius))
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .onAppear {
                updateSearchMatches()
                // Restore the commit the user was looking at when they last
                // left the Graph tab. Approximated by selectedCommitID since
                // measuring topmost-visible row in a SwiftUI LazyVStack
                // without a ScrollPositionReader is more complex than it's
                // worth here.
                if let anchor = model.graphScrollAnchorCommitID {
                    DispatchQueue.main.async {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
            .onChange(of: activeSection) { _, newSection in
                if newSection == .graph {
                    if let anchor = model.graphScrollAnchorCommitID {
                        DispatchQueue.main.async {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                } else {
                    // Leaving Graph: snapshot the current focus so the next
                    // re-entry lands roughly where the user left off.
                    if let id = model.selectedCommitID {
                        model.graphScrollAnchorCommitID = id
                    }
                }
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
                    try? await Task.sleep(nanoseconds: Constants.Timing.commitSearchDebounce)
                    guard !Task.isCancelled else { return }
                    updateSearchMatches()
                    if !searchMatchIDs.isEmpty {
                        scrollToMatch(id: searchMatchIDs[0], proxy: proxy)
                    }
                }
            }
            .onChange(of: model.aiHistorySearchResult) { _, newValue in
                updateSearchMatches()
                guard model.isSemanticSearchActive, newValue != nil else { return }
                if let firstHash = newValue?.matches.first?.hash,
                   let commit = matchingCommit(for: firstHash) {
                    model.selectCommit(commit.id)
                }
                scrollToSemanticResults(proxy: proxy)
            }
            .onChange(of: model.gitSearchResults) { _, newValue in
                guard !newValue.isEmpty else { return }
                scrollToGitSearchResults(proxy: proxy)
            }
            .onChange(of: model.uncommittedChanges) { _, changes in
                if changes.isEmpty, showingPendingChanges {
                    showingPendingChanges = false
                    model.selectChangeFile(nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusCommitField)) { _ in
                if model.uncommittedCount > 0 {
                    showingPendingChanges = true
                    isShowingQuickCommit = true
                }
            }
            .background {
                Button("") { isSearchFocused = true }
                    .applyShortcutBinding(shortcutRegistry.binding(for: .graphFind))
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

    private func commitListPane(proxy: ScrollViewProxy) -> some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Commits"), icon: "list.bullet") {
                Text("\(model.commits.count) \(L10n("itens"))").font(DesignSystem.Typography.label).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()
            GeometryReader { geometry in
                let rowWidth = commitRowWidth(for: geometry.size.width)

                ScrollView(.vertical, showsIndicators: true) {
                    // Avatars are only prefetched while the Graph section is the
                    // visible one — every other section keeps GraphScreen mounted
                    // but hidden, and we don't want to spend network on rows the
                    // user isn't seeing.
                    let avatarsEnabled = graphAuthorAvatarsEnabled && activeSection == .graph
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
                                .padding(.top, DesignSystem.Spacing.standard)
                                .frame(width: rowWidth, alignment: .leading)
                                .id(Self.semanticResultsScrollTarget)
                        }

                        if !model.gitSearchResults.isEmpty || model.isGitSearching {
                            gitSearchResultsPanel(proxy: proxy)
                                .padding(.top, DesignSystem.Spacing.standard)
                                .frame(width: rowWidth, alignment: .leading)
                                .id(Self.gitSearchResultsScrollTarget)
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
                                    DiagnosticLogger.shared.log(.info, "graph.onCheckout", context: "branch=\(branch) isBusy=\(model.isBusy) activeToken=\(model.activeGitActionToken != nil)", source: "GraphScreen")
                                    let isRemote = model.isRemoteRefName(branch)
                                    if isRemote {
                                        var localName = branch
                                        var remoteName = ""
                                        for remote in model.remotes {
                                            if branch.hasPrefix("\(remote.name)/") {
                                                localName = String(branch.dropFirst(remote.name.count + 1))
                                                remoteName = remote.name
                                                break
                                            }
                                        }

                                        // Multi-remote collision: local with same name already
                                        // exists and tracks a different remote. Surface explicit
                                        // dialog so the user picks the intent (matches Sourcetree /
                                        // GitGraph behavior — never silently rewrite metadata).
                                        if let conflictUpstream = model.conflictingUpstream(forLocalName: localName, clickedRemote: branch),
                                           !remoteName.isEmpty {
                                            let suggestedNew = "\(remoteName)-\(localName)"
                                            let alert = NSAlert()
                                            alert.alertStyle = .warning
                                            alert.messageText = L10n("checkout.multiRemote.title", localName)
                                            alert.informativeText = L10n("checkout.multiRemote.message", localName, conflictUpstream, branch)
                                            alert.addButton(withTitle: L10n("checkout.multiRemote.switch", branch))
                                            alert.addButton(withTitle: L10n("checkout.multiRemote.newBranch", suggestedNew))
                                            alert.addButton(withTitle: L10n("Cancelar"))
                                            switch alert.runModal() {
                                            case .alertFirstButtonReturn:
                                                model.switchUpstreamAndPull(localName: localName, remoteTarget: branch)
                                            case .alertSecondButtonReturn:
                                                model.createTrackingBranch(newLocalName: suggestedNew, remoteTarget: branch)
                                            default:
                                                break
                                            }
                                        } else {
                                            let title = L10n("Checkout & Pull")
                                            let message = L10n("Deseja fazer checkout de %@ e puxar as alterações?", localName)
                                            performGitAction(title, message, true) {
                                                model.checkoutAndPull(reference: branch)
                                            }
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
                                avatarImage: avatarsEnabled ? model.avatarImage(for: commit.email) : nil,
                                graphColumnMaxWidth: commitGraphColumnWidth
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
            if model.commits.isEmpty && model.uncommittedChanges.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(DesignSystem.Typography.emptyStateIcon)
                        .foregroundStyle(.tertiary)
                    Text(L10n("graph.empty.title"))
                        .font(DesignSystem.Typography.sheetTitle)
                        .foregroundStyle(.secondary)
                    Text(L10n("graph.empty.hint"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
            if model.hasMoreCommits { loadMoreButton }
        }
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
                    .font(isCurrent ? DesignSystem.Typography.bodySmallBold : DesignSystem.Typography.bodySmallSemibold)
                Text(branch)
                    .font(isCurrent ? DesignSystem.Typography.monoSmallBold : DesignSystem.Typography.monoSmallMedium)
                    .lineLimit(1)
                if isMainWorktree && showRootBadge {
                    Text(L10n("worktree.main.badge"))
                        .font(DesignSystem.Typography.monoMetaBold)
                        .padding(.horizontal, 6)
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
