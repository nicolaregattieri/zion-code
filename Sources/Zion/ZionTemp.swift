import Foundation

enum ZionTemp {
    static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("Zion/tmp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Remove files older than 1 hour (crash recovery).
    static func purgeStaleFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for file in files {
            if let date = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
               date < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }
}
