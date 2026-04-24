import SwiftUI

struct TerminalPaneView: View {
    let node: TerminalPaneNode
    var theme: EditorTheme
    var fontSize: Double
    var fontFamily: String
    var focusedSessionID: UUID?
    var model: RepositoryViewModel
    var transparentBackground: Bool = false

    var body: some View {
        switch node.content {
        case .terminal(let session):
            TerminalTabView(
                session: session,
                theme: theme,
                fontSize: fontSize,
                fontFamily: fontFamily,
                model: model,
                transparentBackground: transparentBackground
            )
            .id(session.id)
            .overlay(alignment: .top) {
                if focusedSessionID == session.id, model.terminalSessions.count > 1 {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 3)
                        .padding(.top, 4)
                }
            }
            .overlay {
                if model.terminalSessions.count > 1, focusedSessionID != session.id {
                    Color.black.opacity(DesignSystem.Opacity.whisper)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.terminalSessions.count > 1 {
                    SearchNavButton(
                        icon: "xmark",
                        tooltip: L10n("Fechar painel") + " (⇧⌘W)",
                        isSecondary: true
                    ) { model.closeTerminalSession(session) }
                    .padding(4)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: focusedSessionID)
            .padding(.horizontal, DesignSystem.Spacing.micro)
            .contentShape(Rectangle())
            .onTapGesture {
                model.focusedSessionID = session.id
                model.focusActiveTerminal()
            }
            .dropDestination(for: String.self) { items, _ in
                guard let text = items.first, !text.isEmpty else { return false }
                model.sendTextToTerminal(text, sessionID: session.id)
                model.focusActiveTerminal()
                return true
            }
            .dropDestination(for: URL.self) { urls, _ in
                let handled = model.handleFileURLsDroppedOnTerminal(urls, sessionID: session.id)
                if handled {
                    model.focusActiveTerminal()
                }
                return handled
            }

        case .split(let direction, let first, let second):
            TerminalSplitView(
                node: node,
                direction: direction,
                first: first,
                second: second,
                theme: theme,
                fontSize: fontSize,
                fontFamily: fontFamily,
                focusedSessionID: focusedSessionID,
                model: model,
                transparentBackground: transparentBackground
            )
        }
    }
}

// MARK: - Draggable Split

private struct TerminalSplitView: View {
    let node: TerminalPaneNode
    let direction: SplitDirection
    let first: TerminalPaneNode
    let second: TerminalPaneNode
    var theme: EditorTheme
    var fontSize: Double
    var fontFamily: String
    var focusedSessionID: UUID?
    var model: RepositoryViewModel
    var transparentBackground: Bool

    private let dividerHitSize: CGFloat = 8
    private let minPaneSize: CGFloat = 80

    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let totalSize = direction == .vertical ? geo.size.width : geo.size.height
            let available = totalSize - dividerHitSize
            let baseLeading = available * node.ratio
            let proposedLeading = baseLeading + dragOffset
            let clampedLeading = max(minPaneSize, min(available - minPaneSize, proposedLeading))

            if direction == .vertical {
                HStack(spacing: 0) {
                    TerminalPaneView(node: first, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                        .frame(width: clampedLeading)

                    dividerView(available: available, baseLeading: baseLeading)

                    TerminalPaneView(node: second, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                        .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "terminalSplit-\(node.id)")
            } else {
                VStack(spacing: 0) {
                    TerminalPaneView(node: first, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                        .frame(height: clampedLeading)

                    dividerView(available: available, baseLeading: baseLeading)

                    TerminalPaneView(node: second, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                        .frame(maxHeight: .infinity)
                }
                .coordinateSpace(name: "terminalSplit-\(node.id)")
            }
        }
    }

    private func dividerView(available: CGFloat, baseLeading: CGFloat) -> some View {
        let cursorStyle: NSCursor = direction == .vertical ? .resizeLeftRight : .resizeUpDown

        return Rectangle()
            .fill(Color.clear)
            .frame(
                width: direction == .vertical ? dividerHitSize : nil,
                height: direction == .horizontal ? dividerHitSize : nil
            )
            .overlay { Divider() }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { cursorStyle.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("terminalSplit-\(node.id)"))
                    .updating($dragOffset) { value, state, _ in
                        state = direction == .vertical ? value.translation.width : value.translation.height
                    }
                    .onEnded { value in
                        let delta = direction == .vertical ? value.translation.width : value.translation.height
                        let newLeading = max(minPaneSize, min(available - minPaneSize, baseLeading + delta))
                        node.ratio = newLeading / available
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    node.ratio = 0.5
                }
            }
    }
}
