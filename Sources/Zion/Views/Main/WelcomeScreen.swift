import SwiftUI

struct WelcomeScreen: View {
    var model: RepositoryViewModel
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.06, blue: 0.25),
                                    Color(red: 0.05, green: 0.02, blue: 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.8, green: 0.7, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.purple.opacity(0.5), radius: 8, x: 0, y: 0)
                }

                Text("Zion")
                    .font(.system(size: 44, weight: .black))

                Text(L10n("Seu cliente Git nativo para macOS."))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    onOpen()
                } label: {
                    Label(L10n("Abrir repositorio..."), systemImage: "folder.badge.plus")
                        .frame(width: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    model.isCloneSheetVisible = true
                } label: {
                    Label(L10n("Clonar repositorio..."), systemImage: "square.and.arrow.down.on.square")
                        .frame(width: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                } label: {
                    Label(L10n("Conheca o Zion"), systemImage: "questionmark.circle")
                        .frame(width: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
