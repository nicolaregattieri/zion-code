import AppKit
import SwiftUI

struct CloneSheet: View {
    @Bindable var model: RepositoryViewModel
    @State private var remoteURL: String = ""
    @State private var destinationPath: String = ""
    @State private var repoName: String = ""
    @Environment(\.dismiss) private var dismiss

    private var destinationURL: URL {
        let base = URL(fileURLWithPath: destinationPath)
        return repoName.isEmpty ? base : base.appendingPathComponent(repoName)
    }

    private var protocolBadge: String {
        if remoteURL.hasPrefix("git@") || remoteURL.hasPrefix("ssh://") {
            return "SSH"
        } else if remoteURL.hasPrefix("https://") || remoteURL.hasPrefix("http://") {
            return "HTTPS"
        }
        return ""
    }

    private var isValid: Bool {
        !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            formContent
            Divider()
            footer
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .onAppear { prefillFromClipboard() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Clonar Repositorio"))
                    .font(.headline)
                Text(L10n("Baixe um repositorio remoto para o disco local."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Remote URL
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n("URL do repositorio"))
                        .font(.subheadline.weight(.medium))
                    if !protocolBadge.isEmpty {
                        Text(protocolBadge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(protocolBadge == "SSH" ? DesignSystem.Colors.statusOrangeBg : DesignSystem.Colors.statusGreenBg)
                            .foregroundStyle(protocolBadge == "SSH" ? .orange : .green)
                            .clipShape(Capsule())
                    }
                }
                TextField("https://github.com/user/repo.git", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: remoteURL) { _, newValue in
                        updateRepoName(from: newValue)
                    }
            }

            // Destination folder
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Pasta de destino"))
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    TextField("~/Developer", text: $destinationPath)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n("Escolher...")) {
                        pickDestination()
                    }
                    .controlSize(.small)
                }
            }

            // Repo name (auto-derived)
            if !repoName.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("Nome do repositorio"))
                        .font(.subheadline.weight(.medium))
                    TextField("repo", text: $repoName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Clone path preview
            if !destinationPath.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(destinationURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Progress
            if model.isCloning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.cloneProgress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
            }

            // Error
            if let error = model.cloneError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignSystem.Colors.error)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.error)
                        .lineLimit(3)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.dangerBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button(L10n("Cancelar")) {
                if model.isCloning {
                    model.cancelClone()
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(L10n("Clonar")) {
                model.cloneRepository(
                    remoteURL: remoteURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    destination: destinationURL
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || model.isCloning)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func prefillFromClipboard() {
        // Default destination
        let developerDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
        if FileManager.default.fileExists(atPath: developerDir.path) {
            destinationPath = developerDir.path
        } else {
            destinationPath = FileManager.default.homeDirectoryForCurrentUser.path
        }

        // Auto-fill URL from clipboard
        if let clip = NSPasteboard.general.string(forType: .string) {
            let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeGitURL(trimmed) {
                remoteURL = trimmed
                updateRepoName(from: trimmed)
            }
        }
    }

    private func looksLikeGitURL(_ value: String) -> Bool {
        value.hasSuffix(".git")
            || value.hasPrefix("git@")
            || value.hasPrefix("ssh://")
            || (value.hasPrefix("https://") && (value.contains("github.com") || value.contains("gitlab.com") || value.contains("bitbucket.org")))
    }

    private func updateRepoName(from url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { repoName = ""; return }
        // Extract repo name from URL: take last path component, strip .git
        let lastComponent: String
        if trimmed.contains(":") && trimmed.hasPrefix("git@") {
            // SSH format: git@github.com:user/repo.git
            lastComponent = String(trimmed.split(separator: "/").last ?? Substring(trimmed.split(separator: ":").last ?? ""))
        } else {
            lastComponent = String(URL(string: trimmed)?.lastPathComponent ?? "")
        }
        repoName = lastComponent
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n("Escolher")
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
        }
    }
}
