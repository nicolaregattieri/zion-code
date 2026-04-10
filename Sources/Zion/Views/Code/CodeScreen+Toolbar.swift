import AppKit
import SwiftUI

extension CodeScreen {

    var editorToolbar: some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Button {
                withAnimation(DesignSystem.Motion.panel) { isFileBrowserVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left").font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .tint(isFileBrowserVisible ? Color.accentColor : .secondary)
            .help(L10n("Alternar painel de arquivos") + " (⌘B)")
            .accessibilityLabel(L10n("Alternar painel de arquivos"))

            // Theme & Font group
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Picker("", selection: $model.selectedTheme) {
                    ForEach(EditorTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Picker("", selection: $model.editorFontFamily) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("Courier").tag("Courier")
                    Text("Fira Code").tag("Fira Code")
                    Text("JetBrains Mono").tag("JetBrains Mono")
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
            .disabled(!isTextEditorActive)

            // Size & Spacing group
            HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                Stepper(value: $model.editorFontSize, in: 8...32, step: 1) {
                    Text("\(Int(model.editorFontSize))pt")
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(width: 30)
                }

                Divider().frame(height: 14)

                Slider(value: $model.editorLineSpacing, in: 0.0...20.0, step: 0.5)
                    .frame(width: 60)
                Text(String(format: "%.1fpt", model.editorLineSpacing))
                    .font(DesignSystem.Typography.monoLabel)
                    .frame(width: 40)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.elementCornerRadius))
            .disabled(!isTextEditorActive)

            Button {
                model.isLineWrappingEnabled.toggle()
            } label: {
                Image(systemName: model.isLineWrappingEnabled ? "arrow.turn.down.left" : "arrow.right.to.line")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .tint(model.isLineWrappingEnabled ? Color.accentColor : .secondary)
            .help(L10n("Quebra de Linha Automática"))
            .accessibilityLabel(L10n("Quebra de Linha Automática"))
            .disabled(!isTextEditorActive)

            if isMarkdownFile {
                Button {
                    withAnimation(DesignSystem.Motion.detail) {
                        isMarkdownPreviewVisible.toggle()
                    }
                } label: {
                    Image(systemName: isMarkdownPreviewVisible ? "eye.fill" : "eye")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .tint(isMarkdownPreviewVisible ? Color.accentColor : .secondary)
                .help(L10n(isMarkdownPreviewVisible ? "editor.markdown.hidePreview" : "editor.markdown.showPreview"))
                .accessibilityLabel(L10n("editor.markdown.preview"))
            }

            EditorSettingsPopoverButton(model: model, showBreadcrumbPath: $showBreadcrumbPath)
                .disabled(!isTextEditorActive)

            Button {
                model.toggleBlame()
            } label: {
                Image(systemName: "person.text.rectangle")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .tint(model.isBlameVisible ? Color.accentColor : .secondary)
            .help(L10n("Git Blame"))
            .accessibilityLabel(L10n("Git Blame"))
            .disabled(model.activeFileID == nil || !isTextEditorActive)

            Button {
                if let file = model.selectedCodeFile, let repoURL = model.repositoryURL {
                    let relativePath = file.url.path.replacingOccurrences(of: repoURL.path + "/", with: "")
                    model.loadFileHistory(for: relativePath)
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .help(L10n("filehistory.title"))
            .accessibilityLabel(L10n("filehistory.title"))
            .disabled(model.activeFileID == nil)

            Button {
                model.formatCurrentFile()
            } label: {
                Image(systemName: "text.alignleft")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .help(L10n("format.document") + " (⇧⌥F)")
            .accessibilityLabel(L10n("format.document"))
            .disabled(
                model.activeFileID == nil
                    || !isTextEditorActive
                    || !CodeFormatter.canFormat(
                        fileExtension: model.selectedCodeFile.map { model.editorFileExtension(for: $0.url) } ?? ""
                    )
            )

            Divider().frame(height: 14).padding(.horizontal, 4)

            // Layout toggle: editor / split / terminal
            HStack(spacing: DesignSystem.Spacing.iconGroupedGap) {
                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .editorOnly }
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(DesignSystem.Typography.bodyMedium)
                        .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .editorOnly ? Color.accentColor : .secondary)
                .help(L10n("Somente editor") + " (⌘J)")
                .accessibilityLabel(L10n("Somente editor"))

                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .split }
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(DesignSystem.Typography.bodyMedium)
                        .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .split ? Color.accentColor : .secondary)
                .help(L10n("Editor e terminal"))
                .accessibilityLabel(L10n("Editor e terminal"))

                Button {
                    withAnimation(DesignSystem.Motion.detail) { layout = .terminalOnly }
                } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                        .font(DesignSystem.Typography.bodyMedium)
                        .iconHitTarget(DesignSystem.IconSize.editorToolbarFrame)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(layout == .terminalOnly ? Color.accentColor : .secondary)
                .help(L10n("Somente terminal") + " (⌃⌘J)")
                .accessibilityLabel(L10n("Somente terminal"))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(DesignSystem.Colors.glassSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))

            if showBreadcrumbPath, !breadcrumbItems.isEmpty {
                breadcrumbPathBar
            }

            Spacer()

            if model.hasRepoEditorConfig {
                HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(DesignSystem.Typography.meta)
                    Text(".zion")
                        .font(DesignSystem.Typography.monoMeta)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DesignSystem.Colors.glassSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                .help(L10n("editor.repoConfig.active"))
                .accessibilityLabel(L10n("editor.repoConfig.active"))
            }

            Button {
                model.createNewFile()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(DesignSystem.Typography.label)
            }
            .buttonStyle(.bordered)
            .help(L10n("Novo Arquivo") + " (⌘N)")
            .accessibilityLabel(L10n("Novo Arquivo"))

            if model.activeFileID != nil {
                Button {
                    model.saveCurrentFileAs()
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .help(L10n("Salvar Como...") + " (⇧⌘S)")
                .accessibilityLabel(L10n("Salvar Como..."))
                .disabled(!isTextEditorActive)

                Button {
                    model.saveCurrentCodeFile()
                } label: {
                    Label(L10n("Salvar"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(model.selectedTheme.isLightAppearance ? DesignSystem.Colors.info : Color.accentColor)
                .help(L10n("Salvar") + " (⌘S)")
                .disabled(!isTextEditorActive)
            }
        }
        .controlSize(.small)
    }

}
