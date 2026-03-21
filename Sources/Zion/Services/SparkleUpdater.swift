import Foundation
import Sparkle
import Combine

@Observable
@MainActor
final class SparkleUpdater: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var updater: SPUUpdater!
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    var canCheckForUpdates = false
    var updateAvailable = false
    var latestVersion: String?

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheck: Date? {
        updater.lastUpdateCheckDate
    }

    override init() {
        super.init()

        let userDriver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)

        do {
            try updater.start()
        } catch {
            print("[SparkleUpdater] Failed to start: \(error)")
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.updateAvailable = true
            self.latestVersion = version
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.updateAvailable = false
            self.latestVersion = nil
        }
    }
}
