import Foundation

extension RepositoryViewModel {
    func loadBridgeState() {
        guard let repositoryURL else {
            bridgeState = .empty
            clearBridgeAnalysis()
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
            applyBridgeSelectionDefaults()
            statusMessage = L10n("bridge.status.analyzed", bridgeSourceTarget.label, bridgeDestinationTarget.label)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyBridgeMigration() {
        guard let repositoryURL, let bridgeAnalysis else { return }
        guard !selectedBridgeRowIDs.isEmpty else { return }

        isBridgeApplying = true
        defer { isBridgeApplying = false }

        do {
            self.bridgeAnalysis = try bridgeService.apply(
                bridgeAnalysis,
                repositoryURL: repositoryURL,
                selectedRowIDs: selectedBridgeRowIDs
            )
            bridgeState = bridgeService.loadState(repositoryURL: repositoryURL)
            applyBridgeSelectionDefaults()
            statusMessage = L10n("bridge.status.synced", bridgeDestinationTarget.label)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearBridgeAnalysis() {
        bridgeAnalysis = nil
        selectedBridgeRowID = nil
        selectedBridgeRowIDs = []
    }

    var selectedBridgeRow: BridgeMappingRow? {
        guard let selectedBridgeRowID else { return bridgeAnalysis?.rows.first }
        return bridgeAnalysis?.rows.first(where: { $0.id == selectedBridgeRowID }) ?? bridgeAnalysis?.rows.first
    }

    var bridgeSelectedSyncableCount: Int {
        selectedBridgeRowIDs.count
    }

    var bridgeSyncableRowCount: Int {
        bridgeAnalysis?.syncableRows.count ?? 0
    }

    var hasSelectedBridgeRows: Bool {
        !selectedBridgeRowIDs.isEmpty
    }

    func toggleBridgeRowSelection(_ row: BridgeMappingRow) {
        guard row.isSyncable else { return }
        if selectedBridgeRowIDs.contains(row.id) {
            selectedBridgeRowIDs.remove(row.id)
        } else {
            selectedBridgeRowIDs.insert(row.id)
        }
    }

    func selectAllBridgeSyncableRows() {
        selectedBridgeRowIDs = Set(bridgeAnalysis?.syncableRows.map(\.id) ?? [])
    }

    func clearBridgeRowSelection() {
        selectedBridgeRowIDs.removeAll()
    }

    func isBridgeRowSelected(_ row: BridgeMappingRow) -> Bool {
        selectedBridgeRowIDs.contains(row.id)
    }

    private func applyBridgeSelectionDefaults() {
        selectedBridgeRowID = bridgeAnalysis?.rows.first?.id
        selectAllBridgeSyncableRows()
    }
}
