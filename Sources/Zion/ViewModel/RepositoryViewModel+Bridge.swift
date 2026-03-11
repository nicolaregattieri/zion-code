import Foundation

extension RepositoryViewModel {
    func loadBridgeState() {
        guard let repositoryURL else {
            bridgeState = .empty
            bridgePreview = nil
            return
        }

        isBridgeLoading = true
        defer { isBridgeLoading = false }
        bridgeState = bridgeService.loadState(repositoryURL: repositoryURL)
    }

    func initializeBridgePackage() {
        guard let repositoryURL else { return }

        isBridgeLoading = true
        defer { isBridgeLoading = false }

        do {
            bridgeState = try bridgeService.initializePackage(repositoryURL: repositoryURL)
            bridgePreview = nil
            statusMessage = L10n("bridge.status.packageReady")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importBridge(from target: BridgeTarget) {
        guard let repositoryURL else { return }

        isBridgeLoading = true
        defer { isBridgeLoading = false }

        do {
            bridgeState = try bridgeService.importConfiguration(from: target, repositoryURL: repositoryURL)
            bridgePreview = nil
            statusMessage = L10n("bridge.status.imported", target.label)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func previewBridgeSync(to target: BridgeTarget) {
        guard let repositoryURL else { return }

        isBridgeLoading = true
        defer { isBridgeLoading = false }

        do {
            bridgePreview = try bridgeService.previewSync(to: target, repositoryURL: repositoryURL)
            statusMessage = L10n("bridge.status.previewed", target.label)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyBridgePreview() {
        guard let repositoryURL, let bridgePreview else { return }

        isBridgeApplying = true
        defer { isBridgeApplying = false }

        do {
            bridgeState = try bridgeService.applySync(bridgePreview, repositoryURL: repositoryURL)
            self.bridgePreview = try bridgeService.previewSync(to: bridgePreview.target, repositoryURL: repositoryURL)
            statusMessage = L10n("bridge.status.synced", bridgePreview.target.label)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func bridgeCompatibility(for item: BridgeItem, target: BridgeTarget) -> BridgeCompatibility {
        bridgeService.compatibility(for: item, target: target)
    }
}
