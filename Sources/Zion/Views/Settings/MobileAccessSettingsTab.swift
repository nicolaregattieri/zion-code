import SwiftUI

struct MobileAccessSettingsTab: View {
    @AppStorage("zion.mobileAccess.enabled") private var isEnabled: Bool = false

    private var state: RemoteAccessState { RemoteAccessState.shared }

    private var currentStep: OnboardingStep {
        if !state.hasCheckedCloudflared { return .checking }
        if !state.isCloudflaredInstalled { return .installCloudflared }
        if !isEnabled { return .ready }

        switch state.connectionState {
        case .disabled: return .ready
        case .starting: return .starting
        case .waitingForPairing: return .scanQR
        case .connected: return .connected
        case .error: return .error
        }
    }

    var body: some View {
        Form {
            // Step indicator
            Section {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
                    Label(L10n("mobile.access.title"), systemImage: "iphone.and.arrow.forward")
                        .font(.headline)

                    Text(L10n("mobile.access.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Progressive content based on current step
            switch currentStep {
            case .checking:
                Section {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L10n("mobile.access.step.checking"))
                    }
                }

            case .installCloudflared:
                stepSection(
                    number: 1,
                    title: L10n("mobile.access.step.install.title"),
                    icon: "arrow.down.circle.fill",
                    color: DesignSystem.Colors.warning
                ) {
                    Text(L10n("mobile.access.step.install.description"))
                        .font(.caption)
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
                        Task {
                            await state.checkCloudflared()
                        }
                    }
                    .font(.caption)
                }

            case .ready:
                stepSection(
                    number: state.isCloudflaredInstalled ? 1 : 2,
                    title: L10n("mobile.access.step.enable.title"),
                    icon: "power.circle.fill",
                    color: DesignSystem.Colors.info
                ) {
                    Toggle(L10n("mobile.access.enable"), isOn: $isEnabled)

                    Text(L10n("mobile.access.step.enable.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .starting:
                stepSection(
                    number: 2,
                    title: L10n("mobile.access.step.starting.title"),
                    icon: "bolt.horizontal.circle.fill",
                    color: DesignSystem.Colors.info
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.compact) {
                        progressRow(L10n("mobile.access.step.starting.server"), isDone: true)
                        progressRow(L10n("mobile.access.step.starting.tunnel"), isDone: false)
                        progressRow(L10n("mobile.access.step.starting.qr"), isDone: false)
                    }
                }

            case .scanQR:
                stepSection(
                    number: 2,
                    title: L10n("mobile.access.step.scan.title"),
                    icon: "qrcode",
                    color: DesignSystem.Colors.actionPrimary
                ) {
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
                        .font(.caption)
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

                disableSection

            case .connected:
                stepSection(
                    number: 3,
                    title: L10n("mobile.access.step.connected.title"),
                    icon: "iphone.radiowaves.left.and.right",
                    color: DesignSystem.Colors.success
                ) {
                    if case .connected(let count) = state.connectionState {
                        Label(
                            L10n("mobile.access.state.connected", count),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(DesignSystem.Colors.success)
                    }

                    Text(L10n("mobile.access.step.connected.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                disableSection

            case .error:
                stepSection(
                    number: 2,
                    title: L10n("mobile.access.step.error.title"),
                    icon: "exclamationmark.triangle.fill",
                    color: DesignSystem.Colors.error
                ) {
                    if case .error(let message) = state.connectionState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.error)
                    }

                    Button(L10n("mobile.access.step.error.retry")) {
                        isEnabled = false
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            isEnabled = true
                        }
                    }
                    .font(.caption)
                }

                disableSection
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
        .task {
            if !state.hasCheckedCloudflared {
                await state.checkCloudflared()
            }
        }
    }

    // MARK: - Reusable Step Section

    private func stepSection<Content: View>(
        number: Int,
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Label {
                Text(L10n("mobile.access.step.header", number, title))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Disable / Security Section

    private var disableSection: some View {
        Section {
            Button(L10n("mobile.access.step.disable")) {
                isEnabled = false
            }
            .font(.caption)

            Button(L10n("mobile.access.regenerateKey")) {
                RemoteAccessState.shared.shouldRegenerateKey = true
            }
            .font(.caption)
            .foregroundStyle(DesignSystem.Colors.destructive)
        } header: {
            Text(L10n("mobile.access.security"))
        }
    }

    // MARK: - Progress Row

    private func progressRow(_ label: String, isDone: Bool) -> some View {
        HStack(spacing: DesignSystem.Spacing.compact) {
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignSystem.Colors.success)
                    .font(.caption)
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(isDone ? .primary : .secondary)
        }
    }

    // MARK: - Steps

    private enum OnboardingStep {
        case checking
        case installCloudflared
        case ready
        case starting
        case scanQR
        case connected
        case error
    }
}
