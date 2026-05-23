import XCTest
@testable import Zion

final class EditBlockTests: XCTestCase {

    func testRoundTrip() throws {
        let fixedID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let original = EditBlock(
            id: fixedID,
            path: "Sources/Foo/Bar.swift",
            search: "let x = 1",
            replace: "let x = 2",
            appliedAt: fixedDate,
            failureReason: nil,
            attemptStrategies: ["exact", "fuzzy"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditBlock.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.id, fixedID)
        XCTAssertEqual(decoded.path, "Sources/Foo/Bar.swift")
        XCTAssertEqual(decoded.search, "let x = 1")
        XCTAssertEqual(decoded.replace, "let x = 2")
        XCTAssertEqual(decoded.appliedAt, fixedDate)
        XCTAssertNil(decoded.failureReason)
        XCTAssertEqual(decoded.attemptStrategies, ["exact", "fuzzy"])
    }

    func testRoundTripWithFailureReason() throws {
        let original = EditBlock(
            path: "Sources/Foo/Bar.swift",
            search: "old",
            replace: "new",
            failureReason: "search string not found"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditBlock.self, from: data)

        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.failureReason, "search string not found")
        XCTAssertNil(decoded.appliedAt)
        XCTAssertTrue(decoded.attemptStrategies.isEmpty)
    }

    func testAttemptLogRoundTrip() throws {
        let log = EditAttemptLog(strategy: "exact", ok: true, note: "matched at line 42")

        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(EditAttemptLog.self, from: data)

        XCTAssertEqual(log, decoded)
        XCTAssertEqual(decoded.strategy, "exact")
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.note, "matched at line 42")
    }

    func testAttemptLogNilNote() throws {
        let log = EditAttemptLog(strategy: "fuzzy", ok: false)

        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(EditAttemptLog.self, from: data)

        XCTAssertEqual(log, decoded)
        XCTAssertNil(decoded.note)
    }
}
