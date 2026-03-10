import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let fileURL: URL?
    let theme: EditorTheme

    private enum ZoomMode {
        case fit
        case actual
        case custom
    }

    private static let canvasPadding: CGFloat = 16
    private static let minZoomScale: CGFloat = 0.25
    private static let maxZoomScale: CGFloat = 8
    private static let zoomStep: CGFloat = 1.25
    private static let zoomPresets: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]

    @State private var image: NSImage?
    @State private var pixelSize: CGSize = .zero
    @State private var fileSize: Int64 = 0
    @State private var hasLoadError: Bool = false
    @State private var zoomMode: ZoomMode = .fit
    @State private var customZoomScale: CGFloat = 1
    @State private var viewportSize: CGSize = .zero

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
            customZoomScale = 1
            viewportSize = .zero
            loadImage()
        }
    }

    private var toolbar: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.toolbarItemGap) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
                Text(fileURL?.lastPathComponent ?? L10n("editor.image.title"))
                    .font(DesignSystem.Typography.bodyMedium)
                    .lineLimit(1)

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(DesignSystem.Typography.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(spacing: DesignSystem.Spacing.compact) {
                Picker("", selection: $zoomMode) {
                    Text(L10n("editor.image.fit")).tag(ZoomMode.fit)
                    Text(L10n("editor.image.actual")).tag(ZoomMode.actual)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Button {
                    adjustZoom(by: 1 / Self.zoomStep)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .help(L10n("editor.image.zoomOut"))
                .disabled(currentZoomScale <= Self.minZoomScale)

                Menu {
                    ForEach(Self.zoomPresets, id: \.self) { preset in
                        Button(zoomLabel(for: preset)) {
                            setCustomZoomScale(preset)
                        }
                    }
                } label: {
                    Text(zoomLabel(for: currentZoomScale))
                        .font(DesignSystem.Typography.monoSmall)
                        .frame(minWidth: 50)
                }
                .menuStyle(.borderlessButton)
                .help(L10n("editor.image.zoom"))

                Button {
                    adjustZoom(by: Self.zoomStep)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(DesignSystem.Typography.label)
                }
                .buttonStyle(.bordered)
                .help(L10n("editor.image.zoomIn"))
                .disabled(currentZoomScale >= Self.maxZoomScale)
            }

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
            GeometryReader { proxy in
                let renderedSize = renderedImageSize(for: proxy.size)

                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        Color.clear
                            .frame(
                                width: max(proxy.size.width, renderedSize.width + (Self.canvasPadding * 2)),
                                height: max(proxy.size.height, renderedSize.height + (Self.canvasPadding * 2))
                            )

                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: renderedSize.width, height: renderedSize.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    viewportSize = proxy.size
                }
                .onChange(of: proxy.size) { _, newSize in
                    viewportSize = newSize
                }
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

    private var currentZoomScale: CGFloat {
        effectiveZoomScale(for: viewportSize)
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

    private func renderedImageSize(for availableSize: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return .zero }
        let scale = effectiveZoomScale(for: availableSize)
        return CGSize(
            width: max(pixelSize.width * scale, 1),
            height: max(pixelSize.height * scale, 1)
        )
    }

    private func effectiveZoomScale(for availableSize: CGSize) -> CGFloat {
        switch zoomMode {
        case .fit:
            return fitScale(for: availableSize)
        case .actual:
            return 1
        case .custom:
            return customZoomScale
        }
    }

    private func fitScale(for availableSize: CGSize) -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return 1 }

        let usableWidth = max(availableSize.width - (Self.canvasPadding * 2), 120)
        let usableHeight = max(availableSize.height - (Self.canvasPadding * 2), 120)

        guard usableWidth > 0, usableHeight > 0 else { return 1 }

        return min(usableWidth / pixelSize.width, usableHeight / pixelSize.height)
    }

    private func adjustZoom(by multiplier: CGFloat) {
        let baseScale = max(currentZoomScale, Self.minZoomScale)
        setCustomZoomScale(baseScale * multiplier)
    }

    private func setCustomZoomScale(_ scale: CGFloat) {
        customZoomScale = min(max(scale, Self.minZoomScale), Self.maxZoomScale)
        zoomMode = customZoomScale == 1 ? .actual : .custom
    }

    private func zoomLabel(for scale: CGFloat) -> String {
        "\(Int((scale * 100).rounded()))%"
    }
}
