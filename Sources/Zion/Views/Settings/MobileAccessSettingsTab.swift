import SwiftUI

struct MobileAccessSettingsTab: View {
    @AppStorage("zion.mobileAccess.enabled") private var isEnabled: Bool = false
    @AppStorage("zion.mobileAccess.lanMode") private var isLANMode: Bool = false
    @AppStorage("zion.mobileAccess.keepAwakeDuration") private var keepAwakeDuration: String = "off"

    private var state: RemoteAccessState { RemoteAccessState.shared }

    private var currentStep: OnboardingStep {
        if !isEnabled { return .off }
        if !state.isLANMode {
            if !state.hasCheckedCloudflared { return .checking }
            if !state.isCloudflaredInstalled { return .installCloudflared }
        }

        switch state.connectionState {
        case .disabled, .starting: return .starting
        case .waitingForPairing: return .scanQR
        case .connected: return .connected
        case .error: return .error
        }
    }

    var body: some View {
        Form {
            // Always-visible header with toggle
            Section {
                Toggle(isOn: $isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(L10n("mobile.access.title"), systemImage: "iphone.and.arrow.forward")
                            .font(DesignSystem.Typography.sheetTitle)
                        Text(L10n("mobile.access.description"))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isEnabled {
                Section {
                    Toggle(isOn: $isLANMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(L10n("mobile.access.lanMode"), systemImage: "wifi")
                                .font(.subheadline)
                            Text(L10n("mobile.access.lanMode.hint"))
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker(selection: $keepAwakeDuration) {
                        ForEach(KeepAwakeDuration.allCases) { duration in
                            Text(duration.label).tag(duration.rawValue)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(L10n("mobile.access.keepAwake"), systemImage: "moon.zzz")
                                .font(.subheadline)
                            Text(L10n("mobile.access.keepAwake.hint"))
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // Progressive content when enabled
            switch currentStep {
            case .off:
                EmptyView()

            case .checking:
                Section {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L10n("mobile.access.step.checking"))
                    }
                }

            case .installCloudflared:
                Section(L10n("mobile.access.step.install.title")) {
                    Text(L10n("mobile.access.step.install.description"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("brew install cloudflared")
                            .font(.system(.caption, design: .monospaced))
                            .padding(DesignSystem.Spacing.compact)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install cloudflared", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .cursorArrow()
                        .help(L10n("mobile.access.copy"))
                    }

                    Button(L10n("mobile.access.step.install.recheck")) {
                        Task { await state.checkCloudflared() }
                    }
                    .font(DesignSystem.Typography.label)
                }

            case .starting:
                Section(L10n("mobile.access.step.starting.title")) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                        progressRow(L10n("mobile.access.step.starting.server"), isDone: true)
                        if !state.isLANMode {
                            progressRow(L10n("mobile.access.step.starting.tunnel"), isDone: false)
                        }
                        progressRow(L10n("mobile.access.step.starting.qr"), isDone: false)
                    }
                }

            case .scanQR:
                Section(L10n("mobile.access.step.scan.title")) {
                    if let qrImage = state.qrImage {
                        HStack {
                            Spacer()
                            Image(nsImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 180, height: 180)
                            Spacer()
                        }
                    }

                    Text(L10n("mobile.access.step.scan.description"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)

                    if !state.tunnelURL.isEmpty {
                        HStack {
                            Text(state.tunnelURL)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(state.tunnelURL, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .cursorArrow()
                            .help(L10n("mobile.access.copy"))
                        }
                    }
                }

                securitySection

            case .connected:
                Section(L10n("mobile.access.step.connected.title")) {
                    if case .connected(let count) = state.connectionState {
                        Label(
                            L10n("mobile.access.state.connected", count),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(DesignSystem.Colors.success)
                    }

                    Text(L10n("mobile.access.step.connected.description"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }

                securitySection

            case .error:
                Section(L10n("mobile.access.step.error.title")) {
                    if case .error(let message) = state.connectionState {
                        Text(message)
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.error)
                    }

                    Button(L10n("mobile.access.step.error.retry")) {
                        isEnabled = false
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            isEnabled = true
                        }
                    }
                    .font(DesignSystem.Typography.label)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
        .task {
            if !isLANMode && !state.hasCheckedCloudflared {
                await state.checkCloudflared()
            }
        }
        .onChange(of: isLANMode) { _, newValue in
            if !newValue && !state.hasCheckedCloudflared {
                Task { await state.checkCloudflared() }
            }
        }
        .onChange(of: keepAwakeDuration) { _, _ in
            RemoteAccessState.shared.keepAwakeChanged = true
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section(L10n("mobile.access.security")) {
            Button(L10n("mobile.access.regenerateKey")) {
                RemoteAccessState.shared.shouldRegenerateKey = true
            }
            .font(DesignSystem.Typography.label)
            .foregroundStyle(DesignSystem.Colors.destructive)
        }
    }

    // MARK: - Progress Row

    private func progressRow(_ label: String, isDone: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.compact) {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignSystem.Colors.success)
                    .font(DesignSystem.Typography.label)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(label)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(isDone ? .primary : .secondary)
        }
    }

    // MARK: - Steps

    private enum OnboardingStep {
        case off
        case checking
        case installCloudflared
        case starting
        case scanQR
        case connected
        case error
    }
}
