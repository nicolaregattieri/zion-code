import XCTest
@testable import Zion

final class CLIProvidersLocalizationTests: XCTestCase {

    private let requiredKeys: [String] = [
        "settings.ai.provider.claudeCLI",
        "settings.ai.provider.codexCLI",
        "settings.ai.cli.subscription.title",
        "settings.ai.cli.installed",
        "settings.ai.cli.notInstalled",
        "settings.ai.cli.notInstalled.claude.hint",
        "settings.ai.cli.notInstalled.codex.hint",
        "settings.ai.cli.notAuthenticated.claude.hint",
        "settings.ai.cli.notAuthenticated.codex.hint",
        "settings.ai.cli.allowEdits",
        "settings.ai.cli.allowEdits.hint",
        "settings.ai.cli.refresh",
        "chat.cli.tool.running",
        "chat.cli.tool.completed",
        "chat.cli.tool.failed",
        "ai.error.cli.notInstalled",
        "ai.error.cli.notAuthenticated",
        "ai.error.cli.versionTooOld",
        "ai.error.cli.execFailed",
    ]

    /// Keys that contain exactly one %@ format argument.
    private let singleFormatArgKeys: [String] = [
        "settings.ai.cli.installed",
        "chat.cli.tool.running",
        "chat.cli.tool.completed",
        "chat.cli.tool.failed",
        "ai.error.cli.execFailed",
    ]

    private let locales = ["en", "pt-BR", "es"]

    // MARK: - Helpers

    private func loadStrings(locale: String) -> [String: String]? {
        guard let path = Bundle.zionResources.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: locale
        ) else {
            XCTFail("Could not find Localizable.strings for locale: \(locale)")
            return nil
        }
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("Could not parse Localizable.strings for locale: \(locale) at \(path)")
            return nil
        }
        return dict
    }

    // MARK: - Tests

    func testAllRequiredKeysPresentInAllLocales() {
        for locale in locales {
            guard let dict = loadStrings(locale: locale) else { continue }

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

    /// For each format-arg key, assert that all locales have the same number of %@ tokens.
    func testFormatArgCountConsistentAcrossLocales() {
        // Build a reference count from EN
        guard let enDict = loadStrings(locale: "en") else { return }

        for key in singleFormatArgKeys {
            guard let enValue = enDict[key] else {
                XCTFail("Missing key \"\(key)\" in EN (reference locale)")
                continue
            }
            let enCount = enValue.components(separatedBy: "%@").count - 1

            for locale in locales where locale != "en" {
                guard let dict = loadStrings(locale: locale),
                      let value = dict[key] else { continue }
                let count = value.components(separatedBy: "%@").count - 1
                XCTAssertEqual(
                    count, enCount,
                    "Format arg count mismatch for key \"\(key)\" in locale \(locale): expected \(enCount), got \(count)"
                )
            }
        }
    }

    /// Spot-check specific translated values to catch copy-paste errors.
    func testKeyTranslationsAreDifferentAcrossLocales() {
        // Provider label should differ between EN and PT-BR (contains "assinatura" vs "subscription")
        guard let enDict = loadStrings(locale: "en"),
              let ptDict = loadStrings(locale: "pt-BR"),
              let esDict = loadStrings(locale: "es") else { return }

        let key = "settings.ai.provider.claudeCLI"
        XCTAssertNotEqual(enDict[key], ptDict[key], "\(key) should differ between en and pt-BR")
        XCTAssertNotEqual(enDict[key], esDict[key], "\(key) should differ between en and es")

        let subKey = "settings.ai.cli.subscription.title"
        XCTAssertNotEqual(enDict[subKey], ptDict[subKey], "\(subKey) should differ between en and pt-BR")
        XCTAssertNotEqual(enDict[subKey], esDict[subKey], "\(subKey) should differ between en and es")
    }
}
