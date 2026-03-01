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
            .overlay(alignment: .top) {
                if focusedSessionID == session.id, model.terminalSessions.count > 1 {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 3)
                        .padding(.top, 4)
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
            .padding(.horizontal, DesignSystem.Spacing.micro)
            .contentShape(Rectangle())
            .onTapGesture { model.focusedSessionID = session.id }

        case .split(let direction, _, _):
            let children = node.flattenedChildren(forDirection: direction)
            let dividerThickness: CGFloat = 1
            GeometryReader { geometry in
                if direction == .vertical {
                    let totalDividers = dividerThickness * CGFloat(children.count - 1)
                    let paneWidth = (geometry.size.width - totalDividers) / CGFloat(children.count)
                    HStack(spacing: 0) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            if index > 0 {
                                Divider().frame(width: dividerThickness)
                            }
                            TerminalPaneView(node: child, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                                .padding(.horizontal, DesignSystem.Spacing.micro)
                                .frame(width: max(0, paneWidth))
                        }
                    }
                } else {
                    let totalDividers = dividerThickness * CGFloat(children.count - 1)
                    let paneHeight = (geometry.size.height - totalDividers) / CGFloat(children.count)
                    VStack(spacing: 0) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                            if index > 0 {
                                Divider().frame(height: dividerThickness)
                            }
                            TerminalPaneView(node: child, theme: theme, fontSize: fontSize, fontFamily: fontFamily, focusedSessionID: focusedSessionID, model: model, transparentBackground: transparentBackground)
                                .padding(.horizontal, DesignSystem.Spacing.micro)
                                .frame(height: max(0, paneHeight))
                        }
                    }
                }
            }
        }
    }
}
