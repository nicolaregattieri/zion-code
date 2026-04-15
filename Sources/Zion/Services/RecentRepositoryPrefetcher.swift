import Foundation

/// Light snapshot of a recent repository captured in the background, used to
/// accelerate the visual transition when the user clicks the repo in the sidebar.
///
/// This is NOT a replacement for `RepositorySwitchSnapshot` — it only fills the
/// small, fast fields read synchronously at the top of `openRepository()`. The
/// full refresh (commits, branches, tags, file tree, terminals) still runs
/// asynchronously after consumption, so any staleness self-corrects within ~500ms.
struct RecentRepoLightSnapshot: Sendable {
    let url: URL
    let isGitRepository: Bool
    let editorConfig: EditorConfig?
    let branch: String?
    let shortHash: String?
    let changedCount: Int
    let capturedAt: Date

    func isFresh(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(capturedAt) < ttl
    }
}

@MainActor
final class RecentRepositoryPrefetcher {
    private enum Entry {
        case inflight(Task<Void, Never>)
        case ready(RecentRepoLightSnapshot)
    }

    private var entries: [URL: Entry] = [:]
    private let ttl: TimeInterval = 120
    private let perCommandTimeout: TimeInterval = 3
    private let semaphore = AsyncSemaphore(maxConcurrent: 2)

    /// Returns a fresh snapshot if available and consumes it (one-shot).
    /// Returns nil if none cached, stale, or still in-flight.
    func consume(for url: URL) -> RecentRepoLightSnapshot? {
        let key = url.standardizedFileURL
        guard let entry = entries[key] else { return nil }
        if case .ready(let snap) = entry, snap.isFresh(ttl: ttl) {
            entries.removeValue(forKey: key)
            return snap
        }
        if case .ready = entry {
            entries.removeValue(forKey: key)
        }
        return nil
    }

    func invalidate(_ url: URL) {
        let key = url.standardizedFileURL
        if case .inflight(let task) = entries[key] { task.cancel() }
        entries.removeValue(forKey: key)
    }

    func cancelAll() {
        for (_, entry) in entries {
            if case .inflight(let task) = entry { task.cancel() }
        }
        entries.removeAll()
    }

    /// Kicks off prefetch for each URL that isn't the active repo and doesn't
    /// have a fresh ready snapshot. Safe to call repeatedly — no-ops on entries
    /// that are in-flight or still fresh.
    func prefetch(urls: [URL], excluding active: URL?) {
        let activeKey = active?.standardizedFileURL
        for url in urls {
            let key = url.standardizedFileURL
            if key == activeKey { continue }
            if let entry = entries[key] {
                if case .ready(let snap) = entry, snap.isFresh(ttl: ttl) { continue }
                if case .inflight = entry { continue }
            }
            let task = Task { [weak self] in
                guard let self else { return }
                await self.semaphore.acquire()
                defer { Task { await self.semaphore.release() } }
                if Task.isCancelled { return }
                let timeout = self.perCommandTimeout
                let snap = await Task.detached(priority: .utility) {
                    RecentRepositoryPrefetcher.capture(url: key, timeout: timeout)
                }.value
                if Task.isCancelled { return }
                if let snap {
                    self.entries[key] = .ready(snap)
                } else {
                    self.entries.removeValue(forKey: key)
                }
            }
            entries[key] = .inflight(task)
        }
    }

    // MARK: - Capture (off-main)

    nonisolated private static func capture(url: URL, timeout: TimeInterval) -> RecentRepoLightSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let isGit = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        let editorConfig = EditorConfig.load(from: url)
        guard isGit else {
            return RecentRepoLightSnapshot(
                url: url,
                isGitRepository: false,
                editorConfig: editorConfig,
                branch: nil,
                shortHash: nil,
                changedCount: 0,
                capturedAt: Date()
            )
        }
        let branchRaw = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"], in: url, timeout: timeout)
        let hashRaw = runGit(args: ["rev-parse", "--short", "HEAD"], in: url, timeout: timeout)
        let statusRaw = runGit(args: ["status", "--porcelain"], in: url, timeout: timeout) ?? ""
        let branch = branchRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = hashRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let changedCount = statusRaw
            .split(whereSeparator: \.isNewline)
            .filter { !$0.isEmpty }
            .count

        return RecentRepoLightSnapshot(
            url: url,
            isGitRepository: true,
            editorConfig: editorConfig,
            branch: (branch?.isEmpty == false) ? branch : nil,
            shortHash: (hash?.isEmpty == false) ? hash : nil,
            changedCount: changedCount,
            capturedAt: Date()
        )
    }

    nonisolated private static func runGit(args: [String], in url: URL, timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = url
        process.qualityOfService = .utility
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
            if process.isRunning { process.interrupt() }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
