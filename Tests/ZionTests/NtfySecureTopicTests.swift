import XCTest
@testable import Zion

final class NtfySecureTopicTests: XCTestCase {

    func testGeneratedTopicHasCorrectPrefix() {
        let topic = NtfyClient.generateSecureTopic()
        XCTAssertTrue(topic.hasPrefix("zion-code-"))
    }

    func testGeneratedTopicHasCorrectLength() {
        let topic = NtfyClient.generateSecureTopic()
        // "zion-code-" (10 chars) + 7 random chars = 17
        XCTAssertEqual(topic.count, 17)
    }

    func testGeneratedTopicSuffixIsAlphanumericOnly() {
        let topic = NtfyClient.generateSecureTopic()
        let suffix = String(topic.dropFirst(10))
        let alphanumeric = CharacterSet.alphanumerics
        for scalar in suffix.unicodeScalars {
            XCTAssertTrue(alphanumeric.contains(scalar), "Unexpected char in suffix: \(scalar)")
        }
    }

    func testGeneratedTopicPassesOwnValidation() {
        let topic = NtfyClient.generateSecureTopic()
        XCTAssertTrue(NtfyClient.validateTopic(topic))
    }

    func testGeneratedTopicsAreUnique() {
        // Note: generateSecureTopic uses UInt8 % 62, which has a ~0.4% modulo bias
        // for values 62-255 mapping unevenly across the 62-char alphabet.
        // This is acceptable for topic generation (not crypto keys).
        var topics = Set<String>()
        for _ in 0..<100 {
            topics.insert(NtfyClient.generateSecureTopic())
        }
        XCTAssertEqual(topics.count, 100, "Expected 100 unique topics from 100 generations")
    }
}
