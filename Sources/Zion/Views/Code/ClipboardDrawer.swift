import SwiftUI

struct ClipboardDrawer: View {
    var model: RepositoryViewModel
    @State private var hoveredItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header

            if !model.clipboardMonitor.isCollapsed {
                Divider()
                content
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
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    model.clipboardMonitor.isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.clipboardMonitor.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
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
                            .background(Color.accentColor.opacity(0.2))
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
                        .font(.system(size: 10))
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
                    featureRow("clipboard", .blue, L10n("Captura automaticamente o que voce copiar"))
                    featureRow("cursorarrow.click", .green, L10n("Clique para colar no terminal"))
                    featureRow("cursorarrow.click.2", .orange, L10n("Duplo clique para executar"))
                    featureRow("hand.draw", .purple, L10n("Arraste para o terminal"))
                    Text(L10n("Copie algo para comecar"))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.top, 4)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.clipboardMonitor.items) { item in
                            clipboardRow(item)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private func featureRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color).frame(width: 16)
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        let isHovered = hoveredItemID == item.id
        let hasText = !item.text.isEmpty

        return HStack(spacing: 8) {
            Image(systemName: item.category.icon)
                .font(.system(size: 10))
                .foregroundStyle(categoryColor(item.category))
                .frame(width: 14)

            if item.isImage {
                Text(L10n("Imagem") + " (\(item.preview))")
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            } else {
                Text(item.preview)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            Spacer()

            if isHovered && hasText {
                Button {
                    model.sendTextToActiveTerminal(item.text)
                } label: {
                    Image(systemName: "text.insert")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(L10n("Colar no Terminal"))
            }

            Text(relativeTime(item.timestamp))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovered ? DesignSystem.Colors.glassHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if hasText {
                let isFile = item.isImage || item.category == .path
                if isFile {
                    model.sendTextToActiveTerminal("open \(shellQuote(item.text))\n")
                } else {
                    model.sendTextToActiveTerminal(item.text + "\n")
                }
            }
        }
        .onTapGesture {
            if hasText {
                let isFile = item.isImage || item.category == .path
                model.sendTextToActiveTerminal(isFile ? "open \(shellQuote(item.text))" : item.text)
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
        case .command: return .green
        case .path: return .blue
        case .hash: return .orange
        case .url: return .purple
        case .image: return .pink
        case .text: return .secondary
        }
    }

    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
