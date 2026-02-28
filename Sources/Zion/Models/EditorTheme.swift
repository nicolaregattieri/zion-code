import Foundation
import SwiftUI
import AppKit

enum EditorTheme: String, CaseIterable, Identifiable {
    case dracula, cityLights, githubLight, catppuccinMocha, oneDarkPro, tokyoNight, synthwave
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dracula: return "Dracula"
        case .cityLights: return "City Lights"
        case .githubLight: return "GitHub Light"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .oneDarkPro: return "One Dark Pro"
        case .tokyoNight: return "Tokyo Night"
        case .synthwave: return "SynthWave '84"
        }
    }
    var isDark: Bool { true } // GOLDEN RULE — always true for ALL themes

    /// Visual appearance — true light theme (light bg, dark text)
    var isLightAppearance: Bool {
        switch self {
        case .githubLight: return true
        case .dracula, .cityLights, .catppuccinMocha, .oneDarkPro, .tokyoNight, .synthwave: return false
        }
    }
}

// MARK: - Theme Colors

struct ThemeColors {
    let background: Color
    let text: Color
    let keyword: Color
    let type: Color
    let string: Color
    let comment: Color
    let number: Color

    // Concrete sRGB NSColors for AppKit text rendering
    let nsBackground: NSColor
    let nsText: NSColor
    let nsKeyword: NSColor
    let nsType: NSColor
    let nsString: NSColor
    let nsComment: NSColor
    let nsNumber: NSColor

    init(
        background: (r: CGFloat, g: CGFloat, b: CGFloat),
        text: (r: CGFloat, g: CGFloat, b: CGFloat),
        keyword: (r: CGFloat, g: CGFloat, b: CGFloat),
        type: (r: CGFloat, g: CGFloat, b: CGFloat),
        string: (r: CGFloat, g: CGFloat, b: CGFloat),
        comment: (r: CGFloat, g: CGFloat, b: CGFloat),
        number: (r: CGFloat, g: CGFloat, b: CGFloat)
    ) {
        self.background = Color(red: background.r, green: background.g, blue: background.b)
        self.text = Color(red: text.r, green: text.g, blue: text.b)
        self.keyword = Color(red: keyword.r, green: keyword.g, blue: keyword.b)
        self.type = Color(red: type.r, green: type.g, blue: type.b)
        self.string = Color(red: string.r, green: string.g, blue: string.b)
        self.comment = Color(red: comment.r, green: comment.g, blue: comment.b)
        self.number = Color(red: number.r, green: number.g, blue: number.b)

        self.nsBackground = NSColor(srgbRed: background.r, green: background.g, blue: background.b, alpha: 1)
        self.nsText = NSColor(srgbRed: text.r, green: text.g, blue: text.b, alpha: 1)
        self.nsKeyword = NSColor(srgbRed: keyword.r, green: keyword.g, blue: keyword.b, alpha: 1)
        self.nsType = NSColor(srgbRed: type.r, green: type.g, blue: type.b, alpha: 1)
        self.nsString = NSColor(srgbRed: string.r, green: string.g, blue: string.b, alpha: 1)
        self.nsComment = NSColor(srgbRed: comment.r, green: comment.g, blue: comment.b, alpha: 1)
        self.nsNumber = NSColor(srgbRed: number.r, green: number.g, blue: number.b, alpha: 1)
    }
}

// MARK: - Theme → Colors mapping

extension EditorTheme {
    var colors: ThemeColors {
        switch self {
        case .dracula: return DesignSystem.EditorThemes.dracula
        case .cityLights: return DesignSystem.EditorThemes.cityLights
        case .githubLight: return DesignSystem.EditorThemes.githubLight
        case .catppuccinMocha: return DesignSystem.EditorThemes.catppuccinMocha
        case .oneDarkPro: return DesignSystem.EditorThemes.oneDarkPro
        case .tokyoNight: return DesignSystem.EditorThemes.tokyoNight
        case .synthwave: return DesignSystem.EditorThemes.synthwave
        }
    }

    var terminalPalette: TerminalPalette {
        switch self {
        case .dracula: return DesignSystem.TerminalPalettes.dracula
        case .cityLights: return DesignSystem.TerminalPalettes.cityLights
        case .githubLight: return DesignSystem.TerminalPalettes.githubLight
        case .catppuccinMocha: return DesignSystem.TerminalPalettes.catppuccinMocha
        case .oneDarkPro: return DesignSystem.TerminalPalettes.oneDarkPro
        case .tokyoNight: return DesignSystem.TerminalPalettes.tokyoNight
        case .synthwave: return DesignSystem.TerminalPalettes.synthwave
        }
    }
}
