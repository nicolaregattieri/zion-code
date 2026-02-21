import Foundation
import Sparkle
import Combine

@Observable
@MainActor
final class SparkleUpdater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var cancellable: AnyCancellable?

    var canCheckForUpdates = false

    var lastUpdateCheck: Date? {
        controller.updater.lastUpdateCheckDate
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Bridge Sparkle's KVO-based canCheckForUpdates to our @Observable property
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
