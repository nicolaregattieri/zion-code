import Foundation

extension RepositoryViewModel {
    func loadBridgeState() {
        guard let repositoryURL else {
            bridgeState = .empty
            bridgeAnalysis = nil
            return
        }

        isBridgeLoading = true
        defer { isBridgeLoading = false }

        bridgeState = bridgeService.loadState(repositoryURL: repositoryURL)
        if !(bridgeState.detection(for: bridgeSourceTarget)?.isDetected ?? false),
           let detected = bridgeState.detections.first(where: \.isDetected)?.target {
            bridgeSourceTarget = detected
        }
        if bridgeDestinationTarget == bridgeSourceTarget,
           let detected = BridgeTarget.allCases.first(where: { $0 != bridgeSourceTarget }) {
            bridgeDestinationTarget = detected
        }
    }

    func analyzeBridgeMigration() {
        guard let repositoryURL else { return }

        isBridgeLoading = true
        defer { isBridgeLoading = false }

        do {
            bridgeAnalysis = try bridgeService.analyze(
                from: bridgeSourceTarget,
                to: bridgeDestinationTarget,
                repositoryURL: repositoryURL
            )
            selectedBridgeRowID = bridgeAnalysis?.rows.first?.id
            statusMessage = L10n("bridge.status.analyzed", bridgeSourceTarget.label, bridgeDestinationTarget.label)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyBridgeMigration() {
        guard let repositoryURL, let bridgeAnalysis else { return }

        isBridgeApplying = true
        defer { isBridgeApplying = false }

        do {
            self.bridgeAnalysis = try bridgeService.apply(bridgeAnalysis, repositoryURL: repositoryURL)
            bridgeState = bridgeService.loadState(repositoryURL: repositoryURL)
            selectedBridgeRowID = self.bridgeAnalysis?.rows.first?.id
            statusMessage = L10n("bridge.status.synced", bridgeDestinationTarget.label)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearBridgeAnalysis() {
        bridgeAnalysis = nil
        selectedBridgeRowID = nil
    }

    var selectedBridgeRow: BridgeMappingRow? {
        guard let selectedBridgeRowID else { return bridgeAnalysis?.rows.first }
        return bridgeAnalysis?.rows.first(where: { $0.id == selectedBridgeRowID }) ?? bridgeAnalysis?.rows.first
    }
}
