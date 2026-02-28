import SwiftUI

struct FindInFilesView: View {
    @Bindable var model: RepositoryViewModel
    @Binding var query: String
    @Binding var includePattern: String
    @Binding var excludePattern: String
    @Binding var results: [FindInFilesFileResult]
    @Binding var isSearching: Bool
    @Binding var scopePath: String?

    @State private var showFilters: Bool = false
    @State private var expandedFiles: Set<String> = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchFields
            Divider()
            resultsList
        }
        .onAppear { isQueryFocused = true }
    }

    // MARK: - Search Fields

    private var searchFields: some View {
        VStack(spacing: 6) {
            // Query field
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField(L10n("Buscar nos Arquivos"), text: $query)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.monoBody)
                    .focused($isQueryFocused)
                    .onSubmit { triggerSearch() }

                if isSearching {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }

                Button {
                    showFilters.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle\(showFilters ? ".fill" : "")")
                        .font(.system(size: 12))
                        .foregroundStyle(showFilters ? .primary : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n("Filtros"))
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
                        .font(.system(size: 9))
                    Text(URL(fileURLWithPath: scope).lastPathComponent)
                        .font(DesignSystem.Typography.monoMeta)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        self.scopePath = nil
                        triggerSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
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
                    .onSubmit { triggerSearch() }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.glassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Text(L10n("Excluir arquivos"))
                    .font(DesignSystem.Typography.monoMeta)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("*.lock, dist/*", text: $excludePattern)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.monoMeta)
                    .onSubmit { triggerSearch() }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.glassBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            if results.isEmpty && !query.isEmpty && !isSearching {
                Text(L10n("Nenhum resultado"))
                    .font(.caption)
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
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(fileResult.file)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
        Button {
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
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        searchTask = Task { await performSearch() }
    }

    private func performSearch() async {
        guard !query.isEmpty else {
            results = []
            return
        }
        isSearching = true
        let searchResults = await model.findInFiles(
            query: query,
            includePattern: includePattern,
            excludePattern: excludePattern,
            scopePath: scopePath
        )
        isSearching = false
        results = searchResults
        // Auto-expand all files when few results
        if searchResults.count <= 10 {
            expandedFiles = Set(searchResults.map(\.file))
        }
    }

    private func openMatch(_ match: FindInFilesMatch) {
        guard model.repositoryURL != nil else { return }
        let location = EditorSymbolLocation(
            relativePath: match.file,
            line: match.line,
            column: 0,
            preview: match.preview
        )
        model.openEditorLocation(location)
    }
}
