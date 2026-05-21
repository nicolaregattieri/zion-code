import XCTest
@testable import Zion

final class LocalLLMLocalizationTests: XCTestCase {

    private let requiredKeys: [String] = [
        "settings.ai.provider.local",
        "settings.ai.local.serverURL",
        "settings.ai.local.serverURL.hint",
        "settings.ai.local.model",
        "settings.ai.local.model.refresh",
        "settings.ai.local.model.empty",
        "settings.ai.local.model.recommended",
        "settings.ai.local.model.lightFallback",
        "settings.ai.local.timeout",
        "settings.ai.local.timeout.unit",
        "settings.ai.local.health.healthy",
        "settings.ai.local.health.unhealthy",
        "settings.ai.local.health.lastCheckedAt",
        "settings.ai.local.health.test",
        "settings.ai.local.singleModelWarning",
        "settings.ai.local.toolCallingDisabled",
        "settings.ai.local.apiKey.optional",
        "settings.ai.local.error.connectionFailed",
        "settings.ai.local.error.serverNotFound",
        "settings.ai.local.error.modelError",
        "settings.ai.local.error.toolCallingUnsupported",
        "settings.ai.local.hint.ollamaServe",
        "settings.ai.local.hint.ollamaPull",
    ]

    func testAllRequiredKeysPresentInAllLocales() {
        let locales = ["en", "pt-BR", "es"]

        for locale in locales {
            guard let path = Bundle.zionResources.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: locale
            ) else {
                XCTFail("Could not find Localizable.strings for locale: \(locale)")
                continue
            }

            guard let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
                XCTFail("Could not parse Localizable.strings for locale: \(locale) at \(path)")
                continue
            }

            for key in requiredKeys {
                guard let value = dict[key] else {
                    XCTFail("Missing key \"\(key)\" in locale: \(locale)")
                    continue
                }
                XCTAssertFalse(
                    value.isEmpty,
                    "Empty value for key \"\(key)\" in locale: \(locale)"
                )
            }
        }
    }
}
