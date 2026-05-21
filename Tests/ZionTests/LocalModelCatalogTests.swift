import XCTest
@testable import Zion

final class LocalModelCatalogTests: XCTestCase {
    private let testModelName = "test-ollama-model:7b"
    private let udKey = UserDefaultsKeys.AI.localConfig

    override func setUp() {
        super.setUp()
        let config = LocalLLMConfig(modelName: testModelName)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: udKey)
        super.tearDown()
    }

    func testSingleModelForAllLanes() {
        for mode in AIMode.allCases {
            for lane in AITaskLane.allCases {
                let selection = AIModelCatalogService.selection(for: .local, mode: mode, lane: lane)
                if lane == .transcription {
                    XCTAssertEqual(
                        selection.primaryModelID, "",
                        "Expected empty primary for transcription lane (mode: \(mode))"
                    )
                } else {
                    XCTAssertEqual(
                        selection.primaryModelID, testModelName,
                        "Expected \(testModelName) for lane \(lane), mode \(mode)"
                    )
                    XCTAssertTrue(
                        selection.fallbackModelIDs.isEmpty,
                        "Expected no fallbacks for local provider (lane: \(lane), mode: \(mode))"
                    )
                }
            }
        }
    }

    func testNilConfigReturnsEmpty() {
        UserDefaults.standard.removeObject(forKey: udKey)
        for mode in AIMode.allCases {
            for lane in AITaskLane.allCases {
                let selection = AIModelCatalogService.selection(for: .local, mode: mode, lane: lane)
                XCTAssertEqual(
                    selection.primaryModelID, "",
                    "Expected empty primary when no config saved (lane: \(lane), mode: \(mode))"
                )
            }
        }
    }
}
