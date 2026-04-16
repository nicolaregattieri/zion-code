import Foundation
import CoreServices

@MainActor
final class FileWatcher {
    struct ChangeEvent: Sendable {
        let changedPaths: [String]
        let hasTreeImpact: Bool
        let hasStructuralImpact: Bool
        let hasWorktreeStatusImpact: Bool
        let hasGitMetadataImpact: Bool
        let requiresRescan: Bool

        func merged(with other: ChangeEvent) -> ChangeEvent {
            ChangeEvent(
                changedPaths: Array(Set(changedPaths + other.changedPaths)).sorted(),
                hasTreeImpact: hasTreeImpact || other.hasTreeImpact,
                hasStructuralImpact: hasStructuralImpact || other.hasStructuralImpact,
                hasWorktreeStatusImpact: hasWorktreeStatusImpact || other.hasWorktreeStatusImpact,
                hasGitMetadataImpact: hasGitMetadataImpact || other.hasGitMetadataImpact,
                requiresRescan: requiresRescan || other.requiresRescan
            )
        }
    }

    private nonisolated(unsafe) var eventStream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private var pendingEvent: ChangeEvent?
    private let debounceInterval: UInt64 = Constants.Timing.fileWatcherDebounce

    // MARK: - Coalescing layer
    // Buffers incoming ChangeEvents into a Set of canonical parent-directory paths.
    // A short timer (fileWatcherCoalesceWindow) fires after the last batch arrives;
    // if the set grows beyond fileWatcherCoalesceMaxPaths it flushes immediately.
    // This sits between the FSEvents callback and handleChange so the debounce
    // layer above still runs on the coalesced output.

    private var coalescerPendingPaths: Set<String> = []
    private var coalescerPendingEvent: ChangeEvent?
    private var coalescerTask: Task<Void, Never>?
    private let coalescerWindow: UInt64

    var onChange: ((ChangeEvent) -> Void)?

    // MARK: - Init

    init() {
        self.coalescerWindow = Constants.Timing.fileWatcherCoalesceWindow
    }

    /// Test seam: creates an instance whose coalescer window can be overridden.
    /// Pass 0 to make the coalescer flush synchronously in tests.
    internal init(coalescerWindow: UInt64) {
        self.coalescerWindow = coalescerWindow
    }

    func watch(directory: URL) {
        stop()

        let path = directory.path as CFString
        let pathsToWatch = [path] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, _ in
                guard let info = clientCallBackInfo else { return }
                guard numEvents > 0 else { return }
                guard let cfArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let paths = Array(cfArray.prefix(numEvents))
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
                guard let event = FileWatcher.classifyChangeEvent(paths: paths, flags: flags) else { return }

                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in
                    watcher.coalesceEvent(event)
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Constants.Timing.fileWatcherLatency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            DiagnosticLogger.shared.log(.warn, "FileWatcher: failed to create FSEventStream", context: directory.path, source: #function)
            return
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        coalescerTask?.cancel()
        coalescerTask = nil
        coalescerPendingPaths = []
        coalescerPendingEvent = nil
        debounceTask?.cancel()
        debounceTask = nil
        pendingEvent = nil
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    // MARK: - Coalescer implementation

    /// Ingest an incoming classified event into the coalescing buffer.
    /// Public-internal for test seam — tests call this directly instead of going through FSEvents.
    private func coalesceEvent(_ event: ChangeEvent) {
        // Derive canonical parent directories for each changed path.
        for path in event.changedPaths {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            coalescerPendingPaths.insert(parent)
        }
        // Merge boolean flags into the pending event.
        coalescerPendingEvent = coalescerPendingEvent?.merged(with: event) ?? event

        // Hard ceiling: flush immediately if we've accumulated too many paths.
        if coalescerPendingPaths.count >= Constants.Limits.fileWatcherCoalesceMaxPaths {
            flushCoalescer()
            return
        }

        // Reset the coalesce timer.
        coalescerTask?.cancel()
        let window = coalescerWindow
        coalescerTask = Task { [weak self] in
            guard let self else { return }
            if window > 0 {
                try? await Task.sleep(nanoseconds: window)
            }
            guard !Task.isCancelled else { return }
            self.flushCoalescer()
        }
    }

    private func flushCoalescer() {
        coalescerTask?.cancel()
        coalescerTask = nil
        guard let base = coalescerPendingEvent else { return }
        let dedupedParents = Array(coalescerPendingPaths).sorted()
        coalescerPendingPaths = []
        coalescerPendingEvent = nil
        // Rebuild the event with deduplicated parent directory paths, preserving flags.
        let flushed = ChangeEvent(
            changedPaths: dedupedParents,
            hasTreeImpact: base.hasTreeImpact,
            hasStructuralImpact: base.hasStructuralImpact,
            hasWorktreeStatusImpact: base.hasWorktreeStatusImpact,
            hasGitMetadataImpact: base.hasGitMetadataImpact,
            requiresRescan: base.requiresRescan
        )
        handleChange(flushed)
    }

    // MARK: - Test seam accessors

    /// Feed a synthetic event into the coalescer without going through FSEvents.
    /// Intended for use with `@testable import Zion` in unit tests.
    internal func ingestForTesting(paths: [String]) {
        // Build a minimal classified event from the supplied paths.
        let normalizedPaths = paths.map(Self.normalizePath)
        let event = ChangeEvent(
            changedPaths: normalizedPaths,
            hasTreeImpact: true,
            hasStructuralImpact: false,
            hasWorktreeStatusImpact: true,
            hasGitMetadataImpact: false,
            requiresRescan: false
        )
        coalesceEvent(event)
    }

    /// Number of unique parent paths currently buffered in the coalescer.
    internal var coalescerPendingCount: Int { coalescerPendingPaths.count }

    /// Synchronously flush the coalescer (useful in tests with coalescerWindow == 0).
    internal func flushCoalescerForTesting() {
        flushCoalescer()
    }

    // MARK: - Debounce layer

    private func handleChange(_ event: ChangeEvent) {
        pendingEvent = pendingEvent?.merged(with: event) ?? event
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceInterval)
            guard !Task.isCancelled else { return }
            guard let pendingEvent = self.pendingEvent else { return }
            self.pendingEvent = nil
            self.onChange?(pendingEvent)
        }
    }

    static func classifyChangeEvent(paths: [String], flags: [FSEventStreamEventFlags]) -> ChangeEvent? {
        let normalizedPaths = paths.map(Self.normalizePath)
        let eventPairs = Array(zip(normalizedPaths, flags))
        let hasTreeImpact = normalizedPaths.contains { !Self.isInsideGitDirectory($0) }
        let hasStructuralImpact = eventPairs.contains { path, flag in
            !Self.isInsideGitDirectory(path) && Self.isStructuralFlag(flag)
        }
        let hasGitMetadataImpact = normalizedPaths.contains(where: Self.isGitMetadataPath)
        let requiresRescan = flags.contains(where: Self.isRescanFlag)
        let hasWorktreeStatusImpact = hasTreeImpact || hasGitMetadataImpact || requiresRescan

        guard hasWorktreeStatusImpact else { return nil }
        return ChangeEvent(
            changedPaths: normalizedPaths,
            hasTreeImpact: hasTreeImpact,
            hasStructuralImpact: hasStructuralImpact,
            hasWorktreeStatusImpact: hasWorktreeStatusImpact,
            hasGitMetadataImpact: hasGitMetadataImpact,
            requiresRescan: requiresRescan
        )
    }

    static func normalizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    static func isInsideGitDirectory(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git")
    }

    static func isGitMetadataPath(_ path: String) -> Bool {
        path.contains("/.git/index")
            || path.contains("/.git/HEAD")
            || path.contains("/.git/FETCH_HEAD")
            || path.contains("/.git/ORIG_HEAD")
            || path.contains("/.git/refs/")
            || path.contains("/.git/logs/HEAD")
    }

    static func isRescanFlag(_ flag: FSEventStreamEventFlags) -> Bool {
        let mask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
        )
        return (flag & mask) != 0
    }

    static func isStructuralFlag(_ flag: FSEventStreamEventFlags) -> Bool {
        let mask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
        )
        return (flag & mask) != 0
    }

    deinit {
        coalescerTask?.cancel()
        debounceTask?.cancel()
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
