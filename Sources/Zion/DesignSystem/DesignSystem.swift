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
    struct Layout {
        static let centeredContentMaxWidth: CGFloat = 920
        static let operationsContentMaxWidth: CGFloat = 1280
        static let onboardingStepContentMaxWidth: CGFloat = 680

        // Window
        static let windowMinWidth: CGFloat = 900
        static let windowMinHeight: CGFloat = 640

        // Sidebar
        static let sidebarMinWidth: CGFloat = 260

        // CodeScreen splits
        static let fileBrowserMinWidth: CGFloat = 160
        static let editorMinWidth: CGFloat = 300
        static let editorTerminalMinPane: CGFloat = 100
        static let markdownPreviewMinLeading: CGFloat = 260
        static let markdownPreviewMinTrailing: CGFloat = 240

        // GraphScreen splits
        static let commitListMinWidth: CGFloat = 300
        static let commitDetailMinWidth: CGFloat = 250
        static let commitRowFloor: CGFloat = 380
        static let commitRowLaneOffset: CGFloat = 200
        static let graphInlineSplitMinLeading: CGFloat = 150
        static let graphInlineSplitMinTrailing: CGFloat = 200

        // ChangesScreen splits
        static let changesFileListMinWidth: CGFloat = 200
        static let changesDiffMinWidth: CGFloat = 300

        // CodeReviewSheet
        static let codeReviewMinWidth: CGFloat = 860
        static let codeReviewMinHeight: CGFloat = 600
        static let codeReviewFileListMinWidth: CGFloat = 180
        static let codeReviewDiffMinWidth: CGFloat = 480

        // ConflictResolutionScreen
        static let conflictMinWidth: CGFloat = 860
        static let conflictMinHeight: CGFloat = 560
        static let conflictFileListMinWidth: CGFloat = 200
        static let conflictViewerMinWidth: CGFloat = 420
    }

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

        // Brand colors (derived from brand hue 265°)
        static let primary = brandPrimary
        static let secondary = codeReview
        static let accent = commitSplit

        // ── Zion brand palette ──
        static let brandPrimary = SwiftUI.Color(red: 101.0/255.0, green: 68.0/255.0, blue: 155.0/255.0)   // Rebecca Purple #65449b
        static let brandDark = SwiftUI.Color(red: 26.0/255.0, green: 0.0/255.0, blue: 78.0/255.0)         // Deep Twilight #1a004e
        static let brandInk = SwiftUI.Color(red: 42.0/255.0, green: 1.0/255.0, blue: 108.0/255.0)         // Indigo Ink #2a016c
        static let brandLight = SwiftUI.Color(red: 212.0/255.0, green: 206.0/255.0, blue: 232.0/255.0)    // Lavender #d4cee8
        static let brandWhite = SwiftUI.Color(red: 248.0/255.0, green: 247.0/255.0, blue: 251.0/255.0)    // Ghost White #f8f7fb

        // ── Semantic status (harmonized with brand) ──
        static let error = SwiftUI.Color(red: 224.0/255.0, green: 82.0/255.0, blue: 82.0/255.0)           // Warm red #e05252
        static let warning = SwiftUI.Color(red: 230.0/255.0, green: 162.0/255.0, blue: 60.0/255.0)        // Amber-gold #e6a23c
        static let success = SwiftUI.Color(red: 77.0/255.0, green: 204.0/255.0, blue: 122.0/255.0)        // Cool green #4dcc7a
        static let info = SwiftUI.Color(red: 107.0/255.0, green: 159.0/255.0, blue: 226.0/255.0)          // Periwinkle #6b9fe2

        // ── File status ──
        static let fileAdded = success
        static let fileModified = warning
        static let fileDeleted = destructive
        static let fileRenamed = info
        static let fileUntracked = Color.secondary
        static let fileStaged = success

        // ── Diff ──
        static let diffAddition = success
        static let diffAdditionBg = success.opacity(0.12)
        static let diffAdditionBgSelected = success.opacity(0.25)
        static let diffAdditionBgRaw = success.opacity(0.15)
        static let diffDeletion = destructive
        static let diffDeletionBg = destructive.opacity(0.12)
        static let diffDeletionBgSelected = destructive.opacity(0.25)
        static let diffDeletionBgRaw = destructive.opacity(0.15)
        static let diffContext = Color.primary.opacity(0.7)
        static let diffHunkHeader = info.opacity(0.8)
        static let diffHunkHeaderBg = info.opacity(0.08)
        static let diffHunkHeaderBgLight = info.opacity(0.05)

        // ── Brand gradient ──
        static let brandGradient = LinearGradient(
            colors: [brandInk, brandPrimary, ai],
            startPoint: .leading, endPoint: .trailing
        )

        // ── Feature accents (brand-derived) ──
        static let ai = SwiftUI.Color(red: 161.0/255.0, green: 123.0/255.0, blue: 223.0/255.0)            // Light purple #a17bdf (265° lighter)
        static let actionPrimary = brandPrimary  // Rebecca Purple for standard prominent buttons
        static let codeReview = SwiftUI.Color(red: 123.0/255.0, green: 111.0/255.0, blue: 199.0/255.0)    // Blue-purple #7b6fc7 (250° analogous)
        static let commitSplit = SwiftUI.Color(red: 94.0/255.0, green: 184.0/255.0, blue: 212.0/255.0)    // Cool cyan #5eb8d4 (195°)
        static let searchHighlight = SwiftUI.Color(red: 240.0/255.0, green: 210.0/255.0, blue: 100.0/255.0) // Complementary gold #f0d264 (48°)
        static let semanticSearch = SwiftUI.Color(red: 192.0/255.0, green: 132.0/255.0, blue: 224.0/255.0) // Orchid #c084e0 (280°)

        // ── Destructive (harmonized rose) ──
        static let destructive = SwiftUI.Color(red: 232.0/255.0, green: 92.0/255.0, blue: 122.0/255.0)    // Rose #e85c7a (348°)
        static let destructiveMuted = destructive.opacity(0.7)
        static let destructiveBg = destructive.opacity(0.1)

        // ── Conflict resolution ──
        static let conflictOurs = warning
        static let conflictTheirs = info
        static let conflictResolved = success

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.7)

        // Selection & interaction states
        static let selectionBackground = Color.accentColor.opacity(0.15)
        static let selectionBorder = Color.accentColor.opacity(0.7)
        static let hoverAccent = Color.accentColor.opacity(0.35)

        // Status backgrounds (consistent scale)
        static let statusGreenBg = success.opacity(0.12)
        static let statusOrangeBg = warning.opacity(0.12)
        static let statusBlueBg = info.opacity(0.12)
        static let statusYellowBg = searchHighlight.opacity(0.15)

        // Shadow tokens
        static let shadowDark = Color.black.opacity(0.14)
        static let shadowLight = Color.black.opacity(0.08)

        // Danger zone
        static let dangerBackground = destructive.opacity(0.06)
        static let dangerBorder = destructive.opacity(0.25)

        // Lane color palette (shared between graph and commit cards — harmonized)
        static let lanePalette: [SwiftUI.Color] = [
            info, SwiftUI.Color.orange, success, warning, commitSplit, brandPrimary, ai, codeReview, searchHighlight, semanticSearch,
            SwiftUI.Color(red: 0.55, green: 0.42, blue: 0.32), // warm brown
            .gray
        ]

        static func laneColor(forKey key: Int) -> SwiftUI.Color {
            if key < lanePalette.count { return lanePalette[key] }
            let hue = Double((key * 137) % 360) / 360.0
            return SwiftUI.Color(hue: hue, saturation: 0.80, brightness: 0.95)
        }
    }

    struct Spacing {
        static let micro: CGFloat = 4
        static let compact: CGFloat = 6
        static let standard: CGFloat = 8
        static let cardPadding: CGFloat = 12
        static let sectionGap: CGFloat = 20
        static let screenEdge: CGFloat = 24
        static let statusBarClearance: CGFloat = 44
        static let clipboardDrawerClearance: CGFloat = 40
        static let toolbarTrailing: CGFloat = 8

        // Icon spacing by context
        static let iconTextGap: CGFloat = 8        // Icon + text in normal rows (CardHeader, sidebar items)
        static let iconLabelGap: CGFloat = 6       // Icon + label in compact rows, tag groups
        static let iconInlineGap: CGFloat = 4      // Icon + badge, tight icon pairs
        static let toolbarItemGap: CGFloat = 10    // Spaced toolbar button groups
        static let iconGroupedGap: CGFloat = 2     // Grouped icon pills (split view toggle)

        // Corner radii (5 tiers)
        static let cardCornerRadius: CGFloat = 14       // GlassCards, commit row cards
        static let containerCornerRadius: CGFloat = 12  // Toolbar groups, overlays
        static let mediumCornerRadius: CGFloat = 10     // Panels, explanation cards, status chips
        static let elementCornerRadius: CGFloat = 8     // Buttons, search bars, inline items
        static let smallCornerRadius: CGFloat = 6       // Tags, tiny pills, code blocks
        static let microCornerRadius: CGFloat = 4       // Badges, progress bars, icon frames
        static let largeCornerRadius: CGFloat = 28      // Branding elements, hero cards
    }

    // MARK: - Typography Tokens

    struct Typography {
        // Headings
        static let screenTitle = Font.system(size: 28, weight: .bold)
        static let sheetTitle = Font.system(size: 16, weight: .semibold)
        static let subtitle = Font.system(size: 14, weight: .medium)
        static let sectionTitle = Font.system(size: 13, weight: .bold)

        // Body
        static let bodyLarge = Font.system(size: 14)
        static let body = Font.system(size: 12)
        static let bodySmall = Font.system(size: 11)
        static let bodyMedium = Font.system(size: 11, weight: .medium)

        // Labels & Meta
        static let label = Font.system(size: 10)
        static let labelMedium = Font.system(size: 10, weight: .medium)
        static let labelBold = Font.system(size: 10, weight: .bold)
        static let meta = Font.system(size: 9)
        static let metaBold = Font.system(size: 9, weight: .bold)
        static let micro = Font.system(size: 8, weight: .bold)

        // Icon-sized
        static let iconLarge = Font.system(size: 20, weight: .medium)

        // Bold variants
        static let bodySmallBold = Font.system(size: 11, weight: .bold)
        static let bodyBold = Font.system(size: 12, weight: .bold)
        static let bodyLargeBold = Font.system(size: 14, weight: .bold)

        // Semibold variants
        static let labelSemibold = Font.system(size: 10, weight: .semibold)
        static let bodySemibold = Font.system(size: 12, weight: .semibold)
        static let bodySmallSemibold = Font.system(size: 11, weight: .semibold)
        static let metaSemibold = Font.system(size: 9, weight: .semibold)

        // Monospaced
        static let monoBody = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 11, design: .monospaced)
        static let monoLabel = Font.system(size: 10, design: .monospaced)
        static let monoLabelBold = Font.system(size: 10, weight: .bold, design: .monospaced)
        static let monoMeta = Font.system(size: 9, design: .monospaced)

        // Monospaced bold/medium
        static let monoMetaBold = Font.system(size: 9, weight: .bold, design: .monospaced)
        static let monoSmallBold = Font.system(size: 11, weight: .bold, design: .monospaced)
        static let monoBodyBold = Font.system(size: 12, weight: .bold, design: .monospaced)
        static let monoLabelMedium = Font.system(size: 10, weight: .medium, design: .monospaced)
        static let monoSmallMedium = Font.system(size: 11, weight: .medium, design: .monospaced)

        // Large decorative/icon sizes
        static let emptyStateIcon = Font.system(size: 48)
        static let decorativeIcon = Font.system(size: 28)
        static let largeIcon = Font.system(size: 32)
        static let heroIcon = Font.system(size: 36)
    }

    // MARK: - Opacity Tokens

    struct Opacity {
        static let full: Double = 1.0
        static let high: Double = 0.9
        static let visible: Double = 0.7
        static let muted: Double = 0.5
        static let subtle: Double = 0.45
        static let dim: Double = 0.3
        static let faint: Double = 0.15
        static let ghost: Double = 0.08
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
        static let terminalToolbarFrame = CGSize(width: 30, height: 28)
        static let editorToolbarFrame = CGSize(width: 28, height: 24)
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

    // MARK: - Motion Tokens

    struct Motion {
        static let springInteractive = Animation.spring(response: 0.25, dampingFraction: 0.8)
        static let panel = Animation.easeInOut(duration: 0.2)
        static let detail = Animation.easeInOut(duration: 0.15)
        static let snappy = Animation.snappy(duration: 0.2)
        static let graph = Animation.easeInOut(duration: 0.12)

        static let glowPulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)

        @MainActor static let fade = AnyTransition.opacity
        @MainActor static let slideFromTop = AnyTransition.move(edge: .top).combined(with: .opacity)
        @MainActor static let slideFromLeading = AnyTransition.move(edge: .leading).combined(with: .opacity)
        @MainActor static let slideFromBottom = AnyTransition.move(edge: .bottom).combined(with: .opacity)
        @MainActor static let fadeScale = AnyTransition.opacity.combined(with: .scale(scale: 0.95))
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

        // SynthWave '84 — neon synthwave / cyberpunk
        static let synthwave = ThemeColors(
            background: (r: 0.149, g: 0.137, b: 0.208),   // #262335
            text: (r: 1.0, g: 1.0, b: 1.0),               // #ffffff
            keyword: (r: 0.996, g: 0.871, b: 0.365),      // #fede5d gold
            type: (r: 0.212, g: 0.976, b: 0.965),         // #36f9f6 cyan
            string: (r: 1.0, g: 0.545, b: 0.224),         // #ff8b39 orange
            comment: (r: 0.518, g: 0.545, b: 0.741),      // #848bbd gray-purple
            number: (r: 0.976, g: 0.494, b: 0.447)        // #f97e72 salmon
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

        static let synthwave = TerminalPalette(
            foreground: nsHex(0xffffff),
            background: nsHex(0x262335),
            cursorColor: nsHex(0xff7edb),
            cursorTextColor: nsHex(0x262335),
            selectionBackground: nsHex(0x463465),
            selectionForeground: nsHex(0xffffff),
            ansiColors: [
                stColor(0x262335), stColor(0xfe4450), stColor(0x72f1b8), stColor(0xfede5d),
                stColor(0x36f9f6), stColor(0xff7edb), stColor(0x36f9f6), stColor(0xffffff),
                stColor(0x848bbd), stColor(0xfe4450), stColor(0x72f1b8), stColor(0xfede5d),
                stColor(0x36f9f6), stColor(0xff7edb), stColor(0x36f9f6), stColor(0xffffff),
            ],
            backgroundSwiftUI: swHex(0x262335),
            accentSwiftUI: swHex(0x72f1b8)
        )
    }

    struct ZionMode {
        static let neonCyan = SwiftUI.Color(red: 0.212, green: 0.976, blue: 0.965)       // #36f9f6
        static let neonMagenta = SwiftUI.Color(red: 1.0, green: 0.494, blue: 0.859)      // #ff7edb
        static let neonGold = SwiftUI.Color(red: 0.996, green: 0.871, blue: 0.365)       // #fede5d
        static let neonOrange = SwiftUI.Color(red: 1.0, green: 0.545, blue: 0.224)       // #ff8b39
        static let neonBase = SwiftUI.Color(red: 0.149, green: 0.137, blue: 0.208)       // #262335
        static let neonBaseDark = SwiftUI.Color(red: 0.071, green: 0.059, blue: 0.114)   // #120f1d
        static let glowBorder = neonMagenta.opacity(0.14)
        static let glowShadow = neonMagenta.opacity(0.08)

        // Gradients
        static let neonGradient = LinearGradient(
            colors: [neonCyan, neonMagenta],
            startPoint: .leading, endPoint: .trailing
        )
        static let neonAIGradient = LinearGradient(
            colors: [neonGold, neonMagenta],
            startPoint: .leading, endPoint: .trailing
        )

        // Line tokens
        static let neonLineHeight: CGFloat = 2
        static let neonLineIdleHeight: CGFloat = 1
        static let neonLineCornerRadius: CGFloat = 1
        static let neonGlowBlur: CGFloat = 2
        static let neonGlowOpacity: Double = 0.25
    }
}

// MARK: - Zion Mode Environment Key

private struct ZionModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var zionModeEnabled: Bool {
        get { self[ZionModeKey.self] }
        set { self[ZionModeKey.self] = newValue }
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
