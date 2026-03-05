import Foundation
import CoreServices

@MainActor
final class FileWatcher {
    private nonisolated(unsafe) var eventStream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: UInt64 = 1_500_000_000 // 1.5 seconds

    var onFileChanged: (() -> Void)?
    var onRepositoryChanged: (() -> Void)?

    func watch(directory: URL) {
        stop()

        let path = directory.path as CFString
        let pathsToWatch = [path] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
                guard let info = clientCallBackInfo else { return }

                // Filter out events that only touch .git/ internals
                if numEvents > 0, let cfArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] {
                    let hasNonGitPath = cfArray.contains { path in
                        !path.contains("/.git/") && !path.hasSuffix("/.git")
                    }
                    guard hasNonGitPath else { return }
                }

                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in
                    watcher.handleChange()
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5,
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
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    private func handleChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceInterval)
            guard !Task.isCancelled else { return }
            self.onFileChanged?()
            self.onRepositoryChanged?()
        }
    }

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
