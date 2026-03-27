import CoreGraphics

struct AppShellLayoutProfile: Equatable {
    let width: CGFloat

    var prefersCollapsedPrimarySidebar: Bool {
        width < DesignSystem.Layout.compactShellWidthThreshold
    }

    var usesCompactToolbar: Bool {
        width < DesignSystem.Layout.compactToolbarWidthThreshold
    }

    var usesCompactStatusBar: Bool {
        width < DesignSystem.Layout.compactStatusBarWidthThreshold
    }
}
