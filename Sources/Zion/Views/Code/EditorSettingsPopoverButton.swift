import SwiftUI

struct EditorSettingsPopoverButton: View {
    @Bindable var model: RepositoryViewModel
    @Binding var showBreadcrumbPath: Bool
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(isPresented ? Color.accentColor : .secondary)
        .help(L10n("settings.editor.popover.title"))
        .accessibilityLabel(L10n("settings.editor.popover.title"))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n("settings.editor.popover.title"))
                    .font(DesignSystem.Typography.bodyMedium)

                // Editing section
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("settings.editor.editing"))
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundStyle(.secondary)

                    HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                        Text(L10n("settings.editor.tabSize"))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $model.editorTabSize) {
                            Text("2").tag(2)
                            Text("4").tag(4)
                            Text("8").tag(8)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }

                    Toggle(L10n("settings.editor.useTabs"), isOn: $model.editorUseTabs)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.autoCloseBrackets"), isOn: $model.editorAutoCloseBrackets)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.autoCloseQuotes"), isOn: $model.editorAutoCloseQuotes)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.bracketPairHighlight"), isOn: $model.editorBracketPairHighlight)
                        .font(DesignSystem.Typography.bodySmall)
                }

                Divider()

                // Display section
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("settings.editor.display"))
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundStyle(.secondary)

                    Toggle(L10n("settings.editor.lineWrap"), isOn: $model.isLineWrappingEnabled)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.showBreadcrumb"), isOn: $showBreadcrumbPath)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.highlightCurrentLine"), isOn: $model.editorHighlightCurrentLine)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.showIndentGuides"), isOn: $model.editorShowIndentGuides)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.showRuler"), isOn: $model.editorShowRuler)
                        .font(DesignSystem.Typography.bodySmall)

                    if model.editorShowRuler {
                        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                            Text(L10n("settings.editor.rulerColumn"))
                                .font(DesignSystem.Typography.label)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $model.editorRulerColumn) {
                                Text("80").tag(80)
                                Text("100").tag(100)
                                Text("120").tag(120)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                }

                Divider()

                // Formatting section
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("settings.editor.formatting"))
                        .font(DesignSystem.Typography.labelMedium)
                        .foregroundStyle(.secondary)

                    Toggle(L10n("settings.editor.formatOnSave"), isOn: $model.editorFormatOnSave)
                        .font(DesignSystem.Typography.bodySmall)

                    Toggle(L10n("settings.editor.jsonSortKeys"), isOn: $model.editorJsonSortKeys)
                        .font(DesignSystem.Typography.bodySmall)
                }

                Divider()

                // Line spacing
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text(L10n("settings.editor.lineSpacing"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    Slider(value: $model.editorLineSpacing, in: 0.0...20.0, step: 0.5)
                        .frame(width: 100)
                    Text(String(format: "%.1fpt", model.editorLineSpacing))
                        .font(DesignSystem.Typography.monoLabel)
                        .frame(width: 42)
                }

                Divider()

                // Letter spacing
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text(L10n("settings.editor.letterSpacing"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    Slider(value: $model.editorLetterSpacing, in: -1.0...5.0, step: 0.1)
                        .frame(width: 100)
                    Text(String(format: "%.1f", model.editorLetterSpacing))
                        .font(DesignSystem.Typography.monoLabel)
                        .frame(width: 30)
                }
            }
            .controlSize(.small)
            .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
            .tint(DesignSystem.Colors.actionPrimary)
            .padding(12)
            .frame(width: 260)
        }
    }
}
