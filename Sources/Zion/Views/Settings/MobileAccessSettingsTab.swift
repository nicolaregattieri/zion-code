import SwiftUI

struct MobileAccessSettingsTab: View {
    @AppStorage("zion.mobileAccess.enabled") private var isEnabled: Bool = false
    @State private var isCheckingCloudflared: Bool = true
    @State private var isCloudflaredInstalled: Bool = false
    @State private var connectionState: RemoteAccessConnectionState = .disabled
    @State private var tunnelURL: String = ""
    @State private var qrImage: NSImage?

    var body: some View {
        Form {
            Section(L10n("mobile.access.title")) {
                Toggle(L10n("mobile.access.enable"), isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        NotificationCenter.default.post(
                            name: .mobileAccessToggled,
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }

                Text(L10n("mobile.access.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isEnabled {
                Section(L10n("mobile.access.status")) {
                    connectionStatusView
                }

                if !tunnelURL.isEmpty {
                    Section(L10n("mobile.access.qrCode")) {
                        if let qrImage {
                            HStack {
                                Spacer()
                                Image(nsImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 180, height: 180)
                                Spacer()
                            }
                            Text(L10n("mobile.access.qrCode.hint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }

                    Section(L10n("mobile.access.tunnelURL")) {
                        HStack {
                            Text(tunnelURL)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(tunnelURL, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .cursorArrow()
                        }
                    }
                }

                Section(L10n("mobile.access.security")) {
                    Button(L10n("mobile.access.regenerateKey")) {
                        NotificationCenter.default.post(
                            name: .mobileAccessRegenerateKey,
                            object: nil
                        )
                    }
                    .foregroundStyle(.red)

                    Text(L10n("mobile.access.regenerateKey.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !isCloudflaredInstalled && !isCheckingCloudflared {
                Section(L10n("mobile.access.requirements")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n("mobile.access.cloudflared.notFound"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text(L10n("mobile.access.cloudflared.install"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("brew install cloudflared")
                                .font(.system(.caption, design: .monospaced))
                                .padding(6)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install cloudflared", forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .cursorArrow()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
        .task {
            isCloudflaredInstalled = await CloudflareTunnelManager.isCloudflaredInstalled()
            isCheckingCloudflared = false
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionState {
        case .disabled:
            Label(L10n("mobile.access.state.disabled"), systemImage: "circle")
                .foregroundStyle(.secondary)
        case .starting:
            HStack {
                ProgressView().controlSize(.small)
                Text(L10n("mobile.access.state.starting"))
            }
        case .waitingForPairing:
            Label(L10n("mobile.access.state.waitingForPairing"), systemImage: "qrcode")
                .foregroundStyle(DesignSystem.Colors.info)
        case .connected(let deviceCount):
            Label(
                L10n("mobile.access.state.connected", deviceCount),
                systemImage: "iphone.radiowaves.left.and.right"
            )
            .foregroundStyle(DesignSystem.Colors.success)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let mobileAccessToggled = Notification.Name("zion.mobileAccess.toggled")
    static let mobileAccessRegenerateKey = Notification.Name("zion.mobileAccess.regenerateKey")
}
