import Foundation

extension RepositoryWorker {

    func buildBranchTree(
        in repositoryURL: URL,
        using infos: [BranchInfo],
        inferOrigins: Bool
    ) throws -> [BranchTreeNode] {
        let locals = infos
            .filter { !$0.isRemote }
            .sorted { $0.committerDate > $1.committerDate }
        let remotes = infos
            .filter(\.isRemote)
            .sorted { $0.name < $1.name }

        let localNames = Set(locals.map(\.name))
        let preferredRoots = ["main", "master", "develop", "dev", "trunk", "production"]
            .filter(localNames.contains)
        var parentByChild: [String: String] = [:]
        var forkByChild: [String: String] = [:]

        let shouldComputeForkMergeBase = inferOrigins && locals.count <= 48

        for branch in locals {
            if preferredRoots.contains(branch.name) {
                continue
            }

            var parentRef: String?
            if !branch.upstream.isEmpty {
                parentRef = branch.upstream
            } else if inferOrigins {
                parentRef = guessBestParent(for: branch.name, preferredRoots: preferredRoots)
            }

            guard let parentRef, parentRef != branch.name else { continue }
            parentByChild[branch.name] = parentRef

            if shouldComputeForkMergeBase,
               localNames.contains(parentRef),
               let mergeBase = mergeBase(branch.name, parentRef, in: repositoryURL) {
                forkByChild[branch.name] = String(mergeBase.prefix(8))
            }
        }

        let childrenByParent = Dictionary(grouping: locals) { branch -> String? in
            guard let parent = parentByChild[branch.name], localNames.contains(parent) else {
                return nil
            }
            return parent
        }

        func subtitle(for branch: BranchInfo) -> String {
            var parts: [String] = []
            if let parent = parentByChild[branch.name] {
                parts.append("from: \(parent)")
            }
            if let fork = forkByChild[branch.name] {
                parts.append("fork: \(fork)")
            }
            if !branch.upstream.isEmpty {
                parts.append("upstream: \(branch.upstream)")
            } else {
                parts.append("HEAD \(branch.shortHead)")
            }
            return parts.joined(separator: " | ")
        }

        func makeLocalNode(_ branch: BranchInfo) -> BranchTreeNode {
            let children = (childrenByParent[branch.name] ?? [])
                .sorted { $0.committerDate > $1.committerDate }
                .map(makeLocalNode)

            return BranchTreeNode(
                id: "local:\(branch.name)",
                title: branch.name,
                subtitle: subtitle(for: branch),
                branchName: branch.name,
                children: children
            )
        }

        let localRootsInfos = locals
            .filter { branch in
                guard let parent = parentByChild[branch.name] else { return true }
                return !localNames.contains(parent)
            }
            .sorted { $0.committerDate > $1.committerDate }

        let localRoots: [BranchTreeNode]
        if localRootsInfos.count > 20 {
            localRoots = groupedLocalRootNodes(localRootsInfos, subtitleProvider: subtitle)
        } else {
            localRoots = localRootsInfos.map(makeLocalNode)
        }

        let localGroup = BranchTreeNode(
            id: "group:locals",
            title: "Local branches",
            subtitle: shouldComputeForkMergeBase ? "\(locals.count)" : "\(locals.count) · inferencia rapida",
            branchName: nil,
            children: localRoots
        )

        let remoteChildrenByRemote = Dictionary(grouping: remotes) { info -> String in
            info.name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? "remote"
        }

        let remoteGroups = remoteChildrenByRemote
            .sorted { $0.key < $1.key }
            .map { remoteName, remoteBranches in
                let children = remoteBranches
                    .sorted { $0.name < $1.name }
                    .map { branch -> BranchTreeNode in
                        let shortName = branch.name.hasPrefix("\(remoteName)/")
                            ? String(branch.name.dropFirst(remoteName.count + 1))
                            : branch.name
                        return BranchTreeNode(
                            id: "remote:\(branch.name)",
                            title: shortName,
                            subtitle: "HEAD \(branch.shortHead)",
                            branchName: branch.name,
                            children: []
                        )
                    }
                return BranchTreeNode(
                    id: "group:remote:\(remoteName)",
                    title: remoteName,
                    subtitle: "\(remoteBranches.count)",
                    branchName: nil,
                    children: children
                )
            }

        let remoteGroup = BranchTreeNode(
            id: "group:remotes",
            title: "Remote branches",
            subtitle: "\(remotes.count)",
            branchName: nil,
            children: remoteGroups
        )

        return [localGroup, remoteGroup]
    }

    func groupedLocalRootNodes(
        _ roots: [BranchInfo],
        subtitleProvider: (BranchInfo) -> String
    ) -> [BranchTreeNode] {
        let grouped = Dictionary(grouping: roots) { branch -> String in
            let parts = branch.name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                return String(parts[0])
            }
            return "misc"
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { namespace, branches in
                let children = branches
                    .sorted { $0.committerDate > $1.committerDate }
                    .map { branch in
                        let title: String
                        if namespace == "misc" {
                            title = branch.name
                        } else if branch.name.hasPrefix("\(namespace)/") {
                            title = String(branch.name.dropFirst(namespace.count + 1))
                        } else {
                            title = branch.name
                        }

                        return BranchTreeNode(
                            id: "local-grouped:\(branch.name)",
                            title: title,
                            subtitle: subtitleProvider(branch),
                            branchName: branch.name,
                            children: []
                        )
                    }

                return BranchTreeNode(
                    id: "local-namespace:\(namespace)",
                    title: namespace,
                    subtitle: "\(branches.count)",
                    branchName: nil,
                    children: children
                )
            }
    }

    func mergeBase(_ lhs: String, _ rhs: String, in repositoryURL: URL) -> String? {
        guard !lhs.clean.isEmpty, !rhs.clean.isEmpty else { return nil }
        do {
            let result = try git.runAllowingFailure(args: ["merge-base", lhs, rhs], in: repositoryURL)
            guard result.status == 0 else { return nil }
            let value = result.stdout.clean
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    func guessBestParent(for branch: String, preferredRoots: [String]) -> String? {
        guard !branch.clean.isEmpty else { return nil }

        if branch.hasPrefix("hotfix/") || branch.hasPrefix("release/") {
            return preferredRoots.first(where: { $0 == "main" || $0 == "master" }) ?? preferredRoots.first
        }
        if branch.hasPrefix("feature/") || branch.hasPrefix("bugfix/") || branch.hasPrefix("chore/") || branch.hasPrefix("test/") {
            return preferredRoots.first(where: { $0 == "develop" || $0 == "dev" })
                ?? preferredRoots.first(where: { $0 == "main" || $0 == "master" })
                ?? preferredRoots.first
        }

        return preferredRoots.first(where: { $0 == "main" || $0 == "master" })
            ?? preferredRoots.first
    }
}
