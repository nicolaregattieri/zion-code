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
        Section(L10n("settings.ai.provider.local")) {
            // Server URL
            LabeledContent(L10n("settings.ai.local.serverURL")) {
                TextField(L10n("settings.ai.local.serverURL.hint"), text: $config.serverURL)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
            }

            // API Key (optional)
            LabeledContent(L10n("settings.ai.local.apiKey.optional")) {
                SecureField(L10n("settings.ai.local.apiKey.optional"), text: $config.apiKey)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
            }

            // Model — free TextField; discovered models offered as Menu suggestions
            LabeledContent(L10n("settings.ai.local.model")) {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    TextField("qwen3-coder:30b", text: $config.modelName)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.body)

                    if !discoveredModels.isEmpty {
                        Menu {
                            ForEach(discoveredModels, id: \.self) { model in
                                Button(model) { config.modelName = model }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }

            // Recommended model hint
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n("settings.ai.local.model.recommended") + ": qwen3-coder:30b")
                    .font(DesignSystem.Typography.labelBold)
                    .foregroundStyle(.secondary)
                Text(L10n("settings.ai.local.model.lightFallback") + ": qwen2.5-coder:7b")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            // Request timeout stepper
            Stepper(
                value: $config.requestTimeoutSeconds,
                in: 5...600,
                step: 5
            ) {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text(L10n("settings.ai.local.timeout"))
                        .font(DesignSystem.Typography.body)
                    Text("\(config.requestTimeoutSeconds) \(L10n("settings.ai.local.timeout.unit"))")
                        .font(DesignSystem.Typography.monoLabel)
                        .foregroundStyle(.secondary)
                }
            }

            // Health indicator row
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 6, height: 6)

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
            }
            .padding(.vertical, 2)

            // Warning: single model configured
            if discoveredModels.count == 1 {
                Label(L10n("settings.ai.local.singleModelWarning"), systemImage: "exclamationmark.triangle.fill")
                    .font(DesignSystem.Typography.labelMedium)
                    .foregroundStyle(DesignSystem.Colors.warning)
            }

            // Warning: tool calling may be limited
            Label(L10n("settings.ai.local.toolCallingDisabled"), systemImage: "info.circle.fill")
                .font(DesignSystem.Typography.labelMedium)
                .foregroundStyle(DesignSystem.Colors.warning)

            // Action buttons
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Button(L10n("settings.ai.local.model.refresh")) {
                    Task { await discoverModels() }
                }
                .buttonStyle(.bordered)
                .disabled(isDiscovering)

                Button(L10n("settings.ai.local.health.test")) {
                    Task { await probeHealth() }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)
            }
        }
        .onAppear {
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
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

    // MARK: - Auto-poll

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
