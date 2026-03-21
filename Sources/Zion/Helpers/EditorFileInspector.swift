import Foundation
import UniformTypeIdentifiers

enum EditorFilePreparationResult: Sendable {
    case missing
    case ready(kind: EditorContentKind, content: String?)
    case readFailure(String)
}

enum EditorFileSaveResult {
    case saved(fileID: String)
    case cancelled
    case failed
}

enum EditorFileClosePreparation {
    case ready(fileID: String)
    case cancelled
}

enum EditorFileInspector {
    static let acceptedTextTypes: [UTType] = [
        .text, .plainText, .sourceCode, .shellScript, .script,
        .json, .xml, .yaml, .html,
    ]

    static let acceptedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "svg",
    ]

    static func contentKind(for url: URL) -> EditorContentKind {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return .markdown
        }
        if ext == "svg" || acceptedImageExtensions.contains(ext) {
            return .image
        }
        if url.path.hasPrefix(ZionTemp.directory.path) {
            return .text
        }
        if isImageFile(url) {
            return .image
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            return .text
        }
        return isTextFile(url) ? .text : .unsupported
    }

    static func isTextFile(_ url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = resourceValues.contentType else {
            return isLikelyTextFileByContent(url)
        }
        if acceptedTextTypes.contains(where: { contentType.conforms(to: $0) }) {
            return true
        }
        return isLikelyTextFileByContent(url)
    }

    static func isImageFile(_ url: URL) -> Bool {
        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType,
           contentType.conforms(to: .image) {
            return true
        }
        let ext = url.pathExtension.lowercased()
        if ext == "svg" {
            return true
        }
        return acceptedImageExtensions.contains(ext)
    }

    static func prepareForEditor(url: URL) -> EditorFilePreparationResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        let kind = contentKind(for: url)
        guard kind == .text || kind == .markdown else {
            return .ready(kind: kind, content: nil)
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return .ready(kind: kind, content: content)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                return .missing
            }
            return .readFailure(error.localizedDescription)
        }
    }

    private static func isLikelyTextFileByContent(_ url: URL, maxBytes: Int = 8_192) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return false }
        if data.isEmpty { return true }
        if data.contains(0) { return false }
        if String(data: data, encoding: .utf8) != nil { return true }
        if String(data: data, encoding: .ascii) != nil { return true }
        return false
    }
}
