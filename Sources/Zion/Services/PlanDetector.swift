import Foundation

// MARK: - PlanDetector

/// Consumes incremental text deltas and emits a complete ChatPlan once
/// a `<plan>...</plan>` block is fully observed. Tolerant of partial-tag
/// splits across deltas. Also handles a fallback `Plan:\n1. …` text format.
struct PlanDetector {

    // MARK: - Constants

    private static let maxBufferBytes = 64 * 1024  // 64 KB hard cap

    private static let openTag  = "<plan>"
    private static let closeTag = "</plan>"

    // Fallback: "plan:" header (case-insensitive, anchored to line start)
    private static let fallbackRegex: NSRegularExpression = {
        // Matches "plan:" at the start of a line (possibly with leading whitespace)
        try! NSRegularExpression(pattern: #"(?im)^\s*plan\s*:\s*$"#, options: [])
    }()

    // Numbered list item: "1. some text"
    private static let numberedItemRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\s*\d+\.\s+(.+)$"#, options: [.anchorsMatchLines])
    }()

    // MARK: - State

    private var buffer: String = ""

    // MARK: - Public API

    /// Feed a new delta. Returns a fully parsed ChatPlan when the closing tag
    /// (or fallback terminator) is observed; returns nil while still streaming.
    /// After a plan is returned the internal buffer resets automatically.
    mutating func feed(_ delta: String) -> ChatPlan? {
        buffer += delta

        // Enforce max-buffer cap — drop buffer and start fresh to avoid runaway memory
        if buffer.utf8.count > Self.maxBufferBytes {
            buffer = ""
            return nil
        }

        // Primary XML path
        if let plan = tryExtractXMLPlan() {
            buffer = ""
            return plan
        }

        // Fallback text path
        if let plan = tryExtractFallbackPlan() {
            buffer = ""
            return plan
        }

        return nil
    }

    // MARK: - XML extraction

    private func tryExtractXMLPlan() -> ChatPlan? {
        guard let openRange  = buffer.range(of: Self.openTag,  options: .caseInsensitive),
              let closeRange = buffer.range(of: Self.closeTag, options: .caseInsensitive),
              openRange.lowerBound < closeRange.lowerBound
        else { return nil }

        // closeRange.upperBound is one-past-end (exclusive), which is exactly what we want
        // for a half-open range. Use ...closeRange.upperBound only if it's within the string.
        let end = closeRange.upperBound
        guard end <= buffer.endIndex else { return nil }
        let fullBlock = String(buffer[openRange.lowerBound..<end])
        return parsePlanXML(fullBlock)
    }

    // MARK: - XML parser

    /// Parses a complete `<plan>...</plan>` substring into a ChatPlan.
    func parsePlanXML(_ xml: String) -> ChatPlan {
        var steps: [ChatPlanStep] = []

        // Extract every <step>...</step> block
        let stepPattern = try! NSRegularExpression(
            pattern: #"<step>([\s\S]*?)</step>"#,
            options: [.caseInsensitive]
        )
        let nsXML = xml as NSString
        let stepMatches = stepPattern.matches(in: xml, range: NSRange(location: 0, length: nsXML.length))

        for match in stepMatches {
            guard match.numberOfRanges > 1 else { continue }
            let innerRange = match.range(at: 1)
            guard innerRange.location != NSNotFound else { continue }
            let inner = nsXML.substring(with: innerRange)
            steps.append(parseStepContent(inner))
        }

        return ChatPlan(rawXML: xml, steps: steps)
    }

    // MARK: - Step content parser

    private func parseStepContent(_ inner: String) -> ChatPlanStep {
        let commit  = extractTag("commit",  from: inner)
        let summary = extractTag("summary", from: inner) ?? ""
        let filesRaw = extractTag("files",  from: inner)

        var filePaths: [String] = []
        if let raw = filesRaw {
            filePaths = raw.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return ChatPlanStep(commitMessage: commit, filePaths: filePaths, summary: summary)
    }

    /// Extracts the content of the first matching `<tag>content</tag>`.
    private func extractTag(_ tag: String, from text: String) -> String? {
        let pattern = "<\(tag)>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fallback text path

    private func tryExtractFallbackPlan() -> ChatPlan? {
        let nsBuffer = buffer as NSString
        let fullRange = NSRange(location: 0, length: nsBuffer.length)

        // Check there is a "plan:" header line
        guard Self.fallbackRegex.firstMatch(in: buffer, range: fullRange) != nil else {
            return nil
        }

        // Collect all numbered items
        let itemMatches = Self.numberedItemRegex.matches(in: buffer, range: fullRange)
        guard !itemMatches.isEmpty else { return nil }

        let steps: [ChatPlanStep] = itemMatches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            let text = nsBuffer.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return ChatPlanStep(commitMessage: nil, filePaths: [], summary: text)
        }

        guard !steps.isEmpty else { return nil }
        return ChatPlan(rawXML: buffer, steps: steps)
    }
}
