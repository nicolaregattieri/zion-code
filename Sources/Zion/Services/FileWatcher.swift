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
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleChange()
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func handleChange() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceInterval)
            guard !Task.isCancelled else { return }
            onFileChanged?()
            onRepositoryChanged?()
        }
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
