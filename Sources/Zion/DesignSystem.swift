import SwiftUI
import AppKit
@preconcurrency import SwiftTerm

struct TerminalPalette {
    let foreground: NSColor
    let background: NSColor
    let cursorColor: NSColor
    let cursorTextColor: NSColor
    let selectionBackground: NSColor
    let selectionForeground: NSColor
    let ansiColors: [SwiftTerm.Color] // 16 elements

    let backgroundSwiftUI: SwiftUI.Color
    let accentSwiftUI: SwiftUI.Color // ANSI green for tab accent
}

struct DesignSystem {
    struct Colors {
        // App background with transparency for glassmorphism
        static let background = Color(NSColor.windowBackgroundColor)
        static let glassBackground = Color.white.opacity(0.05)
        static let glassBorder = Color.white.opacity(0.12)

        // Glass tokens (consistent across all cards/components)
        static let glassBorderDark = Color.white.opacity(0.12)
        static let glassBorderLight = Color.white.opacity(0.55)
        static let glassHover = Color.white.opacity(0.08)
        static let glassSubtle = Color.white.opacity(0.04)
        static let glassOverlay = Color.black.opacity(0.15)
        static let glassInset = Color.black.opacity(0.2)
        static let glassStroke = Color.white.opacity(0.1)
        static let glassMinimal = Color.white.opacity(0.03)
        static let glassElevated = Color.white.opacity(0.06)

        // Brand colors
        static let primary = Color.purple
        static let secondary = Color.indigo
        static let accent = Color.cyan

        // Semantic status
        static let error = Color.red
        static let warning = Color.orange
        static let success = Color.green
        static let info = Color.blue

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.7)

        // Selection & interaction states
        static let selectionBackground = Color.accentColor.opacity(0.15)
        static let selectionBorder = Color.accentColor.opacity(0.7)
        static let hoverAccent = Color.accentColor.opacity(0.35)

        // Status backgrounds (consistent scale)
        static let statusGreenBg = Color.green.opacity(0.12)
        static let statusOrangeBg = Color.orange.opacity(0.12)
        static let statusBlueBg = Color.blue.opacity(0.12)
        static let statusYellowBg = Color.yellow.opacity(0.15)

        // Shadow tokens
        static let shadowDark = Color.black.opacity(0.14)
        static let shadowLight = Color.black.opacity(0.08)

        // Danger zone
        static let dangerBackground = Color.pink.opacity(0.06)
        static let dangerBorder = Color.pink.opacity(0.25)

        // Lane color palette (shared between graph and commit cards)
        static let lanePalette: [SwiftUI.Color] = [
            .blue, .pink, .green, .orange, .teal, .purple, .mint, .indigo, .yellow, .cyan, .brown, .gray
        ]

        static func laneColor(forKey key: Int) -> SwiftUI.Color {
            if key < lanePalette.count { return lanePalette[key] }
            let hue = Double((key * 137) % 360) / 360.0
            return SwiftUI.Color(hue: hue, saturation: 0.80, brightness: 0.95)
        }
    }

    struct Spacing {
        static let cardPadding: CGFloat = 12
        static let sectionGap: CGFloat = 20

        // Corner radii (4 tiers)
        static let cardCornerRadius: CGFloat = 14       // GlassCards, commit row cards
        static let containerCornerRadius: CGFloat = 12  // Toolbar groups, overlays
        static let elementCornerRadius: CGFloat = 8     // Buttons, search bars, inline items
        static let smallCornerRadius: CGFloat = 6       // Tags, tiny pills, code blocks
    }

    // MARK: - Typography Tokens

    struct Typography {
        // Headings
        static let screenTitle = Font.system(size: 28, weight: .bold)
        static let sheetTitle = Font.system(size: 16, weight: .semibold)
        static let sectionTitle = Font.system(size: 13, weight: .bold)

        // Body
        static let body = Font.system(size: 12)
        static let bodyMedium = Font.system(size: 11, weight: .medium)

        // Labels & Meta
        static let label = Font.system(size: 10)
        static let labelBold = Font.system(size: 10, weight: .bold)
        static let meta = Font.system(size: 9)
        static let metaBold = Font.system(size: 9, weight: .bold)
        static let micro = Font.system(size: 8, weight: .bold)

        // Monospaced
        static let monoBody = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 11, design: .monospaced)
        static let monoLabel = Font.system(size: 10, design: .monospaced)
        static let monoLabelBold = Font.system(size: 10, weight: .bold, design: .monospaced)
        static let monoMeta = Font.system(size: 9, design: .monospaced)
    }

    // MARK: - Icon Size Tokens

    struct IconSize {
        // Font sizes by role
        static let sectionHeader = Font.system(size: 13, weight: .semibold)
        static let toolbar = Font.system(size: 11, weight: .medium)
        static let inline = Font.system(size: 10)
        static let meta = Font.system(size: 9)
        static let tiny = Font.system(size: 8)

        // Tap target frames
        static let terminalToolbarFrame = CGSize(width: 28, height: 24)
        static let editorToolbarFrame = CGSize(width: 26, height: 22)
        static let standardFrame = CGSize(width: 24, height: 24)
        static let compactFrame = CGSize(width: 20, height: 20)
        static let smallFrame = CGSize(width: 16, height: 16)
        static let statusFrame = CGSize(width: 32, height: 32)
    }

    // MARK: - Interactive State Tokens

    struct Interactive {
        static let hoverBackground = Colors.glassHover
        static let selectionBackground = Colors.selectionBackground
        static let selectionBorder = Colors.selectionBorder
        static let pressedBackground = Color.white.opacity(0.12)
    }

    struct EditorThemes {
        static let dracula = ThemeColors(
            background: (r: 0.16, g: 0.16, b: 0.21),
            text: (r: 0.97, g: 0.97, b: 0.95),
            keyword: (r: 1.0, g: 0.48, b: 0.77),
            type: (r: 0.54, g: 0.91, b: 0.99),
            string: (r: 0.95, g: 0.99, b: 0.47),
            comment: (r: 0.38, g: 0.41, b: 0.53),
            number: (r: 0.74, g: 0.57, b: 0.97)
        )

        static let cityLights = ThemeColors(
            background: (r: 0.11, g: 0.15, b: 0.17),
            text: (r: 0.44, g: 0.55, b: 0.63),
            keyword: (r: 0.33, g: 0.60, b: 0.99),
            type: (r: 0.0, g: 0.73, b: 0.82),
            string: (r: 0.55, g: 0.83, b: 0.61),
            comment: (r: 0.25, g: 0.31, b: 0.37),
            number: (r: 0.89, g: 0.49, b: 0.55)
        )

        static let githubLight = ThemeColors(
            background: (r: 1.0, g: 1.0, b: 1.0),
            text: (r: 0.141, g: 0.161, b: 0.180),
            keyword: (r: 0.843, g: 0.227, b: 0.286),
            type: (r: 0.435, g: 0.259, b: 0.757),
            string: (r: 0.012, g: 0.184, b: 0.384),
            comment: (r: 0.416, g: 0.451, b: 0.490),
            number: (r: 0.0, g: 0.361, b: 0.773)
        )

        // Catppuccin Mocha — pastel dark, community-driven
        static let catppuccinMocha = ThemeColors(
            background: (r: 0.118, g: 0.118, b: 0.180),  // #1e1e2e
            text: (r: 0.804, g: 0.839, b: 0.957),        // #cdd6f4
            keyword: (r: 0.796, g: 0.651, b: 0.969),      // #cba6f7 mauve
            type: (r: 0.537, g: 0.706, b: 0.980),         // #89b4fa blue
            string: (r: 0.651, g: 0.890, b: 0.631),       // #a6e3a1 green
            comment: (r: 0.424, g: 0.439, b: 0.525),      // #6c7086 overlay0
            number: (r: 0.980, g: 0.702, b: 0.529)        // #fab387 peach
        )

        // One Dark Pro — warm-neutral dark, most popular VS Code theme
        static let oneDarkPro = ThemeColors(
            background: (r: 0.157, g: 0.173, b: 0.204),   // #282c34
            text: (r: 0.671, g: 0.698, b: 0.749),         // #abb2bf
            keyword: (r: 0.776, g: 0.471, b: 0.867),      // #c678dd purple
            type: (r: 0.898, g: 0.753, b: 0.482),         // #e5c07b yellow
            string: (r: 0.596, g: 0.765, b: 0.475),       // #98c379 green
            comment: (r: 0.361, g: 0.388, b: 0.439),      // #5c6370 gray
            number: (r: 0.820, g: 0.604, b: 0.400)        // #d19a66 orange
        )

        // Tokyo Night — indigo dark, "screenshot theme"
        static let tokyoNight = ThemeColors(
            background: (r: 0.102, g: 0.106, b: 0.149),   // #1a1b26
            text: (r: 0.663, g: 0.694, b: 0.839),         // #a9b1d6
            keyword: (r: 0.733, g: 0.604, b: 0.969),      // #bb9af7 purple
            type: (r: 0.165, g: 0.765, b: 0.871),         // #2ac3de cyan
            string: (r: 0.620, g: 0.808, b: 0.416),       // #9ece6a green
            comment: (r: 0.337, g: 0.373, b: 0.537),      // #565f89 muted
            number: (r: 1.0, g: 0.620, b: 0.392)          // #ff9e64 orange
        )
    }

    // MARK: - Terminal Palettes

    private static func stColor(_ h: UInt32) -> SwiftTerm.Color {
        let r = UInt16((h >> 16) & 0xFF) * 257
        let g = UInt16((h >> 8) & 0xFF) * 257
        let b = UInt16(h & 0xFF) * 257
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }

    private static func nsHex(_ h: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255,
                green: CGFloat((h >> 8) & 0xFF) / 255,
                blue: CGFloat(h & 0xFF) / 255, alpha: 1)
    }

    private static func swHex(_ h: UInt32) -> SwiftUI.Color {
        SwiftUI.Color(red: Double((h >> 16) & 0xFF) / 255,
                      green: Double((h >> 8) & 0xFF) / 255,
                      blue: Double(h & 0xFF) / 255)
    }

    struct TerminalPalettes {
        static let dracula = TerminalPalette(
            foreground: nsHex(0xf8f8f2),
            background: nsHex(0x282a36),
            cursorColor: nsHex(0xf8f8f2),
            cursorTextColor: nsHex(0x282a36),
            selectionBackground: nsHex(0x44475a),
            selectionForeground: nsHex(0xf8f8f2),
            ansiColors: [
                stColor(0x21222c), stColor(0xff5555), stColor(0x50fa7b), stColor(0xf1fa8c),
                stColor(0xbd93f9), stColor(0xff79c6), stColor(0x8be9fd), stColor(0xf8f8f2),
                stColor(0x6272a4), stColor(0xff6e6e), stColor(0x69ff94), stColor(0xffffa5),
                stColor(0xd6acff), stColor(0xff92df), stColor(0xa4ffff), stColor(0xffffff),
            ],
            backgroundSwiftUI: swHex(0x282a36),
            accentSwiftUI: swHex(0x50fa7b)
        )

        static let catppuccinMocha = TerminalPalette(
            foreground: nsHex(0xcdd6f4),
            background: nsHex(0x1e1e2e),
            cursorColor: nsHex(0xf5e0dc),
            cursorTextColor: nsHex(0x1e1e2e),
            selectionBackground: nsHex(0x585b70),
            selectionForeground: nsHex(0xcdd6f4),
            ansiColors: [
                stColor(0x45475a), stColor(0xf38ba8), stColor(0xa6e3a1), stColor(0xf9e2af),
                stColor(0x89b4fa), stColor(0xf5c2e7), stColor(0x94e2d5), stColor(0xa6adc8),
                stColor(0x585b70), stColor(0xf37799), stColor(0x89d88b), stColor(0xebd391),
                stColor(0x74a8fc), stColor(0xf2aede), stColor(0x6bd7ca), stColor(0xbac2de),
            ],
            backgroundSwiftUI: swHex(0x1e1e2e),
            accentSwiftUI: swHex(0xa6e3a1)
        )

        static let cityLights = TerminalPalette(
            foreground: nsHex(0x708ca0),
            background: nsHex(0x1d252c),
            cursorColor: nsHex(0x528bff),
            cursorTextColor: nsHex(0x1d252c),
            selectionBackground: nsHex(0x28323b),
            selectionForeground: nsHex(0x708ca0),
            ansiColors: [
                stColor(0x333f4a), stColor(0xd95468), stColor(0x8bd49c), stColor(0xebbf83),
                stColor(0x539afc), stColor(0xb62d65), stColor(0x70e1e8), stColor(0xa0b3c5),
                stColor(0x41505e), stColor(0xd95468), stColor(0x8bd49c), stColor(0xebbf83),
                stColor(0x539afc), stColor(0xb62d65), stColor(0x70e1e8), stColor(0xc7d5e0),
            ],
            backgroundSwiftUI: swHex(0x1d252c),
            accentSwiftUI: swHex(0x8bd49c)
        )

        static let githubLight = TerminalPalette(
            foreground: nsHex(0x24292e),
            background: nsHex(0xffffff),
            cursorColor: nsHex(0x044289),
            cursorTextColor: nsHex(0xffffff),
            selectionBackground: nsHex(0xc8e1ff),
            selectionForeground: nsHex(0x24292e),
            ansiColors: [
                stColor(0x24292e), stColor(0xd73a49), stColor(0x28a745), stColor(0xdbab09),
                stColor(0x0366d6), stColor(0x5a32a3), stColor(0x0598bc), stColor(0x6a737d),
                stColor(0x959da5), stColor(0xcb2431), stColor(0x22863a), stColor(0xb08800),
                stColor(0x005cc5), stColor(0x5a32a3), stColor(0x3192aa), stColor(0xd1d5da),
            ],
            backgroundSwiftUI: swHex(0xffffff),
            accentSwiftUI: swHex(0x28a745)
        )

        static let oneDarkPro = TerminalPalette(
            foreground: nsHex(0xabb2bf),
            background: nsHex(0x282c34),
            cursorColor: nsHex(0x528bff),
            cursorTextColor: nsHex(0x282c34),
            selectionBackground: nsHex(0x3e4451),
            selectionForeground: nsHex(0xabb2bf),
            ansiColors: [
                stColor(0x282c34), stColor(0xe06c75), stColor(0x98c379), stColor(0xe5c07b),
                stColor(0x61afef), stColor(0xc678dd), stColor(0x56b6c2), stColor(0xabb2bf),
                stColor(0x5c6370), stColor(0xe06c75), stColor(0x98c379), stColor(0xe5c07b),
                stColor(0x61afef), stColor(0xc678dd), stColor(0x56b6c2), stColor(0xffffff),
            ],
            backgroundSwiftUI: swHex(0x282c34),
            accentSwiftUI: swHex(0x98c379)
        )

        static let tokyoNight = TerminalPalette(
            foreground: nsHex(0xa9b1d6),
            background: nsHex(0x1a1b26),
            cursorColor: nsHex(0xc0caf5),
            cursorTextColor: nsHex(0x1a1b26),
            selectionBackground: nsHex(0x33467c),
            selectionForeground: nsHex(0xa9b1d6),
            ansiColors: [
                stColor(0x15161e), stColor(0xf7768e), stColor(0x9ece6a), stColor(0xe0af68),
                stColor(0x7aa2f7), stColor(0xbb9af7), stColor(0x7dcfff), stColor(0xa9b1d6),
                stColor(0x414868), stColor(0xf7768e), stColor(0x9ece6a), stColor(0xe0af68),
                stColor(0x7aa2f7), stColor(0xbb9af7), stColor(0x7dcfff), stColor(0xc0caf5),
            ],
            backgroundSwiftUI: swHex(0x1a1b26),
            accentSwiftUI: swHex(0x9ece6a)
        )
    }
}

extension View {
    func cursorArrow() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.arrow.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
