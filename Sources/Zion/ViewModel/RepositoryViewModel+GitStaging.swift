import Foundation
import SwiftUI

extension RepositoryViewModel {
    enum CommitScope {
        case stagedOnly
        case allChanges
    }

    // MARK: - Commit & Stage

    func commit(message: String, scope: CommitScope = .stagedOnly) {
        let msg = message.clean
        guard !msg.isEmpty else { return }

        actionTask?.cancel()
        isBusy = true

        let url = repositoryURL
        let shouldAmend = amendLastCommit

        actionTask = Task {
            do {
                guard let url else { return }

                if scope == .allChanges {
                    let _ = try await worker.runAction(args: ["add", "-A"], in: url)
                } else if !hasStagedChanges {
                    isBusy = false
                    statusMessage = L10n("commit.error.noStagedChanges")
                    return
                }

                var commitArgs = ["commit", "-m", msg]
                if shouldAmend {
                    commitArgs.append("--amend")
                }

                let _ = try await worker.runAction(args: commitArgs, in: url)

                if let newHeadCommitID = try? await worker.runAction(args: ["rev-parse", "HEAD"], in: url).clean,
                   !newHeadCommitID.isEmpty {
                    selectCommit(newHeadCommitID)
                }

                clearError()
                statusMessage = shouldAmend ? L10n("Commit corrigido com sucesso.") : L10n("Commit realizado com sucesso.")
                commitMessageInput = ""
                amendLastCommit = false
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func stageFile(_ path: String) {
        let targetURL = repositoryURL.map { $0.appendingPathComponent(path) } ?? URL(fileURLWithPath: path)
        let snapshot = snapshotPorcelainEntries()
        applyOptimisticStage(urls: [targetURL])
        runGitAction(
            label: "Stage",
            args: ["add", path],
            onFailure: { [weak self] in self?.restorePorcelainEntries(snapshot) },
            operation: .add
        )
    }

    func unstageFile(_ path: String) {
        let targetURL = repositoryURL.map { $0.appendingPathComponent(path) } ?? URL(fileURLWithPath: path)
        let snapshot = snapshotPorcelainEntries()
        applyOptimisticUnstage(urls: [targetURL])
        runGitAction(
            label: "Unstage",
            args: ["reset", "HEAD", "--", path],
            onFailure: { [weak self] in self?.restorePorcelainEntries(snapshot) },
            operation: .restore
        )
    }

    func stageAllFiles() {
        let allURLs = uncommittedChanges.compactMap(Self.parsePorcelainStatusLine)
            .filter { !$0.isStaged || $0.worktreeStatus != " " }
            .compactMap { entry -> URL? in
                guard let repoURL = repositoryURL else { return nil }
                return repoURL.appendingPathComponent(entry.path)
            }
        let snapshot = snapshotPorcelainEntries()
        applyOptimisticStage(urls: allURLs)
        runGitAction(
            label: "Stage All",
            args: ["add", "-A"],
            onFailure: { [weak self] in self?.restorePorcelainEntries(snapshot) },
            operation: .add
        )
    }

    func unstageAllFiles() {
        let allURLs = uncommittedChanges.compactMap(Self.parsePorcelainStatusLine)
            .filter(\.isStaged)
            .compactMap { entry -> URL? in
                guard let repoURL = repositoryURL else { return nil }
                return repoURL.appendingPathComponent(entry.path)
            }
        let snapshot = snapshotPorcelainEntries()
        applyOptimisticUnstage(urls: allURLs)
        runGitAction(
            label: "Unstage All",
            args: ["reset", "HEAD", "--", "."],
            onFailure: { [weak self] in self?.restorePorcelainEntries(snapshot) },
            operation: .restore
        )
    }

    func addToGitIgnore(path: String) {
        guard let url = repositoryURL else { return }
        let gitIgnoreURL = url.appendingPathComponent(".gitignore")

        actionTask?.cancel()
        isBusy = true

        actionTask = Task {
            do {
                var content = ""
                if FileManager.default.fileExists(atPath: gitIgnoreURL.path) {
                    content = try String(contentsOf: gitIgnoreURL, encoding: .utf8)
                }

                if !content.contains(path) {
                    if !content.isEmpty && !content.hasSuffix("\n") {
                        content += "\n"
                    }
                    content += "\(path)\n"
                    try content.write(to: gitIgnoreURL, atomically: true, encoding: .utf8)
                }

                // After adding to gitignore, unstage if tracked. `-r` covers
                // directories; `--ignore-unmatch` keeps untracked paths from
                // erroring out (common case: ignoring a brand new folder).
                let _ = try await worker.runAction(args: ["rm", "-r", "--cached", "--ignore-unmatch", path], in: url)

                clearError()
                statusMessage = L10n("Adicionado ao .gitignore: %@", path)
                refreshRepository(setBusy: true)
            } catch {
                isBusy = false
                handleError(error)
            }
        }
    }

    func renameRemote(oldName: String, newName: String) {
        runGitAction(label: "Rename Remote", args: ["remote", "rename", oldName, newName])
    }

    func abortMerge() {
        confirmAbort(operation: "Merge") {
            self.runGitAction(label: "Abort Merge", args: ["merge", "--abort"])
        }
    }

    func abortRebase() {
        confirmAbort(operation: "Rebase") {
            self.runGitAction(label: "Abort Rebase", args: ["rebase", "--abort"])
        }
    }

    func abortCherryPick() {
        confirmAbort(operation: "Cherry-pick") {
            self.runGitAction(label: "Abort Cherry-pick", args: ["cherry-pick", "--abort"])
        }
    }

    private func confirmAbort(operation: String, onConfirm: @escaping () -> Void) {
        guard !conflictedFiles.isEmpty else {
            onConfirm()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.warning
        alert.messageText = L10n("ops.abort.confirm.title", operation)
        alert.informativeText = L10n("ops.abort.confirm.message", conflictedFiles.count)
        alert.addButton(withTitle: L10n("ops.abort.confirm.proceed"))
        alert.addButton(withTitle: L10n("Cancelar"))

        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }

    func localBranchExists(named name: String) -> Bool {
        branchInfos.contains(where: { !$0.isRemote && $0.name == name })
    }

    func isRemoteRefName(_ value: String) -> Bool {
        branchInfos.contains(where: { $0.isRemote && $0.name == value })
    }
}
