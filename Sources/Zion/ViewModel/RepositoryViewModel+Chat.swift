import Foundation

extension RepositoryViewModel {

    // MARK: - ChatService lifecycle

    /// Lazily creates and returns the ChatService for the current repository.
    /// Backed by `_chatService`; reset on every repo switch via `resetChatService()`.
    var chatService: ChatService {
        if let existing = _chatService { return existing }
        let builder = ChatContextBuilder(worker: worker)
        let repoID = repositoryURL.map { ChatStorage.repoID(for: $0) } ?? ""
        let svc = ChatService(ai: aiClient, worker: worker, contextBuilder: builder, storage: chatStorage, repoID: repoID)
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
