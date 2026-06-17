import SwiftUI

struct MarkdownFullscreenReader: View {
    var model: RepositoryViewModel

    var body: some View {
        ZStack {
            model.effectiveTheme.colors.background
                .ignoresSafeArea()

            Button("") {
                withAnimation(DesignSystem.Motion.detail) {
                    model.isMarkdownFullscreen = false
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)

            Button("") {
                withAnimation(DesignSystem.Motion.detail) {
                    model.isMarkdownReaderSidebarVisible.toggle()
                }
            }
            .keyboardShortcut("o", modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)

            HStack(spacing: 0) {
                if model.isMarkdownReaderSidebarVisible {
                    MarkdownReaderSidebar(
                        model: model,
                        searchText: Binding(
                            get: { model.markdownReaderSidebarSearch },
                            set: { model.markdownReaderSidebarSearch = $0 }
                        )
                    ) { url in
                        model.openExternalFiles([url])
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                VStack(spacing: 0) {
                    header
                    Divider()
                    MarkdownPreviewView(
                        markdownText: model.codeFileContent,
                        fileURL: model.selectedCodeFile?.url,
                        repositoryURL: model.repositoryURL,
                        theme: model.effectiveTheme
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(model.effectiveTheme.colors.background)
            }
        }
        .onAppear { model.refreshAllMarkdownFiles() }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Button {
                withAnimation(DesignSystem.Motion.detail) {
                    model.isMarkdownReaderSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: model.isMarkdownReaderSidebarVisible ? "sidebar.leading" : "list.bullet.indent")
                    .font(DesignSystem.Typography.body)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n("editor.markdown.reader.toggleSidebar"))

            Image(systemName: "doc.text.image")
                .foregroundStyle(.secondary)
            Text(model.selectedCodeFile?.name ?? L10n("editor.markdown.preview"))
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(.secondary)
            Text(L10n("editor.markdown.readerMode"))
                .font(DesignSystem.Typography.metaSemibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.accent.opacity(0.15))
                .foregroundStyle(DesignSystem.Colors.accent)
                .clipShape(Capsule())
            Spacer(minLength: 0)
            Button {
                withAnimation(DesignSystem.Motion.detail) {
                    model.isMarkdownFullscreen = false
                }
            } label: {
                Label(L10n("editor.markdown.edit"), systemImage: "pencil")
                    .font(DesignSystem.Typography.bodySmall)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n("editor.markdown.edit.help"))
            Button {
                withAnimation(DesignSystem.Motion.detail) {
                    model.isMarkdownFullscreen = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Typography.body)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n("editor.markdown.exitFullscreen"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(model.effectiveTheme.colors.background)
    }
}
