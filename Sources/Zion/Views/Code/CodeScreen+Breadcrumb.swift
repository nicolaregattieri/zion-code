import SwiftUI

extension CodeScreen {

    // MARK: - Breadcrumb Path Bar

    var breadcrumbPathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                ForEach(Array(breadcrumbItems.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(DesignSystem.Typography.micro)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    breadcrumbSegmentView(item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 140, idealWidth: 300, maxWidth: 520)
        .layoutPriority(1)
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .help(L10n("editor.breadcrumb.path"))
        .accessibilityLabel(L10n("editor.breadcrumb.path"))
    }

    @ViewBuilder
    func breadcrumbSegmentView(_ item: EditorBreadcrumbItem) -> some View {
        if item.isEllipsis {
            Text("...")
                .font(DesignSystem.Typography.monoLabel)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        } else if !item.isFile, let path = item.targetPath {
            BreadcrumbFolderSegmentButton(title: item.title) {
                revealBreadcrumbTarget(path: path, isFile: false)
            }
        } else {
            Text(item.title)
                .font(item.isFile ? DesignSystem.Typography.monoLabelMedium : DesignSystem.Typography.monoLabel)
                .lineLimit(1)
                .foregroundStyle(item.isFile ? Color.primary : DesignSystem.Colors.textSecondary)
        }
    }

    var breadcrumbItems: [EditorBreadcrumbItem] {
        guard let fileURL = model.selectedCodeFile?.url else { return [] }
        let full = fullBreadcrumbItems(for: fileURL)
        guard full.count > 4 else { return full }

        let ellipsis = EditorBreadcrumbItem(
            id: "ellipsis-\(full.count)-\(full.last?.id ?? "")",
            title: "...",
            targetPath: nil,
            isFile: false,
            isEllipsis: true
        )

        return [full[0], full[1], ellipsis, full[full.count - 2], full[full.count - 1]]
    }

    func fullBreadcrumbItems(for fileURL: URL) -> [EditorBreadcrumbItem] {
        let relativePath = relativePathForBreadcrumb(fileURL: fileURL)
        let segments = relativePath.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return [] }

        var items: [EditorBreadcrumbItem] = []
        var partial = ""
        for (index, segment) in segments.enumerated() {
            if partial.isEmpty {
                partial = segment
            } else {
                partial += "/\(segment)"
            }
            let targetPath = model.repositoryURL?.appendingPathComponent(partial).path
            let isFile = index == segments.count - 1
            items.append(
                EditorBreadcrumbItem(
                    id: "\(index)-\(partial)",
                    title: segment,
                    targetPath: targetPath,
                    isFile: isFile,
                    isEllipsis: false
                )
            )
        }
        return items
    }

    func relativePathForBreadcrumb(fileURL: URL) -> String {
        guard let repositoryURL = model.repositoryURL else {
            return fileURL.lastPathComponent
        }

        let repoPath = repositoryURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = repoPath.hasSuffix("/") ? repoPath : repoPath + "/"
        guard filePath.hasPrefix(prefix) else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(prefix.count))
    }

    func revealBreadcrumbTarget(path: String, isFile: Bool) {
        withAnimation(DesignSystem.Motion.panel) {
            isFileBrowserVisible = true
        }

        guard let repositoryURL = model.repositoryURL else { return }

        let repoPath = repositoryURL.standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard normalizedPath.hasPrefix(repoPath) else { return }

        let relativePath = String(normalizedPath.dropFirst(repoPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }

        var currentURL = repositoryURL
        let foldersToExpand = isFile ? max(components.count - 1, 0) : components.count
        if foldersToExpand > 0 {
            for index in 0..<foldersToExpand {
                currentURL = currentURL.appendingPathComponent(components[index])
                let folderPath = currentURL.path
                if !model.expandedPaths.contains(folderPath) {
                    model.toggleExpansion(for: folderPath)
                }
            }
        }

        if isFile {
            let item = FileItem(url: URL(fileURLWithPath: normalizedPath), isDirectory: false, children: nil)
            model.selectCodeFile(item)
        }

        requestFileBrowserAutoScroll(targetPath: normalizedPath)
    }

    func requestFileBrowserAutoScroll(targetPath: String) {
        Task { @MainActor in
            for _ in 0..<24 {
                if model.visibleFlatFiles().contains(where: { $0.id == targetPath }) {
                    fileBrowserScrollTargetID = targetPath
                    fileBrowserScrollRequestID += 1
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
