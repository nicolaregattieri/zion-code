import XCTest
@testable import Zion

final class AIProviderSupportLocalTests: XCTestCase {

    private let dummyConfig = LocalLLMConfig(
        serverURL: "http://localhost:11434/v1",
        modelName: "test-model"
    )

    // (config nil, probe true) -> false
    func testLocalIsConnectedRequiresConfig_nilConfig_healthTrue() {
        let result = AIProviderSupport.isConnected(
            provider: .local,
            loadLocalConfig: { nil },
            localHealthProbe: { _ in true }
        )
        XCTAssertFalse(result)
    }

    // (config nil, probe false) -> false
    func testLocalIsConnectedRequiresConfig_nilConfig_healthFalse() {
        let result = AIProviderSupport.isConnected(
            provider: .local,
            loadLocalConfig: { nil },
            localHealthProbe: { _ in false }
        )
        XCTAssertFalse(result)
    }

    // (config present, probe false) -> false
    func testLocalIsConnectedRequiresConfig_hasConfig_healthFalse() {
        let result = AIProviderSupport.isConnected(
            provider: .local,
            loadLocalConfig: { self.dummyConfig },
            localHealthProbe: { _ in false }
        )
        XCTAssertFalse(result)
    }

    // (config present, probe true) -> true
    func testLocalIsConnectedRequiresHealthyProbe() {
        let result = AIProviderSupport.isConnected(
            provider: .local,
            loadLocalConfig: { self.dummyConfig },
            localHealthProbe: { _ in true }
        )
        XCTAssertTrue(result)
    }
}
