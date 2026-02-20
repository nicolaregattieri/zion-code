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
    @State private var isShowingQuickCommit: Bool = false
    @State private var isShowingQuickStash: Bool = false
    @State private var isShowingStashList: Bool = false
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isCommitMessageFocused: Bool
    
    @State private var showingPendingChanges: Bool = false
    @FocusState private var isGraphFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 14) {
                header(proxy: proxy)

                HSplitView {
                    commitListPane(proxy: proxy)
                        .focusable()
                        .focused($isGraphFocused)
                        .onMoveCommand { direction in
                            switch direction {
                            case .up: navigateSelection(direction: -1, proxy: proxy)
                            case .down: navigateSelection(direction: 1, proxy: proxy)
                            default: break
                            }
                        }
                        .onExitCommand { model.selectCommit(nil); showingPendingChanges = false }
                        .layoutPriority(1)
                        .frame(minWidth: 400, idealWidth: 800, maxWidth: .infinity)
                        .padding(.trailing, 6)

                    commitDetailsPane
                        .animation(nil, value: showingPendingChanges)
                        .layoutPriority(0)
                        .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity)
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
                updateSearchMatches()
                if !searchMatchIDs.isEmpty {
                    scrollToMatch(id: searchMatchIDs[0], proxy: proxy)
                }
            }
            .background {
                Button("") { isSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0)
            }
        }
    }
    
    private func header(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Zion Tree")).font(.title2.weight(.semibold))
                Text(L10n("Navegue e salte entre as pontas das branches.")).foregroundStyle(.secondary).font(.subheadline)
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

    private var jumpBar: some View {
        HStack(spacing: 8) {
            // Crown: checkout to default branch (develop > main > master)
            jumpButton(icon: "crown.fill", color: .green, label: L10n("Checkout Default")) {
                if let target = findDefaultBranch() {
                    performGitAction(L10n("Checkout"), L10n("Deseja fazer checkout para %@?", target), false) {
                        model.checkout(reference: target)
                    }
                }
            }

            // Shield: scroll to main/master in graph
            if let mainName = findBranchName(matches: ["main", "master", "trunk"]) {
                jumpButton(icon: "shield.fill", color: .orange, label: mainName) { commitSearchQuery = mainName }
            }

            // Flag: scroll to develop in graph
            if let devName = findBranchName(matches: ["develop", "development", "dev"]) {
                jumpButton(icon: "flag.fill", color: .purple, label: devName) { commitSearchQuery = devName }
            }

            Divider().frame(height: 20).padding(.horizontal, 4).opacity(0.3)

            Button(action: { model.refreshRepository() }) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("Atualizar Grafo"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.glassElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func findDefaultBranch() -> String? {
        let priorities = ["develop", "development", "dev", "main", "master", "trunk"]
        for candidate in priorities {
            if let _ = findBranchName(matches: [candidate]) {
                return candidate
            }
        }
        return nil
    }

    private func actionButtonSmall(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(L10n(title)).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func jumpButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).background(color.gradient).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(.plain).help(L10n("Saltar para") + " \(label)")
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
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n("Busca (Cmd+F)"), text: $commitSearchQuery).textFieldStyle(.plain).focused($isSearchFocused)
                if !commitSearchQuery.isEmpty {
                    Button { commitSearchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help(L10n("Limpar busca"))
                    Text("\(searchMatchIDs.isEmpty ? 0 : currentMatchIndex + 1)/\(searchMatchIDs.count)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(Color.black.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
            
            HStack(spacing: 4) {
                Button(action: { navigateSearch(direction: -1, proxy: proxy) }) { Image(systemName: "chevron.up") }.disabled(searchMatchIDs.isEmpty).help(L10n("Resultado anterior"))
                Button(action: { navigateSearch(direction: 1, proxy: proxy) }) { Image(systemName: "chevron.down") }.disabled(searchMatchIDs.isEmpty).help(L10n("Proximo resultado"))
            }.buttonStyle(.bordered)
        }
    }
    
    private func commitListPane(proxy: ScrollViewProxy) -> some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Commits"), icon: "list.bullet") {
                Text("\(model.commits.count) \(L10n("itens"))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    // PENDING CHANGES - TOP OF THE LIST
                    if !model.uncommittedChanges.isEmpty {
                        pendingChangesRow
                            .padding(.top, 8)
                    }
                    
                    ForEach(model.commits) { commit in
                        CommitRowView(
                            commit: commit,
                            isSelected: model.selectedCommitID == commit.id,
                            isSearchMatch: searchMatchIDs.contains(commit.id),
                            searchQuery: commitSearchQuery,
                            laneCount: model.maxLaneCount,
                            currentBranch: model.currentBranch,
                            onCheckout: { branch in
                                let isRemote = model.isRemoteRefName(branch)
                                let title = isRemote ? L10n("Checkout & Pull") : L10n("Checkout")
                                
                                var localName = branch
                                if isRemote {
                                    for remote in model.remotes {
                                        if branch.hasPrefix("\(remote.name)/") {
                                            localName = String(branch.dropFirst(remote.name.count + 1))
                                            break
                                        }
                                    }
                                }

                                let message = isRemote 
                                    ? L10n("Deseja fazer checkout de %@ e puxar as alterações?", localName)
                                    : L10n("Deseja fazer checkout para %@?", branch)
                                
                                performGitAction(title, message, false) {
                                    if isRemote {
                                        model.checkoutAndPull(reference: branch)
                                    } else {
                                        model.checkout(reference: branch)
                                    }
                                }
                            },
                            onSelect: {
                                showingPendingChanges = false
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    model.selectCommit(commit.id)
                                }
                            },
                            contextMenu: commitContextMenu(commit),
                            branchContextMenu: branchContextMenu,
                            tagContextMenu: tagContextMenu,
                            remotes: model.remotes.map(\.name)
                        )
                        .id(commit.id)
                        .overlay(alignment: .trailing) {
                            if !searchMatchIDs.isEmpty && searchMatchIDs[currentMatchIndex] == commit.id {
                                Image(systemName: "arrow.left").foregroundStyle(.yellow).padding(.trailing, 32)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .frame(minWidth: 1000, alignment: .leading)
            }
            if model.hasMoreCommits { loadMoreButton }
        }
    }
    
    /// Build a pending-changes commit that aligns with the first real commit's lane and pass-through lanes.
    private var pendingChangesCommit: Commit {
        if let first = model.commits.first {
            // Inherit lane position and all active pass-through lanes from HEAD
            let pendingColorKey = first.nodeColorKey
            var laneColors = first.laneColors
            // Ensure the pending node's own lane is in the color list
            if !laneColors.contains(where: { $0.lane == first.lane }) {
                laneColors.append(LaneColor(lane: first.lane, colorKey: pendingColorKey))
            }
            return Commit(
                id: "pending",
                shortHash: "",
                parents: [],
                author: "",
                date: Date(),
                subject: "",
                decorations: [],
                lane: first.lane,
                nodeColorKey: pendingColorKey,
                incomingLanes: first.incomingLanes,
                outgoingLanes: first.incomingLanes,
                laneColors: laneColors,
                outgoingEdges: []
            )
        }
        // Fallback when no commits exist
        return Commit(
            id: "pending",
            shortHash: "",
            parents: [],
            author: "",
            date: Date(),
            subject: "",
            decorations: [],
            lane: 0,
            nodeColorKey: 3,
            incomingLanes: [0],
            outgoingLanes: [0],
            laneColors: [LaneColor(lane: 0, colorKey: 3)],
            outgoingEdges: []
        )
    }

    private var pendingChangesRow: some View {
        HStack(spacing: 0) {
            // PERFECT ALIGNMENT: Use the real LaneGraphView with a dummy commit
            LaneGraphView(
                commit: pendingChangesCommit,
                laneCount: model.maxLaneCount,
                isSelected: false,
                isHead: false,
                height: 102
            )

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(showingPendingChanges ? Color.orange.opacity(0.12) : Color.orange.opacity(0.05))
                    .frame(height: 86)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(showingPendingChanges ? Color.orange.opacity(0.5) : Color.orange.opacity(0.2), lineWidth: 1.5)
                    )

                HStack(spacing: 12) {
                    Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.orange.opacity(0.8))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(L10n("Alteracoes Pendentes")).font(.system(size: 13, weight: .bold)).foregroundStyle(.primary.opacity(0.9))
                        Text("\(model.uncommittedCount) \(L10n("arquivos modificados"))").font(.system(size: 10)).foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            isShowingQuickCommit = true
                        } label: {
                            Label(L10n("Commit"), systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                        .sheet(isPresented: $isShowingQuickCommit) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L10n("Criar Commit Rapido")).font(.title3.bold())
                                Text(L10n("Suas alteracoes serao rastreadas automaticamente (git add -A).")).font(.caption).foregroundStyle(.secondary)

                                HStack(alignment: .bottom, spacing: 8) {
                                    TextField(L10n("Mensagem do commit..."), text: $model.commitMessageInput, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(3, reservesSpace: true)
                                        .onSubmit {
                                            if !model.commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                model.commit(message: model.commitMessageInput)
                                                isShowingQuickCommit = false
                                            }
                                        }

                                    Button {
                                        model.suggestCommitMessage()
                                    } label: {
                                        if model.isGeneratingAIMessage {
                                            ProgressView().controlSize(.small).frame(width: 12, height: 12)
                                        } else {
                                            Image(systemName: "sparkles").font(.system(size: 12))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(model.isGeneratingAIMessage)
                                    .help(model.isAIConfigured ? L10n("Gerar mensagem com IA") : L10n("Sugerir mensagem de commit"))
                                    .onChange(of: model.suggestedCommitMessage) { _, newValue in
                                        if !newValue.isEmpty {
                                            model.commitMessageInput = newValue
                                        }
                                    }
                                }

                                HStack {
                                    Button(L10n("Cancelar")) { isShowingQuickCommit = false }
                                        .buttonStyle(.bordered)
                                        .keyboardShortcut(.escape, modifiers: [])

                                    Spacer()

                                    Button(L10n("Commit")) {
                                        model.commit(message: model.commitMessageInput)
                                        isShowingQuickCommit = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .disabled(model.commitMessageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .keyboardShortcut(.return, modifiers: [])
                                }
                            }
                            .padding(24)
                            .frame(width: 450)
                        }

                        // STASH MENU - COMBINED
                        Menu {
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
                            HStack(spacing: 4) {
                                Image(systemName: "archivebox.fill")
                                Text(L10n("Stash"))
                                if !model.stashes.isEmpty {
                                    Text("\(model.stashes.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .background(Color.blue.opacity(0.5))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
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
                                                    Text(stash).font(.system(size: 12, design: .monospaced)).lineLimit(2)
                                                }
                                                Spacer()
                                                HStack(spacing: 8) {
                                                    Button(L10n("Apply")) { model.selectedStash = stash; model.applySelectedStash(); isShowingStashList = false }.buttonStyle(.bordered).controlSize(.small)
                                                    Button(L10n("Pop")) { model.selectedStash = stash; model.popSelectedStash(); isShowingStashList = false }.buttonStyle(.bordered).controlSize(.small)
                                                    Button { model.selectedStash = stash; model.dropSelectedStash() } label: { Image(systemName: "trash") }.buttonStyle(.bordered).tint(.red).controlSize(.small)
                                                }
                                            }
                                            .padding(10).background(DesignSystem.Colors.glassSubtle).cornerRadius(8)
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
                withAnimation(.easeInOut(duration: 0.12)) {
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
            withAnimation(.easeInOut(duration: 0.12)) {
                model.selectCommit(nextCommit.id)
                proxy.scrollTo(nextCommit.id, anchor: .center)
            }
        }
    }

    private func updateSearchMatches() {
        let query = commitSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { searchMatchIDs = []; currentMatchIndex = 0; return }
        
        let priority1 = model.commits.filter { commit in
            commit.decorations.contains { d in
                let cleaned = d.lowercased().replacingOccurrences(of: "head -> ", with: "").replacingOccurrences(of: "tag: ", with: "")
                return cleaned == query || cleaned.hasSuffix("/" + query)
            }
        }.map(\.id)
        
        let priority2 = model.commits.filter { commit in
            !priority1.contains(commit.id) && commit.decorations.contains { $0.lowercased().contains(query) }
        }.map(\.id)
        
        let priority3 = model.commits.filter { commit in
            !priority1.contains(commit.id) && !priority2.contains(commit.id) && (
                commit.shortHash.lowercased().contains(query) ||
                commit.author.lowercased().contains(query) ||
                commit.subject.lowercased().contains(query)
            )
        }.map(\.id)
        
        searchMatchIDs = priority1 + priority2 + priority3
        if currentMatchIndex >= searchMatchIDs.count { currentMatchIndex = 0 }
    }
    
    private func navigateSearch(direction: Int, proxy: ScrollViewProxy) {
        guard !searchMatchIDs.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + direction + searchMatchIDs.count) % searchMatchIDs.count
        scrollToMatch(id: searchMatchIDs[currentMatchIndex], proxy: proxy)
    }
    
    private func scrollToMatch(id: String, proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            proxy.scrollTo(id, anchor: .center)
            model.selectCommit(id)
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
    
    @ViewBuilder
    private var commitDetailsPane: some View {
        if showingPendingChanges {
            inlineChangesPane
        } else {
            GlassCard(spacing: 0) {
                CardHeader(L10n("Detalhes"), icon: "doc.text.magnifyingglass") {
                    if let selectedCommitID = model.selectedCommitID {
                        Text(String(selectedCommitID.prefix(8)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)

                Divider()

                ScrollView {
                    CommitDetailContent(rawDetails: model.commitDetails, model: model, commitID: model.selectedCommitID)
                        .padding(12)
                }
            }
        }
    }

    // MARK: - Inline Changes Pane (replaces detail when pending changes selected)

    private var inlineChangesPane: some View {
        VSplitView {
            inlineFileList
                .frame(minHeight: 150, idealHeight: 250)
            inlineDiffViewer
                .frame(minHeight: 200, idealHeight: 400)
        }
    }

    private var inlineFileList: some View {
        GlassCard(spacing: 0) {
            CardHeader(L10n("Changes"), icon: "pencil.circle", subtitle: "\(model.uncommittedCount) \(L10n("arquivos modificados"))") {
                Button { model.refreshRepository() } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain).help(L10n("Atualizar"))
            }
            .padding(12)
            Divider()
            if model.uncommittedChanges.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 32)).foregroundStyle(.green.opacity(0.6))
                    Text(L10n("Tudo limpo!")).font(.headline)
                    Text(L10n("Nenhuma alteração pendente no momento.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
        return Button {
            model.selectChangeFile(file)
        } label: {
            HStack(spacing: 10) {
                inlineStatusIcon(index: indexStatus, worktree: workTreeStatus).font(.system(size: 14))
                Text(file).font(.system(size: 12, weight: isSelected ? .bold : .regular, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if indexStatus != " " && indexStatus != "?" {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var inlineDiffViewer: some View {
        GlassCard(spacing: 0) {
            if let file = model.selectedChangeFile {
                HStack {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(file).font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                    Spacer()
                    Button { model.stageFile(file) } label: {
                        Label(L10n("Stage"), systemImage: "plus")
                    }.buttonStyle(.bordered).controlSize(.small)
                }.padding(12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let lines = model.currentFileDiff.split(separator: "\n", omittingEmptySubsequences: false)
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            inlineDiffLine(String(line))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.background(Color.black.opacity(0.2))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 48)).foregroundStyle(.tertiary)
                    Text(L10n("Selecione um arquivo para ver as mudanças.")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func inlineDiffLine(_ line: String) -> some View {
        let backgroundColor: Color
        let textColor: Color
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            backgroundColor = Color.green.opacity(0.15); textColor = Color.green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            backgroundColor = Color.red.opacity(0.15); textColor = Color.red
        } else if line.hasPrefix("@@") {
            backgroundColor = Color.blue.opacity(0.1); textColor = Color.blue.opacity(0.8)
        } else {
            backgroundColor = Color.clear; textColor = .primary.opacity(0.8)
        }
        return Text(line).font(.system(size: 12, design: .monospaced)).padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading).background(backgroundColor).foregroundStyle(textColor)
    }

    private func parseInlineGitStatus(_ line: String) -> (String, String, String) {
        if line.count < 3 { return (" ", " ", line) }
        let index = String(line.prefix(1))
        let worktree = String(line.prefix(2).suffix(1))
        let file = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return (index, worktree, file)
    }

    @ViewBuilder
    private func inlineStatusIcon(index: String, worktree: String) -> some View {
        if index != " " && index != "?" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            switch worktree {
            case "?": Image(systemName: "plus.circle").foregroundStyle(.secondary)
            case "M": Image(systemName: "pencil.circle").foregroundStyle(.orange)
            case "D": Image(systemName: "minus.circle").foregroundStyle(.red)
            default: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
    }
}
