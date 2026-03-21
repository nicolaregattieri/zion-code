import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - Tags

    func createTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        createTag(named: target, at: "HEAD", message: tagMessage, type: tagType)
    }

    func createTag(named name: String, at target: String, message: String = "", type: TagType = .lightweight) {
        let tagName = name.clean
        let tagTarget = target.clean
        guard !tagName.isEmpty, !tagTarget.isEmpty else { return }

        switch type {
        case .lightweight:
            runGitAction(label: "Criar tag", args: ["tag", tagName, tagTarget])
        case .annotated:
            let msg = message.isEmpty ? tagName : message
            runGitAction(label: "Criar tag anotada", args: ["tag", "-a", tagName, tagTarget, "-m", msg])
        case .signed:
            let msg = message.isEmpty ? tagName : message
            runGitAction(label: "Criar tag assinada", args: ["tag", "-s", tagName, tagTarget, "-m", msg])
        }
    }

    func deleteTag() {
        let target = tagInput.clean
        guard !target.isEmpty else { return }
        runGitAction(label: "Remover tag", args: ["tag", "-d", target])
    }

    func pushTag(named name: String, to remote: String) {
        let tagName = name.clean
        let remoteName = remote.clean
        guard !tagName.isEmpty, !remoteName.isEmpty else { return }
        runGitAction(label: "Push tag", args: ["push", remoteName, "refs/tags/\(tagName)"])
    }

    func deleteRemoteTag(named name: String, from remote: String) {
        let tagName = name.clean
        let remoteName = remote.clean
        guard !tagName.isEmpty, !remoteName.isEmpty else { return }
        runGitAction(label: "Remover tag remota", args: ["push", remoteName, ":refs/tags/\(tagName)"])
    }
}
