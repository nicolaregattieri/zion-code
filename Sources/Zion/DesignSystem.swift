import SwiftUI

struct DesignSystem {
    struct Colors {
        // App background with transparency for glassmorphism
        static let background = Color(NSColor.windowBackgroundColor)
        static let glassBackground = Color.white.opacity(0.05)
        static let glassBorder = Color.white.opacity(0.1)
        
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
}
