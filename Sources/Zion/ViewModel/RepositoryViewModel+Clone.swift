import Foundation
import SwiftUI

extension RepositoryViewModel {

    // MARK: - ntfy Helpers

    func testNtfyNotification() async {
        let success = await ntfyClient.sendTest(serverURL: ntfyServerURL, topic: ntfyTopic)
        if !success {
            lastError = L10n("ntfy.test.failed")
        }
    }

    func notifyPRCreated(title: String, url: String) async {
        let repoName = repositoryURL?.lastPathComponent ?? ""
        await ntfyClient.sendIfEnabled(
            event: .prCreated,
            title: L10n("ntfy.event.prCreated"),
            body: "\(title)\n\(url)",
            repoName: repoName
        )
    }

    // MARK: - Clone

    func cloneRepository(remoteURL: String, destination: URL) {
        guard !isCloning else { return }
        isCloning = true
        cloneProgress = ""
        cloneError = nil

        cloneTask = Task.detached { [worker] in
            do {
                let process = try worker.cloneRepository(
                    remoteURL: remoteURL,
                    destination: destination
                ) { line in
                    Task { @MainActor [weak self] in
                        self?.cloneProgress = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                await MainActor.run { [weak self] in
                    self?.cloneProcess = process
                }

                process.waitUntilExit()

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.cloneProcess = nil
                    if process.terminationStatus == 0 {
                        self.isCloning = false
                        self.isCloneSheetVisible = false
                        self.cloneProgress = ""
                        self.openRepository(destination)
                        Task {
                            await self.ntfyClient.sendIfEnabled(
                                event: .cloneComplete,
                                title: L10n("ntfy.event.cloneComplete"),
                                body: destination.lastPathComponent,
                                repoName: destination.lastPathComponent
                            )
                        }
                    } else {
                        self.isCloning = false
                        self.cloneError = self.cloneProgress.isEmpty
                            ? "Clone failed (exit code \(process.terminationStatus))"
                            : self.cloneProgress
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isCloning = false
                    self?.cloneError = error.localizedDescription
                }
            }
        }
    }

    func cancelClone() {
        cloneProcess?.terminate()
        cloneProcess = nil
        cloneTask?.cancel()
        cloneTask = nil
        isCloning = false
        cloneProgress = ""
        cloneError = nil
    }

}
