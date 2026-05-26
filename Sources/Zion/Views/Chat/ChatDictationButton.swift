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
    @State private var isPolishing = false
    @State private var permissionDenial: SpeechRecognitionService.PermissionDenial?
    @State private var isPopoverPresented = false
    @State private var isHovered = false

    @AppStorage(DictationPolishService.settingsKey) private var polishEnabled: Bool = true

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // Pulsing ring while listening — proxy for an audio level
                // meter. Real PCM level would require plumbing through
                // SpeechRecognitionService.installTap; the pulse is a clear
                // "I am awake and recording" signal without that refactor.
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
                Image(systemName: micSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(buttonColor)
                if isPolishing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(
                    speechService.isActive
                    ? DesignSystem.Colors.destructive.opacity(0.18)
                    : (isHovered
                       ? DesignSystem.Colors.glassHover
                       : Color.clear)
                )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isPolishing)
        .onHover { h in isHovered = h }
        .help(speechService.isActive
              ? L10n("chat.composer.dictation.stop")
              : L10n("chat.composer.dictation.start"))
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
        return speechService.isActive ? "mic.fill" : "mic"
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
        Task {
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
