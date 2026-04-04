import Foundation

extension RepositoryViewModel {

    func enterZenMode() {
        isZenModePaused = true
        zenResumeTask?.cancel()
        zenResumeTask = nil
    }

    func exitZenMode() {
        isZenModePaused = false
        zenResumeTask?.cancel()
        zenResumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.zenModeResumeDebounce)
            guard let self, !Task.isCancelled, !self.isZenModePaused else { return }
            self.processPendingFileWatcherEventIfNeeded()
            self.refreshRepository(setBusy: false, origin: .fileWatcher)
        }
    }
}
