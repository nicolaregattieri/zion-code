import SwiftUI

struct TerminalFontPopoverButton: View {
    @Bindable var model: RepositoryViewModel
    let accentColor: Color
    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "textformat.size")
                .font(DesignSystem.IconSize.toolbar)
                .foregroundStyle(accentColor)
                .frame(width: DesignSystem.IconSize.terminalToolbarFrame.width,
                       height: DesignSystem.IconSize.terminalToolbarFrame.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? DesignSystem.Interactive.hoverBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.microCornerRadius))
        .onHover { h in isHovered = h }
        .help(L10n("Fonte do terminal"))
        .accessibilityLabel(L10n("Fonte do terminal"))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n("Fonte do terminal"))
                    .font(DesignSystem.Typography.bodyMedium)

                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text(L10n("Fonte"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $model.terminalFontFamily) {
                        Text("SF Mono").tag("SF Mono")
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("Fira Code").tag("Fira Code")
                        Text("JetBrains Mono").tag("JetBrains Mono")
                        Text("Hack").tag("Hack")
                        Text("Roboto Mono").tag("Roboto Mono")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                if !model.isTerminalFontAvailable {
                    HStack(spacing: DesignSystem.Spacing.iconInlineGap) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text(L10n("Fonte nao encontrada, usando fallback"))
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
                }

                HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
                    Text(L10n("Tamanho"))
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(.secondary)
                    Stepper(value: $model.terminalFontSize, in: 8...32, step: 1) {
                        Text("\(Int(model.terminalFontSize))pt")
                            .font(DesignSystem.Typography.monoSmall)
                    }
                }
            }
            .controlSize(.small)
            .padding(12)
            .frame(width: 240)
        }
    }
}
