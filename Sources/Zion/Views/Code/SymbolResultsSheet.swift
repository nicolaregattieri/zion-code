import SwiftUI

struct SymbolResultsSheet: View {
    let title: String
    let emptyText: String
    let locations: [EditorSymbolLocation]
    let onSelect: (EditorSymbolLocation) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Spacing.toolbarItemGap) {
                Text(title)
                    .font(DesignSystem.Typography.sheetTitle)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Typography.sheetTitle)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            if locations.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(locations) { location in
                    Button {
                        onSelect(location)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(location.relativePath):\(location.line)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Text(location.preview)
                                .font(DesignSystem.Typography.bodySmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 760, height: 460)
    }
}
