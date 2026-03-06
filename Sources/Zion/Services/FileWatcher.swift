import Foundation
import CoreServices

@MainActor
final class FileWatcher {
    struct ChangeEvent: Sendable {
        let changedPaths: [String]
        let hasTreeImpact: Bool
        let hasGitMetadataImpact: Bool
        let requiresRescan: Bool

        func merged(with other: ChangeEvent) -> ChangeEvent {
            ChangeEvent(
                changedPaths: Array(Set(changedPaths + other.changedPaths)).sorted(),
                hasTreeImpact: hasTreeImpact || other.hasTreeImpact,
                hasGitMetadataImpact: hasGitMetadataImpact || other.hasGitMetadataImpact,
                requiresRescan: requiresRescan || other.requiresRescan
            )
        }
    }

    private nonisolated(unsafe) var eventStream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private var pendingEvent: ChangeEvent?
    private let debounceInterval: UInt64 = 350_000_000 // 350ms

    var onChange: ((ChangeEvent) -> Void)?

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
                    watcher.handleChange(event)
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
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
        let hasTreeImpact = normalizedPaths.contains { !Self.isInsideGitDirectory($0) }
        let hasGitMetadataImpact = normalizedPaths.contains(where: Self.isGitMetadataPath)
        let requiresRescan = flags.contains(where: Self.isRescanFlag)

        guard hasTreeImpact || hasGitMetadataImpact || requiresRescan else { return nil }
        return ChangeEvent(
            changedPaths: normalizedPaths,
            hasTreeImpact: hasTreeImpact,
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

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
