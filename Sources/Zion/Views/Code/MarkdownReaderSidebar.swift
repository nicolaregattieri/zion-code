import SwiftUI

struct MarkdownReaderSidebar: View {
    var model: RepositoryViewModel
    @Binding var searchText: String
    var onSelect: (FileItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            list
        }
        .frame(width: 280)
        .background(DesignSystem.Colors.glassSubtle)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(DesignSystem.Colors.glassBorderDark),
            alignment: .trailing
        )
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Image(systemName: "list.bullet.indent")
                .foregroundStyle(DesignSystem.Colors.accent)
            Text(L10n("editor.markdown.reader.sidebar.title"))
                .font(DesignSystem.Typography.bodySemibold)
            Spacer(minLength: 0)
            Text("\(markdownFiles.count)")
                .font(DesignSystem.Typography.metaSemibold)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Image(systemName: "magnifyingglass")
                .font(DesignSystem.Typography.bodySmall)
                .foregroundStyle(.tertiary)
            TextField(L10n("editor.markdown.reader.sidebar.search"), text: $searchText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.bodySmall)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if filteredFiles.isEmpty {
                    Text(L10n("editor.markdown.reader.sidebar.empty"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(filteredFiles) { file in
                        row(for: file)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func row(for file: FileItem) -> some View {
        let isSelected = model.selectedCodeFile?.url == file.url
        return Button {
            onSelect(file)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(isSelected ? DesignSystem.Typography.monoBodyBold : DesignSystem.Typography.monoBody)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let folder = folderHint(for: file) {
                    Text(folder)
                        .font(DesignSystem.Typography.metaSemibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                    .fill(isSelected ? DesignSystem.Colors.selectionBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius)
                    .stroke(isSelected ? DesignSystem.Colors.selectionBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    private var markdownFiles: [FileItem] {
        Self.flattenMarkdown(model.repositoryFiles)
            .sorted { $0.url.path.lowercased() < $1.url.path.lowercased() }
    }

    private var filteredFiles: [FileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return markdownFiles }
        return markdownFiles.filter { $0.url.path.lowercased().contains(query) }
    }

    private func folderHint(for file: FileItem) -> String? {
        guard let repoPath = model.repositoryURL?.path else { return nil }
        let filePath = file.url.deletingLastPathComponent().path
        if filePath.hasPrefix(repoPath + "/") {
            let relative = String(filePath.dropFirst(repoPath.count + 1))
            return relative.isEmpty ? nil : relative
        }
        return filePath.isEmpty ? nil : filePath
    }

    static func flattenMarkdown(_ items: [FileItem]) -> [FileItem] {
        var out: [FileItem] = []
        for item in items {
            if item.isDirectory {
                if let kids = item.children {
                    out.append(contentsOf: flattenMarkdown(kids))
                }
            } else if item.url.pathExtension.lowercased() == "md" {
                out.append(item)
            }
        }
        return out
    }
}
