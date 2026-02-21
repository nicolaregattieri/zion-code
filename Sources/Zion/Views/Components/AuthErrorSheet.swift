import SwiftUI

struct AuthErrorSheet: View {
    let errorMessage: String
    let remotes: [RemoteInfo]
    @Environment(\.dismiss) private var dismiss

    private var isSSH: Bool {
        remotes.contains { $0.url.contains("git@") || $0.url.hasPrefix("ssh://") }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Erro de Autenticacao")).font(.headline)
                    Text(L10n("Nao foi possivel acessar o repositorio remoto."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Error details
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Remote info
                    if !remotes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n("Remotes")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            ForEach(remotes) { remote in
                                HStack(spacing: 8) {
                                    Image(systemName: remote.url.contains("git@") ? "key.fill" : "globe")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text(remote.name)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(remote.url)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(remote.url.contains("git@") ? "SSH" : "HTTPS")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DesignSystem.Colors.statusBlueBg)
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Divider()

                    // Help suggestions
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n("Possiveis solucoes:")).font(.system(size: 12, weight: .bold))

                        if isSSH {
                            helpItem(icon: "key.fill", title: L10n("Chave SSH"),
                                     description: L10n("Verifique se sua chave SSH esta adicionada ao ssh-agent."),
                                     command: "ssh-add -l")

                            helpItem(icon: "network", title: L10n("Configuracao SSH"),
                                     description: L10n("Teste a conexao SSH com o GitHub."),
                                     command: "ssh -T git@github.com")
                        } else {
                            helpItem(icon: "person.badge.key", title: "GitHub CLI",
                                     description: L10n("Autentique-se com o GitHub CLI para configurar credenciais."),
                                     command: "gh auth login")
                        }

                        helpItem(icon: "lock.open", title: L10n("Acesso ao Keychain"),
                                 description: L10n("Verifique as credenciais salvas no Keychain Access do macOS."),
                                 command: nil)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n("Fechar")) { dismiss() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(16)
        }
        .frame(width: 550, height: 480)
    }

    private func helpItem(icon: String, title: String, description: String, command: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
                if let command {
                    HStack(spacing: 6) {
                        Text(command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.orange)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}
