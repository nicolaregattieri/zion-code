import Foundation
import CryptoKit

/// Phase 5b — one-shot RAG indexer. Enumerates ignore-filtered repo
/// files, chunks via `ASTChunker`, embeds via `EmbeddingProvider`,
/// writes to `RAGStore` in batches of `Constants.RAG.batchSize`. No
/// FSEvents subscription yet (Phase 5c); the user triggers indexing
/// from `RAGSettingsSection` or programatically via `start(repoURL:)`.
actor RAGIndexer {

    struct Progress: Equatable {
        var filesScanned: Int
        var chunksIndexed: Int
        var totalFiles: Int
        var done: Bool
    }

    private let store: RAGStore
    private let embedder: any EmbeddingProvider
    private let chunker: ASTChunker

    /// Latest progress snapshot. Observers can poll between batches; a
    /// full Combine publisher lands in Phase 5c alongside the watcher.
    private(set) var progress: Progress = Progress(filesScanned: 0, chunksIndexed: 0, totalFiles: 0, done: false)

    private var cancelled: Bool = false

    init(store: RAGStore, embedder: any EmbeddingProvider, chunker: ASTChunker = ASTChunker()) {
        self.store = store
        self.embedder = embedder
        self.chunker = chunker
    }

    /// Cancel an in-flight cold index. Safe to call multiple times.
    func cancel() {
        cancelled = true
    }

    /// One-shot cold index over the given repo. Returns the number of
    /// chunks written. Skips paths under the ignore list. Embeds in
    /// `Constants.RAG.batchSize`-file batches and commits each batch
    /// in a single transaction (via `RAGStore.insertDocuments`).
    func index(repoURL: URL) async throws -> Int {
        cancelled = false
        progress = Progress(filesScanned: 0, chunksIndexed: 0, totalFiles: 0, done: false)

        guard await embedder.ready() else {
            await DiagnosticLogger.shared.log(.warn, "rag.index.embedder.notReady")
            return 0
        }

        let allFiles = Self.enumerateRepoFiles(at: repoURL)
        progress.totalFiles = allFiles.count

        var totalChunks = 0
        var pendingChunks: [RAGChunk] = []
        var pendingTexts: [String] = []

        for url in allFiles {
            if cancelled { break }
            let relative = url.path
                .replacingOccurrences(of: repoURL.path + "/", with: "")
            let language = Self.guessLanguage(for: url)
            let chunks: [RAGChunk]
            do {
                chunks = try chunker.chunk(file: url, language: language)
            } catch {
                progress.filesScanned += 1
                continue
            }

            // Rebind every chunk's path to the relative form so the
            // store sees a stable identifier independent of where the
            // user mounted the repo.
            let rebound = chunks.map { chunk in
                RAGChunk(
                    path: relative,
                    startLine: chunk.startLine,
                    endLine: chunk.endLine,
                    kind: chunk.kind,
                    contentSHA: chunk.contentSHA,
                    fallback: chunk.fallback,
                    content: chunk.content
                )
            }
            pendingChunks.append(contentsOf: rebound)
            pendingTexts.append(contentsOf: rebound.map { $0.content ?? "" })

            progress.filesScanned += 1

            if pendingChunks.count >= Constants.RAG.batchSize {
                try await flushBatch(&pendingChunks, &pendingTexts)
                totalChunks = progress.chunksIndexed
                if let warn = Self.scaleTripwireMessage(totalChunks: totalChunks) {
                    await DiagnosticLogger.shared.log(.warn, warn)
                }
            }
        }

        // Drain remainder.
        if !pendingChunks.isEmpty {
            try await flushBatch(&pendingChunks, &pendingTexts)
        }
        progress.done = true
        return progress.chunksIndexed
    }

    /// Phase 5f — incremental delta. For each path in `paths` that
    /// lives under `repoURL` and is RAG-eligible (language-supported,
    /// not ignored, within size limit), delete every existing row
    /// keyed by the relative path, then re-chunk + re-embed + re-insert
    /// in a single transaction (via `RAGStore.insertDocuments`). Paths
    /// outside the repo or in the ignore list are no-ops.
    func processDelta(paths: [String], repoURL: URL) async {
        guard await embedder.ready() else { return }
        let repoPath = repoURL.path
        for raw in paths {
            if cancelled { return }
            let abs = raw.hasPrefix("/") ? raw : repoPath + "/" + raw
            guard abs.hasPrefix(repoPath) else { continue }
            let url = URL(fileURLWithPath: abs)
            // Reject if ANY path component lives inside an ignored dir
            // (FSEvents fires on files nested deep inside .git/, etc.).
            let components = url.pathComponents
            if components.contains(where: { Self.ignoredDirs.contains($0) }) { continue }
            // Ignore directory hits — FSEvents fires both for the file
            // and its parent. We re-index per file.
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            let language = Self.guessLanguage(for: url)
            if language == .plain { continue }
            let relative = abs.replacingOccurrences(of: repoPath + "/", with: "")

            // Delete the file's old rows even if the file no longer
            // exists on disk (rename / delete event).
            try? await store.deleteByPath(relative)

            // Re-index only when the file still exists + is small.
            guard FileManager.default.fileExists(atPath: abs) else { continue }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > Constants.RAG.maxBytesPerFile { continue }

            let chunks: [RAGChunk]
            do {
                chunks = try chunker.chunk(file: url, language: language)
            } catch {
                continue
            }
            let rebound = chunks.map { chunk in
                RAGChunk(
                    path: relative,
                    startLine: chunk.startLine,
                    endLine: chunk.endLine,
                    kind: chunk.kind,
                    contentSHA: chunk.contentSHA,
                    fallback: chunk.fallback,
                    content: chunk.content
                )
            }
            let texts = rebound.map { $0.content?.isEmpty ?? true ? " " : $0.content! }
            do {
                let vectors = try await embedder.embed(texts)
                try await store.insertDocuments(rebound, embeddings: vectors)
                progress.chunksIndexed += rebound.count
            } catch {
                continue
            }
        }
    }

    private func flushBatch(_ chunks: inout [RAGChunk], _ texts: inout [String]) async throws {
        let toEmbed = texts.map { $0.isEmpty ? " " : $0 } // empty strings → space sentinel for the embedder
        let vectors = try await embedder.embed(toEmbed)
        try await store.insertDocuments(chunks, embeddings: vectors)
        progress.chunksIndexed += chunks.count
        chunks.removeAll(keepingCapacity: true)
        texts.removeAll(keepingCapacity: true)
    }

    // MARK: - File enumeration

    /// Ignore list mirrors the existing FileBrowser filter: `.git`,
    /// `node_modules`, `.build`, `dist`, `.zion`, `.sdd`, hidden
    /// directories. Conservative — Phase 5c can swap to the actual
    /// `.gitignore`-driven filter the file browser uses.
    private static let ignoredDirs: Set<String> = [
        ".git", "node_modules", ".build", "dist", ".zion", ".sdd",
        "Pods", "DerivedData", ".swiftpm"
    ]

    static func enumerateRepoFiles(at repoURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: repoURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let lastComponent = url.lastPathComponent
            if ignoredDirs.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > Constants.RAG.maxBytesPerFile {
                    continue
                }
                if Self.guessLanguage(for: url) == .plain { continue }
                out.append(url)
            }
        }
        return out
    }

    static func guessLanguage(for url: URL) -> SourceLanguage {
        let ext = url.pathExtension.lowercased()
        return SourceLanguage.forExtension(ext) ?? .plain
    }

    static func scaleTripwireMessage(totalChunks: Int) -> String? {
        if totalChunks >= Constants.RAG.scaleTripwireChunks {
            return "rag.scale.annRequired chunks=\(totalChunks)"
        }
        return nil
    }
}
