import SwiftUI

struct QuickOpenOverlay: View {
    var model: RepositoryViewModel
    @Binding var isVisible: Bool
    @State private var query: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex: Int = 0
    @State private var eventMonitor: Any?

    private var filteredFiles: [FileItem] {
        let allFiles = model.allFlatFiles()
        guard !query.isEmpty else { return Array(allFiles.prefix(15)) }
        let lowercasedQuery = query.lowercased()

        return allFiles
            .map { file -> (FileItem, Int) in
                let path = file.url.path.lowercased()
                let name = file.name.lowercased()
                var score = 0
                if name == lowercasedQuery { score = 1000 }
                else if name.hasPrefix(lowercasedQuery) { score = 500 }
                else if name.contains(lowercasedQuery) { score = 200 }
                else if path.contains(lowercasedQuery) { score = 100 }
                else {
                    var queryIndex = lowercasedQuery.startIndex
                    for ch in name {
                        if queryIndex < lowercasedQuery.endIndex && ch == lowercasedQuery[queryIndex] {
                            queryIndex = lowercasedQuery.index(after: queryIndex)
                            score += 1
                        }
                    }
                    if queryIndex < lowercasedQuery.endIndex { score = 0 }
                }
                return (file, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(15)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n("Buscar arquivo..."), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isSearchFocused)
                        .onSubmit { selectCurrentFile() }
                }
                .padding(12)

                Divider()

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            let files = filteredFiles
                            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                                quickOpenRow(file: file, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        model.selectCodeFile(file)
                                        isVisible = false
                                    }
                            }
                            if files.isEmpty {
                                Text(L10n("Nenhum arquivo encontrado"))
                                    .foregroundStyle(.secondary)
                                    .padding(20)
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: selectedIndex) { _, idx in
                        scrollProxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
            .frame(width: 500)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous).stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1))
            .shadow(color: DesignSystem.Colors.shadowDark, radius: 20, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
        .background(Color.black.opacity(0.3))
        .contentShape(Rectangle())
        .onTapGesture { isVisible = false }
        .onAppear {
            query = ""
            selectedIndex = 0
            isSearchFocused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private func installKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape
                isVisible = false
                return nil
            case 125: // Down arrow
                let max = filteredFiles.count
                if selectedIndex < max - 1 { selectedIndex += 1 }
                return nil
            case 126: // Up arrow
                if selectedIndex > 0 { selectedIndex -= 1 }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func quickOpenRow(file: FileItem, isSelected: Bool) -> some View {
        let relativePath: String = {
            guard let repoURL = model.repositoryURL else { return file.name }
            return file.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
        }()

        return HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
            Image(systemName: "doc.text").foregroundStyle(.secondary).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 13, weight: .medium))
                Text(relativePath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? DesignSystem.Colors.selectionBackground : Color.clear)
        .contentShape(Rectangle())
    }

    private func selectCurrentFile() {
        let files = filteredFiles
        guard selectedIndex < files.count else { return }
        model.selectCodeFile(files[selectedIndex])
        isVisible = false
    }
}
