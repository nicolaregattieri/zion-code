import Foundation

// MARK: - Effective Editor Configuration (per-file > repo config > global)

extension RepositoryViewModel {

    var effectiveTabSize: Int { fileDetectedTabSize ?? repoEditorConfig?.tabSize ?? editorTabSize }
    var effectiveUseTabs: Bool { fileDetectedUseTabs ?? repoEditorConfig?.useTabs ?? editorUseTabs }
    var effectiveFontSize: Double { repoEditorConfig?.fontSize ?? editorFontSize }
    var effectiveRulerColumn: Int { repoEditorConfig?.rulerColumn ?? editorRulerColumn }
    var effectiveLineSpacing: Double { repoEditorConfig?.lineSpacing ?? editorLineSpacing }
    var effectiveShowRuler: Bool { repoEditorConfig?.showRuler ?? editorShowRuler }
    var effectiveShowIndentGuides: Bool { repoEditorConfig?.showIndentGuides ?? editorShowIndentGuides }
    var effectiveTheme: EditorTheme {
        if let name = repoEditorConfig?.theme, let t = EditorTheme(rawValue: name) { return t }
        return selectedTheme
    }
}

// MARK: - Terminal Computed Properties

extension RepositoryViewModel {

    var isTerminalFontAvailable: Bool {
        MonospaceFontResolver.isAvailable(name: terminalFontFamily)
    }
}

// MARK: - Worktree Computed Properties

extension RepositoryViewModel {

    var worktreeNameSlug: String {
        slugifiedWorktreeName(from: worktreeNameInput)
    }

    var derivedWorktreeBranch: String {
        guard !worktreeNameSlug.isEmpty else { return "" }
        return "\(worktreePrefix.rawValue)/\(worktreeNameSlug)"
    }

    var derivedWorktreePath: String {
        guard let repositoryURL, !worktreeNameSlug.isEmpty else { return "" }
        let parentDir = repositoryURL.deletingLastPathComponent()
        let repoName = repositoryURL.lastPathComponent
        let baseName = "\(repoName)-\(worktreePrefix.rawValue)-\(worktreeNameSlug)"
        return uniquePath(forBaseName: baseName, in: parentDir).path
    }

    var canSmartCreateWorktree: Bool {
        let manualPath = worktreePathInput.clean
        let manualBranch = worktreeBranchInput.clean
        if !manualPath.isEmpty, !manualBranch.isEmpty {
            return true
        }
        return !worktreeNameSlug.isEmpty
    }
}
