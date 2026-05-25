import SwiftUI

struct ChatComposer: View {

    @Bindable var chat: ChatService
    @Binding var text: String

    let onSend: () -> Void
    let onStop: () -> Void
    let onNewChat: () -> Void
    /// Optional slot rendered ABOVE the chip row but INSIDE the composer card.
    /// Used by ChatScreen to surface the local-server status bar / auto-start
    /// banner so they share the composer's horizontal padding instead of
    /// floating loose at the edge of the window.
    let topSlot: AnyView

    @AppStorage(UserDefaultsKeys.AI.provider) private var selectedProviderRaw: String = AIProvider.none.rawValue

    @State private var selectedModelID: String = ""
    @State private var availableModels: [String] = []
    /// Locally-installed models discovered on disk (Ollama / LM Studio / MLX
    /// / llama.cpp). Surfaces an inline picker so the user can swap models
    /// without leaving the composer.
    @State private var localHints: [LocalModelHint] = []
    @State private var swapInFlight: Bool = false

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: selectedProviderRaw) ?? .none
    }

    private var canSend: Bool {
        !chat.isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.compact) {
            topSlot
            HStack {
                AutoResolvedChip(chat: chat, livePreviewText: text)
                Spacer(minLength: 0)
            }
            inputField
            // Cost preview for @mentions (300 ms debounce, no I/O)
            if let resolver = chat.mentionResolver {
                MentionsCostPreview(message: text, resolver: resolver)
            }
            HStack(spacing: DesignSystem.Spacing.standard) {
                providerMenu
                modelMenu
                if !localHints.isEmpty {
                    localSwapMenu
                }
                Spacer()
                newChatButton
                if chat.isStreaming {
                    stopButton
                } else {
                    sendButton
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.glassBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .onAppear {
            refreshModelList()
            Task { await loadLocalHints() }
        }
        .onChange(of: selectedProviderRaw) { _, _ in refreshModelList() }
    }

    /// Inline swap menu. Lists every locally-installed model. Pick = stop
    /// running server, update `LocalLLMConfig.modelName`, restart with the
    /// new model. Avoids the long Settings → Local → swap → back-to-Auto loop.
    private var localSwapMenu: some View {
        Menu {
            ForEach(localHints, id: \.self) { hint in
                Button {
                    swapLocalModel(to: hint)
                } label: {
                    HStack {
                        Text(hint.label)
                        Spacer()
                        if let sz = hint.sizeBytes {
                            Text(MemoryMonitor.formatBytes(UInt64(sz)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider()
            Button("Refresh list") {
                Task { await loadLocalHints() }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: swapInFlight ? "arrow.triangle.2.circlepath" : "shippingbox")
                    .font(DesignSystem.Typography.label)
                Text(L10n("chat.composer.localSwap"))
                    .font(DesignSystem.Typography.labelMedium)
                    .lineLimit(1)
            }
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(Capsule().fill(DesignSystem.Colors.glassSubtle))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(swapInFlight)
    }

    private func loadLocalHints() async {
        let cfg = AIClient.loadLocalConfig()
        let hints = await LocalModelDiscovery.scan(
            config: cfg,
            probeCustomServer: false
        )
        await MainActor.run { self.localHints = hints }
    }

    /// Swap to a different local model: stop server, persist new modelName,
    /// hot-restart with new config. Fixes the OOM where MLX kept both the
    /// old and the new model resident in RAM during a hot reload.
    private func swapLocalModel(to hint: LocalModelHint) {
        var cfg = AIClient.loadLocalConfig() ?? LocalLLMConfig()
        cfg.modelName = hint.modelID
        AIClient.saveLocalConfig(cfg)
        // Picking a model from the menu is an explicit opt-in to use local
        // again — clear the session suppression that Disconnect set so Smart
        // Auto resumes routing to local.
        chat.localSessionSuppressed = false
        Task { await chat.orchestrator.markHealthy(.local) }
        swapInFlight = true
        Task {
            _ = await LocalServerLauncher().restart(config: cfg, engine: cfg.engineKind)
            await MainActor.run { self.swapInFlight = false }
        }
    }

    /// Public — read by ChatScreen when calling chat.send so the chosen
    /// model is passed through to the provider stream.
    var currentModelOverride: String? {
        selectedModelID.isEmpty ? nil : selectedModelID
    }

    private func refreshModelList() {
        let static_ = ProviderModelCatalog.staticModels(for: selectedProvider)
        availableModels = static_
        selectedModelID = ProviderModelCatalog.selectedModel(for: selectedProvider)
        if selectedProvider == .local {
            Task {
                let discovered = await ProviderModelCatalog.discoverLocalModels()
                await MainActor.run {
                    availableModels = discovered
                    if !discovered.isEmpty, !discovered.contains(selectedModelID) {
                        selectedModelID = discovered.first ?? selectedModelID
                        ProviderModelCatalog.setSelectedModel(selectedModelID, for: .local)
                    }
                }
            }
        }
    }

    private var modelMenu: some View {
        Menu {
            if availableModels.isEmpty {
                Text(L10n("chat.composer.model.empty"))
            } else {
                ForEach(availableModels, id: \.self) { model in
                    Button {
                        selectedModelID = model
                        ProviderModelCatalog.setSelectedModel(model, for: selectedProvider)
                    } label: {
                        HStack {
                            Text(model)
                            if model == selectedModelID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "brain")
                    .font(DesignSystem.Typography.label)
                Text(selectedModelID.isEmpty ? L10n("chat.composer.model.empty") : selectedModelID)
                    .font(DesignSystem.Typography.labelMedium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DesignSystem.Typography.label)
            }
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.glassHover)
            )
            .overlay(
                Capsule()
                    .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var inputField: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder — shown when text is empty
            if text.isEmpty {
                Text(L10n("chat.composer.placeholder.discoverable"))
                    .chatScaledFont(role: .body)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, DesignSystem.Spacing.compact + 4)
                    .padding(.vertical, DesignSystem.Spacing.micro + 6)
                    .allowsHitTesting(false)
            }
            // NSTextView replacement — multi-line, enter-to-send, shift-enter newline
            ComposerNSTextView(text: $text, onSend: {
                if canSend { onSend() }
            })
            .frame(minHeight: 28, maxHeight: 120)
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
        }
    }

    private var providerMenu: some View {
        Menu {
            ForEach(AIProviderSupport.configurableProviders) { provider in
                Button {
                    selectedProviderRaw = provider.rawValue
                } label: {
                    HStack {
                        Text(provider.label)
                        if selectedProvider == provider {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "cpu")
                    .font(DesignSystem.Typography.label)
                Text(selectedProvider == .none ? L10n("settings.ai.provider.local") : selectedProvider.label)
                    .font(DesignSystem.Typography.labelMedium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DesignSystem.Typography.label)
            }
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.glassHover)
            )
            .overlay(
                Capsule()
                    .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(canSend ? DesignSystem.Colors.brandWhite : DesignSystem.Colors.textTertiary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(canSend
                              ? LinearGradient(colors: [DesignSystem.Colors.brandPrimary, DesignSystem.Colors.brandInk], startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [DesignSystem.Colors.glassHover, DesignSystem.Colors.glassHover], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(L10n("chat.composer.send"))
        .keyboardShortcut(.return, modifiers: [.command])
    }

    private var stopButton: some View {
        Button {
            onStop()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.brandWhite)
                .frame(width: 30, height: 30)
                .background(Circle().fill(DesignSystem.Colors.destructive))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.composer.stop"))
    }

    private var newChatButton: some View {
        Button {
            onNewChat()
        } label: {
            Image(systemName: "plus.message")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.composer.newChat"))
    }
}
