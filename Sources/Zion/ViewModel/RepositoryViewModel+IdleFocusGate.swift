import Foundation
import AppKit

// MARK: - Idle + Focus Gate for file-watcher refreshes
//
// Mirrors VS Code's eventuallyUpdateWhenIdleAndWait pattern (repository.ts:3186).
// File-watcher-driven refreshes are deferred while the app window is
// backgrounded OR any non-read-only operation is in flight. When conditions
// clear (app becomes active AND operations idle), the latest deferred request
// fires exactly once.
//
// User-initiated and repository-switch refreshes bypass this gate entirely.

extension RepositoryViewModel {

    /// True when a file-watcher refresh should be deferred rather than run now.
    /// Exposed internally so tests can assert directly on the gate predicate.
    func shouldDeferFileWatcherRefresh() -> Bool {
        let active = isActiveOverrideForTesting ?? NSApp.isActive
        if !active { return true }
        if operations.hasActiveNonReadOnlyOperation { return true }
        return false
    }

    /// Public gate entry point. Call this wherever the file-watcher pipeline
    /// would otherwise invoke `refreshRepository(origin: .fileWatcher)` directly.
    /// If gate conditions permit, runs immediately; otherwise parks a single
    /// pending flag and arms a `didBecomeActiveNotification` observer.
    func requestFileWatcherRefresh() {
        if shouldDeferFileWatcherRefresh() {
            pendingFileWatcherRefresh = true
            armActivationObserverIfNeeded()
            return
        }
        fireDeferredFileWatcherRefresh()
    }

    /// Flushes a parked refresh. Used by the observer and by tests to simulate
    /// activation without posting a real NotificationCenter event.
    func simulateActivationForTesting() {
        handleDidBecomeActive()
    }

    // MARK: - Internals

    fileprivate func fireDeferredFileWatcherRefresh() {
        pendingFileWatcherRefresh = false
        refreshFireCountForTesting += 1
        refreshRepository(setBusy: false, options: .worktreeStatus, origin: .fileWatcher)
    }

    fileprivate func armActivationObserverIfNeeded() {
        guard !didArmActivationObserver else { return }
        didArmActivationObserver = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidBecomeActive()
            }
        }
    }

    fileprivate func handleDidBecomeActive() {
        guard pendingFileWatcherRefresh else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.refreshRepositoryIdleGrace)
            guard let self else { return }
            guard self.pendingFileWatcherRefresh else { return }
            guard !self.shouldDeferFileWatcherRefresh() else { return }
            self.fireDeferredFileWatcherRefresh()
        }
    }
}
