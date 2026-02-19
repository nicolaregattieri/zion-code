import SwiftUI

struct WelcomeScreen: View {
    @ObservedObject var model: RepositoryViewModel
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

                Text(L10n("Seu Git Graph nativo para macOS."))
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
                
                if !model.recentRepositories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n("Recentes"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        ForEach(model.recentRepositories, id: \.self) { url in
                            Button {
                                model.openRepository(url)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue.opacity(0.8))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(url.lastPathComponent)
                                            .font(.subheadline.weight(.semibold))
                                        Text(url.path)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 320)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear {
            model.loadRecentRepositories()
        }
    }
}
