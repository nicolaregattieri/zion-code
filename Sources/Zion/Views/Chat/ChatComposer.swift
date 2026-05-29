import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ChatComposer: View {

    @Bindable var chat: ChatService
    @Binding var text: String

    let onSend: () -> Void
    let onStop: () -> Void
    let onNewChat: () -> Void

    /// Banner shown briefly when an attachment is rejected (oversize, unreadable).
    @State private var attachmentError: String?
    /// Optional slot rendered ABOVE the chip row but INSIDE the composer card.
    /// Used by ChatScreen to surface the local-server status bar / auto-start
    /// banner so they share the composer's horizontal padding instead of
    /// floating loose at the edge of the window.
    let topSlot: AnyView
    /// Repository this composer is targeting. Forwarded to the dictation
    /// button so the polish call carries `cwd` to CLI providers.
    var repoURL: URL? = nil

    @AppStorage(UserDefaultsKeys.AI.provider) private var selectedProviderRaw: String = AIProvider.none.rawValue
    /// Per-session opt-in for letting native provider tool loops call the
    /// `bash` MCP tool. Rendered as a composer pill so the toggle is visible
    /// before the user hits Send — burying it in Settings made the choice
    /// invisible the moment the LLM said "I cannot run shell commands".
    @AppStorage(MCPConfigBuilder.bashToolToggleKey) private var allowBashTool: Bool = false

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

    /// Allow send even while a stream is in flight — the typed message will
    /// queue and dispatch automatically when the current turn finishes. The
    /// composer is only disabled when the input is empty/whitespace.
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.compact) {
            topSlot
            if let notice = chat.transientNotice {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: "info.circle.fill")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.warning)
                    Text(notice)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignSystem.Spacing.compact)
                .padding(.vertical, DesignSystem.Spacing.micro)
                .background(Capsule().fill(DesignSystem.Colors.warning.opacity(0.12)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack {
                AutoResolvedChip(chat: chat, livePreviewText: text)
                Spacer(minLength: 0)
            }
            if let err = attachmentError {
                Text(err)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.destructive)
                    .padding(.horizontal, DesignSystem.Spacing.compact)
                    .padding(.vertical, DesignSystem.Spacing.micro)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let pending = chat.threadAttachments[chat.activeThreadID] ?? []
            if !pending.isEmpty {
                AttachmentChipRow(pending: pending) { id in
                    removeAttachment(id: id)
                }
            }
            inputField
            // Cost preview for @mentions (300 ms debounce, no I/O)
            if let resolver = chat.mentionResolver {
                MentionsCostPreview(message: text, resolver: resolver)
            }
            // Composer action row. ViewThatFits picks the widest layout the
            // container can show: full row when the window is comfortable,
            // compressed row with an overflow `…` menu when the window is
            // narrow (split panes / portrait monitors / small laptops). Send
            // + Stop + provider + queue badge stay visible at every width
            // because they are the primary actions; everything else moves
            // into the overflow.
            ViewThatFits(in: .horizontal) {
                fullActionRow
                compactActionRow
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
            // NSTextView replacement — multi-line, enter-to-send, shift-enter newline.
            // The custom NSTextView consults the pasteboard before letting the
            // system paste a path-as-text when an image is on the clipboard;
            // see ZionComposerTextView.paste(_:).
            ComposerNSTextView(
                text: $text,
                onSend: { if canSend { onSend() } },
                onPasteAttachments: { items in addAttachments(items) },
                onPasteAutoInstall: { payload in
                    Task { await chat.handlePasteAutoInstall(payload) }
                }
            )
            .frame(minHeight: 28, maxHeight: 120)
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
        }
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.pdf], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Attachment helpers

    private func addAttachments(_ items: [PendingChatAttachment]) {
        guard !items.isEmpty else { return }
        let key = chat.activeThreadID
        var current = chat.threadAttachments[key] ?? []
        current.append(contentsOf: items)
        chat.threadAttachments[key] = current
    }

    private func removeAttachment(id: UUID) {
        let key = chat.activeThreadID
        var current = chat.threadAttachments[key] ?? []
        current.removeAll { $0.id == id }
        if current.isEmpty {
            chat.threadAttachments.removeValue(forKey: key)
        } else {
            chat.threadAttachments[key] = current
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            // Prefer file URL representation so we get a real on-disk file
            // we can copy from. Falls back to a generic data load for
            // pasteboard-only providers.
            if provider.canLoadObject(ofClass: NSURL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                    guard let url = item as? URL else { return }
                    do {
                        let pending = try ChatAttachmentService.captureFromFile(url: url)
                        DispatchQueue.main.async {
                            addAttachments([pending])
                        }
                    } catch {
                        DispatchQueue.main.async {
                            surfaceAttachmentError(error)
                        }
                    }
                }
            }
        }
        return accepted
    }

    fileprivate func surfaceAttachmentError(_ error: Error) {
        attachmentError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        // Auto-dismiss the inline error after a few seconds so it doesn't
        // hang around forever.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            attachmentError = nil
        }
    }

    /// Paperclip pill — opens NSOpenPanel scoped to images + PDFs.
    private var attachButton: some View {
        Button {
            presentAttachmentPicker()
        } label: {
            Image(systemName: "paperclip")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n("chat.composer.attach"))
    }

    private func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf]
        panel.prompt = L10n("chat.composer.attach")
        if panel.runModal() == .OK {
            var collected: [PendingChatAttachment] = []
            for url in panel.urls {
                do {
                    collected.append(try ChatAttachmentService.captureFromFile(url: url))
                } catch {
                    surfaceAttachmentError(error)
                }
            }
            if !collected.isEmpty {
                addAttachments(collected)
            }
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

    /// Wide layout — everything inline. Used when the composer has room.
    private var fullActionRow: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            providerMenu
            modelMenu
            if !localHints.isEmpty {
                localSwapMenu
            }
            bashTogglePill
            Spacer()
            attachButton
            ChatDictationButton(composerText: $text, repoURL: repoURL)
            newChatButton
            if chat.activePendingQueueCount > 0 {
                queueBadge
            }
            if chat.isStreaming {
                stopButton
            }
            sendButton
        }
    }

    /// Narrow layout — secondary controls collapse into an overflow menu.
    /// Provider chip + model name still visible (you need them to know what
    /// will respond), Send + Stop + queue badge stay clickable. Everything
    /// else routes through the `…` menu so the row fits a 360pt wide pane.
    private var compactActionRow: some View {
        HStack(spacing: DesignSystem.Spacing.compact) {
            providerMenu
            modelMenu
            Spacer()
            attachButton
            overflowMenu
            if chat.activePendingQueueCount > 0 {
                queueBadge
            }
            if chat.isStreaming {
                stopButton
            }
            sendButton
        }
    }

    /// Overflow menu shown in the compact layout. Each entry mirrors the
    /// inline control that was hidden so the user does not lose any
    /// functionality just because the window is narrow.
    private var overflowMenu: some View {
        Menu {
            Toggle(L10n("chat.composer.bashTool"), isOn: $allowBashTool)
            if !localHints.isEmpty {
                Section(L10n("chat.composer.localSwap")) {
                    ForEach(localHints, id: \.self) { hint in
                        Button {
                            swapLocalModel(to: hint)
                        } label: {
                            Text(hint.label)
                        }
                    }
                }
            }
            Divider()
            Button {
                onNewChat()
            } label: {
                Label(L10n("chat.composer.newChat"), systemImage: "plus.message")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n("chat.composer.more"))
    }

    /// One-tap pill that gates the `bash` MCP tool for native provider
    /// loops. Visible state: terminal icon + "Bash" label; tinted accent +
    /// filled background when on, secondary text + glass when off. Settings
    /// page does not duplicate this — the pill IS the control.
    private var bashTogglePill: some View {
        Button {
            allowBashTool.toggle()
        } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: allowBashTool ? "terminal.fill" : "terminal")
                    .font(DesignSystem.Typography.label)
                // Explicit "Shell: ON / OFF" label — bare "Bash" left the
                // user guessing whether the pill was a status badge or a
                // toggle (Image #x feedback).
                Text(allowBashTool
                     ? L10n("chat.composer.bashTool.labelOn")
                     : L10n("chat.composer.bashTool.labelOff"))
                    .font(DesignSystem.Typography.labelMedium)
                // Mini status dot for at-a-glance recognition independent of
                // the text label / icon fill state.
                Circle()
                    .fill(allowBashTool
                          ? DesignSystem.Colors.warning
                          : DesignSystem.Colors.textTertiary)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(
                Capsule().fill(allowBashTool
                               ? DesignSystem.Colors.warning.opacity(0.18)
                               : DesignSystem.Colors.glassHover)
            )
            .overlay(
                Capsule().strokeBorder(allowBashTool
                                       ? DesignSystem.Colors.warning
                                       : DesignSystem.Colors.glassStroke,
                                       lineWidth: 1)
            )
            .foregroundStyle(allowBashTool
                             ? DesignSystem.Colors.warning
                             : DesignSystem.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(allowBashTool
              ? L10n("chat.composer.bashTool.on.help")
              : L10n("chat.composer.bashTool.off.help"))
    }

    /// Pill showing how many messages the user has typed-and-fired while a
    /// stream was running. Tap → popover lists each queued message with a
    /// dismiss button so the user can drop any without aborting the live
    /// turn.
    private var queueBadge: some View {
        Menu {
            ForEach(chat.pendingQueueByThread[chat.activeThreadID] ?? []) { item in
                Button(role: .destructive) {
                    chat.dropPendingMessage(id: item.id, threadID: chat.activeThreadID)
                } label: {
                    let preview = String(item.text.prefix(60))
                    Label(preview, systemImage: "minus.circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(chat.activePendingQueueCount)")
                    .font(DesignSystem.Typography.labelMedium)
                    .monospacedDigit()
            }
            .padding(.horizontal, DesignSystem.Spacing.compact)
            .padding(.vertical, DesignSystem.Spacing.micro)
            .background(Capsule().fill(DesignSystem.Colors.glassSubtle))
            .overlay(Capsule().strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1))
            .foregroundStyle(DesignSystem.Colors.ai)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n("chat.composer.queue.help"))
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
