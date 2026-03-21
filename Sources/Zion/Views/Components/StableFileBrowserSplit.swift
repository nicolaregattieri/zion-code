import SwiftUI

/// A split view that keeps the main content in a stable structural position regardless
/// of whether the file browser sidebar is visible. This prevents SwiftUI from destroying
/// and recreating NSViewRepresentable views when toggling the sidebar or entering zen mode.
struct StableFileBrowserSplit<Sidebar: View, Content: View>: View {
    let isVisible: Bool
    @Binding var ratio: CGFloat
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let dividerSize: CGFloat = isVisible ? 8 : 0
            let available = totalWidth - dividerSize

            // Live drag preview
            let baseLeading = available * ratio
            let proposedLeading = baseLeading + dragOffset
            let clampedLeading = max(
                DesignSystem.Layout.fileBrowserMinWidth,
                min(available - DesignSystem.Layout.editorMinWidth, proposedLeading)
            )
            let sidebarWidth: CGFloat = isVisible ? clampedLeading : 0

            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                    .clipped()
                    .allowsHitTesting(isVisible)
                    .opacity(isVisible ? 1 : 0)

                if isVisible {
                    sidebarDivider(available: available, baseLeading: baseLeading)
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .coordinateSpace(name: "fileBrowserSplit")
        }
    }

    private func sidebarDivider(available: CGFloat, baseLeading: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("fileBrowserSplit"))
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let delta = value.translation.width
                        let newLeading = max(
                            DesignSystem.Layout.fileBrowserMinWidth,
                            min(available - DesignSystem.Layout.editorMinWidth, baseLeading + delta)
                        )
                        ratio = newLeading / available
                    }
            )
    }
}
