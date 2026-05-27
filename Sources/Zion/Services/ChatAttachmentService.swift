// ChatAttachmentService.swift
// Helpers that turn raw user input (NSPasteboard, drag drop, NSOpenPanel)
// into ChatAttachment records, plus PDF text extraction used for non-vision
// providers.

import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - PendingChatAttachment

/// Draft attachment held by the composer before send. Same shape as
/// `ChatAttachment` but the binary already lives in App Support — we just
/// haven't bound it to a real `ChatMessage` yet.
struct PendingChatAttachment: Identifiable, Equatable {
    let id: UUID
    let kind: ChatAttachmentKind
    let originalName: String
    let mimeType: String
    let size: Int
    /// Absolute URL inside App Support's `attachments/draft/<id>/`.
    let fileURL: URL

    var isImage: Bool { kind == .image }
}

// MARK: - ChatAttachmentService

enum ChatAttachmentService {

    /// Draft folder used before the attachment is bound to a real message.
    /// On send the file is rehomed under the message's directory.
    private static var draftBaseURL: URL {
        ChatAttachmentStore.shared.baseDirectory
            .appendingPathComponent("draft", isDirectory: true)
    }

    // MARK: - Capture from clipboard

    /// Looks at the current pasteboard and, if it carries an image or a file
    /// URL to a supported file (image/PDF), captures it as a draft
    /// attachment. Returns nil when nothing capture-worthy is present so the
    /// caller can fall back to normal text paste.
    static func captureFromPasteboard(_ pb: NSPasteboard = .general) -> [PendingChatAttachment] {
        var out: [PendingChatAttachment] = []

        // Case 1: file URLs (Finder drag, screenshot saved to Desktop, etc.)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            for url in urls where url.isFileURL {
                if let pending = try? captureFromFile(url: url) {
                    out.append(pending)
                }
            }
            if !out.isEmpty { return out }
        }

        // Case 2: raw image data on the pasteboard (Cmd-Shift-Ctrl-4
        // screenshot, image copied from a browser, etc.)
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in imageTypes {
            if let data = pb.data(forType: type) {
                let (saveData, mime, ext) = normalizeImageData(data, sourceType: type)
                let name = "Pasted-\(timestampSlug()).\(ext)"
                if let pending = try? saveDraft(data: saveData, originalName: name, mimeType: mime, kind: .image) {
                    out.append(pending)
                    return out
                }
            }
        }

        return out
    }

    /// Captures a file URL from drag-drop or NSOpenPanel.
    static func captureFromFile(url: URL) throws -> PendingChatAttachment {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ChatAttachmentError.readFailure(error.localizedDescription)
        }
        guard data.count <= ChatAttachmentStore.maxBytes else {
            throw ChatAttachmentError.tooLarge(bytes: data.count, limit: ChatAttachmentStore.maxBytes)
        }
        let (kind, mime) = classify(url: url, data: data)
        return try saveDraft(
            data: data,
            originalName: url.lastPathComponent,
            mimeType: mime,
            kind: kind
        )
    }

    // MARK: - Bind draft to message

    /// Moves a set of draft files under the message's permanent location and
    /// returns the persisted `ChatAttachment` records.
    static func bindDrafts(
        _ drafts: [PendingChatAttachment],
        threadID: UUID,
        messageID: UUID
    ) -> [ChatAttachment] {
        var results: [ChatAttachment] = []
        for draft in drafts {
            guard let data = try? Data(contentsOf: draft.fileURL) else { continue }
            do {
                let record = try ChatAttachmentStore.shared.store(
                    data: data,
                    originalName: draft.originalName,
                    mimeType: draft.mimeType,
                    kind: draft.kind,
                    threadID: threadID,
                    messageID: messageID
                )
                results.append(record)
                // Best-effort cleanup of the draft copy.
                try? FileManager.default.removeItem(at: draft.fileURL)
            } catch {
                continue
            }
        }
        return results
    }

    // MARK: - PDF text extraction

    /// Extracts plain text from a PDF for inlining into the model context.
    /// Returns nil if PDFKit can't open the file (e.g. encrypted PDFs).
    static func extractText(fromPDF url: URL, maxChars: Int = 30_000) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var collected = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let text = page.string else { continue }
            collected += text
            collected += "\n"
            if collected.count >= maxChars { break }
        }
        if collected.count > maxChars {
            collected = String(collected.prefix(maxChars)) + "\n…[truncated]"
        }
        return collected.isEmpty ? nil : collected
    }

    // MARK: - Internal

    private static func saveDraft(
        data: Data,
        originalName: String,
        mimeType: String,
        kind: ChatAttachmentKind
    ) throws -> PendingChatAttachment {
        guard data.count <= ChatAttachmentStore.maxBytes else {
            throw ChatAttachmentError.tooLarge(bytes: data.count, limit: ChatAttachmentStore.maxBytes)
        }
        let id = UUID()
        let safeName = ChatAttachmentStore.sanitize(filename: originalName)
        let folder = draftBaseURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(safeName)
        try data.write(to: target, options: .atomic)
        return PendingChatAttachment(
            id: id,
            kind: kind,
            originalName: originalName,
            mimeType: mimeType,
            size: data.count,
            fileURL: target
        )
    }

    private static func classify(url: URL, data: Data) -> (ChatAttachmentKind, String) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return (.image, "image/png")
        case "jpg", "jpeg": return (.image, "image/jpeg")
        case "gif": return (.image, "image/gif")
        case "webp": return (.image, "image/webp")
        case "heic": return (.image, "image/heic")
        case "tiff", "tif": return (.image, "image/tiff")
        case "pdf": return (.pdf, "application/pdf")
        default:
            // Fall back to UTType resolution where possible.
            if let type = UTType(filenameExtension: ext) {
                if type.conforms(to: .image) {
                    return (.image, type.preferredMIMEType ?? "application/octet-stream")
                }
                if type.conforms(to: .pdf) {
                    return (.pdf, "application/pdf")
                }
                return (.other, type.preferredMIMEType ?? "application/octet-stream")
            }
            return (.other, "application/octet-stream")
        }
    }

    /// Anthropic's vision endpoint only accepts a small set of media types.
    /// We re-encode TIFFs to PNG so screenshots pasted via Cmd-Shift-Ctrl-4
    /// (which land as TIFF on the pasteboard) don't get rejected.
    private static func normalizeImageData(
        _ data: Data,
        sourceType: NSPasteboard.PasteboardType
    ) -> (Data, String, String) {
        if sourceType == .png {
            return (data, "image/png", "png")
        }
        if let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "image/png", "png")
        }
        return (data, "image/png", "png")
    }

    private static func timestampSlug() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
