import CoreGraphics

struct CodeScreenLayoutProfile: Equatable {
    let width: CGFloat

    var prefersVerticalMarkdownPreview: Bool {
        width < DesignSystem.Layout.verticalMarkdownPreviewWidthThreshold
    }

    var prefersAutoCollapsedFileBrowser: Bool {
        width < DesignSystem.Layout.autoCollapseFileBrowserWidthThreshold
    }
}
