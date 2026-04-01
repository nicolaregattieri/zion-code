import SwiftUI

struct GeneralSettingsTab: View {
    var updater: SparkleUpdater
    @AppStorage(UserDefaultsKeys.General.uiLanguage) private var uiLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage(UserDefaultsKeys.General.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(UserDefaultsKeys.General.confirmationMode) private var confirmationModeRaw: String = ConfirmationMode.destructiveOnly.rawValue
    @AppStorage(UserDefaultsKeys.General.zionModeEnabled) private var zionModeEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.General.graphAuthorAvatarsEnabled) private var graphAuthorAvatarsEnabled: Bool = false
    // Multi-account state
    @State private var accounts: [HostingAccount] = []

    // Add-account form state
    @State private var newTokenKind: GitHostingKind?
    @State private var newPAT: String = ""
    @State private var newBitbucketUsername: String = ""
    @State private var newGitLabHost: String = ""
    @State private var isAddingAccount: Bool = false
    @State private var addAccountError: String?

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

            // Updates
            Section(L10n("settings.update.title")) {
                Toggle(L10n("settings.update.autoCheck"), isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))

                if let lastCheck = updater.lastUpdateCheck {
                    HStack {
                        Text(L10n("settings.update.lastCheck"))
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button(L10n("Buscar Atualizacoes...")) {
                        updater.checkForUpdates()
                    }
                    .controlSize(.small)
                    .disabled(!updater.canCheckForUpdates)
                }
            }

            // Git Hosting — Multi-Account
            Section(L10n("settings.hosting.title")) {
                // GitHub
                DisclosureGroup(L10n("settings.hosting.github")) {
                    accountList(for: .github)
                    gitHubDeviceFlowSection
                    addAccountSection(kind: .github, tokenURL: "https://github.com/settings/tokens/new?scopes=repo&description=Zion")
                }

                // GitLab
                DisclosureGroup(L10n("settings.hosting.gitlab")) {
                    accountList(for: .gitlab)
                    addAccountSection(kind: .gitlab, tokenURL: "https://gitlab.com/-/user_settings/personal_access_tokens")
                }

                // Bitbucket
                DisclosureGroup(L10n("settings.hosting.bitbucket")) {
                    accountList(for: .bitbucket)
                    addAccountSection(kind: .bitbucket, tokenURL: "https://bitbucket.org/account/settings/app-passwords/")
                }

                // Azure DevOps
                DisclosureGroup(L10n("settings.hosting.azureDevOps")) {
                    accountList(for: .azureDevOps)
                    addAccountSection(kind: .azureDevOps, tokenURL: "https://dev.azure.com/_usersSettings/tokens")
                }
            }

            // Safety
            Section(L10n("settings.general.safety")) {
                Picker(L10n("settings.general.confirmation"), selection: $confirmationModeRaw) {
                    ForEach(ConfirmationMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }

                Toggle(L10n("settings.general.graphAuthorAvatars"), isOn: $graphAuthorAvatarsEnabled)

                Text(L10n("settings.general.graphAuthorAvatarsHint"))
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accounts = HostingAccountStore.allAccounts()

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
                withAnimation(DesignSystem.Motion.panel) {
                    glowPulse = false
                }
            }
        }
    }

    // MARK: - Account List

    @ViewBuilder
    private func accountList(for kind: GitHostingKind) -> some View {
        let kindAccounts: [HostingAccount] = accounts.filter { $0.kind == kind }
        if !kindAccounts.isEmpty {
            ForEach(kindAccounts) { account in
                accountRow(account)
            }
        }
    }

    private func accountRow(_ account: HostingAccount) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.label)
                        .font(DesignSystem.Typography.body)
                    Text("@\(account.username)")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.secondary)
                }
                if !account.owners.isEmpty {
                    Text(account.owners.joined(separator: ", "))
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(role: .destructive) {
                removeAccount(account)
            } label: {
                Image(systemName: "trash")
                    .font(DesignSystem.Typography.bodySmall)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    // MARK: - Add Account Section

    @ViewBuilder
    private func addAccountSection(kind: GitHostingKind, tokenURL: String) -> some View {
        DisclosureGroup(L10n("hosting.addWithPAT")) {
            if kind == .bitbucket {
                TextField(L10n("hosting.bitbucket.username"), text: $newBitbucketUsername)
                    .textFieldStyle(.roundedBorder)
            }
            if kind == .gitlab {
                TextField(L10n("hosting.gitlab.host"), text: $newGitLabHost)
                    .textFieldStyle(.roundedBorder)
            }
            SecureField(L10n("hosting.pat.placeholder"), text: $newPAT)
                .textFieldStyle(.roundedBorder)

            HStack {
                if isAddingAccount && newTokenKind == kind {
                    ProgressView()
                        .controlSize(.small)
                }
                if let error = addAccountError, newTokenKind == kind {
                    Text(error)
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(DesignSystem.Colors.destructive)
                }
                Spacer()
                Link(L10n("hosting.generateToken"), destination: URL(string: tokenURL)!)
                    .font(DesignSystem.Typography.bodySmall)
                Button(L10n("hosting.add")) {
                    addManualAccount(kind: kind)
                }
                .controlSize(.small)
                .disabled(newPAT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingAccount)
            }
        }
    }

    // MARK: - GitHub Device Flow Section

    @ViewBuilder
    private var gitHubDeviceFlowSection: some View {
        switch deviceFlowState {
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
                    .foregroundStyle(DesignSystem.Colors.success)
                Text(L10n("hosting.github.authSuccess", username))
                    .font(DesignSystem.Typography.bodySmall)
                Spacer()
                Button(L10n("hosting.github.addAnother")) {
                    deviceFlowState = .idle
                }
                .controlSize(.small)
            }

        case .error(let message):
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DesignSystem.Colors.destructive)
                Text(message)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(.secondary)
                Button(L10n("hosting.github.signIn")) {
                    startDeviceFlow()
                }
                .controlSize(.small)
            }

        default: // .idle
            Button {
                startDeviceFlow()
            } label: {
                Label(L10n("hosting.github.signIn"), systemImage: "person.badge.key")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    // MARK: - Actions

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

                // Discover username and orgs
                let (username, owners) = await GitHubClient.fetchAccessibleOwners(token: tokenResponse.accessToken)
                let label = username.isEmpty ? "GitHub" : username

                let account = HostingAccount(
                    kind: .github,
                    username: username.isEmpty ? "unknown" : username,
                    label: label,
                    owners: owners
                )
                HostingAccountStore.addAccount(account, secret: tokenResponse.accessToken)
                accounts = HostingAccountStore.allAccounts()

                deviceFlowState = .success("@\(username)")
            } catch GitHubDeviceFlow.DeviceFlowError.expired {
                deviceFlowState = .error(L10n("hosting.github.authExpired"))
            } catch {
                deviceFlowState = .error(L10n("hosting.github.authError"))
            }
        }
    }

    private func addManualAccount(kind: GitHostingKind) {
        let token = newPAT.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isAddingAccount = true
        addAccountError = nil
        newTokenKind = kind

        Task {
            switch kind {
            case .github:
                let (username, owners) = await GitHubClient.fetchAccessibleOwners(token: token)
                guard !username.isEmpty else {
                    addAccountError = L10n("hosting.account.invalidToken")
                    isAddingAccount = false
                    return
                }
                let account = HostingAccount(kind: .github, username: username, label: username, owners: owners)
                HostingAccountStore.addAccount(account, secret: token)

            case .gitlab:
                let host = newGitLabHost.trimmingCharacters(in: .whitespacesAndNewlines)
                let (username, owners) = await GitLabClient.fetchAccessibleOwners(
                    token: token,
                    host: host.isEmpty ? nil : host
                )
                guard !username.isEmpty else {
                    addAccountError = L10n("hosting.account.invalidToken")
                    isAddingAccount = false
                    return
                }
                let account = HostingAccount(
                    kind: .gitlab, username: username, label: username, owners: owners,
                    gitlabHost: host.isEmpty ? nil : host
                )
                HostingAccountStore.addAccount(account, secret: token)

            case .bitbucket:
                let bbUser = newBitbucketUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bbUser.isEmpty else {
                    addAccountError = L10n("hosting.bitbucket.usernameRequired")
                    isAddingAccount = false
                    return
                }
                let (_, owners) = await BitbucketClient.fetchAccessibleOwners(username: bbUser, appPassword: token)
                let account = HostingAccount(
                    kind: .bitbucket, username: bbUser, label: bbUser, owners: owners,
                    bitbucketUsername: bbUser
                )
                HostingAccountStore.addAccount(account, secret: token)

            case .azureDevOps:
                // Azure DevOps doesn't have a simple API to discover orgs
                // Create account with empty owners; user's repos will match via legacy fallback
                let account = HostingAccount(kind: .azureDevOps, username: "default", label: "Azure DevOps", owners: [])
                HostingAccountStore.addAccount(account, secret: token)
            }

            accounts = HostingAccountStore.allAccounts()
            newPAT = ""
            newBitbucketUsername = ""
            newGitLabHost = ""
            isAddingAccount = false
            newTokenKind = nil
        }
    }

    private func removeAccount(_ account: HostingAccount) {
        HostingAccountStore.removeAccount(account)
        accounts = HostingAccountStore.allAccounts()
    }
}
