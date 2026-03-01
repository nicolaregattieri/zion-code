import SwiftUI

struct ClipboardPopoverButton: View {
    @Bindable var model: RepositoryViewModel
    var accentColor: Color
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                Image(systemName: "clipboard")
                    .font(DesignSystem.Typography.bodyMedium)
                if !model.clipboardMonitor.items.isEmpty {
                    Text("\(model.clipboardMonitor.items.count)")
                        .font(DesignSystem.Typography.monoMeta)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DesignSystem.Colors.selectionBackground)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isPresented ? Color.accentColor : accentColor)
        }
        .buttonStyle(.borderless)
        .frame(height: 24)
        .contentShape(Rectangle())
        .help(L10n("Clipboard"))
        .popover(isPresented: $isPresented) {
            ClipboardDrawer(model: model)
                .frame(width: 280, height: 350)
        }
    }
}
