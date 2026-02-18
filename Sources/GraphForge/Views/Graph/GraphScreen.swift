import SwiftUI

struct GraphScreen: View {
    @ObservedObject var model: RepositoryViewModel
    @Binding var selectedSection: AppSection?
    @Binding var commitSearchQuery: String
    let performGitAction: (String, String, Bool, @escaping () -> Void) -> Void
    let commitContextMenu: (Commit) -> AnyView
    let branchContextMenu: (String) -> AnyView
    let tagContextMenu: (String) -> AnyView
    
    @State private var currentMatchIndex: Int = 0
    @State private var searchMatchIDs: [String] = []
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 14) {
                header(proxy: proxy)
                
                HSplitView {
                    commitListPane(proxy: proxy)
                        .layoutPriority(1)
                        .frame(minWidth: 400, idealWidth: 800, maxWidth: .infinity)
                    
                    commitDetailsPane
                        .layoutPriority(0)
                        .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .onAppear {
                updateSearchMatches()
                setupKeyboardMonitor(proxy: proxy)
            }
            .onChange(of: commitSearchQuery) { _ in 
                updateSearchMatches()
                if !searchMatchIDs.isEmpty {
                    scrollToMatch(id: searchMatchIDs[0], proxy: proxy)
                }
            }
        }
    }
    
    private func header(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Git Graph")).font(.title2.weight(.semibold))
                Text(L10n("Navegue e salte entre as pontas das branches.")).foregroundStyle(.secondary).font(.subheadline)
            }
            Spacer()
            jumpBar
            searchBar(proxy: proxy).frame(minWidth: 250, idealWidth: 350, maxWidth: 400)
            if model.isBusy { ProgressView().controlSize(.small) }
        }
    }

    private var jumpBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                jumpButton(icon: "crown.fill", color: .green, label: "HEAD") { commitSearchQuery = "HEAD" }
                if let mainName = findBranchName(matches: ["main", "master", "trunk"]) {
                    jumpButton(icon: "shield.fill", color: .orange, label: mainName) { commitSearchQuery = mainName }
                }
            }
            .padding(.trailing, 4)
            
            Divider().frame(height: 20).opacity(0.3)
            
            HStack(spacing: 8) {
                actionButtonSmall(title: "Fetch", icon: "arrow.down.circle", color: .blue, action: model.fetch)
                actionButtonSmall(title: "Pull", icon: "arrow.down.and.line.horizontal", color: .green, action: model.pull)
                actionButtonSmall(title: "Push", icon: "arrow.up.circle", color: .orange, action: model.push)
                
                Button(action: { model.refreshRepository() }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }.buttonStyle(.bordered).controlSize(.small).help(L10n("Atualizar"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    Button { commitSearchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    Text("\(searchMatchIDs.isEmpty ? 0 : currentMatchIndex + 1)/\(searchMatchIDs.count)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6).background(Color.black.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
            
            HStack(spacing: 4) {
                Button(action: { navigateSearch(direction: -1, proxy: proxy) }) { Image(systemName: "chevron.up") }.disabled(searchMatchIDs.isEmpty)
                Button(action: { navigateSearch(direction: 1, proxy: proxy) }) { Image(systemName: "chevron.down") }.disabled(searchMatchIDs.isEmpty)
            }.buttonStyle(.bordered)
        }
    }
    
    private func commitListPane(proxy: ScrollViewProxy) -> some View {
        GlassCard(spacing: 0) {
            HStack {
                Text(L10n("Commits")).font(.headline)
                Spacer()
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
                                performGitAction(L10n("Checkout"), L10n("Deseja fazer checkout para %@", branch), false) {
                                    model.checkout(reference: branch)
                                }
                            },
                            onSelect: {
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
    
    private var pendingChangesRow: some View {
        HStack(spacing: 0) {
            // Visualize as a special node in the graph
            VStack(spacing: 0) {
                Rectangle().fill(Color.orange).frame(width: 3, height: 40)
                Circle().fill(Color.orange).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                Rectangle().fill(Color.orange.opacity(0.3)).frame(width: 3, height: 40)
            }
            .frame(width: 60)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                    )
                
                HStack(spacing: 16) {
                    Image(systemName: "pencil.and.outline").font(.title2).foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n("Alteracoes Pendentes")).font(.system(size: 14, weight: .bold)).foregroundStyle(.orange)
                        Text("\(model.uncommittedCount) \(L10n("arquivos modificados"))").font(.caption).foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation { selectedSection = .operations }
                    } label: {
                        Label(L10n("Fazer Commit"), systemImage: "plus.square.fill")
                            .font(.system(size: 12, weight: .bold))
                    }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                }
                .padding(.horizontal, 20)
            }
            .padding(.trailing, 24)
        }
        .frame(height: 96)
    }

    private func setupKeyboardMonitor(proxy: ScrollViewProxy) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isSearchFocused { return event }
            switch event.keyCode {
            case 126: navigateSelection(direction: -1, proxy: proxy); return nil
            case 125: navigateSelection(direction: 1, proxy: proxy); return nil
            default:
                if event.modifierFlags.contains(.command) {
                    if event.charactersIgnoringModifiers == "f" { isSearchFocused = true; return nil }
                    if event.charactersIgnoringModifiers == "r" { model.refreshRepository(); return nil }
                }
                return event
            }
        }
    }
    
    private func navigateSelection(direction: Int, proxy: ScrollViewProxy) {
        let commits = model.commits
        guard !commits.isEmpty else { return }
        let currentIndex = commits.firstIndex(where: { $0.id == model.selectedCommitID }) ?? -1
        let nextIndex = currentIndex + direction
        if nextIndex >= 0 && nextIndex < commits.count {
            let nextCommit = commits[nextIndex]
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
    
    private var commitDetailsPane: some View {
        GlassCard(spacing: 0) {
            HStack {
                Text(L10n("Detalhes")).font(.headline)
                Spacer()
                if let selectedCommitID = model.selectedCommitID {
                    Text(String(selectedCommitID.prefix(8))).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            Divider()
            ScrollView {
                Text(model.commitDetails).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
    }
}
