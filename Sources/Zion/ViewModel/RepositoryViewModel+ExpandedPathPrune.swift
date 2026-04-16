import Foundation

// MARK: - Expanded Path Pruning

extension RepositoryViewModel {

    /// Filters out paths that no longer exist on disk so ghost expanded-path
    /// entries do not trigger "Failed to load files" warnings on restore.
    ///
    /// The `FileManager.fileExists` scan runs on a detached utility task to
    /// avoid blocking the main thread. The returned set is safe to assign back
    /// to `@MainActor`-isolated state from within a `Task { @MainActor in … }`
    /// block.
    ///
    /// - Parameter paths: The raw stored path strings (not canonicalized).
    /// - Returns: The subset of `paths` whose on-disk entry still exists.
    func pruneExpandedPaths(_ paths: Set<String>) async -> Set<String> {
        guard !paths.isEmpty else { return paths }
        return await Task.detached(priority: .utility) {
            paths.filter { FileManager.default.fileExists(atPath: $0) }
        }.value
    }
}
