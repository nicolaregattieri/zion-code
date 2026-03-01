import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
    static func generate(from string: String, size: CGFloat = Constants.RemoteAccess.qrCodeSize) -> NSImage? {
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
        lanMode: Bool = false,
        size: CGFloat = Constants.RemoteAccess.qrCodeSize
    ) -> NSImage? {
        // Pass key and token as query params (survive QR scanners, redirects, refreshes).
        // URL-safe base64 (RFC 4648 §5): replace +→-, /→_, strip = padding
        let urlSafeKey = keyBase64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var pairingURL = "\(tunnelURL)/?k=\(urlSafeKey)&t=\(pairingToken)&v=1"
        if lanMode {
            pairingURL += "&m=lan"
        }
        return generate(from: pairingURL, size: size)
    }
}
