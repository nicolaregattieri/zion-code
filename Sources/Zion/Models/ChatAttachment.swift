// ChatAttachment.swift
// Model + on-disk storage for chat message attachments (images, PDFs, generic files).
//
// MVP scope:
// - User can paste / drop / pick an image or PDF into the composer.
// - Binary is copied to Application Support so we don't depend on the
//   source file existing later (or being in a sandbox-readable location).
// - Metadata travels on the ChatMessage and is persisted as JSON.
// - Anthropic provider routes images as base64 content blocks; PDFs are
//   text-extracted via PDFKit and inlined as additional context.
// - Other providers receive a text marker placeholder (TODO: native
//   multimodal support).

import Foundation
import AppKit
import CryptoKit

// MARK: - ChatAttachmentKind

/// Coarse classification used to drive rendering + provider routing.
enum ChatAttachmentKind: String, Codable, Sendable {
    case image
    case pdf
    case other
}

// MARK: - ChatAttachment

struct ChatAttachment: Identifiable, Equatable, Codable, Sendable {

    /// Stable id used in storage paths.
    let id: UUID

    let kind: ChatAttachmentKind

    /// Original filename the user gave us (or auto-derived for clipboard
    /// images). Surfaced in the UI pill.
    let originalName: String

    /// IANA media type (e.g. `image/png`, `application/pdf`).
    let mimeType: String

    /// Byte size on disk at the time of capture.
    let size: Int

    /// SHA-256 of the on-disk bytes. Used for de-dup + integrity check.
    let sha256: String

    /// Path relative to `ChatAttachmentStore.baseDirectory` so the storage
    /// root can be moved without rewriting message records.
    let relativePath: String

    init(
        id: UUID = UUID(),
        kind: ChatAttachmentKind,
        originalName: String,
        mimeType: String,
        size: Int,
        sha256: String,
        relativePath: String
    ) {
        self.id = id
        self.kind = kind
        self.originalName = originalName
        self.mimeType = mimeType
        self.size = size
        self.sha256 = sha256
        self.relativePath = relativePath
    }

    /// Absolute URL on disk. Nil if the storage root is unavailable.
    func fileURL() -> URL? {
        ChatAttachmentStore.shared.absoluteURL(for: relativePath)
    }
}

// MARK: - ChatAttachmentStore

/// File-on-disk store for attachments. We keep binaries OUT of SQLite
/// so the chat DB stays small and easy to back up. Each attachment lives
/// at `~/Library/Application Support/Zion/attachments/<threadID>/<messageID>/<originalName>`.
struct ChatAttachmentStore {

    static let shared = ChatAttachmentStore()

    /// Max attachment size we accept (raw bytes). Above this we surface a
    /// warning and refuse to capture — keeps base64 payloads sane and avoids
    /// pasting a 200 MB video by accident.
    static let maxBytes = 20 * 1024 * 1024

    /// Root: `~/Library/Application Support/Zion/attachments/`.
    var baseDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Zion", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    func absoluteURL(for relativePath: String) -> URL? {
        baseDirectory.appendingPathComponent(relativePath)
    }

    /// Persists `data` for the given message, returning a fully populated
    /// `ChatAttachment` record. Throws if the file exceeds `maxBytes` or
    /// the I/O fails.
    func store(
        data: Data,
        originalName: String,
        mimeType: String,
        kind: ChatAttachmentKind,
        threadID: UUID,
        messageID: UUID
    ) throws -> ChatAttachment {
        guard data.count <= Self.maxBytes else {
            throw ChatAttachmentError.tooLarge(bytes: data.count, limit: Self.maxBytes)
        }
        let attachmentID = UUID()
        let safeName = Self.sanitize(filename: originalName)
        let relative = "\(threadID.uuidString)/\(messageID.uuidString)/\(attachmentID.uuidString)-\(safeName)"
        let target = baseDirectory.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: target, options: .atomic)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ChatAttachment(
            id: attachmentID,
            kind: kind,
            originalName: originalName,
            mimeType: mimeType,
            size: data.count,
            sha256: digest,
            relativePath: relative
        )
    }

    /// Slash and colon are stripped so the on-disk filename stays POSIX-safe.
    static func sanitize(filename: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\0")
        let scalars = filename.unicodeScalars.map { illegal.contains($0) ? "_" : String($0) }
        let cleaned = scalars.joined()
        return cleaned.isEmpty ? "file" : cleaned
    }
}

// MARK: - ChatAttachmentError

enum ChatAttachmentError: Error, LocalizedError {
    case tooLarge(bytes: Int, limit: Int)
    case unsupportedType(String)
    case readFailure(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes, let limit):
            return String(
                format: L10n("chat.attach.error.tooLarge"),
                ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file),
                ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            )
        case .unsupportedType(let type):
            return String(format: L10n("chat.attach.error.unsupported"), type)
        case .readFailure(let detail):
            return String(format: L10n("chat.attach.error.read"), detail)
        }
    }
}
