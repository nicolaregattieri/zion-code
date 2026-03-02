import SwiftUI
import AppKit

struct ClipboardDrawer: View {
    var model: RepositoryViewModel
    var onNavigateToGraph: (() -> Void)?
    @State private var hoveredItemID: UUID?
    @State private var searchQuery: String = ""

    private var filteredItems: [ClipboardItem] {
        if searchQuery.isEmpty { return model.clipboardMonitor.items }
        return model.clipboardMonitor.items.filter { $0.preview.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.clipboardMonitor.isCollapsed {
                Divider()
                content
                    .transition(DesignSystem.Motion.slideFromBottom)
            }
        }
        .background(DesignSystem.Colors.background.opacity(0.3))
        .overlay(alignment: .top) {
            Rectangle().fill(DesignSystem.Colors.glassBorderDark).frame(height: 1)
        }
        .onAppear { model.clipboardMonitor.start() }
        .onDisappear { model.clipboardMonitor.stop() }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Button {
                withAnimation(DesignSystem.Motion.snappy) {
                    model.clipboardMonitor.isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Image(systemName: model.clipboardMonitor.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(DesignSystem.Typography.micro)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(L10n("Clipboard"))
                        .font(.system(size: 12, weight: .semibold))

                    if !model.clipboardMonitor.items.isEmpty {
                        Text("\(model.clipboardMonitor.items.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(DesignSystem.Colors.selectionBackground)
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if !model.clipboardMonitor.items.isEmpty && !model.clipboardMonitor.isCollapsed {
                Button {
                    model.clipboardMonitor.clearAll()
                } label: {
                    Image(systemName: "trash")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n("Limpar tudo"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var content: some View {
        Group {
            if model.clipboardMonitor.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n("Clipboard Inteligente"))
                        .font(.system(size: 11, weight: .bold))
                    featureRow("clipboard", DesignSystem.Colors.info, L10n("Captura automaticamente o que voce copiar"))
                    featureRow("cursorarrow.click", DesignSystem.Colors.success, L10n("Clique para colar no terminal"))
                    featureRow("cursorarrow.click.2", DesignSystem.Colors.warning, L10n("Duplo clique para executar"))
                    featureRow("hand.draw", DesignSystem.Colors.brandPrimary, L10n("Arraste para o terminal"))
                    Text(L10n("Copie algo para comecar"))
                        .font(DesignSystem.Typography.label).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.top, 4)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "magnifyingglass")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(.secondary)
                        TextField(L10n("Filtrar clipboard..."), text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Typography.bodySmall)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DesignSystem.Colors.glassSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(filteredItems) { item in
                                clipboardRow(item)
                            }
                        }
                        .padding(6)
                    }
                }
            }
        }
    }

    private func featureRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: icon).font(DesignSystem.Typography.bodySmall).foregroundStyle(color).frame(width: 16)
            Text(text).font(DesignSystem.Typography.label).foregroundStyle(.secondary)
        }
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        let isHovered = hoveredItemID == item.id
        let hasText = !item.text.isEmpty

        return HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Image(systemName: item.category.icon)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(categoryColor(item.category))
                .frame(width: 14)

            if item.isImage {
                if let path = item.imagePath {
                    ClipboardImageThumb(path: path)
                }
                Text(item.preview)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text(item.preview)
                    .font(DesignSystem.Typography.monoSmall)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            Spacer()

            if isHovered && hasText {
                if let action = smartAction(for: item) {
                    Button { action.handler() } label: {
                        Image(systemName: action.icon)
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(action.tint)
                    }
                    .buttonStyle(.plain)
                    .help(action.label)
                }

                Button {
                    model.sendTextToActiveTerminal(item.text)
                } label: {
                    Image(systemName: "text.insert")
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(L10n("Colar no Terminal"))
            }

            Text(relativeTime(item.timestamp))
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovered ? DesignSystem.Colors.glassHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if hasText {
                let isFile = item.isImage || item.category == .path
                if isFile {
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.text))
                } else {
                    model.sendTextToActiveTerminal(item.text + "\n")
                }
            }
        }
        .onTapGesture {
            if hasText {
                let isFile = item.isImage || item.category == .path
                model.sendTextToActiveTerminal(isFile ? "open \(TerminalShellEscaping.quotePath(item.text))" : item.text)
            }
        }
        .draggable(item.text)
        .onHover { h in hoveredItemID = h ? item.id : nil }
        .contextMenu {
            if hasText {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                } label: {
                    Label(L10n("Copiar"), systemImage: "doc.on.doc")
                }
                Button {
                    model.sendTextToActiveTerminal(item.text)
                } label: {
                    Label(L10n("Colar no Terminal"), systemImage: "terminal")
                }
                Divider()
            }
            Button(role: .destructive) {
                model.clipboardMonitor.remove(item)
            } label: {
                Label(L10n("Remover"), systemImage: "trash")
            }
        }
    }

    private func categoryColor(_ category: ClipboardItem.Category) -> Color {
        switch category {
        case .command: return DesignSystem.Colors.success
        case .path: return DesignSystem.Colors.info
        case .hash: return DesignSystem.Colors.warning
        case .url: return DesignSystem.Colors.brandPrimary
        case .image: return DesignSystem.Colors.semanticSearch
        case .text: return .secondary
        }
    }

    // MARK: - Smart Clipboard Actions

    private struct SmartAction {
        let icon: String
        let label: String
        let tint: Color
        let handler: () -> Void
    }

    private static let gitHashRegex = try! NSRegularExpression(pattern: "^[0-9a-f]{7,40}$", options: [])

    private func smartAction(for item: ClipboardItem) -> SmartAction? {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Git hash → Show in Graph
        let range = NSRange(text.startIndex..., in: text)
        if Self.gitHashRegex.firstMatch(in: text, range: range) != nil {
            return SmartAction(
                icon: "point.3.connected.trianglepath.dotted",
                label: L10n("Mostrar no Graph"),
                tint: DesignSystem.Colors.info
            ) {
                model.selectCommit(text)
                onNavigateToGraph?()
            }
        }

        // Branch name → Checkout
        if model.branches.contains(text) {
            return SmartAction(
                icon: "arrow.triangle.branch",
                label: L10n("Checkout %@", text),
                tint: DesignSystem.Colors.success
            ) {
                model.branchInput = text
                model.setBranchFocus(text)
            }
        }

        // File path → Open in Editor
        if let repoURL = model.repositoryURL {
            let fullPath = repoURL.appendingPathComponent(text).path
            if FileManager.default.fileExists(atPath: fullPath) {
                return SmartAction(
                    icon: "pencil.and.outline",
                    label: L10n("Abrir no Editor"),
                    tint: DesignSystem.Colors.brandPrimary
                ) {
                    model.openFileInEditor(relativePath: text)
                }
            }
        }

        return nil
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return L10n("agora") }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

private struct ClipboardImageThumb: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.glassSubtle)
                    .overlay(
                        Image(systemName: "photo")
                            .font(DesignSystem.Typography.bodySmall)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorderDark, lineWidth: 1)
        )
        .onAppear {
            if image == nil {
                image = NSImage(contentsOfFile: path)
            }
        }
    }
}
