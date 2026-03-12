import SwiftUI

struct BridgeScreen: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                sessionCard
                detectionCard

                if let analysis = model.bridgeAnalysis {
                    summaryCard(analysis)
                    mappingsCard(analysis)

                    if let row = model.selectedBridgeRow {
                        detailCard(row)
                    }
                }

                if !allWarnings.isEmpty {
                    warningsCard
                }
            }
            .padding(16)
        }
        .background(DesignSystem.Colors.background)
        .onAppear {
            model.loadBridgeState()
        }
    }

    private var headerCard: some View {
        GlassCard(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.ai)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.containerCornerRadius, style: .continuous)
                            .fill(DesignSystem.Colors.ai.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("bridge.title"))
                        .font(DesignSystem.Typography.sheetTitle)
                    Text(L10n("bridge.subtitle"))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(L10n("bridge.action.close")) {
                    model.isBridgeVisible = false
                }
                .buttonStyle(.bordered)

                Button(L10n("bridge.action.reload")) {
                    model.loadBridgeState()
                    model.clearBridgeAnalysis()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var sessionCard: some View {
        GlassCard(spacing: 12) {
            CardHeader(L10n("bridge.session.title"), icon: "slider.horizontal.3")

            HStack(alignment: .bottom, spacing: 12) {
                toolPicker(title: L10n("bridge.session.from"), selection: $model.bridgeSourceTarget)
                toolPicker(title: L10n("bridge.session.to"), selection: $model.bridgeDestinationTarget)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n("bridge.session.policy"))
                        .font(DesignSystem.Typography.monoMeta)
                        .foregroundStyle(.secondary)
                    Text(L10n("bridge.session.policyValue", model.bridgeDestinationTarget.label))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(L10n("bridge.action.analyze")) {
                    model.analyzeBridgeMigration()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.actionPrimary)
                .disabled(model.bridgeSourceTarget == model.bridgeDestinationTarget || model.isBridgeLoading)
            }

            if let analysis = model.bridgeAnalysis {
                HStack(spacing: 8) {
                    Text(L10n("bridge.session.route", analysis.sourceTarget.label, analysis.destinationTarget.label))
                        .font(DesignSystem.Typography.bodySmallBold)
                    Spacer(minLength: 0)
                    Button(L10n("bridge.action.sync")) {
                        model.applyBridgeMigration()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.actionPrimary)
                    .disabled(model.isBridgeApplying || !model.hasSelectedBridgeRows)
                }
            }
        }
    }

    private var detectionCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.detect.title"), icon: "eye")

            if model.bridgeState.detections.isEmpty {
                Text(L10n("bridge.detect.empty"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.bridgeState.detections) { detection in
                    HStack(alignment: .center, spacing: 10) {
                        statusDot(active: detection.isDetected)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detection.target.label)
                                .font(DesignSystem.Typography.sectionTitle)
                            Text(detection.detail)
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(detection.isDetected ? L10n("bridge.detect.detected") : L10n("bridge.detect.missing"))
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(detection.isDetected ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                    }

                    if detection.id != model.bridgeState.detections.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func summaryCard(_ analysis: BridgeMigrationAnalysis) -> some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.summary.title"), icon: "chart.bar.xaxis")

            HStack(spacing: 8) {
                summaryPill(title: L10n("bridge.mapping.knownMirror"), value: "\(analysis.summary.knownMirrors)", tint: DesignSystem.Colors.info)
                summaryPill(title: L10n("bridge.summary.updates"), value: "\(analysis.summary.updates)", tint: DesignSystem.Colors.warning)
                summaryPill(title: L10n("bridge.mapping.newImport"), value: "\(analysis.summary.newImports)", tint: DesignSystem.Colors.success)
                summaryPill(title: L10n("bridge.summary.review"), value: "\(analysis.summary.needsReview)", tint: DesignSystem.Colors.brandPrimary)
                summaryPill(title: L10n("bridge.summary.unsupported"), value: "\(analysis.summary.unsupported)", tint: DesignSystem.Colors.error)
            }
        }
    }

    private func mappingsCard(_ analysis: BridgeMigrationAnalysis) -> some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.mapping.title"), icon: "point.3.connected.trianglepath.dotted")

            if analysis.rows.isEmpty {
                Text(L10n("bridge.mapping.empty"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Text(selectionSummary(for: analysis))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if !analysis.syncableRows.isEmpty {
                        Button(L10n("bridge.action.selectAllSyncable")) {
                            model.selectAllBridgeSyncableRows()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(L10n("bridge.action.clearSyncSelection")) {
                            model.clearBridgeRowSelection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                ForEach(analysis.rows) { row in
                    mappingRow(row)
                }
            }
        }
    }

    private func mappingRow(_ row: BridgeMappingRow) -> some View {
        let isSelected = model.selectedBridgeRowID == row.id
        let isSyncSelected = model.isBridgeRowSelected(row)

        return HStack(alignment: .top, spacing: 10) {
            if row.isSyncable {
                Button {
                    model.toggleBridgeRowSelection(row)
                } label: {
                    Image(systemName: isSyncSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSyncSelected ? DesignSystem.Colors.actionPrimary : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isSyncSelected ? L10n("bridge.selection.remove") : L10n("bridge.selection.add"))
            } else {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 24, height: 24)
            }

            Button {
                model.selectedBridgeRowID = row.id
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.sourceArtifact.relativePath)
                                .font(DesignSystem.Typography.bodySmallSemibold)
                                .multilineTextAlignment(.leading)
                            Text(row.destinationRelativePath ?? L10n("bridge.mapping.noDestination"))
                                .font(DesignSystem.Typography.monoMeta)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 6) {
                            badge(row.mappingKind.label, tint: mappingTint(row.mappingKind))
                            badge(row.action.label, tint: actionTint(row.action))
                        }
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text(row.reason)
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text(row.confidence.label)
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(confidenceTint(row.confidence))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                        .fill(isSelected ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassSubtle)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func selectionSummary(for analysis: BridgeMigrationAnalysis) -> String {
        if analysis.syncableRows.isEmpty {
            return L10n("bridge.selection.empty")
        }

        return L10n(
            "bridge.selection.summary",
            model.bridgeSelectedSyncableCount,
            analysis.syncableRows.count
        )
    }

    private func detailCard(_ row: BridgeMappingRow) -> some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.detail.title"), icon: "doc.text.magnifyingglass")

            HStack(spacing: 12) {
                previewColumn(
                    title: L10n("bridge.detail.source", row.sourceArtifact.sourceTarget.label),
                    path: row.sourceArtifact.relativePath,
                    body: row.sourcePreview
                )
                previewColumn(
                    title: L10n("bridge.detail.destination", row.destinationTarget.label),
                    path: row.destinationRelativePath ?? L10n("bridge.mapping.noDestination"),
                    body: row.destinationPreview
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("bridge.detail.reason"))
                    .font(DesignSystem.Typography.monoMeta)
                    .foregroundStyle(.secondary)
                Text(row.reason)
                    .font(DesignSystem.Typography.bodySmall)
                Text(L10n("bridge.detail.readOnly"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var warningsCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.warnings.title"), icon: "exclamationmark.triangle.fill")

            ForEach(Array(allWarnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var allWarnings: [String] {
        var warnings = model.bridgeState.warnings
        warnings.append(contentsOf: model.bridgeAnalysis?.warnings ?? [])
        return Array(NSOrderedSet(array: warnings)) as? [String] ?? warnings
    }

    private func toolPicker(title: String, selection: Binding<BridgeTarget>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignSystem.Typography.monoMeta)
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(BridgeTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
        }
    }

    private func previewColumn(title: String, path: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignSystem.Typography.sectionTitle)
            Text(path)
                .font(DesignSystem.Typography.monoMeta)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(body.isEmpty ? L10n("bridge.detail.empty") : body)
                    .font(DesignSystem.Typography.bodySmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160, maxHeight: 220)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.glassHover)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignSystem.Typography.monoMeta)
                .foregroundStyle(.secondary)
            Text(value)
                .font(DesignSystem.Typography.bodySmallBold)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous))
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(DesignSystem.Typography.monoMeta)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func statusDot(active: Bool) -> some View {
        Circle()
            .fill(active ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
            .frame(width: 10, height: 10)
    }

    private func mappingTint(_ kind: BridgeMappingKind) -> Color {
        switch kind {
        case .knownMirror: return DesignSystem.Colors.info
        case .inferredMirror: return DesignSystem.Colors.warning
        case .newImport: return DesignSystem.Colors.success
        case .manualReview: return DesignSystem.Colors.brandPrimary
        case .unsupported: return DesignSystem.Colors.error
        }
    }

    private func actionTint(_ action: BridgeSyncActionKind) -> Color {
        switch action {
        case .create: return DesignSystem.Colors.success
        case .update: return DesignSystem.Colors.warning
        case .noop: return DesignSystem.Colors.info
        case .manualReview: return DesignSystem.Colors.brandPrimary
        case .unsupported: return DesignSystem.Colors.error
        }
    }

    private func confidenceTint(_ confidence: BridgeConfidence) -> Color {
        switch confidence {
        case .high: return DesignSystem.Colors.success
        case .medium: return DesignSystem.Colors.warning
        case .low: return DesignSystem.Colors.error
        }
    }
}
