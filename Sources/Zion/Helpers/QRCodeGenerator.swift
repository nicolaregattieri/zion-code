import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
    static func generate(from string: String, size: CGFloat = 200) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = size / ciImage.extent.width
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    struct QRPayload: Codable {
        let url: String
        let key: String
        let token: String
        let version: Int
    }

    static func generatePairingQR(
        tunnelURL: String,
        keyBase64: String,
        pairingToken: String,
        size: CGFloat = 200
    ) -> NSImage? {
        let payload = QRPayload(url: tunnelURL, key: keyBase64, token: pairingToken, version: 1)
        guard let jsonData = try? JSONEncoder().encode(payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return generate(from: jsonString, size: size)
    }
}
