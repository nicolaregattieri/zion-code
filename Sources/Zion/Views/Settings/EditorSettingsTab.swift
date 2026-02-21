import SwiftUI

struct EditorSettingsTab: View {
    @AppStorage("editor.theme") private var themeRaw: String = EditorTheme.dracula.rawValue
    @AppStorage("editor.fontFamily") private var fontFamily: String = "SF Mono"
    @AppStorage("editor.fontSize") private var fontSize: Double = 13.0
    @AppStorage("editor.lineSpacing") private var lineSpacing: Double = 1.2
    @AppStorage("editor.letterSpacing") private var letterSpacing: Double = 0.0

    @AppStorage("editor.tabSize") private var tabSize: Int = 4
    @AppStorage("editor.useTabs") private var useTabs: Bool = false
    @AppStorage("editor.autoCloseBrackets") private var autoCloseBrackets: Bool = true
    @AppStorage("editor.autoCloseQuotes") private var autoCloseQuotes: Bool = true
    @AppStorage("editor.bracketPairHighlight") private var bracketPairHighlight: Bool = true

    @AppStorage("editor.lineWrap") private var lineWrap: Bool = true
    @AppStorage("editor.showRuler") private var showRuler: Bool = false
    @AppStorage("editor.rulerColumn") private var rulerColumn: Int = 80
    @AppStorage("editor.highlightCurrentLine") private var highlightCurrentLine: Bool = true
    @AppStorage("editor.showIndentGuides") private var showIndentGuides: Bool = false

    var body: some View {
        Form {
            Section(L10n("settings.editor.appearance")) {
                Picker(L10n("settings.editor.theme"), selection: $themeRaw) {
                    ForEach(EditorTheme.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }

                Picker(L10n("settings.editor.font"), selection: $fontFamily) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                    Text("Courier").tag("Courier")
                    Text("Fira Code").tag("Fira Code")
                    Text("JetBrains Mono").tag("JetBrains Mono")
                }

                HStack {
                    Text(L10n("settings.editor.fontSize"))
                    Spacer()
                    Stepper(value: $fontSize, in: 8...32, step: 1) {
                        Text("\(Int(fontSize))pt")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                HStack {
                    Text(L10n("settings.editor.lineSpacing"))
                    Spacer()
                    Slider(value: $lineSpacing, in: 0.0...5.0, step: 0.1)
                        .frame(width: 120)
                    Text(String(format: "%.1fx", lineSpacing))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text(L10n("settings.editor.letterSpacing"))
                    Spacer()
                    Slider(value: $letterSpacing, in: -1.0...5.0, step: 0.1)
                        .frame(width: 120)
                    Text(String(format: "%.1f", letterSpacing))
                        .font(.system(size: 11, design: .monospaced))
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

                Toggle(L10n("settings.editor.showRuler"), isOn: $showRuler)

                if showRuler {
                    Picker(L10n("settings.editor.rulerColumn"), selection: $rulerColumn) {
                        Text("80").tag(80)
                        Text("100").tag(100)
                        Text("120").tag(120)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .formStyle(.grouped)
    }
}
