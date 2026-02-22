import SwiftUI

struct WelcomeScreen: View {
    var model: RepositoryViewModel
    let onOpen: () -> Void
    let onInit: () -> Void

    var body: some View {
        ViewportContentContainer {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Group {
                        if let logoURL = Bundle.module.url(forResource: "zion-logo", withExtension: "png"),
                           let nsImage = NSImage(contentsOf: logoURL) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: DesignSystem.Colors.brandPrimary.opacity(0.5), radius: 12, x: 0, y: 4)

                    Text("Zion")
                        .font(.system(size: 44, weight: .black))

                    Text(L10n("The view from the top."))
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
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
                    .tint(DesignSystem.Colors.actionPrimary)

                    Button {
                        model.isCloneSheetVisible = true
                    } label: {
                        Label(L10n("Clonar repositorio..."), systemImage: "square.and.arrow.down.on.square")
                            .frame(width: 240)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        onInit()
                    } label: {
                        Label(L10n("Inicializar repositorio..."), systemImage: "plus.rectangle.on.folder")
                            .frame(width: 240)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help(L10n("Criar um novo repositorio Git em uma pasta existente"))
                    .accessibilityLabel(L10n("Inicializar repositorio..."))

                    Divider()
                        .frame(width: 120)
                        .padding(.vertical, 4)

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
        }
        .padding(32)
    }
}
