// ResolvedMention.swift — Model types for @mention expansion in chat messages.

import Foundation

// MARK: - MentionKind

enum MentionKind: String, Sendable, CaseIterable {
    case file
    case folder
    case selection
    case web
    case diff
    case pr
    case code
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
    /// Stable, cache-friendly context (repomap auto-seed + git header).
    /// Should be byte-identical across turns when the repo state is unchanged.
    /// Filled by ChatService at send time; MentionResolver always leaves this empty.
    let stableContext: String

    /// Volatile, per-turn context (resolved @mention blocks + dynamic additions).
    /// Changes every turn — must NOT be marked with `cache_control`.
    let volatileContext: String

    /// Total byte count across all resolved mentions.
    let totalBytes: Int
    /// Per-file breakdown: (path, bytes). May have multiple entries for @folder.
    let perFileBreakdown: [(path: String, bytes: Int)]
    /// All resolved mentions in order.
    let mentions: [ResolvedMention]

    /// Back-compat: concatenated for callers not yet rewired to use stable/volatile.
    var systemContext: String {
        if stableContext.isEmpty { return volatileContext }
        if volatileContext.isEmpty { return stableContext }
        return stableContext + "\n\n" + volatileContext
    }

    static let empty = MentionPayload(
        stableContext: "",
        volatileContext: "",
        totalBytes: 0,
        perFileBreakdown: [],
        mentions: []
    )
}
