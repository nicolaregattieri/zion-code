import XCTest
@testable import Zion

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testShouldNotSkipIncomingImageWhenFingerprintDiffers() {
        let firstData = Data("image-a".utf8)
        let secondData = Data("image-b".utf8)
        let firstFingerprint = ClipboardMonitor.makeImageFingerprint(firstData)
        let secondFingerprint = ClipboardMonitor.makeImageFingerprint(secondData)

        let topItem = ClipboardItem(
            imageWidth: 1512,
            imageHeight: 982,
            filePath: "/tmp/image-a.jpg",
            fingerprint: firstFingerprint
        )

        XCTAssertFalse(
            ClipboardMonitor.shouldSkipIncomingImage(
                previousTopItem: topItem,
                incomingFingerprint: secondFingerprint
            )
        )
    }

    func testShouldSkipIncomingImageWhenFingerprintMatches() {
        let data = Data("same-image".utf8)
        let fingerprint = ClipboardMonitor.makeImageFingerprint(data)
        let topItem = ClipboardItem(
            imageWidth: 1512,
            imageHeight: 982,
            filePath: "/tmp/image-a.jpg",
            fingerprint: fingerprint
        )

        XCTAssertTrue(
            ClipboardMonitor.shouldSkipIncomingImage(
                previousTopItem: topItem,
                incomingFingerprint: fingerprint
            )
        )
    }

    func testShouldNotSkipWhenTopItemIsNotImage() {
        XCTAssertFalse(
            ClipboardMonitor.shouldSkipIncomingImage(
                previousTopItem: ClipboardItem(text: "hello"),
                incomingFingerprint: "abc"
            )
        )
    }
}
