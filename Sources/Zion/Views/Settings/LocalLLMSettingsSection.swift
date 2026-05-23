import SwiftUI

struct LocalLLMSettingsSection: View {
    @Binding var config: LocalLLMConfig

    @State private var discoveredModels: [String] = []
    @State private var isHealthy: Bool = false
    @State private var lastChecked: Date? = nil
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var isDiscovering: Bool = false
    @State private var isTesting: Bool = false
    @State private var isStopping: Bool = false
    @State private var stopFeedback: String? = nil

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
                engineRow
                autoStartRow
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

            if !discoveredModels.isEmpty {
                Menu {
                    ForEach(discoveredModels, id: \.self) { model in
                        Button {
                            config.modelName = model
                        } label: {
                            if model == config.modelName {
                                Label(model, systemImage: "checkmark")
                            } else {
                                Text(model)
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await discoverModels() }
                    } label: {
                        Label(L10n("settings.ai.local.model.refresh"), systemImage: "arrow.clockwise")
                    }
                } label: {
                    HStack {
                        Text(config.modelName.isEmpty ? L10n("settings.ai.local.model") : config.modelName)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
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
                .menuStyle(.borderlessButton)
            } else {
                // No discovered models yet — let the user type the name manually.
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
            }
        }
    }

    private var engineRow: some View {
        Picker(L10n("settings.ai.local.engine"), selection: $config.engineKind) {
            Text(L10n("settings.ai.local.engine.ollama")).tag(LocalEngineKind.ollama)
            Text(L10n("settings.ai.local.engine.mlx")).tag(LocalEngineKind.mlx)
            Text(L10n("settings.ai.local.engine.llamaCpp")).tag(LocalEngineKind.llamaCpp)
            Text(L10n("settings.ai.local.engine.lmStudio")).tag(LocalEngineKind.lmStudio)
            Text(L10n("settings.ai.local.engine.custom")).tag(LocalEngineKind.custom)
        }
    }

    private var autoStartRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L10n("settings.ai.local.autostart"), isOn: $config.autoStartEnabled)
                .disabled(config.engineKind == .custom)
            Text(L10n("settings.ai.local.autostart.hint"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recommendedHint: some View {
        Text(L10n("settings.ai.local.model.discoveryHint"))
            .font(DesignSystem.Typography.label)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

            Button(role: .destructive) {
                Task { await stopServer() }
            } label: {
                Label(L10n("settings.ai.local.server.stop"), systemImage: "stop.circle")
            }
            .buttonStyle(.bordered)
            .disabled(isStopping || !isHealthy)

            Spacer()
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
        .overlay(alignment: .topTrailing) {
            if let msg = stopFeedback {
                Text(msg)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stopServer() async {
        isStopping = true
        defer { isStopping = false }
        let launcher = LocalServerLauncher()
        let outcome = await launcher.stop(config: config)
        switch outcome {
        case .stopped(let pid):
            stopFeedback = L10n("settings.ai.local.server.stopped", "\(pid)")
            isHealthy = false
        case .notRunning:
            stopFeedback = L10n("settings.ai.local.server.stop.notRunning")
        case .noOwnerProcess:
            stopFeedback = L10n("settings.ai.local.server.stop.noOwner")
        case .failed(let message):
            stopFeedback = L10n("settings.ai.local.server.stop.failed", message)
        }
    }

    // MARK: - Actions

    private func discoverModels() async {
        isDiscovering = true
        defer { isDiscovering = false }
        let models = (try? await AIClient.discoverModels(config: config)) ?? []
        discoveredModels = models
        // Auto-select when server serves a single model and the configured name doesn't match.
        // Common case: MLX server, llama.cpp server, mlx_lm.server — all serve one model.
        if models.count == 1, !models.contains(config.modelName) {
            config.modelName = models[0]
        }
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
                        if models.count == 1, !models.contains(config.modelName) {
                            config.modelName = models[0]
                        }
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
