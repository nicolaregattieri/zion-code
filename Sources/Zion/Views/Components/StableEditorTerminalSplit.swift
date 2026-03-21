import SwiftUI

/// A split view that keeps both editor and terminal in stable structural positions
/// regardless of the active layout mode. This prevents SwiftUI from destroying and
/// recreating NSViewRepresentable views (like TerminalTabView) when switching between
/// editorOnly / split / terminalOnly layouts.
struct StableEditorTerminalSplit<Editor: View, Terminal: View>: View {
    let layout: EditorTerminalLayout
    @Binding var terminalRatio: CGFloat
    @ViewBuilder let editor: Editor
    @ViewBuilder let terminal: Terminal

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let dividerSize: CGFloat = layout == .split ? 8 : 0
            let available = totalHeight - dividerSize

            let editorHeight: CGFloat = switch layout {
            case .split: available * (1 - terminalRatio)
            case .editorOnly: totalHeight
            case .terminalOnly: 0
            }

            let terminalHeight: CGFloat = switch layout {
            case .split: available * terminalRatio
            case .editorOnly: 0
            case .terminalOnly: totalHeight
            }

            VStack(spacing: 0) {
                editor
                    .frame(height: editorHeight)
                    .clipped()
                    .allowsHitTesting(layout != .terminalOnly)
                    .opacity(layout == .terminalOnly ? 0 : 1)

                if layout == .split {
                    splitDivider(available: available)
                }

                terminal
                    .frame(height: terminalHeight)
                    .clipped()
                    .allowsHitTesting(layout != .editorOnly)
                    .opacity(layout == .editorOnly ? 0 : 1)
            }
        }
    }

    @GestureState private var dragOffset: CGFloat = 0

    private func splitDivider(available: CGFloat) -> some View {
        let baseTrailing = available * terminalRatio
        return Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let delta = -value.translation.height
                        let newTrailing = max(
                            DesignSystem.Layout.editorTerminalMinPane,
                            min(available - DesignSystem.Layout.editorTerminalMinPane, baseTrailing + delta)
                        )
                        terminalRatio = newTrailing / available
                    }
            )
    }
}
