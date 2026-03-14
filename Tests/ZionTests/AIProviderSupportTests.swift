import XCTest
@testable import Zion

final class AIProviderSupportTests: XCTestCase {

    func testDashboardURLMapping() {
        XCTAssertEqual(AIProviderSupport.dashboardURL(for: .anthropic)?.absoluteString, "https://console.anthropic.com/settings/keys")
        XCTAssertEqual(AIProviderSupport.dashboardURL(for: .openai)?.absoluteString, "https://platform.openai.com/api-keys")
        XCTAssertEqual(AIProviderSupport.dashboardURL(for: .gemini)?.absoluteString, "https://aistudio.google.com/apikey")
        XCTAssertNil(AIProviderSupport.dashboardURL(for: .none))
    }

    func testConnectionInfoSupportsMultipleKeysAtOnce() {
        let info = AIProviderSupport.connectionInfo { provider in
            switch provider {
            case .openai:
                return "openai-key"
            case .gemini:
                return "gemini-key"
            default:
                return nil
            }
        }

        XCTAssertEqual(info.count, 3)
        XCTAssertTrue(info.first(where: { $0.provider == .openai })?.isConnected == true)
        XCTAssertTrue(info.first(where: { $0.provider == .gemini })?.isConnected == true)
        XCTAssertTrue(info.first(where: { $0.provider == .anthropic })?.isConnected == false)
    }

    func testAlternativeProvidersExcludeCurrentDefault() {
        let alternatives = AIProviderSupport.alternativeProviders(excluding: .gemini) { provider in
            switch provider {
            case .openai:
                return "openai-key"
            case .gemini:
                return "gemini-key"
            default:
                return nil
            }
        }

        XCTAssertEqual(alternatives, [.openai])
    }

    func testQuotaRecoveryInfoTracksAlternatives() {
        let recovery = AIProviderSupport.quotaRecoveryInfo(defaultProvider: .anthropic) { provider in
            switch provider {
            case .openai:
                return "openai-key"
            case .gemini:
                return "gemini-key"
            default:
                return nil
            }
        }

        XCTAssertTrue(recovery.hasAlternativeProvider)
        XCTAssertEqual(recovery.alternativeProviders, [.openai, .gemini])
    }

    func testWhisperFallsBackToAppleWithoutOpenAIKey() {
        let effective = SpeechEngineSupport.effectiveEngine(storedValue: "whisper") { _ in nil }
        XCTAssertEqual(effective, .apple)
    }

    func testWhisperRemainsAvailableWhenOpenAIKeyExists() {
        let effective = SpeechEngineSupport.effectiveEngine(storedValue: "whisper") { provider in
            provider == .openai ? "openai-key" : nil
        }
        XCTAssertEqual(effective, .whisper)
    }

    func testOpenAISettingsNotificationNameExists() {
        XCTAssertEqual(Notification.Name.openAISettings.rawValue, "openAISettings")
    }

    @MainActor
    func testOpenAISettingsNotificationCanBePostedAndReceived() {
        let expectation = expectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .openAISettings,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .openAISettings, object: nil)

        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
