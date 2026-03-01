import SwiftUI

struct GitAuthPromptSheet: View {
    let context: GitAuthContext
    let onSubmit: (String, String) -> Void
    let onCancel: () -> Void

    @State private var username: String
    @State private var secret: String = ""

    init(
        context: GitAuthContext,
        onSubmit: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.context = context
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _username = State(initialValue: context.usernameHint ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                Image(systemName: "key.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Colors.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("git.auth.title"))
                        .font(.headline)
                    Text(context.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if context.isAzureDevOps {
                Text(L10n("git.auth.azure.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("git.auth.username.label"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(L10n("git.auth.username.placeholder"), text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("git.auth.secret.label"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SecureField(L10n("git.auth.secret.placeholder"), text: $secret)
                    .textFieldStyle(.roundedBorder)
            }

            Text(context.commandSummary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Button(L10n("Cancelar")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n("git.auth.continue")) {
                    onSubmit(username, secret)
                }
                .buttonStyle(.borderedProminent)
                .disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
