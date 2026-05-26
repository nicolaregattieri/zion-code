import SwiftUI
import Speech

/// Mic button rendered inside the chat composer. Tap → start Apple Speech
/// dictation in the active locale. Tap again → stop, optionally polish via
/// the configured AI provider, append to the composer text binding.
///
/// Long-press the button to surface a popover with engine / locale pickers
/// and a "Polish with LLM" toggle. Whisper is intentionally hidden — the
/// terminal feature still exposes it but the chat composer ships only the
/// engines we can guarantee (Apple native always available, Gemini when the
/// user has a key configured).
struct ChatDictationButton: View {

    @Binding var composerText: String
    let repoURL: URL?

    @State private var speechService = SpeechRecognitionService()
    /// True between tap-to-stop and the transcript actually landing in the
    /// composer. Apple Speech returns immediately on stop but the closing
    /// frames + final transcript settle on a background queue; Gemini /
    /// Whisper engines have an explicit network transcribe call. Without
    /// this state the user sees the pulse die and assumes recording is
    /// still on (no feedback that we are now working on the transcript).
    @State private var isTranscribing = false
    @State private var isPolishing = false
    @State private var permissionDenial: SpeechRecognitionService.PermissionDenial?
    @State private var isPopoverPresented = false
    @State private var isHovered = false

    @AppStorage(DictationPolishService.settingsKey) private var polishEnabled: Bool = true

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                if speechService.isActive {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                        let scale = 1.0 + 0.18 * sin(phase * 4.4)
                        Circle()
                            .stroke(DesignSystem.Colors.destructive.opacity(0.55), lineWidth: 1.4)
                            .frame(width: 26, height: 26)
                            .scaleEffect(scale)
                            .opacity(2 - scale)
                    }
                }
                // Working states (transcribing / polishing) draw their own
                // spinner ring around the glyph so the user has clear "still
                // working" feedback after the pulse dies.
                if isTranscribing || isPolishing {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                }
                Image(systemName: micSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(buttonColor)
                    .opacity((isTranscribing || isPolishing) ? 0.35 : 1.0)
            }
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(
                    speechService.isActive
                    ? DesignSystem.Colors.destructive.opacity(0.18)
                    : (isTranscribing || isPolishing
                       ? DesignSystem.Colors.ai.opacity(0.18)
                       : (isHovered ? DesignSystem.Colors.glassHover : Color.clear))
                )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Globally-listenable shortcut to mirror the terminal feature's
        // mic toggle. ⌥⌘X starts dictation when idle, stops when active.
        // Disabled state still receives the shortcut so the user does not
        // accidentally fire a tap while a transcript is settling — the
        // .disabled below blocks the action explicitly.
        .keyboardShortcut("x", modifiers: [.option, .command])
        .disabled(isTranscribing || isPolishing)
        .onHover { h in isHovered = h }
        .help(tooltipText)
        .onLongPressGesture(minimumDuration: 0.45) {
            isPopoverPresented = true
        }
        .popover(isPresented: $isPopoverPresented) {
            settingsPopover
        }
        .alert(
            L10n("speech.permission.alert.title"),
            isPresented: Binding(
                get: { permissionDenial != nil },
                set: { if !$0 { permissionDenial = nil } }
            )
        ) {
            if let url = permissionDenial?.settingsURL {
                Button(L10n("speech.permission.alert.openSettings")) {
                    NSWorkspace.shared.open(url)
                    permissionDenial = nil
                }
            }
            Button(L10n("Cancelar"), role: .cancel) {
                permissionDenial = nil
            }
        } message: {
            Text(permissionDenial == .microphone
                 ? L10n("speech.permission.alert.micMessage")
                 : L10n("speech.permission.alert.speechMessage"))
        }
    }

    // MARK: - Popover (long-press settings)

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            Text(L10n("chat.composer.dictation.title"))
                .font(DesignSystem.Typography.bodyMedium)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                Text(L10n("speech.engine"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                Picker("", selection: $speechService.selectedEngine) {
                    ForEach(supportedEngines, id: \.self) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                Text(L10n("speech.language"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
                Picker("", selection: $speechService.selectedLocale) {
                    ForEach(speechService.supportedLocales, id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale)
                    }
                }
                .labelsHidden()
            }

            Toggle(L10n("chat.composer.dictation.polish"), isOn: $polishEnabled)
            Text(L10n("chat.composer.dictation.polish.hint"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if speechService.isActive && !speechService.currentTranscript.isEmpty {
                Text(speechService.currentTranscript)
                    .font(DesignSystem.Typography.label)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.compact)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
            }
        }
        .controlSize(.small)
        .padding(DesignSystem.Spacing.standard)
        .frame(width: 300)
    }

    /// Whisper is hidden from chat dictation — we cannot ship a model bundle
    /// and the user reported they neither test nor pay for Whisper locally.
    /// Keeping Apple + Gemini gives "always works offline" + "best quality
    /// when a Gemini key exists" without forcing a download.
    private var supportedEngines: [SpeechRecognitionService.Engine] {
        SpeechRecognitionService.Engine.allCases.filter { $0 != .whisper }
    }

    private var micSymbol: String {
        if isPolishing { return "wand.and.sparkles" }
        if isTranscribing { return "waveform" }
        return speechService.isActive ? "mic.fill" : "mic"
    }

    private var tooltipText: String {
        if isPolishing { return L10n("chat.composer.dictation.polishing") }
        if isTranscribing { return L10n("chat.composer.dictation.transcribing") }
        if speechService.isActive { return L10n("chat.composer.dictation.stop") }
        return L10n("chat.composer.dictation.start") + " (⌥⌘X)"
    }

    private var buttonColor: Color {
        if speechService.isActive {
            return DesignSystem.Colors.destructive
        }
        if isHovered {
            return DesignSystem.Colors.textPrimary
        }
        return DesignSystem.Colors.textSecondary
    }

    // MARK: - Actions

    private func handleTap() {
        if speechService.isActive {
            stopAndApply()
        } else {
            startListening()
        }
    }

    private func startListening() {
        Task {
            if let denial = await speechService.requestPermission() {
                permissionDenial = denial
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            switch speechService.selectedEngine {
            case .apple:
                speechService.startListening(
                    locale: speechService.selectedLocale,
                    targetSessionID: nil
                )
            case .whisper, .gemini:
                speechService.startRecording(targetSessionID: nil)
            }
        }
    }

    private func stopAndApply() {
        // Flip the transcribing state immediately so the spinner replaces the
        // pulse ring as soon as the user taps stop. Apple Speech returns
        // synchronously but the SwiftUI render cycle still benefits from this
        // explicit "we are now working" state — without it the user sees the
        // pulse die and assumes the mic is still hot.
        isTranscribing = true
        Task {
            defer { isTranscribing = false }
            let result: (transcript: String, sessionID: UUID?)
            switch speechService.selectedEngine {
            case .apple:
                result = speechService.stopListening()
            case .whisper, .gemini:
                result = await speechService.stopAndTranscribe()
            }
            let raw = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }

            let final: String
            if polishEnabled {
                isPolishing = true
                final = await DictationPolishService.polish(rawText: raw, repoURL: repoURL)
                isPolishing = false
            } else {
                final = raw
            }
            appendToComposer(final)
        }
    }

    /// Insert with a leading space if the composer already has text. The
    /// dictated chunk is appended rather than replacing so the user can mix
    /// typing and dictation in the same turn.
    private func appendToComposer(_ chunk: String) {
        if composerText.isEmpty {
            composerText = chunk
        } else {
            let separator = composerText.hasSuffix(" ") ? "" : " "
            composerText += separator + chunk
        }
    }
}
