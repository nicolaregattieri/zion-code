import Foundation

extension RepositoryViewModel {

    // MARK: - Load PR Comments

    func loadPRComments(prNumber: Int) {
        guard let (provider, remote) = detectHostingProvider() else { return }

        Task {
            let comments = await provider.fetchPRComments(remote: remote, prNumber: prNumber)
            prComments = comments

            // Distribute comments to matching code review files
            for i in codeReviewFiles.indices {
                let path = codeReviewFiles[i].path
                codeReviewFiles[i].inlineComments = comments.filter { $0.path == path }
            }
        }
    }

    // MARK: - Post Comment

    func postPRComment(prNumber: Int, body: String, path: String, line: Int) {
        guard let (provider, remote) = detectHostingProvider() else { return }

        // Find the head SHA for the PR
        let headSHA = pullRequests.first(where: { $0.number == prNumber })?.headSHA ?? ""
        guard !headSHA.isEmpty else {
            lastError = "Missing head SHA for PR #\(prNumber)"
            return
        }

        Task {
            do {
                let newComment = try await provider.postPRComment(
                    remote: remote,
                    prNumber: prNumber,
                    body: body,
                    commitID: headSHA,
                    path: path,
                    line: line
                )

                prComments.append(newComment)

                // Append to matching code review file
                if let idx = codeReviewFiles.firstIndex(where: { $0.path == path }) {
                    codeReviewFiles[idx].inlineComments.append(newComment)
                }
            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - Submit Review

    func submitPRReview(body: String, event: PRReviewEvent) async throws {
        guard let (provider, remote) = detectHostingProvider() else {
            throw HostingError.invalidURL
        }

        // Find the current PR number from context (head branch match)
        guard let prNumber = pullRequests.first(where: { $0.headBranch == branchReviewSource })?.number else {
            throw HostingError.apiError("No PR found for branch \(branchReviewSource)")
        }

        try await provider.submitPRReview(
            remote: remote,
            prNumber: prNumber,
            body: body,
            event: event,
            comments: pendingReviewComments
        )

        pendingReviewComments.removeAll()
        isPRReviewSubmitSheetVisible = false
        statusMessage = L10n("pr.review.submitted")
    }

    // MARK: - Add Pending Draft Comment

    func addPendingReviewComment(path: String, line: Int, body: String) {
        pendingReviewComments.append(PRReviewDraftComment(path: path, line: line, body: body))
    }
}
