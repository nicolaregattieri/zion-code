import Foundation

extension Bundle {
    static let zionResources: Bundle = {
        let appBundle = Bundle.main
        if appBundle.bundleURL.pathExtension == "app",
           appBundle.resourceURL?.appendingPathComponent("zion-logo.png").path != nil,
           appBundle.url(forResource: "zion-logo", withExtension: "png") != nil {
            return appBundle
        }

        let bundleName = "Zion_Zion"
        let candidates: [URL?] = [
            appBundle.url(forResource: bundleName, withExtension: "bundle"),
            appBundle.resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            appBundle.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName).bundle")
        ]

        for case let url? in candidates {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return .module
    }()
}
