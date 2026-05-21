import SwiftUI

struct LocalLLMSettingsSection: View {
    @Binding var config: LocalLLMConfig

    @State private var discoveredModels: [String] = []
    @State private var isHealthy: Bool = false
    @State private var lastChecked: Date? = nil
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var isDiscovering: Bool = false
    @State private var isTesting: Bool = false

    private var healthColor: Color {
        isHealthy ? DesignSystem.Colors.success : DesignSystem.Colors.destructive
    }

    private var lastCheckedText: String {
        guard let date = lastChecked else { return "" }
        return L10n("settings.ai.local.health.lastCheckedAt", DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium))
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                statusRow
                serverURLField
                apiKeyField
                modelField
                recommendedHint
                timeoutStepper
                warningsBlock
                actionButtons
            }
            .padding(.vertical, 4)
        } header: {
            Text(L10n("settings.ai.provider.local"))
        }
    }

    // MARK: - Components

    private var statusRow: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)

            Text(isHealthy
                ? L10n("settings.ai.local.health.healthy")
                : L10n("settings.ai.local.health.unhealthy"))
                .font(DesignSystem.Typography.labelMedium)
                .foregroundStyle(healthColor)

            if !lastCheckedText.isEmpty {
                Text(lastCheckedText)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var serverURLField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n("settings.ai.local.serverURL"))
                .font(DesignSystem.Typography.labelBold)

            TextField("http://localhost:11434/v1", text: $config.serverURL)
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(DesignSystem.Typography.body)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                        .fill(DesignSystem.Colors.glassHover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                        .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                )

            Text(L10n("settings.ai.local.serverURL.hint"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n("settings.ai.local.apiKey.optional"))
                .font(DesignSystem.Typography.labelBold)

            SecureField("", text: $config.apiKey, prompt: Text(verbatim: "sk-..."))
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(DesignSystem.Typography.body)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                        .fill(DesignSystem.Colors.glassHover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                        .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                )
        }
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n("settings.ai.local.model"))
                .font(DesignSystem.Typography.labelBold)

            HStack(spacing: 8) {
                TextField("qwen3-coder:30b", text: $config.modelName)
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .font(DesignSystem.Typography.body)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                            .fill(DesignSystem.Colors.glassHover)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius, style: .continuous)
                            .stroke(DesignSystem.Colors.glassStroke, lineWidth: 1)
                    )

                if !discoveredModels.isEmpty {
                    Menu {
                        ForEach(discoveredModels, id: \.self) { model in
                            Button(model) { config.modelName = model }
                        }
                    } label: {
                        Label(L10n("settings.ai.local.model.refresh"), systemImage: "chevron.down.circle")
                            .labelStyle(.iconOnly)
                            .font(DesignSystem.Typography.body)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    private var recommendedHint: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(L10n("settings.ai.local.model.recommended") + ":")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                Text("qwen3-coder:30b")
                    .font(DesignSystem.Typography.monoLabel)
            }
            HStack(spacing: 4) {
                Text(L10n("settings.ai.local.model.lightFallback") + ":")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                Text("qwen2.5-coder:7b")
                    .font(DesignSystem.Typography.monoLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeoutStepper: some View {
        Stepper(value: $config.requestTimeoutSeconds, in: 5...600, step: 5) {
            HStack(spacing: 4) {
                Text(L10n("settings.ai.local.timeout"))
                    .font(DesignSystem.Typography.body)
                Spacer()
                Text("\(config.requestTimeoutSeconds)")
                    .font(DesignSystem.Typography.monoLabel)
                Text(L10n("settings.ai.local.timeout.unit"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var warningsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n("settings.ai.local.singleModelWarning"), systemImage: "exclamationmark.triangle.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.warning)
            Label(L10n("settings.ai.local.toolCallingDisabled"), systemImage: "info.circle.fill")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Button {
                Task { await discoverModels() }
            } label: {
                Label(L10n("settings.ai.local.model.refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isDiscovering)

            Button {
                Task { await probeHealth() }
            } label: {
                Label(L10n("settings.ai.local.health.test"), systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.bordered)
            .disabled(isTesting)

            Spacer()
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Actions

    private func discoverModels() async {
        isDiscovering = true
        defer { isDiscovering = false }
        let models = (try? await AIClient.discoverModels(config: config)) ?? []
        discoveredModels = models
    }

    private func probeHealth() async {
        isTesting = true
        defer { isTesting = false }
        isHealthy = await AIClient.probeHealth(config: config)
        lastChecked = Date()
    }

    private func startPolling() {
        pollTask = Task {
            while !Task.isCancelled {
                isHealthy = await AIClient.probeHealth(config: config)
                lastChecked = Date()
                if discoveredModels.isEmpty {
                    let models = (try? await AIClient.discoverModels(config: config)) ?? []
                    if !models.isEmpty {
                        discoveredModels = models
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(Constants.Timing.localHealthPollSeconds) * 1_000_000_000)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
