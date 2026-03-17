import Foundation

extension RepositoryViewModel {

    // MARK: - Notification Helpers

    static func enrichedReviewRequestPR(_ pr: HostedPRInfo, catalog: [HostedPRInfo]) -> HostedPRInfo {
        guard let fullPR = catalog.first(where: { $0.id == pr.id || $0.number == pr.number }) else {
            return pr
        }

        return HostedPRInfo(
            id: pr.id,
            number: pr.number,
            title: pr.title.isEmpty ? fullPR.title : pr.title,
            state: fullPR.state,
            headBranch: pr.headBranch.isEmpty ? fullPR.headBranch : pr.headBranch,
            baseBranch: pr.baseBranch.isEmpty ? fullPR.baseBranch : pr.baseBranch,
            url: pr.url.isEmpty ? fullPR.url : pr.url,
            isDraft: fullPR.isDraft,
            author: pr.author.isEmpty ? fullPR.author : pr.author,
            headSHA: pr.headSHA.isEmpty ? fullPR.headSHA : pr.headSHA
        )
    }

    static func reviewRequestNotificationTransition(
        existingIDs: Set<Int>,
        activePRs: [HostedPRInfo]
    ) -> (newlyRequested: [HostedPRInfo], nextIDs: Set<Int>) {
        let activeIDs = Set(activePRs.map(\.id))
        let newlyRequested = activePRs.filter { !existingIDs.contains($0.id) }
        return (newlyRequested, activeIDs)
    }

    static func openPRNotificationTransition(
        existingIDs: Set<Int>?,
        activePRs: [HostedPRInfo]
    ) -> (newlyCreated: [HostedPRInfo], nextIDs: Set<Int>) {
        let activeIDs = Set(activePRs.map(\.id))
        guard let existingIDs else {
            return ([], activeIDs)
        }

        let newlyCreated = activePRs.filter { !existingIDs.contains($0.id) }
        return (newlyCreated, activeIDs)
    }

    static func reviewRequestFileHints(
        from files: [(filename: String, status: String, additions: Int, deletions: Int, patch: String)]
    ) -> [String] {
        let unique = NSOrderedSet(array: files.map(\.filename).filter { !$0.isEmpty })
        return unique.array as? [String] ?? []
    }

    static func reviewRequestExtraNotes(
        pr: HostedPRInfo,
        files: [(filename: String, status: String, additions: Int, deletions: Int, patch: String)]
    ) -> [String] {
        var notes = [
            "source branch: \(pr.headBranch)",
            "target branch: \(pr.baseBranch)",
            "pr title: \(pr.title)",
            "author: \(pr.author)"
        ]

        if let summary = reviewRequestTouchedFilesSummary(from: files) {
            notes.append("changed files: \(summary)")
        }

        return notes
    }

    static func reviewRequestTouchedFilesSummary(
        from files: [(filename: String, status: String, additions: Int, deletions: Int, patch: String)]
    ) -> String? {
        let names = reviewRequestFileHints(from: files).map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
        guard !names.isEmpty else { return nil }
        return names.prefix(3).joined(separator: ", ")
    }

    static func buildReviewRequestNotificationBody(
        pr: HostedPRInfo,
        repoContext: String,
        fileCount: Int = 0,
        additions: Int = 0,
        deletions: Int = 0,
        autoReviewScore: Int? = nil,
        topFinding: String? = nil
    ) -> String {
        let highlights = notificationHighlights(from: repoContext)
        var lines = [String(format: L10n("pr.notification.request.header"), pr.author, pr.title)]

        if !pr.headBranch.isEmpty, !pr.baseBranch.isEmpty {
            lines.append(String(format: L10n("pr.notification.request.flow"), pr.headBranch, pr.baseBranch))
        }

        // Lines changed and complexity estimate
        if additions > 0 || deletions > 0 {
            let complexity = reviewComplexityLabel(fileCount: fileCount, additions: additions, deletions: deletions)
            lines.append("+\(additions)/-\(deletions) (\(fileCount) files) - \(complexity)")
        }

        if let touches = highlights.touches {
            lines.append(String(format: L10n("pr.notification.request.touches"), touches))
        }
        if let strategy = highlights.strategy {
            lines.append(String(format: L10n("pr.notification.request.strategy"), strategy))
        }
        if let constraints = highlights.constraints {
            lines.append(String(format: L10n("pr.notification.request.constraints"), constraints))
        }

        // Auto-review results if available
        if let score = autoReviewScore {
            lines.append(L10n("pr.notification.request.riskScore", score))
        }
        if let finding = topFinding {
            lines.append(L10n("pr.notification.request.topFinding", finding))
        }

        return lines.joined(separator: "\n")
    }

    static func reviewComplexityLabel(fileCount: Int, additions: Int, deletions: Int) -> String {
        let totalChanges = additions + deletions
        if fileCount <= 3 && totalChanges < 100 {
            return L10n("pr.complexity.small")
        } else if fileCount <= 10 && totalChanges < 500 {
            return L10n("pr.complexity.medium")
        } else {
            return L10n("pr.complexity.large")
        }
    }

    static func buildReviewNotificationBody(
        pr: HostedPRInfo,
        findings: [ReviewFinding],
        repoContext: String
    ) -> String {
        let highlights = notificationHighlights(from: repoContext)
        let passSignal = reviewPassSignal(findings: findings)
        var lines = [String(format: L10n("pr.notification.review.header"), pr.title, "\(passSignal)")]

        if let strategy = highlights.strategy {
            lines.append(String(format: L10n("pr.notification.request.strategy"), strategy))
        }
        if let constraints = highlights.constraints {
            lines.append(String(format: L10n("pr.notification.request.constraints"), constraints))
        }

        let fixes = findings
            .filter { $0.severity == .critical || $0.severity == .warning }
            .prefix(3)
            .map { finding in
                let file = finding.file.split(separator: "/").last.map(String.init) ?? finding.file
                return "\(file): \(finding.message)"
            }

        if fixes.isEmpty {
            lines.append(L10n("pr.notification.review.clean"))
        } else {
            lines.append(String(format: L10n("pr.notification.review.fixes"), fixes.joined(separator: " | ")))
        }

        return lines.joined(separator: "\n")
    }

    static func reviewPassSignal(findings: [ReviewFinding]) -> Int {
        let critical = findings.filter { $0.severity == .critical }.count
        let warning = findings.filter { $0.severity == .warning }.count
        let suggestion = findings.filter { $0.severity == .suggestion }.count
        let penalty = critical * 30 + warning * 15 + suggestion * 5
        return max(5, 100 - penalty)
    }

    static func notificationHighlights(from repoContext: String) -> (touches: String?, strategy: String?, constraints: String?) {
        let lines = repoContext
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let touches = value(forPrefix: "changed files:", in: lines)
            ?? value(forPrefix: "focus files:", in: lines)
        let strategy = value(forPrefix: "modules:", in: lines)
            ?? value(forPrefix: "branch patterns:", in: lines)
        let constraints = value(forPrefix: "conventions:", in: lines)
            ?? value(forPrefix: "sensitive areas:", in: lines)

        return (
            touches: touches.map { trimmedNotificationValue($0) },
            strategy: strategy.map { trimmedNotificationValue($0) },
            constraints: constraints.map { trimmedNotificationValue($0) }
        )
    }

    private static func value(forPrefix prefix: String, in lines: [String]) -> String? {
        lines.first(where: { $0.hasPrefix(prefix) }).map { line in
            line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func trimmedNotificationValue(_ value: String) -> String {
        value
            .split(separator: ",")
            .prefix(3)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: ", ")
    }
}
