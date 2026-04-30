import SwiftUI

struct EditorSettingsTab: View {
    private static let systemFonts = ["SF Mono", "Menlo", "Monaco", "Courier"]
    private static let installableFonts = [
        "Fira Code", "JetBrains Mono", "Hack", "Roboto Mono",
        "Source Code Pro", "IBM Plex Mono", "Cascadia Code",
        "Hack Nerd Font Mono", "Inconsolata", "Anonymous Pro"
    ]
    private static let cachedInstalledFonts: [String] = installableFonts.filter { MonospaceFontResolver.isAvailable(name: $0) }

    @AppStorage(UserDefaultsKeys.Editor.theme) private var themeRaw: String = EditorTheme.dracula.rawValue
    @AppStorage(UserDefaultsKeys.Editor.fontFamily) private var fontFamily: String = "SF Mono"
    @AppStorage(UserDefaultsKeys.Editor.fontSize) private var fontSize: Double = 13.0
    @AppStorage(UserDefaultsKeys.Editor.markdownPreviewFontSize) private var markdownPreviewFontSize: Double = MarkdownPreviewView.defaultPreviewFontSize
    @AppStorage(UserDefaultsKeys.Editor.lineSpacing) private var lineSpacing: Double = 4.0
    @AppStorage(UserDefaultsKeys.Editor.letterSpacing) private var letterSpacing: Double = 0.0

    @AppStorage(UserDefaultsKeys.Editor.tabSize) private var tabSize: Int = 4
    @AppStorage(UserDefaultsKeys.Editor.useTabs) private var useTabs: Bool = false
    @AppStorage(UserDefaultsKeys.Editor.autoCloseBrackets) private var autoCloseBrackets: Bool = true
    @AppStorage(UserDefaultsKeys.Editor.autoCloseQuotes) private var autoCloseQuotes: Bool = true
    @AppStorage(UserDefaultsKeys.Editor.bracketPairHighlight) private var bracketPairHighlight: Bool = true

    @AppStorage(UserDefaultsKeys.Editor.lineWrap) private var lineWrap: Bool = true
    @AppStorage(UserDefaultsKeys.Editor.showRuler) private var showRuler: Bool = false
    @AppStorage(UserDefaultsKeys.Editor.rulerColumn) private var rulerColumn: Int = 80
    @AppStorage(UserDefaultsKeys.Editor.highlightCurrentLine) private var highlightCurrentLine: Bool = true
    @AppStorage(UserDefaultsKeys.Editor.showIndentGuides) private var showIndentGuides: Bool = false

    @AppStorage(UserDefaultsKeys.Editor.formatOnSave) private var formatOnSave: Bool = false
    @AppStorage(UserDefaultsKeys.Editor.jsonSortKeys) private var jsonSortKeys: Bool = false
    @AppStorage(UserDefaultsKeys.Editor.trimTrailingWhitespace) private var trimTrailingWhitespace: Bool = false
    @AppStorage(UserDefaultsKeys.Editor.renderWhitespace) private var renderWhitespace: String = "none"
    @AppStorage(UserDefaultsKeys.Editor.topPadding) private var topPadding: Double = 6.0
    @AppStorage(UserDefaultsKeys.Editor.scrollPastEnd) private var scrollPastEnd: Bool = true

    @AppStorage(UserDefaultsKeys.FileBrowser.showHiddenFiles) private var showDotfiles: Bool = true

    var body: some View {
        Form {
            Section(L10n("settings.editor.appearance")) {
                Picker(L10n("settings.editor.theme"), selection: $themeRaw) {
                    ForEach(EditorTheme.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }

                Picker(L10n("settings.editor.font"), selection: $fontFamily) {
                    Section(L10n("settings.editor.font.system")) {
                        ForEach(Self.systemFonts, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    if !Self.cachedInstalledFonts.isEmpty {
                        let installed = Self.cachedInstalledFonts
                        Section(L10n("settings.editor.font.installed")) {
                            ForEach(installed, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }

                HStack {
                    Text(L10n("settings.editor.fontSize"))
                    Spacer()
                    Text("\(Int(fontSize))pt")
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(width: 46, alignment: .trailing)
                    Stepper("", value: $fontSize, in: 8...32, step: 1)
                        .labelsHidden()
                }

                HStack {
                    Text(L10n("settings.editor.markdownPreviewFontSize"))
                    Spacer()
                    Text("\(Int(markdownPreviewFontSize))pt")
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(width: 46, alignment: .trailing)
                    Stepper("", value: $markdownPreviewFontSize, in: 10...32, step: 1)
                        .labelsHidden()
                }

                HStack {
                    Text(L10n("settings.editor.lineSpacing"))
                    Spacer()
                    Slider(value: $lineSpacing, in: 0.0...20.0, step: 0.5)
                        .frame(width: 120)
                    Text(String(format: "%.1fpt", lineSpacing))
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(width: 46, alignment: .trailing)
                }

                HStack {
                    Text(L10n("settings.editor.letterSpacing"))
                    Spacer()
                    Slider(value: $letterSpacing, in: -1.0...5.0, step: 0.1)
                        .frame(width: 120)
                    Text(String(format: "%.1f", letterSpacing))
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Section(L10n("settings.editor.editing")) {
                Picker(L10n("settings.editor.tabSize"), selection: $tabSize) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)

                Toggle(L10n("settings.editor.useTabs"), isOn: $useTabs)

                Toggle(L10n("settings.editor.autoCloseBrackets"), isOn: $autoCloseBrackets)

                Toggle(L10n("settings.editor.autoCloseQuotes"), isOn: $autoCloseQuotes)

                Toggle(L10n("settings.editor.bracketPairHighlight"), isOn: $bracketPairHighlight)
            }

            Section(L10n("settings.editor.display")) {
                Toggle(L10n("settings.editor.lineWrap"), isOn: $lineWrap)

                Toggle(L10n("settings.editor.highlightCurrentLine"), isOn: $highlightCurrentLine)

                Toggle(L10n("settings.editor.showIndentGuides"), isOn: $showIndentGuides)

                Picker(L10n("settings.editor.renderWhitespace"), selection: $renderWhitespace) {
                    Text(L10n("settings.editor.renderWhitespace.none")).tag("none")
                    Text(L10n("settings.editor.renderWhitespace.boundary")).tag("boundary")
                    Text(L10n("settings.editor.renderWhitespace.trailing")).tag("trailing")
                    Text(L10n("settings.editor.renderWhitespace.all")).tag("all")
                }

                Toggle(L10n("settings.editor.showRuler"), isOn: $showRuler)

                if showRuler {
                    Picker(L10n("settings.editor.rulerColumn"), selection: $rulerColumn) {
                        Text("80").tag(80)
                        Text("100").tag(100)
                        Text("120").tag(120)
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(L10n("settings.editor.scrollPastEnd"), isOn: $scrollPastEnd)

                HStack {
                    Text(L10n("settings.editor.topPadding"))
                    Spacer()
                    Slider(value: $topPadding, in: 0...60, step: 2)
                        .frame(width: 120)
                    Text("\(Int(topPadding))pt")
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            Section(L10n("settings.editor.fileBrowser")) {
                Toggle(L10n("settings.editor.showDotfiles"), isOn: $showDotfiles)
            }

            Section(L10n("settings.editor.formatting")) {
                Toggle(L10n("settings.editor.formatOnSave"), isOn: $formatOnSave)

                Toggle(L10n("settings.editor.jsonSortKeys"), isOn: $jsonSortKeys)

                Toggle(L10n("settings.editor.trimTrailingWhitespace"), isOn: $trimTrailingWhitespace)
            }

        }
        .formStyle(.grouped)
        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.actionPrimary))
        .tint(DesignSystem.Colors.actionPrimary)
    }
}
