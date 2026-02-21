import SwiftUI

struct ConflictRegionCard: View {
    let region: ConflictRegion
    let index: Int
    let fileName: String
    let onChoose: (ConflictChoice) -> Void
    var model: RepositoryViewModel

    @State private var customText: String = ""
    @State private var isEditingCustom: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            oursBlock
            separator
            theirsBlock
            actionButtons
        }
        .background(DesignSystem.Colors.glassSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }

    private var borderColor: Color {
        switch region.choice {
        case .ours: return .green.opacity(0.4)
        case .theirs: return .blue.opacity(0.4)
        case .both, .bothReverse: return .purple.opacity(0.4)
        case .custom: return .orange.opacity(0.4)
        case .undecided: return DesignSystem.Colors.glassBorderDark
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(L10n("Conflito") + " #\(index + 1)")
                .font(.system(size: 12, weight: .bold))
            Spacer()
            Text(region.oursLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.green)
            Text("vs")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(region.theirsLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue)
            if region.choice != .undecided {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.glassOverlay)
    }

    private var oursBlock: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.green)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(region.oursLines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.06))
        }
        .opacity(region.choice == .theirs ? 0.4 : 1.0)
    }

    private var separator: some View {
        HStack {
            Spacer()
            Text("=======")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.5))
            Spacer()
        }
        .padding(.vertical, 2)
        .background(DesignSystem.Colors.glassMinimal)
    }

    private var theirsBlock: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(region.theirsLines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.06))
        }
        .opacity(region.choice == .ours ? 0.4 : 1.0)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                choiceButton(L10n("Aceitar Nosso"), icon: "checkmark", color: .green, choice: .ours)
                choiceButton(L10n("Aceitar Deles"), icon: "checkmark", color: .blue, choice: .theirs)
                choiceButton(L10n("Aceitar Ambos"), icon: "arrow.up.arrow.down", color: .purple, choice: .both)
                Button {
                    isEditingCustom.toggle()
                    if isEditingCustom {
                        customText = (region.oursLines + region.theirsLines).joined(separator: "\n")
                    }
                } label: {
                    Label(L10n("Editar Manualmente"), systemImage: "pencil")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)

                if model.isAIConfigured {
                    Button {
                        model.resolveConflictWithAI(region: region, fileName: fileName)
                    } label: {
                        if model.isGeneratingAIMessage {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                        } else {
                            Label(L10n("Resolver com IA"), systemImage: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.pink)
                    .disabled(model.isGeneratingAIMessage)
                    .help(L10n("Resolver conflito com IA"))
                    .onChange(of: model.aiConflictResolution) { _, newValue in
                        if !newValue.isEmpty {
                            customText = newValue
                            isEditingCustom = true
                            model.aiConflictResolution = ""
                        }
                    }
                }
            }

            if isEditingCustom {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $customText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignSystem.Colors.glassBorderDark)
                        )
                    HStack {
                        Spacer()
                        Button(L10n("Aplicar")) {
                            onChoose(.custom(customText))
                            isEditingCustom = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(10)
    }

    private func choiceButton(_ label: String, icon: String, color: Color, choice: ConflictChoice) -> some View {
        Button {
            onChoose(choice)
        } label: {
            Label(label, systemImage: region.choice == choice ? "checkmark.circle.fill" : icon)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(region.choice == choice ? color : nil)
    }
}
