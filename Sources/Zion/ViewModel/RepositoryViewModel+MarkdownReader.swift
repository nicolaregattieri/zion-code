import Foundation

extension RepositoryViewModel {

    func refreshAllMarkdownFiles() {
        guard let url = repositoryURL else {
            allMarkdownFiles = []
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let urls = await Self.loadMarkdownFiles(in: url, worker: self.worker)
            guard self.repositoryURL == url else { return }
            if self.allMarkdownFiles != urls { self.allMarkdownFiles = urls }
        }
    }

    private static func loadMarkdownFiles(in repoURL: URL, worker: RepositoryWorker) async -> [URL] {
        // Tracked + untracked .md files, gitignore honored. Includes dotfolders
        // such as `.claude/` because git already tracks them when committed.
        let trackedOutput = (try? await worker.runAction(
            args: ["ls-files", "-c", "-o", "--exclude-standard", "-z", "--", "*.md", "*.MD"],
            in: repoURL
        )) ?? ""

        var paths: Set<String> = []
        // NUL-separated to handle paths with spaces/special chars without quoting.
        for path in trackedOutput.split(separator: "\0") {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            paths.insert(trimmed)
        }

        return paths
            .sorted { $0.lowercased() < $1.lowercased() }
            .map { repoURL.appendingPathComponent($0) }
    }
}
