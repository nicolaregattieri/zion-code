import SwiftUI

struct MobileAccessSettingsTab: View {
    @AppStorage("zion.mobileAccess.enabled") private var isEnabled: Bool = false
    @AppStorage("zion.mobileAccess.keepAwakeDuration") private var keepAwakeDuration: String = "off"
    @State private var showRegenerateConfirm = false

    private var state: RemoteAccessState { RemoteAccessState.shared }

    private var currentStep: OnboardingStep {
        if !isEnabled { return .off }
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
                    Picker(selection: $keepAwakeDuration) {
                        ForEach(KeepAwakeDuration.allCases) { duration in
                            Text(duration.label).tag(duration.rawValue)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(L10n("mobile.access.keepAwake"), systemImage: "moon.zzz")
                                .font(DesignSystem.Typography.subtitle)
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

            case .starting:
                Section(L10n("mobile.access.step.starting.title")) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                        progressRow(L10n("mobile.access.step.starting.server"), isDone: true)
                        progressRow(L10n("mobile.access.step.starting.qr"), isDone: false)
                    }
                }

            case .scanQR:
                dualQRCards

            case .connected:
                dualQRCards

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
        .onChange(of: keepAwakeDuration) { _, _ in
            RemoteAccessState.shared.keepAwakeChanged = true
            // Post again so syncSettingsFromDefaults picks up the flag
            // (the first didChangeNotification fires before onChange sets the flag)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }
    }

    // MARK: - Dual QR Cards

    @ViewBuilder
    private var dualQRCards: some View {
        // LAN Card - always visible
        Section {
            Label(L10n("mobile.access.lan.title"), systemImage: "wifi")
                .font(DesignSystem.Typography.subtitle)

            if let lanQR = state.lanQRImage {
                qrCodeView(lanQR)
            }

            Text(L10n("mobile.access.lan.description"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)

            if !state.lanURL.isEmpty {
                urlRow(state.lanURL)
            }

            if state.lanConnectedCount > 0 {
                Label(
                    L10n("mobile.access.state.connected", state.lanConnectedCount),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(DesignSystem.Colors.success)
            }
        }

        // Tunnel Card
        Section {
            Label(L10n("mobile.access.tunnel.title"), systemImage: "globe")
                .font(DesignSystem.Typography.subtitle)

            if state.isTunnelReady, let tunnelQR = state.tunnelQRImage {
                qrCodeView(tunnelQR)

                Text(L10n("mobile.access.tunnel.description"))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)

                if !state.tunnelURL.isEmpty {
                    urlRow(state.tunnelURL)
                }

                if state.tunnelConnectedCount > 0 {
                    Label(
                        L10n("mobile.access.state.connected", state.tunnelConnectedCount),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(DesignSystem.Colors.success)
                }
            } else if state.isCloudflaredMissing {
                cloudflaredInstallView
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L10n("mobile.access.tunnel.loading"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }
        }

        securitySection
    }

    // MARK: - Helpers

    private func qrCodeView(_ image: NSImage) -> some View {
        HStack {
            Spacer()
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 140, height: 140)
            Spacer()
        }
    }

    private func urlRow(_ url: String) -> some View {
        HStack {
            Text(url)
                .font(DesignSystem.Typography.monoLabel)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .cursorArrow()
            .help(L10n("mobile.access.copy"))
        }
    }

    private var cloudflaredInstallView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
            Text(L10n("mobile.access.step.install.description"))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(.secondary)

            HStack {
                Text("brew install cloudflared")
                    .font(DesignSystem.Typography.monoLabel)
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
                Task {
                    let installed = await CloudflareTunnelManager.isCloudflaredInstalled()
                    if installed {
                        // Restart to pick up cloudflared
                        isEnabled = false
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        isEnabled = true
                    }
                }
            }
            .font(DesignSystem.Typography.label)
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section(L10n("mobile.access.security")) {
            Button(L10n("mobile.access.regenerateKey")) {
                showRegenerateConfirm = true
            }
            .font(DesignSystem.Typography.label)
            .foregroundStyle(DesignSystem.Colors.destructive)
            .alert(
                L10n("mobile.access.regenerateKey"),
                isPresented: $showRegenerateConfirm
            ) {
                Button(L10n("Cancelar"), role: .cancel) {}
                Button(L10n("mobile.access.regenerateKey.confirm"), role: .destructive) {
                    RemoteAccessState.shared.shouldRegenerateKey = true
                }
            } message: {
                Text(L10n("mobile.access.regenerateKey.hint"))
            }
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
        case starting
        case scanQR
        case connected
        case error
    }
}
