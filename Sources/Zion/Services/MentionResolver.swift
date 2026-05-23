// MentionResolver.swift — Expands @file/@folder/@selection/@web mentions in chat messages.
//
// Scans only outside code fences. Caps @folder at maxFilesPerFolder BEFORE I/O fan-out.
// Each individual file is capped at maxBytesPerFile bytes.

import Foundation

// MARK: - MentionToolClient protocol

/// Thin string-returning protocol so tests can inject a mock without
/// bridging the full MCPClientProtocol dict format.
protocol MentionToolClient: Sendable {
    func callTool(_ name: String, args: [String: Any]) async throws -> String
}

// MARK: - MCPClientProtocol adapter

/// Wraps an MCPClientProtocol so MentionResolver can call it as a MentionToolClient.
/// Extracts a text string from the MCP result dict (tries "content", "text", "result").
final class MCPMentionAdapter: MentionToolClient, @unchecked Sendable {
    private let client: any MCPClientProtocol
    init(_ client: any MCPClientProtocol) { self.client = client }

    func callTool(_ name: String, args: [String: Any]) async throws -> String {
        let result = try await client.callTool(name, args: args)
        // MCP result may wrap content in various keys depending on the server.
        if let text = result["content"] as? String { return text }
        if let text = result["text"] as? String { return text }
        if let text = result["result"] as? String { return text }
        // Fallback: JSON-encode the dict
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let str = String(data: data, encoding: .utf8) { return str }
        return ""
    }
}

// MARK: - MentionResolver

/// Parses and resolves @mention tokens in user chat messages.
/// Code fences (triple-backtick blocks) are excluded from parsing.
actor MentionResolver {

    // MARK: Constants

    static let defaultMaxFilesPerFolder = 20
    static let defaultMaxBytesPerFile = 65_536

    private static let textExtensions: Set<String> = [
        "swift", "kt", "java", "py", "js", "ts", "jsx", "tsx",
        "go", "rs", "rb", "php", "c", "cpp", "h", "hpp", "m", "mm",
        "sh", "bash", "zsh", "fish",
        "html", "htm", "css", "scss", "sass", "less",
        "json", "yaml", "yml", "toml", "xml", "plist",
        "md", "markdown", "txt", "rst", "adoc",
        "sql", "graphql", "proto",
        "env", "gitignore", "dockerfile", "makefile",
        ""   // no extension
    ]

    // MARK: Dependencies

    private let toolClient: any MentionToolClient
    private let selectionProvider: @Sendable () -> String?

    // MARK: Init

    init(
        toolClient: any MentionToolClient,
        selectionProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.toolClient = toolClient
        self.selectionProvider = selectionProvider
    }

    /// Convenience init that wraps an MCPClientProtocol.
    init(
        mcpClient: any MCPClientProtocol,
        selectionProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.toolClient = MCPMentionAdapter(mcpClient)
        self.selectionProvider = selectionProvider
    }

    // MARK: Public API

    /// Parse and resolve all @mentions in the message. Code fences are excluded.
    func expand(message: String) async -> MentionPayload {
        let parsed = Self.parseMentions(message)
        guard !parsed.isEmpty else { return .empty }

        let maxFiles = UserDefaults.standard.object(forKey: "chat.mentions.maxFilesPerFolder") as? Int
            ?? Self.defaultMaxFilesPerFolder
        let maxBytes = UserDefaults.standard.object(forKey: "chat.mentions.maxBytesPerFile") as? Int
            ?? Self.defaultMaxBytesPerFile

        var resolved: [ResolvedMention] = []
        var breakdown: [(path: String, bytes: Int)] = []

        for mention in parsed {
            switch mention.kind {

            case .file:
                let (contents, bytes) = await resolveFile(path: mention.argument, maxBytes: maxBytes)
                resolved.append(ResolvedMention(kind: .file, argument: mention.argument, contents: contents, bytes: bytes))
                breakdown.append((path: mention.argument, bytes: bytes))

            case .folder:
                let results = await resolveFolder(path: mention.argument, maxFiles: maxFiles, maxBytes: maxBytes)
                for (path, contents, bytes) in results {
                    breakdown.append((path: path, bytes: bytes))
                }
                let folderContents = buildFolderContents(mention.argument, files: results)
                let totalFolderBytes = results.reduce(0) { $0 + $1.bytes }
                resolved.append(ResolvedMention(kind: .folder, argument: mention.argument, contents: folderContents, bytes: totalFolderBytes))

            case .selection:
                if let text = selectionProvider() {
                    let capped = ByteSafeTruncate.cap(text, maxBytes: maxBytes)
                    let bytes = capped.utf8.count
                    resolved.append(ResolvedMention(kind: .selection, argument: "", contents: capped, bytes: bytes))
                    breakdown.append((path: "@selection", bytes: bytes))
                } else {
                    resolved.append(ResolvedMention(kind: .selection, argument: "", contents: "[error: no selection]", bytes: 0))
                }

            case .web:
                let (contents, bytes) = await resolveWeb(url: mention.argument, maxBytes: maxBytes)
                resolved.append(ResolvedMention(kind: .web, argument: mention.argument, contents: contents, bytes: bytes))
                breakdown.append((path: mention.argument, bytes: bytes))
            }
        }

        let context = buildSystemContext(resolved)
        let total = breakdown.reduce(0) { $0 + $1.bytes }
        return MentionPayload(systemContext: context, totalBytes: total, perFileBreakdown: breakdown, mentions: resolved)
    }

    /// Dry-run: count mentions and estimate byte cost without performing I/O.
    func dryRun(message: String) async -> (estimatedBytes: Int, mentionCount: Int) {
        let parsed = Self.parseMentions(message)
        let maxBytes = UserDefaults.standard.object(forKey: "chat.mentions.maxBytesPerFile") as? Int
            ?? Self.defaultMaxBytesPerFile
        let maxFiles = UserDefaults.standard.object(forKey: "chat.mentions.maxFilesPerFolder") as? Int
            ?? Self.defaultMaxFilesPerFolder
        let estimated = parsed.reduce(0) { sum, m in
            switch m.kind {
            case .file, .web: return sum + maxBytes
            case .folder: return sum + (maxFiles * maxBytes)
            case .selection: return sum + maxBytes
            }
        }
        return (estimatedBytes: estimated, mentionCount: parsed.count)
    }

    // MARK: Static parsers (exposed for tests)

    /// Splits message into alternating (text, inFence) segments by walking line by line.
    static func splitCodeFences(_ message: String) -> [(text: String, inFence: Bool)] {
        var segments: [(text: String, inFence: Bool)] = []
        var inFence = false
        var current = ""

        for line in message.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                // Emit the current segment before the fence delimiter
                if !current.isEmpty {
                    segments.append((text: current, inFence: inFence))
                    current = ""
                }
                // The fence line itself belongs to the transitioning block — skip it
                inFence.toggle()
            } else {
                current += (current.isEmpty ? "" : "\n") + line
            }
        }
        if !current.isEmpty {
            segments.append((text: current, inFence: inFence))
        }
        return segments
    }

    /// Parse @mention tokens outside code fences.
    /// Returns (kind, argument, range) tuples in order of appearance.
    static func parseMentions(_ message: String) -> [(kind: MentionKind, argument: String, range: Range<String.Index>)] {
        let segments = splitCodeFences(message)
        var results: [(kind: MentionKind, argument: String, range: Range<String.Index>)] = []

        // Regex: (^|whitespace)@(file|folder|selection|web)(\s+\S+)?
        // We parse segments that are NOT in a fence.
        for segment in segments where !segment.inFence {
            let text = segment.text
            var searchStart = text.startIndex

            while searchStart < text.endIndex {
                // Find the next '@'
                guard let atRange = text.range(of: "@", range: searchStart..<text.endIndex) else { break }

                // Verify leading char is whitespace or start-of-text
                if atRange.lowerBound != text.startIndex {
                    let prevIdx = text.index(before: atRange.lowerBound)
                    let prevChar = text[prevIdx]
                    guard prevChar.isWhitespace || prevChar.isNewline else {
                        searchStart = text.index(after: atRange.lowerBound)
                        continue
                    }
                }

                // Extract the word after '@'
                let afterAt = atRange.upperBound
                let wordEnd = text[afterAt...].firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? text.endIndex
                let kindStr = String(text[afterAt..<wordEnd])

                guard let kind = MentionKind(rawValue: kindStr.lowercased()) else {
                    searchStart = wordEnd == text.endIndex ? text.endIndex : text.index(after: wordEnd)
                    continue
                }

                // Argument: next non-whitespace token (or quoted string) after the kind
                var argument = ""
                let afterKind = wordEnd

                if afterKind < text.endIndex {
                    // Skip whitespace
                    let argStart = text[afterKind...].firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) ?? text.endIndex
                    if argStart < text.endIndex {
                        if text[argStart] == "\"" {
                            // Quoted argument
                            let contentStart = text.index(after: argStart)
                            if let closingQuote = text[contentStart...].firstIndex(of: "\"") {
                                argument = String(text[contentStart..<closingQuote])
                                searchStart = text.index(after: closingQuote)
                            } else {
                                // Unterminated quote — treat rest as argument
                                argument = String(text[contentStart...])
                                searchStart = text.endIndex
                            }
                        } else {
                            // Unquoted argument: read until whitespace or newline
                            let argEnd = text[argStart...].firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? text.endIndex
                            argument = String(text[argStart..<argEnd])
                            searchStart = argEnd == text.endIndex ? text.endIndex : text.index(after: argEnd)
                        }
                    } else {
                        searchStart = text.endIndex
                    }
                } else {
                    searchStart = text.endIndex
                }

                // Only emit if we have an argument (or it's @selection, which doesn't need one)
                if kind == .selection || !argument.isEmpty {
                    let mentionEnd = searchStart == text.endIndex ? text.endIndex : searchStart
                    results.append((kind: kind, argument: argument, range: atRange.lowerBound..<mentionEnd))
                }
                // If no argument for non-selection kinds, skip silently
            }
        }

        return results
    }

    // MARK: Private resolution helpers

    private func resolveFile(path: String, maxBytes: Int) async -> (contents: String, bytes: Int) {
        guard !path.isEmpty else { return ("[error: missing argument]", 0) }
        do {
            let raw = try await toolClient.callTool("read_file", args: ["path": path])
            // Binary detection: check first 1024 bytes for NULL
            let probe = String(raw.prefix(1024))
            if probe.contains("\0") {
                return ("[error: binary file skipped]", 0)
            }
            let cappedStr = cap(raw, maxBytes: maxBytes)
            let bytes = cappedStr.utf8.count
            return (cappedStr, bytes)
        } catch {
            return ("[error: \(error.localizedDescription)]", 0)
        }
    }

    private func resolveFolder(path: String, maxFiles: Int, maxBytes: Int) async -> [(path: String, contents: String, bytes: Int)] {
        guard !path.isEmpty else { return [] }
        let listing: String
        do {
            listing = try await toolClient.callTool("list_dir", args: ["path": path])
        } catch {
            return [(path, "[error: \(error.localizedDescription)]", 0)]
        }

        // Parse listing: one path per line
        let allPaths = listing.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Filter to text-looking files by extension
        let textPaths = allPaths.filter { isTextFile($0) }

        // CAP BEFORE I/O fan-out
        let capped = Array(textPaths.prefix(maxFiles))

        // Fan-out: read each file
        var results: [(path: String, contents: String, bytes: Int)] = []
        for filePath in capped {
            let (contents, bytes) = await resolveFile(path: filePath, maxBytes: maxBytes)
            results.append((filePath, contents, bytes))
        }
        return results
    }

    private func resolveWeb(url: String, maxBytes: Int) async -> (contents: String, bytes: Int) {
        guard !url.isEmpty else { return ("[error: missing argument]", 0) }
        do {
            let raw = try await toolClient.callTool("web_fetch", args: ["url": url])
            let capped = cap(raw, maxBytes: maxBytes)
            return (capped, capped.utf8.count)
        } catch {
            return ("[error: \(error.localizedDescription)]", 0)
        }
    }

    // MARK: Private helpers

    private func cap(_ text: String, maxBytes: Int) -> String {
        ByteSafeTruncate.cap(text, maxBytes: maxBytes)
    }

    private func isTextFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return Self.textExtensions.contains(ext)
    }

    private func buildFolderContents(_ folderPath: String, files: [(path: String, contents: String, bytes: Int)]) -> String {
        var parts: [String] = []
        for (path, contents, _) in files {
            parts.append("### \(path)\n\(contents)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func buildSystemContext(_ mentions: [ResolvedMention]) -> String {
        guard !mentions.isEmpty else { return "" }
        var sections: [String] = []
        for mention in mentions {
            switch mention.kind {
            case .file:
                sections.append("## @file \(mention.argument)\n\(mention.contents)")
            case .folder:
                let fileCount = mention.contents.components(separatedBy: "### ").count - 1
                sections.append("## @folder \(mention.argument) (\(fileCount) files)\n\(mention.contents)")
            case .selection:
                sections.append("## @selection\n\(mention.contents)")
            case .web:
                sections.append("## @web \(mention.argument)\n\(mention.contents)")
            }
        }
        return "<attached_context>\n" + sections.joined(separator: "\n\n") + "\n</attached_context>"
    }
}
