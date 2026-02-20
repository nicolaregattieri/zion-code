import SwiftUI

struct SubmodulesCard: View {
    var model: RepositoryViewModel

    var body: some View {
        GlassCard(spacing: 12) {
            CardHeader(L10n("Submodulos"), icon: "cube.transparent", subtitle: L10n("Dependencias externas do repositorio"))

            if model.submodules.isEmpty {
                HStack {
                    Text(L10n("Nenhum submodulo encontrado."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.loadSubmodules()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(model.submodules) { sub in
                        HStack(spacing: 10) {
                            Image(systemName: sub.status.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(sub.status.color)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(sub.name)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                Text(sub.path)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(String(sub.hash.prefix(8)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text(sub.status.label)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(sub.status.color.opacity(0.15))
                                .foregroundStyle(sub.status.color)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Button {
                        model.submoduleInit()
                    } label: {
                        Label(L10n("Init"), systemImage: "play")
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button {
                        model.submoduleUpdate(recursive: true)
                    } label: {
                        Label(L10n("Update"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button {
                        model.submoduleSync()
                    } label: {
                        Label(L10n("Sync"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Spacer()

                    Button {
                        model.loadSubmodules()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { model.loadSubmodules() }
    }
}
