import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let fileURL: URL?
    let theme: EditorTheme

    private enum ZoomMode: String, CaseIterable, Identifiable {
        case fit
        case actual

        var id: String { rawValue }
    }

    @State private var image: NSImage?
    @State private var pixelSize: CGSize = .zero
    @State private var fileSize: Int64 = 0
    @State private var hasLoadError: Bool = false
    @State private var zoomMode: ZoomMode = .fit

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .background(theme.colors.background)
        .environment(\.colorScheme, theme.isLightAppearance ? .light : .dark)
        .onAppear { loadImage() }
        .onChange(of: fileURL?.path) { _, _ in
            zoomMode = .fit
            loadImage()
        }
    }

    private var toolbar: some View {
        HStack(spacing: DesignSystem.Spacing.iconTextGap) {
            Text(fileURL?.lastPathComponent ?? L10n("editor.image.title"))
                .font(DesignSystem.Typography.bodyMedium)
                .lineLimit(1)

            Spacer(minLength: 0)

            Picker("", selection: $zoomMode) {
                Text(L10n("editor.image.fit")).tag(ZoomMode.fit)
                Text(L10n("editor.image.actual")).tag(ZoomMode.actual)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            if let fileURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Image(systemName: "folder")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .help(L10n("editor.image.revealFinder"))

                Button {
                    NSWorkspace.shared.open(fileURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .help(L10n("editor.image.openExternal"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .bottomLeading) {
            if !metadataText.isEmpty {
                Text(metadataText)
                    .font(DesignSystem.Typography.monoSmall)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if hasLoadError {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(L10n("editor.image.loadFailed"))
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image {
            if zoomMode == .fit {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(
                                maxWidth: max(proxy.size.width - 24, 120),
                                maxHeight: max(proxy.size.height - 24, 120)
                            )
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .interpolation(.high)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var metadataText: String {
        var parts: [String] = []
        if pixelSize.width > 0, pixelSize.height > 0 {
            parts.append("\(Int(pixelSize.width))x\(Int(pixelSize.height))")
        }
        let ext = fileURL?.pathExtension.uppercased() ?? ""
        if !ext.isEmpty {
            parts.append(ext)
        }
        if fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        return parts.joined(separator: " • ")
    }

    private func loadImage() {
        image = nil
        pixelSize = .zero
        fileSize = 0
        hasLoadError = false

        guard let fileURL else { return }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let bytes = attributes[.size] as? NSNumber {
            fileSize = bytes.int64Value
        }

        guard let loadedImage = NSImage(contentsOf: fileURL) else {
            hasLoadError = true
            return
        }

        image = loadedImage
        pixelSize = imagePixelSize(for: loadedImage)
    }

    private func imagePixelSize(for image: NSImage) -> CGSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
    }
}
