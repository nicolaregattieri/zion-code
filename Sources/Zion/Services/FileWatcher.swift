import Foundation

@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: UInt64 = 1_500_000_000 // 1.5 seconds

    var onFileChanged: (() -> Void)?
    var onRepositoryChanged: (() -> Void)?

    func watch(directory: URL) {
        stop()

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            DiagnosticLogger.shared.log(.warn, "FileWatcher: failed to open directory", context: directory.path, source: #function)
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        self.source = source
        source.resume()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
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
        let fd = fileDescriptor
        let s = source
        Task { @MainActor in
            s?.cancel()
            if fd >= 0 {
                close(fd)
            }
        }
    }
}
