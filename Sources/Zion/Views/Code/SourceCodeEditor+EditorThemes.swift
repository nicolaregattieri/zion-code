import AppKit

extension SourceCodeEditor {

    func getEditorColors(for theme: EditorTheme) -> EditorColors {
        switch theme {
        case .dracula:
            return EditorColors(
                background: NSColor(srgbRed: 0.157, green: 0.165, blue: 0.212, alpha: 1.0),
                text: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.949, alpha: 1.0),
                keyword: NSColor(srgbRed: 1.0, green: 0.475, blue: 0.776, alpha: 1.0),
                type: NSColor(srgbRed: 0.545, green: 0.914, blue: 0.992, alpha: 1.0),
                string: NSColor(srgbRed: 0.945, green: 0.980, blue: 0.549, alpha: 1.0),
                comment: NSColor(srgbRed: 0.384, green: 0.447, blue: 0.643, alpha: 1.0),
                number: NSColor(srgbRed: 0.741, green: 0.576, blue: 0.976, alpha: 1.0),
                call: NSColor(srgbRed: 0.314, green: 0.980, blue: 0.482, alpha: 1.0)
            )
        case .cityLights:
            return EditorColors(
                background: NSColor(srgbRed: 0.114, green: 0.145, blue: 0.173, alpha: 1.0),
                text: NSColor(srgbRed: 0.443, green: 0.549, blue: 0.631, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.325, green: 0.604, blue: 0.988, alpha: 1.0),
                type: NSColor(srgbRed: 0.0, green: 0.733, blue: 0.824, alpha: 1.0),
                string: NSColor(srgbRed: 0.545, green: 0.831, blue: 0.612, alpha: 1.0),
                comment: NSColor(srgbRed: 0.255, green: 0.314, blue: 0.369, alpha: 1.0),
                number: NSColor(srgbRed: 0.886, green: 0.494, blue: 0.553, alpha: 1.0),
                call: NSColor(srgbRed: 0.325, green: 0.604, blue: 0.988, alpha: 1.0)
            )
        case .githubLight:
            return EditorColors(
                background: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
                text: NSColor(srgbRed: 0.141, green: 0.161, blue: 0.180, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.843, green: 0.227, blue: 0.286, alpha: 1.0),
                type: NSColor(srgbRed: 0.435, green: 0.259, blue: 0.757, alpha: 1.0),
                string: NSColor(srgbRed: 0.012, green: 0.184, blue: 0.384, alpha: 1.0),
                comment: NSColor(srgbRed: 0.416, green: 0.451, blue: 0.490, alpha: 1.0),
                number: NSColor(srgbRed: 0.0, green: 0.361, blue: 0.773, alpha: 1.0),
                call: NSColor(srgbRed: 0.435, green: 0.259, blue: 0.757, alpha: 1.0)
            )
        case .catppuccinMocha:
            return EditorColors(
                background: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1.0),
                text: NSColor(srgbRed: 0.804, green: 0.839, blue: 0.957, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.796, green: 0.651, blue: 0.969, alpha: 1.0),
                type: NSColor(srgbRed: 0.537, green: 0.706, blue: 0.980, alpha: 1.0),
                string: NSColor(srgbRed: 0.651, green: 0.890, blue: 0.631, alpha: 1.0),
                comment: NSColor(srgbRed: 0.424, green: 0.439, blue: 0.525, alpha: 1.0),
                number: NSColor(srgbRed: 0.980, green: 0.702, blue: 0.529, alpha: 1.0),
                call: NSColor(srgbRed: 0.537, green: 0.706, blue: 0.980, alpha: 1.0)
            )
        case .oneDarkPro:
            return EditorColors(
                background: NSColor(srgbRed: 0.157, green: 0.173, blue: 0.204, alpha: 1.0),
                text: NSColor(srgbRed: 0.671, green: 0.698, blue: 0.749, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.776, green: 0.471, blue: 0.867, alpha: 1.0),
                type: NSColor(srgbRed: 0.898, green: 0.753, blue: 0.482, alpha: 1.0),
                string: NSColor(srgbRed: 0.596, green: 0.765, blue: 0.475, alpha: 1.0),
                comment: NSColor(srgbRed: 0.361, green: 0.388, blue: 0.439, alpha: 1.0),
                number: NSColor(srgbRed: 0.820, green: 0.604, blue: 0.400, alpha: 1.0),
                call: NSColor(srgbRed: 0.380, green: 0.686, blue: 0.937, alpha: 1.0)
            )
        case .tokyoNight:
            return EditorColors(
                background: NSColor(srgbRed: 0.102, green: 0.106, blue: 0.149, alpha: 1.0),
                text: NSColor(srgbRed: 0.663, green: 0.694, blue: 0.839, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.733, green: 0.604, blue: 0.969, alpha: 1.0),
                type: NSColor(srgbRed: 0.165, green: 0.765, blue: 0.871, alpha: 1.0),
                string: NSColor(srgbRed: 0.620, green: 0.808, blue: 0.416, alpha: 1.0),
                comment: NSColor(srgbRed: 0.337, green: 0.373, blue: 0.537, alpha: 1.0),
                number: NSColor(srgbRed: 1.0, green: 0.620, blue: 0.392, alpha: 1.0),
                call: NSColor(srgbRed: 0.478, green: 0.635, blue: 0.969, alpha: 1.0)
            )
        case .synthwave:
            return EditorColors(
                background: NSColor(srgbRed: 0.149, green: 0.137, blue: 0.208, alpha: 1.0),
                text: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
                keyword: NSColor(srgbRed: 0.996, green: 0.871, blue: 0.365, alpha: 1.0),
                type: NSColor(srgbRed: 0.212, green: 0.976, blue: 0.965, alpha: 1.0),
                string: NSColor(srgbRed: 1.0, green: 0.545, blue: 0.224, alpha: 1.0),
                comment: NSColor(srgbRed: 0.518, green: 0.545, blue: 0.741, alpha: 1.0),
                number: NSColor(srgbRed: 0.976, green: 0.494, blue: 0.447, alpha: 1.0),
                call: NSColor(srgbRed: 0.447, green: 0.945, blue: 0.722, alpha: 1.0)
            )
        }
    }
}
