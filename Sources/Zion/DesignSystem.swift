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

        // Danger zone
        static let dangerBackground = Color.red.opacity(0.06)
        static let dangerBorder = Color.red.opacity(0.25)
    }

    struct Spacing {
        static let cardPadding: CGFloat = 12
        static let sectionGap: CGFloat = 20
        static let cardCornerRadius: CGFloat = 14
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
    }
}
