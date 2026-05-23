import XCTest
@testable import Zion

@MainActor
final class ProviderSwitchBannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvent(reason: String = "rate limited") -> ProviderSwitchEvent {
        ProviderSwitchEvent(
            id: UUID(),
            from: .anthropic,
            to: .openai,
            reason: reason,
            at: Date()
        )
    }

    // MARK: - testDismissCallbackFires

    func testDismissCallbackFires() {
        var fired = false
        let event = makeEvent()
        let banner = ProviderSwitchBanner(event: event, onDismiss: { fired = true })
        banner.dismissTapped()
        XCTAssertTrue(fired, "onDismiss should fire when dismissTapped() is called")
    }

    // MARK: - testReasonRenderedNonEmpty

    func testReasonRenderedNonEmpty() {
        let reason = "rate limited"
        let event = makeEvent(reason: reason)
        let banner = ProviderSwitchBanner(event: event)
        // Confirm the event wired into the banner carries the expected reason.
        XCTAssertEqual(banner.event.reason, reason)
        XCTAssertFalse(banner.event.reason.isEmpty)
    }

    // MARK: - testEventRoundTrip

    func testEventRoundTrip() throws {
        let id = UUID()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ProviderSwitchEvent(
            id: id,
            from: .claudeCLI,
            to: .auto,
            reason: "quota exceeded",
            at: at
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderSwitchEvent.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.from, original.from)
        XCTAssertEqual(decoded.to, original.to)
        XCTAssertEqual(decoded.reason, original.reason)
        XCTAssertEqual(decoded.at.timeIntervalSince1970,
                       original.at.timeIntervalSince1970,
                       accuracy: 0.001)
    }
}
