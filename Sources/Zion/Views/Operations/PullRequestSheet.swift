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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("Criar Pull Request")).font(.headline)
                    Text(model.currentBranch)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Titulo")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        TextField(L10n("Titulo do PR..."), text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Base branch
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Branch base")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
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
                            Text(L10n("Descricao")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            Spacer()
                            if model.isAIConfigured {
                                Button {
                                    isGeneratingAI = true
                                    Task {
                                        if let result = await model.suggestPRDescription() {
                                            title = result.title
                                            body_ = result.body
                                        }
                                        isGeneratingAI = false
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if isGeneratingAI {
                                            ProgressView().controlSize(.small).frame(width: 10, height: 10)
                                        } else {
                                            Image(systemName: "sparkles").font(.system(size: 10))
                                        }
                                        Text(L10n("Gerar com IA")).font(.system(size: 10))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(isGeneratingAI)
                            }
                        }
                        TextEditor(text: $body_)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 120)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                    }

                    // Draft toggle
                    Toggle(isOn: $isDraft) {
                        Text(L10n("Criar como Draft"))
                            .font(.system(size: 12))
                    }

                    // Error
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Success
                    if let url = createdPRURL {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(L10n("PR criado com sucesso!"))
                                .font(.system(size: 12, weight: .semibold))
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
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .tint(.green)
                .disabled(title.isEmpty || isCreating || createdPRURL != nil)
            }
            .padding(16)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            // Default title from branch name
            title = model.currentBranch
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "/", with: ": ")
            // Default base
            if model.branches.contains("main") {
                baseBranch = "main"
            } else if model.branches.contains("master") {
                baseBranch = "master"
            }
        }
    }

    private func createPR() {
        guard let remote = detectGitHubRemote() else {
            errorMessage = L10n("Nenhum remote GitHub detectado.")
            return
        }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let pr = try await model.githubClient.createPullRequest(
                    remote: remote,
                    title: title,
                    body: body_,
                    head: model.currentBranch,
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

    private func detectGitHubRemote() -> GitHubRemote? {
        for remote in model.remotes {
            if let gh = GitHubClient.parseRemote(remote.url) {
                return gh
            }
        }
        return nil
    }
}
