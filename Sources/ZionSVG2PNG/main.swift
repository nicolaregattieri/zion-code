import AppKit

// zion_svg2png — Sandbox-safe SVG to PNG converter
// Uses NSImage + CoreSVG (in-process, no WindowServer needed)
//
// Usage: zion_svg2png <input.svg> [maxWidth] [--out output.png]

@MainActor
func convert() -> Int32 {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        fputs("Usage: zion_svg2png <input.svg> [maxWidth] [--out output.png]\n", stderr)
        return 1
    }

    let inputPath = args[1]
    var maxWidth: CGFloat = 600
    var outputPath: String? = nil

    var i = 2
    while i < args.count {
        if args[i] == "--out", i + 1 < args.count {
            outputPath = args[i + 1]
            i += 2
        } else if let w = Double(args[i]), w > 0 {
            maxWidth = CGFloat(w)
            i += 1
        } else {
            fputs("Unknown argument: \(args[i])\n", stderr)
            return 1
        }
    }

    // Initialize AppKit (no event loop needed)
    _ = NSApplication.shared

    guard let image = NSImage(contentsOfFile: inputPath) else {
        fputs("Error: cannot load SVG: \(inputPath)\n", stderr)
        return 1
    }

    let originalSize = image.size
    guard originalSize.width > 0, originalSize.height > 0 else {
        fputs("Error: invalid image dimensions\n", stderr)
        return 1
    }

    // Scale preserving aspect ratio
    let scale = min(maxWidth / originalSize.width, 1.0)
    let targetSize = NSSize(
        width: round(originalSize.width * scale),
        height: round(originalSize.height * scale)
    )

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(targetSize.width),
        pixelsHigh: Int(targetSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("Error: cannot create bitmap\n", stderr)
        return 1
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: targetSize))
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Error: PNG encoding failed\n", stderr)
        return 1
    }

    let outFile = outputPath ?? inputPath.replacingOccurrences(
        of: ".svg", with: ".png", options: [.caseInsensitive, .anchored.union(.backwards)]
    )

    do {
        try pngData.write(to: URL(fileURLWithPath: outFile))
    } catch {
        fputs("Error: cannot write output: \(error.localizedDescription)\n", stderr)
        return 1
    }

    print(outFile)
    return 0
}

exit(convert())
