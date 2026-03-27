import Foundation

extension RepositoryViewModel {

    // MARK: - File Tree Loading & Enumeration

    func refreshFileTree(forceReloadExpandedDirectories: Bool = true) {
        guard let url = repositoryURL?.standardizedFileURL else { return }
        if isRefreshingFileTree {
            pendingFileTreeRefreshRepositoryURL = url
            pendingFileTreeRefreshForceReload = pendingFileTreeRefreshForceReload || forceReloadExpandedDirectories
            return
        }
        runFileTreeRefresh(for: url, forceReloadExpandedDirectories: forceReloadExpandedDirectories)
    }

    private func runFileTreeRefresh(for url: URL, forceReloadExpandedDirectories: Bool) {
        let requestID = UUID()
        fileTreeRefreshRequestID = requestID
        isRefreshingFileTree = true
        pendingFileTreeRefreshRepositoryURL = nil
        pendingFileTreeRefreshForceReload = false
        fileTreeRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.completeFileTreeRefresh(requestID: requestID, repositoryURL: url)
            }

            let initial = await self.loadFiles(at: url, ignoredPaths: nil, maxDepth: 0)
            guard !Task.isCancelled else { return }

            let ignoredPaths = await self.loadGitIgnoredPaths(for: url)
            let files: [FileItem]
            if !ignoredPaths.isEmpty {
                files = await self.loadFiles(at: url, ignoredPaths: ignoredPaths, maxDepth: 0)
            } else {
                files = initial
            }

            guard !Task.isCancelled else { return }
            guard self.fileTreeRefreshRequestID == requestID, self.repositoryURL?.standardizedFileURL == url else { return }

            self.repositoryFiles = self.mergeTopLevel(old: self.repositoryFiles, new: files)
            self.reloadExpandedDirectories(forceReload: forceReloadExpandedDirectories)
            self.pruneStaleSelections()
            self.recalculateMissingOpenFileState(updateEditorForActiveFile: true)
            self.expandedPathsByRepository[url] = self.expandedPaths
            self.captureRepositorySnapshot(for: url)
            self.scheduleEditorSymbolIndexRebuild(repositoryURL: url)
        }
    }

    private func completeFileTreeRefresh(requestID: UUID, repositoryURL: URL) {
        guard fileTreeRefreshRequestID == requestID else { return }
        fileTreeRefreshTask = nil
        isRefreshingFileTree = false

        guard let pendingURL = pendingFileTreeRefreshRepositoryURL,
              pendingURL == repositoryURL,
              repositoryURL == self.repositoryURL?.standardizedFileURL else { return }

        let pendingForceReload = pendingFileTreeRefreshForceReload
        pendingFileTreeRefreshRepositoryURL = nil
        pendingFileTreeRefreshForceReload = false
        runFileTreeRefresh(for: pendingURL, forceReloadExpandedDirectories: pendingForceReload)
    }

    func reloadExpandedDirectories(forceReload: Bool = false) {
        guard let repositoryURL else { return }
        guard !_isReloadingExpandedDirs else { return }
        _isReloadingExpandedDirs = true
        defer { _isReloadingExpandedDirs = false }
        for path in sortedExpandedDirectoryPaths(expandedPaths) {
            loadChildrenIfNeeded(for: path, forceReload: forceReload, expectedRepositoryURL: repositoryURL)
        }
    }

    /// Merges new top-level items into the existing tree, preserving loaded children
    /// on directories that still exist. This avoids the collapse-then-expand flicker
    /// caused by replacing the entire array.
    func mergeTopLevel(old: [FileItem], new: [FileItem]) -> [FileItem] {
        mergeDirectoryChildren(old: old, new: new)
    }

    /// Merge directory children while preserving already loaded descendants to avoid
    /// expansion flicker during external file updates.
    func mergeDirectoryChildren(old: [FileItem], new: [FileItem]) -> [FileItem] {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return new.map { newItem in
            if let existing = oldByID[newItem.id],
               newItem.isDirectory,
               existing.isDirectory,
               existing.children != nil {
                // Preserve loaded children from the existing item
                return FileItem(
                    url: newItem.url,
                    isDirectory: true,
                    children: existing.children,
                    isGitIgnored: newItem.isGitIgnored
                )
            }
            return newItem
        }
    }

    func loadChildrenIfNeeded(
        for path: String,
        forceReload: Bool = false,
        expectedRepositoryURL: URL? = nil
    ) {
        guard let repositoryURL else { return }
        let targetRepositoryURL = expectedRepositoryURL ?? repositoryURL
        guard repositoryURL == targetRepositoryURL else { return }
        guard let item = findItem(path: path, in: repositoryFiles),
              item.isDirectory,
              item.children == nil || forceReload else { return }
        let itemURL = item.url
        let existingChildren = item.children ?? []
        let ignoredPaths = cachedIgnoredPaths
        Task { [weak self] in
            guard let self else { return }
            let children = await self.loadFiles(at: itemURL, ignoredPaths: ignoredPaths, maxDepth: 0)
            guard !Task.isCancelled else { return }
            guard self.repositoryURL == targetRepositoryURL else { return }
            let mergedChildren = self.mergeDirectoryChildren(old: existingChildren, new: children)
            self.repositoryFiles = self.updateTree(self.repositoryFiles, path: path, newChildren: mergedChildren)
            self.captureRepositorySnapshot(for: targetRepositoryURL)
            // Breadcrumb/path navigation can request deep expansions before parent nodes
            // finish loading. Re-run only pending descendants so deeper levels load as soon
            // as they become discoverable in the tree without rescanning every expanded dir.
            self.loadExpandedDescendantsIfNeeded(beneath: path, expectedRepositoryURL: targetRepositoryURL)
        }
    }

    func pendingExpandedDescendantPaths(beneath path: String) -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return sortedExpandedDirectoryPaths(expandedPaths.filter { $0.hasPrefix(prefix) })
    }

    func loadExpandedDescendantsIfNeeded(beneath path: String, expectedRepositoryURL: URL) {
        for descendantPath in pendingExpandedDescendantPaths(beneath: path) {
            loadChildrenIfNeeded(for: descendantPath, expectedRepositoryURL: expectedRepositoryURL)
        }
    }

    func sortedExpandedDirectoryPaths(_ paths: some Sequence<String>) -> [String] {
        paths
            .map { ($0, $0.split(separator: "/").count) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending
            }
            .map(\.0)
    }

    func findItem(path: String, in items: [FileItem]) -> FileItem? {
        for item in items {
            if item.id == path { return item }
            if let children = item.children,
               let found = findItem(path: path, in: children) {
                return found
            }
        }
        return nil
    }

    func updateTree(_ items: [FileItem], path: String, newChildren: [FileItem]) -> [FileItem] {
        items.map { item in
            if item.id == path {
                return FileItem(url: item.url, isDirectory: item.isDirectory, children: newChildren, isGitIgnored: item.isGitIgnored)
            }
            if let children = item.children {
                return FileItem(url: item.url, isDirectory: item.isDirectory,
                              children: updateTree(children, path: path, newChildren: newChildren), isGitIgnored: item.isGitIgnored)
            }
            return item
        }
    }

    func loadGitIgnoredPaths(for repositoryURL: URL, forceRefresh: Bool = false) async -> Set<String> {
        if !forceRefresh,
           let cached = ignoredPathsCacheByRepository[repositoryURL],
           Date().timeIntervalSince(cached.capturedAt) <= ignoredPathsCacheTTL {
            cachedIgnoredPaths = cached.paths
            return cached.paths
        }
        do {
            let output = try await worker.runAction(
                args: ["ls-files", "--others", "--ignored", "--exclude-standard", "--directory"],
                in: repositoryURL
            )
            let paths = output.split(separator: "\n").map {
                // git outputs paths relative to repo root, trailing / for dirs
                repositoryURL.appendingPathComponent(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/"))).path
            }
            let resolved = Set(paths)
            ignoredPathsCacheByRepository[repositoryURL] = IgnoredPathsCacheEntry(
                paths: resolved,
                capturedAt: Date()
            )
            if self.repositoryURL == repositoryURL {
                cachedIgnoredPaths = resolved
            }
            return resolved
        } catch {
            logger.log(.warn, "Failed to load gitignored paths: \(error.localizedDescription)", source: #function)
            return []
        }
    }

    func loadFiles(at url: URL, ignoredPaths: Set<String>? = nil, maxDepth: Int = .max) async -> [FileItem] {
        let showDotfiles = self.showDotfiles
        do {
            return try await Task.detached(priority: .utility) {
                try Self.enumerateFiles(
                    at: url,
                    ignoredPaths: ignoredPaths,
                    maxDepth: maxDepth,
                    showDotfiles: showDotfiles
                )
            }.value
        } catch {
            logger.log(.warn, "Failed to load files: \(error.localizedDescription)", context: url.path, source: #function)
            return []
        }
    }

    nonisolated static func enumerateFiles(
        at url: URL,
        ignoredPaths: Set<String>?,
        maxDepth: Int,
        showDotfiles: Bool
    ) throws -> [FileItem] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = showDotfiles ? [] : [.skipsHiddenFiles]
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options)
        var items: [FileItem] = []
        items.reserveCapacity(contents.count)

        for item in contents {
            let isIgnored = ignoredPaths?.contains(item.path) ?? false
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let children: [FileItem]?

            if isDirectory && maxDepth > 0 {
                children = try enumerateFiles(
                    at: item,
                    ignoredPaths: ignoredPaths,
                    maxDepth: maxDepth - 1,
                    showDotfiles: showDotfiles
                )
            } else {
                children = nil
            }

            items.append(
                FileItem(
                    url: item,
                    isDirectory: isDirectory,
                    children: children,
                    isGitIgnored: isIgnored
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
