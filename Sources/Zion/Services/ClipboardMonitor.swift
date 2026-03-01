import Foundation
import AppKit
import SwiftUI

struct ClipboardItem: Identifiable, Sendable {
    let id: UUID
    let text: String
    let timestamp: Date
    let preview: String
    let category: Category
    let isImage: Bool
    let imageSize: CGSize?
    var imagePath: String? { isImage && !text.isEmpty ? text : nil }

    enum Category: Sendable {
        case command, path, hash, url, image, text

        var icon: String {
            switch self {
            case .command: return "terminal"
            case .path: return "folder"
            case .hash: return "number"
            case .url: return "link"
            case .image: return "photo"
            case .text: return "doc.text"
            }
        }
    }

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.preview = Self.makePreview(text)
        self.category = Self.detectCategory(text)
        self.isImage = false
        self.imageSize = nil
    }

    init(imageWidth: Int, imageHeight: Int, filePath: String? = nil) {
        self.id = UUID()
        self.text = filePath ?? ""
        self.timestamp = Date()
        let sizeLabel = "\(imageWidth) x \(imageHeight)"
        if let path = filePath {
            self.preview = (path as NSString).lastPathComponent + " (\(sizeLabel))"
        } else {
            self.preview = sizeLabel
        }
        self.category = .image
        self.isImage = true
        self.imageSize = CGSize(width: imageWidth, height: imageHeight)
    }

    private static func makePreview(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = Constants.Limits.clipboardPreviewTruncationLength
        if singleLine.count > maxLength {
            return String(singleLine.prefix(maxLength - 3)) + "..."
        }
        return singleLine
    }

    private static let commandPrefixes: Set<String> = [
        "git", "npm", "yarn", "docker", "cd", "ls", "cat", "echo", "mkdir",
        "rm", "cp", "mv", "grep", "find", "curl", "wget", "ssh", "scp",
        "swift", "python", "node", "ruby", "cargo", "make", "brew",
        "pod", "xcodebuild", "open", "kill", "ps", "top", "chmod",
        "chown", "sudo", "apt", "pip", "go", "rustc", "javac"
    ]

    private static func detectCategory(_ text: String) -> Category {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        // URL
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("ssh://") || trimmed.hasPrefix("git@") {
            return .url
        }

        // Path
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed.hasPrefix("./") {
            return .path
        }

        // Git hash (7-40 hex chars, single token)
        if !trimmed.contains(" "),
           trimmed.count >= 7, trimmed.count <= 40,
           trimmed.allSatisfy({ $0.isHexDigit }) {
            return .hash
        }

        // Command (first word matches known CLI tools)
        let firstWord = String(trimmed.prefix(while: { !$0.isWhitespace }))
        if commandPrefixes.contains(firstWord.lowercased()) {
            return .command
        }

        return .text
    }
}

@Observable @MainActor
final class ClipboardMonitor {
    var items: [ClipboardItem] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount: Int = 0
    @ObservationIgnored private var lastPurge: Date = .distantPast

    private let maxItems = 20
    private static let maxFileAge: TimeInterval = 60 * 60 // 1 hour

    private static let imageDir: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("Zion/clipboard", isDirectory: true)
    }()

    var isCollapsed: Bool = UserDefaults.standard.bool(forKey: "clipboard.collapsed") {
        didSet { UserDefaults.standard.set(isCollapsed, forKey: "clipboard.collapsed") }
    }

    static func purgeStaleFilesOnLaunch() {
        purgeOldTempFiles(in: imageDir, maxAge: maxFileAge)
    }

    static func cleanupAllTempFiles() {
        try? FileManager.default.removeItem(at: imageDir)
    }

    func start() {
        guard timer == nil else { return }
        purgeOldTempFiles()
        lastChangeCount = NSPasteboard.general.changeCount
        // Use .common mode so the timer fires even during UI interactions (scrolling, resizing)
        let pollTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        timer = pollTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clearAll() {
        deleteTempFiles(for: items)
        items.removeAll()
    }

    func remove(_ item: ClipboardItem) {
        deleteTempFiles(for: [item])
        items.removeAll { $0.id == item.id }
    }

    private func poll() {
        // Purge old temp files every 10 minutes
        if Date().timeIntervalSince(lastPurge) > 600 {
            lastPurge = Date()
            purgeOldTempFiles()
        }

        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check for file URLs first (covers copied files from Finder, including images)
        if let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let firstURL = fileURLs.first {
            let path = firstURL.path
            let ext = firstURL.pathExtension.lowercased()
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "tiff", "bmp", "ico", "heic"]
            if imageExtensions.contains(ext), let image = NSImage(contentsOf: firstURL) {
                let imageWidth = Int(image.size.width)
                let imageHeight = Int(image.size.height)
                if let first = items.first, first.isImage, first.text == path { return }
                let item = ClipboardItem(imageWidth: imageWidth, imageHeight: imageHeight, filePath: path)
                addItem(item)
                return
            }
            // Non-image file — treat path as text
            if let first = items.first, first.text == path { return }
            let item = ClipboardItem(text: path)
            addItem(item)
            return
        }

        // Check for image data without file URL (e.g. screenshot, copy from browser)
        if let imageType = pb.availableType(from: [.tiff, .png]),
           let imageData = pb.data(forType: imageType),
           let image = NSImage(data: imageData) {
            let imageWidth = Int(image.size.width)
            let imageHeight = Int(image.size.height)
            if let first = items.first, first.isImage, first.imageSize == CGSize(width: imageWidth, height: imageHeight) {
                return
            }
            _ = imageType
            // Save image data to temp file so we have a draggable file path
            let savedPath = saveImageToTemp(imageData, width: imageWidth, height: imageHeight)
            let item = ClipboardItem(imageWidth: imageWidth, imageHeight: imageHeight, filePath: savedPath)
            addItem(item)
            return
        }

        // Check for text
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Avoid duplicates of the exact same text at the top
        if let first = items.first, first.text == text { return }

        let item = ClipboardItem(text: text)
        addItem(item)
    }

    private func saveImageToTemp(_ data: Data, width: Int, height: Int) -> String {
        let dir = Self.imageDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = friendlyImageFileName(width: width, height: height)
        let fileURL = uniqueImageURL(in: dir, preferredName: name)
        if let image = NSImage(data: data),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpgData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            try? jpgData.write(to: fileURL)
        } else {
            try? data.write(to: fileURL)
        }
        return fileURL.path
    }

    private func friendlyImageFileName(width: Int, height: Int, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: now)
        return "IMG_\(timestamp)_\(width)x\(height).jpg"
    }

    private func uniqueImageURL(in dir: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(preferredName)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        for index in 1...1000 {
            let nextName = "\(base)-\(index).\(ext)"
            candidate = dir.appendingPathComponent(nextName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return dir.appendingPathComponent(UUID().uuidString + ".jpg")
    }

    /// Delete temp files belonging to specific clipboard items
    private func deleteTempFiles(for clipboardItems: [ClipboardItem]) {
        let fm = FileManager.default
        let prefix = Self.imageDir.path
        for item in clipboardItems where item.isImage && item.text.hasPrefix(prefix) {
            try? fm.removeItem(atPath: item.text)
        }
    }

    /// Delete temp files older than maxFileAge (1h)
    private func purgeOldTempFiles() {
        Self.purgeOldTempFiles(in: Self.imageDir, maxAge: Self.maxFileAge)
    }

    private static func purgeOldTempFiles(in dir: URL, maxAge: TimeInterval) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for file in files {
            let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate
            if let date, date < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func addItem(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        if items.count > maxItems {
            // Delete temp files for items being evicted
            let evicted = Array(items.suffix(from: maxItems))
            deleteTempFiles(for: evicted)
            items = Array(items.prefix(maxItems))
        }
    }

    func cleanup() {
        timer?.invalidate()
        timer = nil
        // Wipe all clipboard image files on shutdown
        try? FileManager.default.removeItem(at: Self.imageDir)
    }
}
