import XCTest
@testable import Zion

final class RoutingPolicyTests: XCTestCase {

    private let udKey = "chat.routing.policy.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: udKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: udKey)
        super.tearDown()
    }

    // MARK: - Tests

    func testDefaultPolicyHasAllLanes() {
        let policy = RoutingPolicy.defaultPolicy
        for lane in AITaskLane.allCases {
            let chain = policy.chain(for: lane)
            XCTAssertFalse(chain.isEmpty, "Default chain for lane '\(lane.rawValue)' must not be empty")
        }
    }

    func testCodableRoundTrip() throws {
        let original = RoutingPolicy(chains: [
            "general": ["anthropic", "openai"],
            "cheapSummary": ["local"]
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoutingPolicy.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testLoadReturnsDefaultWhenMissing() {
        UserDefaults.standard.removeObject(forKey: udKey)
        let loaded = RoutingPolicy.load()
        XCTAssertEqual(loaded, RoutingPolicy.defaultPolicy)
    }

    func testSaveAndLoadRoundTrip() {
        let custom = RoutingPolicy(chains: [
            "reasoning": ["openai", "anthropic"],
            "transcription": ["openai"]
        ])
        custom.save()
        let loaded = RoutingPolicy.load()
        XCTAssertEqual(loaded, custom)
    }

    func testChainForLaneFallsBackToDefault() {
        // Empty chains map — should fall back to default for .general
        let empty = RoutingPolicy(chains: [:])
        let chain = empty.chain(for: .general)
        let defaultChain = RoutingPolicy.defaultPolicy.chain(for: .general)
        XCTAssertEqual(chain, defaultChain)
        XCTAssertFalse(chain.isEmpty)
    }
}
