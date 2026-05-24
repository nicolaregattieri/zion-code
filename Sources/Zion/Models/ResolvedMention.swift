// ResolvedMention.swift — Model types for @mention expansion in chat messages.

import Foundation

// MARK: - MentionKind

enum MentionKind: String, Sendable, CaseIterable {
    case file
    case folder
    case selection
    case web
}

// MARK: - ResolvedMention

struct ResolvedMention: Sendable {
    /// Which kind of mention this was.
    let kind: MentionKind
    /// Raw token after @file/@folder/@web; empty string for @selection.
    let argument: String
    /// Resolved bytes (may be an error marker like "[error: ...]").
    let contents: String
    /// Byte count of `contents`.
    let bytes: Int
}

// MARK: - MentionPayload

struct MentionPayload: Sendable {
    /// Ready-to-prepend Markdown block; empty string if no mentions found.
    let systemContext: String
    /// Total byte count across all resolved mentions.
    let totalBytes: Int
    /// Per-file breakdown: (path, bytes). May have multiple entries for @folder.
    let perFileBreakdown: [(path: String, bytes: Int)]
    /// All resolved mentions in order.
    let mentions: [ResolvedMention]

    static let empty = MentionPayload(
        systemContext: "",
        totalBytes: 0,
        perFileBreakdown: [],
        mentions: []
    )
}
