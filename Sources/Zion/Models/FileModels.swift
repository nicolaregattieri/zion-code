import Foundation
import UniformTypeIdentifiers

// MARK: - File Tree

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let children: [FileItem]?
    let isGitIgnored: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool, children: [FileItem]?, isGitIgnored: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
        self.isGitIgnored = isGitIgnored
    }
}

struct FileHistoryEntry: Identifiable {
    let id = UUID()
    let hash: String
    let shortHash: String
    let author: String
    let date: String
    let message: String
}

enum EditorContentKind: Equatable, Sendable {
    case text
    case markdown
    case image
    case unsupported
}

enum EditorDirtyCloseDecision: Equatable, Sendable {
    case save
    case discard
    case cancel
}

// MARK: - Per-Repo Editor Config (.zion/editor.json)

struct EditorConfig: Codable {
    var tabSize: Int?
    var useTabs: Bool?
    var fontSize: Double?
    var theme: String?
    var rulerColumn: Int?
    var lineSpacing: Double?
    var showRuler: Bool?
    var showIndentGuides: Bool?

    static func load(from repoURL: URL) -> EditorConfig? {
        let configURL = repoURL.appendingPathComponent(".zion/editor.json")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(EditorConfig.self, from: data) else {
            return nil
        }
        return config
    }
}

// MARK: - Find in Files

struct FindInFilesMatch: Identifiable {
    let file: String
    let line: Int
    let preview: String
    let column: Int?
    let matchLength: Int?
    var id: String {
        if let column {
            return "\(file):\(line):\(column)"
        }
        return "\(file):\(line)"
    }

    init(
        file: String,
        line: Int,
        preview: String,
        column: Int? = nil,
        matchLength: Int? = nil
    ) {
        self.file = file
        self.line = line
        self.preview = preview
        self.column = column
        self.matchLength = matchLength
    }
}

struct FindInFilesFileResult: Identifiable {
    let file: String
    let matches: [FindInFilesMatch]
    var id: String { file }
}
