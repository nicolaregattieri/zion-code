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

        bridgeAnalysisTask?.cancel()
        isBridgeLoading = true

        bridgeAnalysisTask = Task {
            do {
                let result = try bridgeService.analyze(
                    from: bridgeSourceTarget,
                    to: bridgeDestinationTarget,
                    repositoryURL: repositoryURL
                )

                guard !Task.isCancelled else { return }
                bridgeAnalysis = result
                applyBridgeSelectionDefaults()
                statusMessage = L10n("bridge.status.analyzed", bridgeSourceTarget.label, bridgeDestinationTarget.label)
            } catch {
                guard !Task.isCancelled else { return }
                lastError = error.localizedDescription
            }

            isBridgeLoading = false
        }
    }

    func applyBridgeMigration() {
        guard let repositoryURL, let bridgeAnalysis else { return }
        guard !selectedBridgeRowIDs.isEmpty else { return }

        bridgeAnalysisTask?.cancel()
        isBridgeApplying = true

        let analysis = bridgeAnalysis
        let selectedIDs = selectedBridgeRowIDs

        bridgeAnalysisTask = Task {
            do {
                let applied = try bridgeService.apply(
                    analysis,
                    repositoryURL: repositoryURL,
                    selectedRowIDs: selectedIDs
                )
                let newState = bridgeService.loadState(repositoryURL: repositoryURL)

                guard !Task.isCancelled else { return }
                self.bridgeAnalysis = applied
                bridgeState = newState
                applyBridgeSelectionDefaults()
                statusMessage = L10n("bridge.status.synced", bridgeDestinationTarget.label)
            } catch {
                guard !Task.isCancelled else { return }
                lastError = error.localizedDescription
            }

            isBridgeApplying = false
        }
    }

    func cancelBridgeAnalysis() {
        bridgeAnalysisTask?.cancel()
        bridgeAnalysisTask = nil
        isBridgeLoading = false
        isBridgeApplying = false
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

    // MARK: - AI Content Transformation (Phase 1A)

    func transformBridgeContentWithAI() {
        guard isAIConfigured, var analysis = bridgeAnalysis else { return }
        let smartSyncEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.Bridge.smartSync)
        guard smartSyncEnabled else { return }

        bridgeAnalysisTask?.cancel()
        isBridgeLoading = true

        bridgeAnalysisTask = Task {
            for i in analysis.rows.indices {
                guard !Task.isCancelled else { break }
                guard analysis.rows[i].isSyncable, analysis.rows[i].renderedContent != nil else { continue }
                guard let sourceContent = analysis.rows[i].renderedContent else { continue }

                do {
                    let result = try await aiClient.transformBridgeContent(
                        sourceContent: sourceContent,
                        sourceToolName: analysis.sourceTarget.label,
                        destinationToolName: analysis.destinationTarget.label,
                        provider: aiProvider,
                        apiKey: aiAPIKey,
                        mode: aiMode
                    )
                    guard !Task.isCancelled else { break }
                    analysis.rows[i].transformedContent = result.content
                    analysis.rows[i].compatibilityScore = result.confidence
                } catch {
                    if let aiErr = error as? AIError, case .quotaExceeded = aiErr {
                        aiQuotaExceeded = true
                        break
                    }
                    logger.log(.warn, "Bridge AI transform failed for \(analysis.rows[i].sourceArtifact.relativePath): \(error.localizedDescription)", source: #function)
                }
            }

            guard !Task.isCancelled else { return }
            bridgeAnalysis = analysis
            statusMessage = L10n("bridge.status.aiTransformed")
            isBridgeLoading = false
        }
    }

    private func applyBridgeSelectionDefaults() {
        selectedBridgeRowID = bridgeAnalysis?.rows.first?.id
        selectAllBridgeSyncableRows()
    }
}
