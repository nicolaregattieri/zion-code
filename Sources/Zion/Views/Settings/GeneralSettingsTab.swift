import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("zion.uiLanguage") private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("zion.appearance") private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("zion.confirmationMode") private var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage("zion.zionModeEnabled") private var zionModeEnabled: Bool = false
    @AppStorage("zion.gitlab.host") private var gitlabHost: String = ""
    @AppStorage("zion.bitbucket.username") private var bitbucketUsername: String = ""

    // Secrets — backed by Keychain, NOT UserDefaults
    @State private var githubPAT: String = ""
    @State private var gitlabPAT: String = ""
    @State private var bitbucketAppPassword: String = ""
    @State private var azureDevOpsPAT: String = ""

    // GitHub Device Flow state
    @State private var deviceFlowState: DeviceFlowState = .idle
    @State private var deviceFlowUserCode: String = ""

    @State private var glowPulse: Bool = false

    private enum DeviceFlowState: Equatable {
        case idle
        case showingCode
        case polling
        case success(String)
        case error(String)
    }

    var body: some View {
        Form {
            // Zion Mode
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(DesignSystem.Typography.sheetTitle)
                        .foregroundStyle(
                            zionModeEnabled
                                ? AnyShapeStyle(.linearGradient(
                                    colors: [DesignSystem.ZionMode.neonMagenta, DesignSystem.ZionMode.neonGold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(.linearGradient(
                                    colors: [.purple, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                        .frame(width: 28, height: 28)
                        .background(
                            zionModeEnabled
                                ? LinearGradient(
                                    colors: [DesignSystem.ZionMode.neonMagenta.opacity(0.15), DesignSystem.ZionMode.neonGold.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [.purple.opacity(0.15), .orange.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                        .shadow(
                            color: zionModeEnabled ? DesignSystem.ZionMode.neonMagenta.opacity(glowPulse ? 0.35 : 0.15) : .clear,
                            radius: glowPulse ? 6 : 3
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zion Mode")
                            .font(DesignSystem.Typography.sectionTitle)
                        Text(L10n("settings.zionMode.subtitle"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $zionModeEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: zionModeEnabled ? DesignSystem.ZionMode.neonMagenta : .purple))
                }
            }

            // Interface
            Section(L10n("settings.general.interface")) {
                Picker(L10n("Idioma"), selection: $uiLanguageRaw) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }

                Picker(L10n("Aparencia"), selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }

            // Git Hosting
            Section(L10n("settings.hosting.title")) {
                // GitHub
                DisclosureGroup(L10n("settings.hosting.github")) {
                    gitHubDeviceFlowSection
                    SecureField(L10n("hosting.github.pat"), text: $githubPAT)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: githubPAT) { _, newValue in
                            HostingCredentialStore.saveSecret(newValue, for: .githubPAT)
                        }
                    HStack {
                        Text(L10n("hosting.github.hint"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link(L10n("hosting.generateToken"),
                             destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=Zion")!)
                            .font(DesignSystem.Typography.bodySmall)
                    }
                }

                // GitLab
                DisclosureGroup(L10n("settings.hosting.gitlab")) {
                    SecureField(L10n("hosting.gitlab.pat"), text: $gitlabPAT)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: gitlabPAT) { _, newValue in
                            HostingCredentialStore.saveSecret(newValue, for: .gitlabPAT)
                        }
                    TextField(L10n("hosting.gitlab.host"), text: $gitlabHost)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Link(L10n("hosting.generateToken"),
                             destination: URL(string: "https://\(gitlabHost.isEmpty ? "gitlab.com" : gitlabHost)/-/user_settings/personal_access_tokens")!)
                            .font(DesignSystem.Typography.bodySmall)
                    }
                }

                // Bitbucket
                DisclosureGroup(L10n("settings.hosting.bitbucket")) {
                    TextField(L10n("hosting.bitbucket.username"), text: $bitbucketUsername)
                        .textFieldStyle(.roundedBorder)
                    SecureField(L10n("hosting.bitbucket.appPassword"), text: $bitbucketAppPassword)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: bitbucketAppPassword) { _, newValue in
                            HostingCredentialStore.saveSecret(newValue, for: .bitbucketAppPassword)
                        }
                    HStack {
                        Spacer()
                        Link(L10n("hosting.generateToken"),
                             destination: URL(string: "https://bitbucket.org/account/settings/app-passwords/")!)
                            .font(DesignSystem.Typography.bodySmall)
                    }
                }

                // Azure DevOps
                DisclosureGroup(L10n("settings.hosting.azureDevOps")) {
                    SecureField(L10n("hosting.azure.pat"), text: $azureDevOpsPAT)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: azureDevOpsPAT) { _, newValue in
                            HostingCredentialStore.saveSecret(newValue, for: .azureDevOpsPAT)
                        }
                    HStack {
                        Text(L10n("hosting.azure.hint"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link(L10n("hosting.generateToken"),
                             destination: URL(string: "https://dev.azure.com/_usersSettings/tokens")!)
                            .font(DesignSystem.Typography.bodySmall)
                    }
                }
            }

            // Safety
            Section(L10n("settings.general.safety")) {
                Picker(L10n("settings.general.confirmation"), selection: $confirmationModeRaw) {
                    ForEach(ConfirmationMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Load secrets from Keychain
            githubPAT = HostingCredentialStore.loadSecret(for: .githubPAT) ?? ""
            gitlabPAT = HostingCredentialStore.loadSecret(for: .gitlabPAT) ?? ""
            bitbucketAppPassword = HostingCredentialStore.loadSecret(for: .bitbucketAppPassword) ?? ""
            azureDevOpsPAT = HostingCredentialStore.loadSecret(for: .azureDevOpsPAT) ?? ""

            if zionModeEnabled {
                withAnimation(DesignSystem.Motion.glowPulse) {
                    glowPulse = true
                }
            }
        }
        .onChange(of: zionModeEnabled) { _, enabled in
            if enabled {
                withAnimation(DesignSystem.Motion.glowPulse) {
                    glowPulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    glowPulse = false
                }
            }
        }
    }

    // MARK: - GitHub Device Flow Section

    @ViewBuilder
    private var gitHubDeviceFlowSection: some View {
        switch deviceFlowState {
        case .idle:
            Button {
                startDeviceFlow()
            } label: {
                Label(L10n("hosting.github.signIn"), systemImage: "person.badge.key")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .showingCode, .polling:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n("hosting.github.enterCode"))
                        .font(DesignSystem.Typography.bodySmall)
                    Text(deviceFlowUserCode)
                        .font(.system(.body, design: .monospaced).bold())
                        .textSelection(.enabled)
                }
                HStack(spacing: 12) {
                    Link(L10n("hosting.github.openGitHub"),
                         destination: URL(string: "https://github.com/login/device")!)
                        .font(DesignSystem.Typography.bodySmall)
                    if deviceFlowState == .polling {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n("hosting.github.waitingAuth"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))

        case .success(let username):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(L10n("hosting.github.authSuccess", username))
                    .font(DesignSystem.Typography.bodySmall)
            }

        case .error(let message):
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
                Button(L10n("hosting.github.signIn")) {
                    startDeviceFlow()
                }
                .controlSize(.small)
            }
        }
    }

    private func startDeviceFlow() {
        deviceFlowState = .showingCode
        Task {
            let flow = GitHubDeviceFlow()
            do {
                let codeResponse = try await flow.requestDeviceCode()
                deviceFlowUserCode = codeResponse.userCode
                deviceFlowState = .polling

                let tokenResponse = try await flow.pollForToken(
                    deviceCode: codeResponse.deviceCode,
                    interval: codeResponse.interval
                )

                // Save to Keychain and update state
                HostingCredentialStore.saveSecret(tokenResponse.accessToken, for: .githubPAT)
                githubPAT = tokenResponse.accessToken

                // Fetch username for display
                let username = await fetchGitHubUsername(token: tokenResponse.accessToken)
                deviceFlowState = .success(username ?? "GitHub")
            } catch GitHubDeviceFlow.DeviceFlowError.expired {
                deviceFlowState = .error(L10n("hosting.github.authExpired"))
            } catch {
                deviceFlowState = .error(L10n("hosting.github.authError"))
            }
        }
    }

    private func fetchGitHubUsername(token: String) async -> String? {
        guard let url = URL(string: "https://api.github.com/user") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String else { return nil }
        return "@\(login)"
    }
}
