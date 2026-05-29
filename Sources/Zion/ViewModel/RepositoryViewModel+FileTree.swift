import Foundation

extension RepositoryViewModel {

    // MARK: - File Tree Loading & Enumeration

    func refreshFileTree(forceReloadExpandedDirectories: Bool = true, onFinish: (() -> Void)? = nil) {
        guard let url = repositoryURL?.standardizedFileURL else { onFinish?(); return }
        if let onFinish { fileTreeRefreshOnFinish = onFinish }
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
            guard self.fileTreeRefreshRequestID == requestID, self.repositoryURL?.standardizedFileURL == url else { return }

            // Publish the tree immediately without waiting for the gitignored
            // pass. `git ls-files --others --ignored --exclude-standard` can
            // serialize behind other RepositoryWorker calls (refreshForCodeTabOnly
            // status, deferred fetch, etc.) on a freshly-switched repo and was
            // observed to stall the file-tree refresh — and therefore the
            // loading overlay — for 10s+. Ignored-path annotation runs in a
            // background pass below and re-publishes when ready.
            self.repositoryFiles = self.mergeTopLevel(old: self.repositoryFiles, new: initial)
            self.reloadExpandedDirectories(forceReload: forceReloadExpandedDirectories)
            self.pruneStaleSelections()
            self.recalculateMissingOpenFileState(updateEditorForActiveFile: true)
            self.expandedPathsByRepository[url] = self.expandedPaths
            self.captureRepositorySnapshot(for: url)
            self.scheduleEditorSymbolIndexRebuild(repositoryURL: url)

            // Background pass — annotate gitignored entries without blocking
            // the overlay-clearing onFinish callback.
            Task { [weak self] in
                guard let self else { return }
                let ignoredPaths = await self.loadGitIgnoredPaths(for: url)
                guard !Task.isCancelled, !ignoredPaths.isEmpty else { return }
                guard self.repositoryURL?.standardizedFileURL == url else { return }
                let annotated = await self.loadFiles(at: url, ignoredPaths: ignoredPaths, maxDepth: 0)
                guard self.repositoryURL?.standardizedFileURL == url else { return }
                self.repositoryFiles = self.mergeTopLevel(old: self.repositoryFiles, new: annotated)
            }
        }
    }

    private func completeFileTreeRefresh(requestID: UUID, repositoryURL: URL) {
        guard fileTreeRefreshRequestID == requestID else { return }
        fileTreeRefreshTask = nil
        isRefreshingFileTree = false

        guard let pendingURL = pendingFileTreeRefreshRepositoryURL,
              pendingURL == repositoryURL,
              repositoryURL == self.repositoryURL?.standardizedFileURL else {
            // No queued re-run — fire any stored onFinish callback now.
            let callback = fileTreeRefreshOnFinish
            fileTreeRefreshOnFinish = nil
            callback?()
            return
        }

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
        if new.isEmpty && !old.isEmpty { return old }
        return mergeDirectoryChildren(old: old, new: new)
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

    /// Path-targeted refresh driven by `FileWatcher.ChangeEvent.changedPaths`.
    /// For each event path, walks ancestors up to the repo root and ensures
    /// every directory along the way has its children loaded. Directories
    /// discovered for the first time on this cycle (no entry yet, or entry
    /// with `children == nil`) are auto-added to `expandedPaths` so a file
    /// dropped inside a brand-new folder is visible immediately — fixes the
    /// case where `newFolder/newFile.swift` only showed the empty folder
    /// until the user clicked it. (RT-005)
    func ensureChildrenLoadedForChangedPaths(_ paths: [String], maxDepth: Int = 6) {
        guard let repositoryURL = repositoryURL?.standardizedFileURL else { return }
        let repoPath = FileWatcher.normalizePath(repositoryURL.path)
        var ancestors = Set<String>()
        for changed in paths {
            let normalized = FileWatcher.normalizePath(changed)
            guard normalized.hasPrefix(repoPath) else { continue }
            var ancestor = URL(fileURLWithPath: normalized).deletingLastPathComponent().path
            var hops = 0
            while ancestor.count >= repoPath.count, ancestor.hasPrefix(repoPath), hops < maxDepth {
                ancestors.insert(FileWatcher.normalizePath(ancestor))
                if ancestor == repoPath { break }
                ancestor = URL(fileURLWithPath: ancestor).deletingLastPathComponent().path
                hops += 1
            }
        }
        let sortedAncestors = sortedExpandedDirectoryPaths(ancestors)
        var didMutateExpandedPaths = false
        for ancestorPath in sortedAncestors {
            // Top-level files are already merged in `runFileTreeRefresh` via
            // the maxDepth-0 walk, so skip the repo root itself.
            if ancestorPath == repoPath { continue }
            // Auto-expand: when an ancestor directory has no children loaded
            // and is not in `expandedPaths`, treat it as a brand-new folder
            // and expand it. Without this the file inside it stays invisible
            // until the user clicks. Existing collapsed dirs that already had
            // children stay collapsed — children load silently and surface on
            // first click.
            let item = findItem(path: ancestorPath, in: repositoryFiles)
            let isFreshDir = item?.isDirectory == true && item?.children == nil && !expandedPaths.contains(ancestorPath)
            if isFreshDir {
                expandedPaths.insert(ancestorPath)
                didMutateExpandedPaths = true
            }
            loadChildrenIfNeeded(for: ancestorPath, forceReload: true, expectedRepositoryURL: repositoryURL)
        }
        if didMutateExpandedPaths {
            expandedPathsByRepository[repositoryURL] = expandedPaths
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
        if self.repositoryURL == repositoryURL, !isGitRepository {
            if self.repositoryURL == repositoryURL { cachedIgnoredPaths = [] }
            ignoredPathsCacheByRepository[repositoryURL] = IgnoredPathsCacheEntry(paths: [], capturedAt: Date())
            return []
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

            if isDirectory && maxDepth > 0 && !isIgnored {
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
