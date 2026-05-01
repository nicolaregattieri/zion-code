import Foundation
import SwiftUI
import AppKit

enum EditorTheme: String, CaseIterable, Identifiable {
    case dracula, cityLights, githubLight, catppuccinMocha, oneDarkPro, tokyoNight, synthwave
    case lunarPinkSatellite, neonGreenDarkTerminal, macOSModernDarkVenturaXcode, everforestProLight, colorblindLight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dracula: return L10n("theme.dracula")
        case .cityLights: return L10n("theme.cityLights")
        case .githubLight: return L10n("theme.githubLight")
        case .catppuccinMocha: return L10n("theme.catppuccinMocha")
        case .oneDarkPro: return L10n("theme.oneDarkPro")
        case .tokyoNight: return L10n("theme.tokyoNight")
        case .synthwave: return L10n("theme.synthwave")
        case .lunarPinkSatellite: return L10n("theme.lunarPinkSatellite")
        case .neonGreenDarkTerminal: return L10n("theme.neonGreenDarkTerminal")
        case .macOSModernDarkVenturaXcode: return L10n("theme.macOSModernDarkVenturaXcode")
        case .everforestProLight: return L10n("theme.everforestProLight")
        case .colorblindLight: return L10n("theme.colorblindLight")
        }
    }
    var isDark: Bool { true } // GOLDEN RULE — always true for ALL themes

    /// Visual appearance — true light theme (light bg, dark text)
    var isLightAppearance: Bool {
        switch self {
        case .githubLight, .everforestProLight, .colorblindLight: return true
        case .dracula, .cityLights, .catppuccinMocha, .oneDarkPro, .tokyoNight, .synthwave,
             .lunarPinkSatellite, .neonGreenDarkTerminal, .macOSModernDarkVenturaXcode:
            return false
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

    init(
        backgroundHex: UInt32,
        textHex: UInt32,
        keywordHex: UInt32,
        typeHex: UInt32,
        stringHex: UInt32,
        commentHex: UInt32,
        numberHex: UInt32
    ) {
        self.init(
            background: Self.rgb(backgroundHex),
            text: Self.rgb(textHex),
            keyword: Self.rgb(keywordHex),
            type: Self.rgb(typeHex),
            string: Self.rgb(stringHex),
            comment: Self.rgb(commentHex),
            number: Self.rgb(numberHex)
        )
    }

    private static func rgb(_ hex: UInt32) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        (
            r: CGFloat((hex >> 16) & 0xFF) / 255,
            g: CGFloat((hex >> 8) & 0xFF) / 255,
            b: CGFloat(hex & 0xFF) / 255
        )
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
        case .lunarPinkSatellite: return DesignSystem.EditorThemes.lunarPinkSatellite
        case .neonGreenDarkTerminal: return DesignSystem.EditorThemes.neonGreenDarkTerminal
        case .macOSModernDarkVenturaXcode: return DesignSystem.EditorThemes.macOSModernDarkVenturaXcode
        case .everforestProLight: return DesignSystem.EditorThemes.everforestProLight
        case .colorblindLight: return DesignSystem.EditorThemes.colorblindLight
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
        case .lunarPinkSatellite: return DesignSystem.TerminalPalettes.lunarPinkSatellite
        case .neonGreenDarkTerminal: return DesignSystem.TerminalPalettes.neonGreenDarkTerminal
        case .macOSModernDarkVenturaXcode: return DesignSystem.TerminalPalettes.macOSModernDarkVenturaXcode
        case .everforestProLight: return DesignSystem.TerminalPalettes.everforestProLight
        case .colorblindLight: return DesignSystem.TerminalPalettes.colorblindLight
        }
    }
}
