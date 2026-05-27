import XCTest
@testable import Zion

/// Phase 4 spec criteria #7 + #8 — vision payload MIME guard and
/// text-only-model banner. Skips the full golden-body fixture suite
/// (deferred) and asserts the MIME filter + provider capability probe
/// directly.
final class AIClientImagePayloadTests: XCTestCase {

    func test_acceptedMIMEs_contains_png_jpeg_pdf() {
        let accepted = Constants.Attachments.acceptedMIMEs
        XCTAssertTrue(accepted.contains("image/png"))
        XCTAssertTrue(accepted.contains("image/jpeg"))
        XCTAssertTrue(accepted.contains("application/pdf"))
    }

    func test_acceptedImageAttachments_filtersUnknownMIME() {
        let png = AIImageAttachment(mimeType: "image/png", base64: "AAA", originalName: "a.png")
        let heic = AIImageAttachment(mimeType: "image/heic", base64: "BBB", originalName: "b.heic")
        let pdf = AIImageAttachment(mimeType: "application/pdf", base64: "CCC", originalName: "c.pdf")
        var payload = AIPromptPayload(
            systemInstructions: "",
            taskInstructions: "",
            untrustedSections: [],
            suspiciousPatterns: []
        )
        payload.imageAttachments = [png, heic, pdf]
        let kept = AIClient.acceptedImageAttachments(from: payload)
        let mimes = kept.map { $0.mimeType }
        XCTAssertEqual(Set(mimes), Set(["image/png", "application/pdf"]))
        XCTAssertFalse(mimes.contains("image/heic"))
    }

    func test_isVisionCapable_returnsExpected() {
        XCTAssertTrue(ProviderOrchestrator.isVisionCapable(for: .anthropic))
        XCTAssertTrue(ProviderOrchestrator.isVisionCapable(for: .openai))
        XCTAssertTrue(ProviderOrchestrator.isVisionCapable(for: .gemini))
        XCTAssertTrue(ProviderOrchestrator.isVisionCapable(for: .claudeCLI))
        XCTAssertFalse(ProviderOrchestrator.isVisionCapable(for: .none))
    }
}
