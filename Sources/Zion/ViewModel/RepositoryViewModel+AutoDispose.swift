import Foundation

extension RepositoryViewModel {

    // MARK: - Repository Dispose

    func markRepositoryDisposed(reason: String) {
        isGitRepository = false
        isRepositoryDisposed = true
        DiagnosticLogger.shared.log(.warn, reason, context: repositoryURL?.path, source: #function)
    }

    func shouldSkipBecauseDisposed() -> Bool {
        isRepositoryDisposed
    }

    func clearRepositoryDisposedFlag() {
        isRepositoryDisposed = false
    }
}
