import SwiftUI

struct BridgeScreen: View {
    @Bindable var model: RepositoryViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                importCard
                inventoryCard
                targetsCard

                if let preview = model.bridgePreview {
                    previewCard(preview)
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
                Image(systemName: "arrow.trianglehead.branch")
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
                }
                .buttonStyle(.bordered)

                Button(model.bridgeState.exists ? L10n("bridge.action.rebuild") : L10n("bridge.action.create")) {
                    model.initializeBridgePackage()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.actionPrimary)
            }

            HStack(spacing: 8) {
                summaryPill(title: L10n("bridge.summary.items"), value: "\(model.bridgeState.itemCount)", tint: DesignSystem.Colors.info)
                summaryPill(title: L10n("bridge.summary.targets"), value: "\(model.bridgeState.manifest.enabledTargets.count)", tint: DesignSystem.Colors.success)
                summaryPill(
                    title: L10n("bridge.summary.source"),
                    value: model.bridgeState.manifest.lastImportedTarget?.label ?? L10n("bridge.summary.empty"),
                    tint: DesignSystem.Colors.ai
                )
            }
        }
    }

    private var importCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.import.title"), icon: "arrow.down.doc") {
                Text(L10n("bridge.import.hint"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(BridgeTarget.allCases) { target in
                    Button {
                        model.importBridge(from: target)
                    } label: {
                        Text(target.label)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var inventoryCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.inventory.title"), icon: "shippingbox.fill")

            if model.bridgeState.items.isEmpty {
                Text(L10n("bridge.inventory.empty"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.bridgeState.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(item.title)
                                .font(DesignSystem.Typography.sectionTitle)
                            Text(item.kind.label)
                                .font(DesignSystem.Typography.monoMeta)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignSystem.Colors.glassHover)
                                .clipShape(Capsule())
                            Spacer(minLength: 0)
                        }

                        Text(item.summary)
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(BridgeTarget.allCases) { target in
                                compatibilityPill(model.bridgeCompatibility(for: item, target: target), target: target)
                            }
                        }
                    }
                    .padding(.vertical, 6)

                    if item.id != model.bridgeState.items.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var targetsCard: some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.targets.title"), icon: "point.3.connected.trianglepath.dotted")

            ForEach(BridgeTarget.allCases) { target in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(target.label)
                            .font(DesignSystem.Typography.sectionTitle)
                        Text(L10n("bridge.targets.subtitle", target.label))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button(L10n("bridge.action.preview")) {
                        model.previewBridgeSync(to: target)
                    }
                    .buttonStyle(.bordered)

                    if model.bridgePreview?.target == target {
                        Button(L10n("bridge.action.sync")) {
                            model.applyBridgePreview()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.actionPrimary)
                        .disabled(model.isBridgeApplying)
                    }
                }
                .padding(.vertical, 4)

                if target != BridgeTarget.allCases.last {
                    Divider()
                }
            }
        }
    }

    private func previewCard(_ preview: BridgeSyncPreview) -> some View {
        GlassCard(spacing: 10) {
            CardHeader(L10n("bridge.preview.title", preview.target.label), icon: "doc.text.magnifyingglass")

            if preview.operations.isEmpty {
                Text(L10n("bridge.preview.empty"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preview.operations) { operation in
                    HStack(alignment: .top, spacing: 10) {
                        Text(operation.kind.label)
                            .font(DesignSystem.Typography.monoMeta)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(operationBackground(operation.kind))
                            .clipShape(Capsule())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(operation.relativePath)
                                .font(DesignSystem.Typography.bodySmallSemibold)
                            Text(operation.detail)
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Text(operation.compatibility.label)
                            .font(DesignSystem.Typography.monoMeta)
                            .foregroundStyle(compatibilityColor(operation.compatibility))
                    }

                    if operation.id != preview.operations.last?.id {
                        Divider()
                    }
                }
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
        warnings.append(contentsOf: model.bridgePreview?.warnings ?? [])
        return Array(NSOrderedSet(array: warnings)) as? [String] ?? warnings
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

    private func compatibilityPill(_ compatibility: BridgeCompatibility, target: BridgeTarget) -> some View {
        Text("\(target.label): \(compatibility.label)")
            .font(DesignSystem.Typography.monoMeta)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(compatibilityColor(compatibility).opacity(0.12))
            .foregroundStyle(compatibilityColor(compatibility))
            .clipShape(Capsule())
    }

    private func compatibilityColor(_ compatibility: BridgeCompatibility) -> Color {
        switch compatibility {
        case .native: return DesignSystem.Colors.success
        case .adapted: return DesignSystem.Colors.warning
        case .unsupported: return DesignSystem.Colors.destructive
        }
    }

    private func operationBackground(_ kind: BridgeSyncOperationKind) -> Color {
        switch kind {
        case .create: return DesignSystem.Colors.success.opacity(0.12)
        case .update: return DesignSystem.Colors.warning.opacity(0.12)
        case .remove: return DesignSystem.Colors.destructive.opacity(0.12)
        case .noop: return DesignSystem.Colors.glassHover
        }
    }
}
