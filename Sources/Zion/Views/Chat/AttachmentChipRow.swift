// AttachmentChipRow.swift
// Renders the row of pending attachments above the composer input. Image
// attachments show a 36pt thumbnail; PDFs / generic files show a coloured
// pill with the filename and byte size. Each chip has an X to remove it
// before the message is sent.

import SwiftUI
import AppKit

struct AttachmentChipRow: View {

    let pending: [PendingChatAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.compact) {
                ForEach(pending) { item in
                    chip(for: item)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.micro)
            .padding(.vertical, DesignSystem.Spacing.micro)
        }
    }

    @ViewBuilder
    private func chip(for item: PendingChatAttachment) -> some View {
        switch item.kind {
        case .image:
            imageChip(for: item)
        case .pdf, .other:
            fileChip(for: item)
        }
    }

    private func imageChip(for item: PendingChatAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = NSImage(contentsOf: item.fileURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Spacing.smallCornerRadius, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1)
            )

            removeButton(for: item)
                .offset(x: 4, y: -4)
        }
        .help(item.originalName)
    }

    private func fileChip(for item: PendingChatAttachment) -> some View {
        HStack(spacing: DesignSystem.Spacing.iconLabelGap) {
            Image(systemName: iconName(for: item))
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.brandPrimary)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.originalName)
                    .font(DesignSystem.Typography.labelMedium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            Button {
                onRemove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help(L10n("chat.attach.remove"))
        }
        .padding(.horizontal, DesignSystem.Spacing.compact)
        .padding(.vertical, DesignSystem.Spacing.micro)
        .background(Capsule().fill(DesignSystem.Colors.glassSubtle))
        .overlay(Capsule().strokeBorder(DesignSystem.Colors.glassStroke, lineWidth: 1))
    }

    private func removeButton(for item: PendingChatAttachment) -> some View {
        Button {
            onRemove(item.id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandWhite)
                .background(Circle().fill(Color.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .help(L10n("chat.attach.remove"))
    }

    private func iconName(for item: PendingChatAttachment) -> String {
        switch item.kind {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .other: return "doc"
        }
    }
}
