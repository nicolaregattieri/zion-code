import SwiftUI

struct PullRequestSheet: View {
    var model: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var baseBranch: String = "main"
    @State private var isDraft: Bool = false
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var createdPRURL: String?
    @State private var isGeneratingAI: Bool = false
    @State private var needsTokenForKind: GitHostingKind?
    @State private var inlineToken: String = ""
    @State private var selectedRemoteName: String = ""

    private var headBranch: String {
        model.prSheetTargetBranch ?? model.currentBranch
    }

    private var hostedRemoteList: [(remote: RemoteInfo, provider: any GitHostingProvider, hosted: HostedRemote)] {
        model.hostedRemotes()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.pull")
                    .font(DesignSystem.Typography.sheetTitle)
                    .foregroundStyle(DesignSystem.Colors.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("Criar Pull Request")).font(DesignSystem.Typography.sheetTitle)
                    Text(headBranch)
                        .font(DesignSystem.Typography.monoSmall)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Remote selection (only when multiple hosted remotes exist)
                    remoteSection

                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Titulo")).font(DesignSystem.Typography.bodySmallBold).foregroundStyle(.secondary)
                        TextField(L10n("Titulo do PR..."), text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Base branch
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Branch base")).font(DesignSystem.Typography.bodySmallBold).foregroundStyle(.secondary)
                        Picker("", selection: $baseBranch) {
                            ForEach(model.branches.filter { !$0.contains("/") }, id: \.self) { branch in
                                Text(branch).tag(branch)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }

                    // Body
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n("Descricao")).font(DesignSystem.Typography.bodySmallBold).foregroundStyle(.secondary)
                            Spacer()
                            if model.isAIConfigured {
                                Button {
                                    isGeneratingAI = true
                                    Task {
                                        if let result = await model.suggestPRDescription(baseBranch: baseBranch) {
                                            title = result.title
                                            body_ = result.body
                                        }
                                        isGeneratingAI = false
                                    }
                                } label: {
                                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                                        if isGeneratingAI {
                                            ProgressView().controlSize(.small).frame(width: 10, height: 10)
                                        } else {
                                            Image(systemName: "sparkles").font(DesignSystem.Typography.label)
                                        }
                                        Text(L10n("Gerar com IA")).font(DesignSystem.Typography.label)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(isGeneratingAI)
                            }
                        }
                        TextEditor(text: $body_)
                            .font(DesignSystem.Typography.monoBody)
                            .frame(minHeight: 120)
                            .overlay(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius).stroke(DesignSystem.Colors.glassBorderDark))
                    }

                    // Draft toggle
                    Toggle(isOn: $isDraft) {
                        Text(L10n("Criar como Draft"))
                            .font(DesignSystem.Typography.body)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
                    .tint(DesignSystem.Colors.actionPrimary)

                    // Inline token prompt
                    if let tokenKind = needsTokenForKind {
                        VStack(alignment: .leading, spacing: 8) {
                            // Provider name in header for clarity
                            Text(tokenKind.label)
                                .font(DesignSystem.Typography.labelBold)
                                .foregroundStyle(DesignSystem.Colors.warning)
                            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                                Image(systemName: "key.fill").foregroundStyle(DesignSystem.Colors.warning)
                                Text(L10n("hosting.noToken"))
                                    .font(DesignSystem.Typography.label)
                                    .foregroundStyle(.secondary)
                            }

                            SecureField(L10n("hosting.tokenPlaceholder"), text: $inlineToken)
                                .textFieldStyle(.roundedBorder)

                            if tokenKind == .github {
                                Text(L10n("hosting.github.hint"))
                                    .font(DesignSystem.Typography.bodySmall)
                                    .foregroundStyle(.tertiary)
                            }

                            Button {
                                saveInlineTokenAndRetry(kind: tokenKind)
                            } label: {
                                if isCreating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(L10n("hosting.saveAndCreate"), systemImage: "arrow.triangle.pull")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(DesignSystem.Colors.success)
                            .disabled(inlineToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                        }
                        .padding(10)
                        .background(DesignSystem.Colors.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Error
                    if let error = errorMessage {
                        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DesignSystem.Colors.warning)
                            Text(error)
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(DesignSystem.Colors.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                    }

                    // Success
                    if let url = createdPRURL {
                        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignSystem.Colors.success)
                            Text(L10n("PR criado com sucesso!"))
                                .font(DesignSystem.Typography.bodySemibold)
                            Spacer()
                            Button(L10n("Abrir no Navegador")) {
                                if let nsURL = URL(string: url) {
                                    NSWorkspace.shared.open(nsURL)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(DesignSystem.Colors.success.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(L10n("Cancelar")) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    createPR()
                } label: {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L10n("Criar PR"), systemImage: "arrow.triangle.pull")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DesignSystem.Colors.success)
                .disabled(title.isEmpty || isCreating || createdPRURL != nil || needsTokenForKind != nil)
            }
            .padding(16)
        }
        .frame(width: 600, height: 500)
        .onChange(of: selectedRemoteName) { _, newValue in
            guard !newValue.isEmpty else { return }
            model.preferredRemoteName = newValue
        }
        .onAppear {
            // Seed remote selection following the same priority resolveTargetRemote uses,
            // but constrained to the subset of remotes that have a hosting provider.
            let hosted = hostedRemoteList
            if let preferred = model.preferredRemoteName,
               hosted.contains(where: { $0.remote.name == preferred }) {
                selectedRemoteName = preferred
            } else if let origin = hosted.first(where: { $0.remote.name == "origin" }) {
                selectedRemoteName = origin.remote.name
            } else if let first = hosted.first {
                selectedRemoteName = first.remote.name
            }

            // Default base
            if model.branches.contains("main") {
                baseBranch = "main"
            } else if model.branches.contains("master") {
                baseBranch = "master"
            }

            // Default title from branch name
            if headBranch.hasPrefix("release/") {
                let version = String(headBranch.dropFirst("release/".count))
                title = "Release \(version)"
            } else {
                title = headBranch
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "/", with: ": ")
            }

            // Auto-populate changelog for release branches
            if headBranch.hasPrefix("release/") {
                Task {
                    if let changelog = await model.generateReleaseChangelog() {
                        body_ = changelog
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var remoteSection: some View {
        let list = hostedRemoteList
        if list.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n("pr.remote.picker.label"))
                    .font(DesignSystem.Typography.bodySmallBold)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedRemoteName) {
                    ForEach(list, id: \.remote.name) { entry in
                        Text("\(entry.remote.name) (\(entry.provider.kind.label))").tag(entry.remote.name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }
        } else if let single = list.first {
            HStack(spacing: DesignSystem.Spacing.iconTextGap) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(DesignSystem.Colors.success)
                Text(L10n("pr.remote.single", single.remote.name, single.provider.kind.label))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resolvedTarget() -> (provider: any GitHostingProvider, remote: HostedRemote)? {
        if !selectedRemoteName.isEmpty,
           let match = model.detectHostingProvider(for: selectedRemoteName) {
            return match
        }
        return model.detectHostingProvider()
    }

    private func createPR() {
        // 1. No remotes at all
        guard !model.remotes.isEmpty else {
            errorMessage = L10n("hosting.noRemotes")
            return
        }

        // 2. Check if the current branch has been pushed to the remote
        let currentBranchInfo = model.branchInfos.first { $0.name == headBranch && !$0.isRemote }
        if let info = currentBranchInfo, info.upstream.isEmpty {
            errorMessage = L10n("hosting.branchNotPushed", headBranch)
            return
        }

        // 3. Detect provider from the selected remote (falls back to first hosted)
        guard let (provider, remote) = resolvedTarget() else {
            errorMessage = L10n("hosting.noProviderMatch")
            return
        }

        // 3. Check if token is available — if not, show inline prompt
        isCreating = true
        errorMessage = nil
        needsTokenForKind = nil

        Task {
            let tokenAvailable = await provider.hasToken()
            if !tokenAvailable {
                withAnimation(DesignSystem.Motion.snappy) {
                    needsTokenForKind = provider.kind
                }
                isCreating = false
                return
            }

            do {
                let pr = try await provider.createPullRequest(
                    remote: remote,
                    title: title,
                    body: body_,
                    head: headBranch,
                    base: baseBranch,
                    draft: isDraft
                )
                createdPRURL = pr.url
                isCreating = false
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }

    private func saveInlineTokenAndRetry(kind: GitHostingKind) {
        let token = inlineToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        Task {
            // Save to Keychain and invalidate client cache so it picks up the new token
            switch kind {
            case .github:
                HostingCredentialStore.saveSecret(token, for: .githubPAT)
                await model.githubClient.invalidateCache()
            case .gitlab:
                HostingCredentialStore.saveSecret(token, for: .gitlabPAT)
                await model.gitlabClient.invalidateCache()
            case .bitbucket:
                HostingCredentialStore.saveSecret(token, for: .bitbucketAppPassword)
                await model.bitbucketClient.invalidateCache()
            case .azureDevOps:
                HostingCredentialStore.saveSecret(token, for: .azureDevOpsPAT)
                await model.azureDevOpsClient.invalidateCache()
            }

            needsTokenForKind = nil

            // Retry PR creation (honor the currently-selected remote)
            guard let (provider, remote) = resolvedTarget() else {
                errorMessage = L10n("hosting.noProviderMatch")
                isCreating = false
                return
            }

            do {
                let pr = try await provider.createPullRequest(
                    remote: remote,
                    title: title,
                    body: body_,
                    head: headBranch,
                    base: baseBranch,
                    draft: isDraft
                )
                createdPRURL = pr.url
                isCreating = false
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
