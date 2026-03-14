import SwiftUI
import Speech

struct VoiceInputButton: View {
    @Bindable var model: RepositoryViewModel
    @Bindable var speechService: SpeechRecognitionService
    var accentColor: Color
    var isTerminalSearchVisible: Bool = false
    var voiceToggleRequestID: Int = 0

    @State private var isPopoverPresented = false
    @State private var permissionDenied = false
    @State private var isHovered = false

    var body: some View {
        Button {
            handleTap()
        } label: {
            Image(systemName: speechService.isActive ? "mic.fill" : "mic")
                .font(DesignSystem.IconSize.toolbar)
                .foregroundStyle(buttonColor)
                .frame(width: DesignSystem.IconSize.terminalToolbarFrame.width,
                       height: DesignSystem.IconSize.terminalToolbarFrame.height)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if speechService.isActive {
                        Circle()
                            .fill(DesignSystem.Colors.error)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                            .transition(DesignSystem.Motion.fadeScale)
                    }
                }
        }
        .buttonStyle(.plain)
        .background(isHovered ? DesignSystem.Interactive.hoverBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
        .onHover { h in isHovered = h }
        .help(L10n("speech.button.tooltip"))
        .accessibilityLabel(L10n("speech.button.tooltip"))
        .popover(isPresented: $isPopoverPresented) {
            voicePopover
                .frame(width: 260)
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            isPopoverPresented = true
        }
        .onChange(of: voiceToggleRequestID) {
            handleTap()
        }
    }

    // MARK: - Popover

    private var voicePopover: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            // Engine picker
            if speechService.isWhisperAvailable {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                    Text(L10n("speech.engine"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $speechService.selectedEngine) {
                        ForEach(SpeechRecognitionService.Engine.allCases) { engine in
                            Text(engine.label).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                    Text(L10n("speech.engine"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    Text(L10n("settings.speech.engine.whisperUnavailable"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    openAISettingsLink(label: L10n("settings.speech.engine.configureOpenAI"))
                }
            }

            // Language picker
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

            // Live transcript preview
            if speechService.isActive && !speechService.currentTranscript.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                    Text(L10n("speech.listening"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    Text(speechService.currentTranscript)
                        .font(DesignSystem.Typography.bodyMedium)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.compact)
                        .background(DesignSystem.Colors.glassSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
                }
            }

            // Permission denied message
            if permissionDenied {
                Text(L10n("speech.permission.denied"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.error)
            }

            if let recoveryIssue = speechService.recoveryIssue {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                    Text(recoveryIssue.message)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.warning)

                    HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                        Button(L10n("speech.recovery.useAppleSpeech")) {
                            speechService.selectedEngine = .apple
                            speechService.clearRecoveryIssue()
                        }
                        .buttonStyle(.bordered)

                        openAISettingsLink(label: L10n("speech.recovery.manageOpenAI"))
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.standard)
    }

    // MARK: - Actions

    private func handleTap() {
        if speechService.isActive {
            stopAndSend()
        } else {
            startRecognition()
        }
    }

    private func startRecognition() {
        let logger = DiagnosticLogger.shared
        Task {
            logger.log(.info, "handleTap → startRecognition: requesting permission…", context: "Speech")
            let authorized = await speechService.requestPermission()
            guard authorized else {
                logger.log(.warn, "Permission denied", context: "Speech")
                permissionDenied = true
                return
            }
            permissionDenied = false

            // Give audio hardware time to initialize after first permission grant
            logger.log(.info, "Permission granted, waiting 300ms for audio hardware…", context: "Speech")
            try? await Task.sleep(for: .milliseconds(300))

            // Capture the current terminal session ID at START time
            let sessionID = model.activeTerminalID
            logger.log(.info, "Starting engine=\(speechService.selectedEngine.rawValue)…", context: "Speech")

            switch speechService.selectedEngine {
            case .apple:
                speechService.startListening(
                    locale: speechService.selectedLocale,
                    targetSessionID: sessionID
                )
            case .whisper:
                speechService.startRecording(targetSessionID: sessionID)
            }

            // If engine didn't start (format not ready), retry once
            if !speechService.isActive {
                logger.log(.warn, "Engine didn't start, retrying in 500ms…", context: "Speech")
                try? await Task.sleep(for: .milliseconds(500))
                switch speechService.selectedEngine {
                case .apple:
                    speechService.startListening(
                        locale: speechService.selectedLocale,
                        targetSessionID: sessionID
                    )
                case .whisper:
                    speechService.startRecording(targetSessionID: sessionID)
                }
            }
        }
    }

    private func stopAndSend() {
        Task {
            let result: (transcript: String, sessionID: UUID?)

            switch speechService.selectedEngine {
            case .apple:
                result = speechService.stopListening()
            case .whisper:
                result = await speechService.stopAndTranscribe()
            }

            guard !result.transcript.isEmpty else { return }

            // Send to the CAPTURED target session (not the currently active one)
            if let sessionID = result.sessionID,
               let callback = model.terminalSendCallbacks[sessionID],
               let data = result.transcript.data(using: .utf8) {
                callback(data)
            }

            // Restore focus unless terminal search is active
            if !isTerminalSearchVisible {
                model.focusActiveTerminal()
            }
        }
    }

    // MARK: - Visual

    private var buttonColor: Color {
        if speechService.isActive {
            return DesignSystem.Colors.error
        }
        return isPopoverPresented ? Color.accentColor : accentColor
    }

    private func openAISettingsLink(label: String) -> some View {
        SettingsLink {
            Text(label)
                .font(DesignSystem.Typography.label)
        }
        .buttonStyle(.bordered)
        .simultaneousGesture(TapGesture().onEnded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .openAISettings, object: nil)
            }
        })
    }
}
