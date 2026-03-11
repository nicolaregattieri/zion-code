import Foundation

struct BridgeCacheStore {
    private let fileManager: FileManager
    private let baseDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseDirectory = caches.appendingPathComponent("Zion/Bridge", isDirectory: true)
        }
    }

    func loadMatrix(for repositoryURL: URL) -> BridgeMirrorMatrix {
        let url = matrixURL(for: repositoryURL)
        guard let data = try? Data(contentsOf: url) else {
            return .empty
        }

        return (try? JSONDecoder.bridgeCacheDecoder.decode(BridgeMirrorMatrix.self, from: data)) ?? .empty
    }

    func saveMatrix(_ matrix: BridgeMirrorMatrix, for repositoryURL: URL) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.bridgeCacheEncoder.encode(matrix)
        try data.write(to: matrixURL(for: repositoryURL), options: .atomic)
    }

    private func matrixURL(for repositoryURL: URL) -> URL {
        baseDirectory.appendingPathComponent("\(RepoMemoryService.repoFingerprint(for: repositoryURL)).json")
    }
}

private extension JSONEncoder {
    static var bridgeCacheEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var bridgeCacheDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
