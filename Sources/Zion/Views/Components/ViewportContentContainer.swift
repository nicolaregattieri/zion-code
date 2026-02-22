import SwiftUI

struct ViewportContentContainer<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(maxWidth: CGFloat = DesignSystem.Layout.centeredContentMaxWidth, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, DesignSystem.Spacing.sectionGap)
    }
}
