import Foundation

// MARK: - AI Computed Properties

extension RepositoryViewModel {

    var aiAPIKey: String {
        get {
            let _ = _aiKeyRevision // Register dependency
            if _cachedAIKeyProvider == aiProvider, let cached = _cachedAIKey {
                return cached
            }
            let key = AIClient.loadAPIKey(for: aiProvider) ?? ""
            _cachedAIKey = key
            _cachedAIKeyProvider = aiProvider
            return key
        }
        set {
            if newValue.isEmpty {
                AIClient.deleteAPIKey(for: aiProvider)
            } else {
                AIClient.saveAPIKey(newValue, for: aiProvider)
            }
            _cachedAIKey = newValue
            _cachedAIKeyProvider = aiProvider
            _aiKeyRevision += 1 // Trigger observation
            aiQuotaExceeded = false // Reset on key change
        }
    }

    var isAIConfigured: Bool {
        aiProvider != .none && !aiAPIKey.isEmpty
    }
}

// MARK: - Branch Computed Properties

extension RepositoryViewModel {

    var localBranchOptions: [String] {
        branchInfos
            .filter { !$0.isRemote }
            .map(\.name)
            .sorted()
    }

    var remoteBranchOptions: [String] {
        branchInfos
            .filter(\.isRemote)
            .map(\.name)
            .sorted()
    }
}
