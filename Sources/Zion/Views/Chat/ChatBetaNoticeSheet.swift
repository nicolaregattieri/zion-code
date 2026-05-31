import SwiftUI

/// One-time beta acknowledgement sheet shown the first time a user opens
/// Zion Talks. The user must tick "I understand" before the OK button
/// enables. Acknowledgement is persisted under
/// `chat.betaNoticeAcknowledged` so the sheet never reappears.
struct ChatBetaNoticeSheet: View {

    @Binding var isPresented: Bool
    @State private var understood: Bool = false

    @AppStorage("chat.betaNoticeAcknowledged") private var acknowledged: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                Text(L10n("chat.beta.notice.title"))
                    .font(DesignSystem.Typography.cardTitle)
            }

            Text(L10n("chat.beta.notice.body"))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $understood) {
                Text(L10n("chat.beta.notice.understood"))
                    .font(DesignSystem.Typography.body)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(L10n("chat.beta.notice.continue")) {
                    acknowledged = true
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!understood)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
