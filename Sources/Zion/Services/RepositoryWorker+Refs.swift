import Foundation

extension RepositoryWorker {

    nonisolated func currentBranchName(in repositoryURL: URL) throws -> String {
        let branch = try git.runAllowingFailure(args: ["branch", "--show-current"], in: repositoryURL).stdout.clean
        if !branch.isEmpty { return branch }

        // If empty, we are likely in detached HEAD. Try to find if we are at a tag or remote branch.
        let describe = try? git.runAllowingFailure(args: ["describe", "--tags", "--exact-match"], in: repositoryURL).stdout.clean
        if let tag = describe, !tag.isEmpty {
            return "detached (tag: \(tag))"
        }

        let hash = try? currentHeadHash(in: repositoryURL)
        return "detached (\(hash ?? "unknown"))"
    }

    nonisolated func currentHeadHash(in repositoryURL: URL) throws -> String {
        try git.run(args: ["rev-parse", "--short", "HEAD"], in: repositoryURL).stdout.clean
    }

    nonisolated func remoteList(in repositoryURL: URL) throws -> [RemoteInfo] {
        let output = try git.run(args: ["remote", "-v"], in: repositoryURL).stdout
        var remotesMap: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count >= 2 {
                let name = String(parts[0])
                let urlAndType = String(parts[1])
                let url = urlAndType.split(separator: " ").first.map(String.init) ?? ""
                remotesMap[name] = url
            }
        }
        return remotesMap.map { RemoteInfo(name: $0.key, url: $0.value) }.sorted { $0.name < $1.name }
    }

    nonisolated func branchInfoList(in repositoryURL: URL) throws -> [BranchInfo] {
        let output = try git.run(
            args: [
                "for-each-ref",
                "--sort=-committerdate",
                "--format=%(refname)\t%(refname:short)\t%(objectname)\t%(upstream:short)\t%(committerdate:iso-strict)",
                "refs/heads",
                "refs/remotes"
            ],
            in: repositoryURL
        ).stdout

        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawRecord in
                let fields = rawRecord.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 5 else { return nil }

                let fullRef = fields[0].clean
                let name = fields[1].clean
                let head = fields[2].clean
                let upstream = fields[3].clean
                let date = parseISODate(fields[4].clean)
                let isRemote = fullRef.hasPrefix("refs/remotes/")

                if isRemote, name.hasSuffix("/HEAD") {
                    return nil
                }

                return BranchInfo(
                    name: name,
                    fullRef: fullRef,
                    head: head,
                    upstream: upstream,
                    committerDate: date,
                    isRemote: isRemote
                )
            }
    }

    nonisolated func tagList(in repositoryURL: URL) throws -> [String] {
        let output = try git.run(args: ["tag", "--list", "--sort=-creatordate"], in: repositoryURL).stdout
        let tags = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return sortTagsDescending(tags)
    }

    nonisolated func stashList(in repositoryURL: URL) throws -> [String] {
        let output = try git.run(args: ["stash", "list"], in: repositoryURL).stdout
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
