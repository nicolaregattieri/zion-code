import SwiftUI

enum FindInFilesViewLogic {
    static func shouldApplySearchResults(
        requestID: Int,
        latestRequestID: Int,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && requestID == latestRequestID
    }

    static func preferredSelectedMatchID(
        currentSelectedID: String?,
        matches: [FindInFilesMatch]
    ) -> String? {
        guard !matches.isEmpty else { return nil }
        if let currentSelectedID,
           matches.contains(where: { $0.id == currentSelectedID }) {
            return currentSelectedID
        }
        return matches.first?.id
    }

    static func nextMatch(
        matches: [FindInFilesMatch],
        currentSelectedID: String?,
        direction: Int
    ) -> FindInFilesMatch? {
        guard !matches.isEmpty else { return nil }

        let nextIndex: Int
        if let currentSelectedID,
           let index = matches.firstIndex(where: { $0.id == currentSelectedID }) {
            nextIndex = (index + direction + matches.count) % matches.count
        } else {
            nextIndex = direction < 0 ? max(matches.count - 1, 0) : 0
        }
        return matches[nextIndex]
    }
}

struct FindInFilesView: View {
    @Bindable var model: RepositoryViewModel
    @Binding var query: String
    @Binding var includePattern: String
    @Binding var excludePattern: String
    @Binding var results: [FindInFilesFileResult]
    @Binding var isSearching: Bool
    @Binding var scopePath: String?
    let onClose: () -> Void

    @State private var showFilters: Bool = false
    @State private var expandedFiles: Set<String> = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedMatchID: String?
    @State private var searchRequestID: Int = 0
    @State private var keyMonitor: Any?
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case query
        case include
        case exclude
    }

    private var flattenedMatches: [FindInFilesMatch] {
        results.flatMap(\.matches)
    }

    private var selectedMatchPositionText: String? {
        guard !flattenedMatches.isEmpty,
              let selectedMatchID,
              let index = flattenedMatches.firstIndex(where: { $0.id == selectedMatchID }) else {
            return nil
        }
        return "\(index + 1)/\(flattenedMatches.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            searchFields
            Divider()
            resultsList
        }
        .onAppear {
            focusedField = .query
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
            searchTask?.cancel()
        }
    }

    // MARK: - Search Fields

    private var searchFields: some View {
        VStack(spacing: 6) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "magnifyingglass")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)

                TextField(L10n("Buscar nos Arquivos"), text: $query)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.monoBody)
                    .focused($focusedField, equals: .query)
                    .onSubmit { triggerSearch(openDirectionAfterSearch: 1) }

                if isSearching {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }

                if let selectedMatchPositionText {
                    Text(selectedMatchPositionText)
                        .font(DesignSystem.Typography.monoLabel)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 42)
                }

                if !flattenedMatches.isEmpty {
                    SearchNavButton(
                        icon: "chevron.up",
                        tooltip: L10n("editor.search.previous") + " (⇧Enter)"
                    ) {
                        openRelativeMatch(direction: -1)
                    }

                    SearchNavButton(
                        icon: "chevron.down",
                        tooltip: L10n("editor.search.next") + " (Enter)"
                    ) {
                        openRelativeMatch(direction: 1)
                    }
                }

                if !query.isEmpty {
                    SearchNavButton(icon: "xmark.circle.fill", tooltip: L10n("Limpar busca"), isSecondary: true) {
                        query = ""
                        selectedMatchID = nil
                        triggerSearch()
                    }
                }

                SearchNavButton(
                    icon: "line.3.horizontal.decrease.circle\(showFilters ? ".fill" : "")",
                    tooltip: L10n("Filtros"),
                    isSecondary: !showFilters
                ) {
                    showFilters.toggle()
                }

                SearchNavButton(icon: "xmark.circle.fill", tooltip: L10n("findInFiles.close"), isSecondary: true) {
                    onClose()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))

            if showFilters {
                filterFields
            }

            // Scope indicator
            if let scope = scopePath {
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "folder")
                        .font(DesignSystem.Typography.meta)
                    Text(URL(fileURLWithPath: scope).lastPathComponent)
                        .font(DesignSystem.Typography.monoMeta)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        self.scopePath = nil
                        triggerSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }

            // Summary
            if !results.isEmpty {
                let totalMatches = results.reduce(0) { $0 + $1.matches.count }
                Text(L10n("findInFiles.summary", "\(totalMatches)", "\(results.count)"))
                    .font(DesignSystem.Typography.monoMeta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .onChange(of: query) { _, _ in
            debounceSearch()
        }
        .onChange(of: includePattern) { _, _ in
            debounceSearch()
        }
        .onChange(of: excludePattern) { _, _ in
            debounceSearch()
        }
    }

    private var filterFields: some View {
        VStack(spacing: 4) {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Text(L10n("Incluir arquivos"))
                    .font(DesignSystem.Typography.monoMeta)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("*.swift, *.ts", text: $includePattern)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.monoMeta)
                    .focused($focusedField, equals: .include)
                    .onSubmit { triggerSearch(openDirectionAfterSearch: 1) }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.glassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
            }
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Text(L10n("Excluir arquivos"))
                    .font(DesignSystem.Typography.monoMeta)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("*.lock, dist/*", text: $excludePattern)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.monoMeta)
                    .focused($focusedField, equals: .exclude)
                    .onSubmit { triggerSearch(openDirectionAfterSearch: 1) }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.glassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
            }
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            if results.isEmpty && !query.isEmpty && !isSearching {
                Text(L10n("Nenhum resultado"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                    .padding(DesignSystem.Spacing.sectionGap)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { fileResult in
                        fileResultRow(fileResult)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func fileResultRow(_ fileResult: FindInFilesFileResult) -> some View {
        let isExpanded = expandedFiles.contains(fileResult.file)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DesignSystem.Motion.snappy) {
                    if isExpanded {
                        expandedFiles.remove(fileResult.file)
                    } else {
                        expandedFiles.insert(fileResult.file)
                    }
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(DesignSystem.Typography.micro)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "doc.text")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)

                    Text(fileResult.file)
                        .font(DesignSystem.Typography.monoSmallMedium)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text("\(fileResult.matches.count)")
                        .font(DesignSystem.Typography.monoMeta)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignSystem.Colors.selectionBackground)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(fileResult.matches) { match in
                    matchRow(match)
                }
            }
        }
    }

    private func matchRow(_ match: FindInFilesMatch) -> some View {
        let isSelected = selectedMatchID == match.id
        return Button {
            openMatch(match)
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Text("\(match.line)")
                    .font(DesignSystem.Typography.monoMeta)
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, alignment: .trailing)

                highlightedPreview(match.preview, query: query)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.leading, 22)
            .padding(.vertical, 3)
            .background(isSelected ? DesignSystem.Colors.selectionBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func highlightedPreview(_ text: String, query: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty,
              let range = trimmed.range(of: query, options: .caseInsensitive) else {
            return Text(trimmed)
                .font(DesignSystem.Typography.monoMeta)
                .foregroundStyle(.secondary)
        }

        let before = String(trimmed[trimmed.startIndex..<range.lowerBound])
        let matched = String(trimmed[range])
        let after = String(trimmed[range.upperBound...])

        return Text(before)
            .font(DesignSystem.Typography.monoMeta)
            .foregroundStyle(.secondary)
        + Text(matched)
            .font(DesignSystem.Typography.monoMeta)
            .bold()
            .foregroundStyle(.primary)
        + Text(after)
            .font(DesignSystem.Typography.monoMeta)
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func debounceSearch() {
        scheduleSearch(debounced: true, openDirectionAfterSearch: nil)
    }

    private func triggerSearch(openDirectionAfterSearch: Int? = nil) {
        scheduleSearch(debounced: false, openDirectionAfterSearch: openDirectionAfterSearch)
    }

    private func scheduleSearch(debounced: Bool, openDirectionAfterSearch: Int?) {
        searchTask?.cancel()
        searchRequestID += 1
        let requestID = searchRequestID

        searchTask = Task {
            if debounced {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            await performSearch(requestID: requestID, openDirectionAfterSearch: openDirectionAfterSearch)
        }
    }

    private func performSearch(requestID: Int, openDirectionAfterSearch: Int?) async {
        guard requestID == searchRequestID else { return }

        guard !query.isEmpty else {
            isSearching = false
            results = []
            selectedMatchID = nil
            return
        }

        isSearching = true
        let searchResults = await model.findInFiles(
            query: query,
            includePattern: includePattern,
            excludePattern: excludePattern,
            scopePath: scopePath
        )

        guard FindInFilesViewLogic.shouldApplySearchResults(
            requestID: requestID,
            latestRequestID: searchRequestID,
            isCancelled: Task.isCancelled
        ) else { return }

        isSearching = false
        results = searchResults

        // Auto-expand all files when few results
        if searchResults.count <= 10 {
            expandedFiles = Set(searchResults.map(\.file))
        }

        // Keep selection stable when possible.
        let resultMatches = searchResults.flatMap(\.matches)
        self.selectedMatchID = FindInFilesViewLogic.preferredSelectedMatchID(
            currentSelectedID: selectedMatchID,
            matches: resultMatches
        )

        if let direction = openDirectionAfterSearch {
            openRelativeMatch(direction: direction, in: searchResults)
        }
    }

    private func openRelativeMatch(direction: Int, in searchResults: [FindInFilesFileResult]? = nil) {
        let matches = (searchResults ?? results).flatMap(\.matches)
        guard let nextMatch = FindInFilesViewLogic.nextMatch(
            matches: matches,
            currentSelectedID: selectedMatchID,
            direction: direction
        ) else { return }
        openMatch(nextMatch)
    }

    private func openMatch(_ match: FindInFilesMatch) {
        guard model.repositoryURL != nil else { return }
        selectedMatchID = match.id
        expandedFiles.insert(match.file)

        let location = EditorSymbolLocation(
            relativePath: match.file,
            line: match.line,
            column: 0,
            preview: match.preview
        )
        model.openEditorLocation(location)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                onClose()
                return nil
            }

            if event.keyCode == 51, focusedField == .query, query.isEmpty { // Delete
                onClose()
                return nil
            }

            if event.keyCode == 36, event.modifierFlags.intersection([.shift]).contains(.shift) { // Shift+Enter
                triggerSearch(openDirectionAfterSearch: -1)
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
