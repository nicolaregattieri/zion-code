import SwiftUI

struct WelcomeScreen: View {
    var model: RepositoryViewModel
    let onOpen: () -> Void
    let onInit: () -> Void

    @State private var hoveredURL: URL?

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

                // Recent repositories
                if !model.recentRepositories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n("Recentes"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 4) {
                            ForEach(model.recentRepositories, id: \.self) { url in
                                Button {
                                    model.openRepository(url)
                                } label: {
                                    HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                                        Image(systemName: "folder.fill")
                                            .font(DesignSystem.Typography.body)
                                            .foregroundStyle(Color.accentColor.opacity(0.8))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent)
                                                .font(.system(size: 13, weight: .semibold))
                                                .lineLimit(1)
                                            Text(url.path)
                                                .font(DesignSystem.Typography.meta)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(DesignSystem.Typography.micro)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius)
                                            .fill(hoveredURL == url ? DesignSystem.Colors.glassHover : DesignSystem.Colors.glassMinimal)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { h in hoveredURL = h ? url : nil }
                            }
                        }
                    }
                    .frame(width: 320)
                }
            }
        }
        .padding(32)
        .onAppear {
            model.loadRecentRepositories()
        }
    }
}
