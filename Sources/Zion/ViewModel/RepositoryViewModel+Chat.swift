import Foundation

extension RepositoryViewModel {

    // MARK: - ChatService lifecycle

    /// Lazily creates and returns the ChatService for the current repository.
    /// Backed by `_chatService`; reset on every repo switch via `resetChatService()`.
    var chatService: ChatService {
        if let existing = _chatService { return existing }
        let builder = ChatContextBuilder(worker: worker)
        let url = repositoryURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let harness = ZionHarness(worker: worker, repoURL: url)
        let svc = ChatService(ai: aiClient, worker: worker, contextBuilder: builder, harness: harness)
        _chatService = svc
        return svc
    }

    /// Stops any in-flight streaming and discards the current ChatService instance.
    /// Called by `cancelRepositoryBackgroundActivityForSwitch()` on every repo switch.
    func resetChatService() {
        _chatService?.stop()
        _chatService = nil
    }
}
