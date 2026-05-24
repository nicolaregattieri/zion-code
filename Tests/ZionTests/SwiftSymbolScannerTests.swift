// SwiftSymbolScannerTests.swift
// Phase 12, Task 3 — regex-based Swift symbol extractor tests.

import XCTest
@testable import Zion

final class SwiftSymbolScannerTests: XCTestCase {

    let scanner = SwiftSymbolScanner()

    // Inline fixture — a representative Swift source string.
    let fixture = """
import Foundation

struct User {
    let id: String
    func greet() {}
}

class API {
    static let shared = API()
    func fetch() {}
}

enum Status {
    case active
    case inactive
}

protocol Drawable {
    func draw()
}

extension Array where Element == Int {
    func sum() -> Int { reduce(0, +) }
}

func standalone() {}
"""

    // Parsed once, reused across tests.
    private var parsed: [ParsedSymbol] = []

    override func setUp() async throws {
        try await super.setUp()
        let url = URL(fileURLWithPath: "/tmp/fixture.swift")
        parsed = try scanner.parse(file: url, content: fixture)
    }

    // MARK: 1 — rejects non-swift extension

    func test_rejects_non_swift_extension() throws {
        let url = URL(fileURLWithPath: "/tmp/foo.txt")
        XCTAssertThrowsError(try scanner.parse(file: url, content: "")) { error in
            XCTAssertEqual(error as? ParserError, ParserError.unsupportedLanguage(extension: "txt"))
        }
    }

    // MARK: 2 — finds struct

    func test_finds_struct() {
        XCTAssertTrue(
            parsed.contains { $0.name == "User" && $0.kind == .struct },
            "Expected struct User; got: \(parsed)"
        )
    }

    // MARK: 3 — finds class

    func test_finds_class() {
        XCTAssertTrue(
            parsed.contains { $0.name == "API" && $0.kind == .class },
            "Expected class API; got: \(parsed)"
        )
    }

    // MARK: 4 — finds enum with cases

    func test_finds_enum_with_cases() {
        XCTAssertTrue(
            parsed.contains { $0.name == "Status" && $0.kind == .enum },
            "Expected enum Status; got: \(parsed)"
        )
        XCTAssertTrue(
            parsed.contains { $0.name == "active" && $0.kind == .enumCase },
            "Expected enumCase active; got: \(parsed)"
        )
        XCTAssertTrue(
            parsed.contains { $0.name == "inactive" && $0.kind == .enumCase },
            "Expected enumCase inactive; got: \(parsed)"
        )
    }

    // MARK: 5 — finds protocol

    func test_finds_protocol() {
        XCTAssertTrue(
            parsed.contains { $0.name == "Drawable" && $0.kind == .protocol },
            "Expected protocol Drawable; got: \(parsed)"
        )
    }

    // MARK: 6 — finds extension

    func test_finds_extension() {
        XCTAssertTrue(
            parsed.contains { $0.name == "Array" && $0.kind == .extension },
            "Expected extension Array; got: \(parsed)"
        )
    }

    // MARK: 7 — distinguishes function vs method

    func test_distinguishes_function_vs_method() {
        // standalone is at top level → .function
        XCTAssertTrue(
            parsed.contains { $0.name == "standalone" && $0.kind == .function },
            "Expected standalone to be .function; got: \(parsed)"
        )
        // greet, fetch, draw, sum are inside type bodies → .method
        for methodName in ["greet", "fetch", "draw", "sum"] {
            XCTAssertTrue(
                parsed.contains { $0.name == methodName && $0.kind == .method },
                "Expected \(methodName) to be .method; got: \(parsed)"
            )
        }
    }

    // MARK: 8 — finds at least 3 symbols including a struct and a func (AC literal)

    func test_finds_struct_and_func() {
        XCTAssertGreaterThanOrEqual(parsed.count, 3, "Expected at least 3 symbols")
        XCTAssertTrue(
            parsed.contains { $0.kind == .struct },
            "Expected at least one .struct symbol"
        )
        // "func" in AC covers both .function and .method
        XCTAssertTrue(
            parsed.contains { $0.kind == .function || $0.kind == .method },
            "Expected at least one function/method symbol"
        )
    }
}
