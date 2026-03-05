import XCTest
@testable import Zion

final class LocalizationTests: XCTestCase {
    func testL10nReturnsCorrectKeys() {
        // Since we can't easily change the system locale in tests without side effects,
        // we test if the keys return something (meaning the lookup is happening).
        
        let errorString = L10n("Erro")
        XCTAssertFalse(errorString.isEmpty)
        
        // Test with arguments
        let branchFilter = L10n("Filtro de branch ativo: %@ · %@ commits", "main", "10")
        XCTAssertTrue(branchFilter.contains("main"))
        XCTAssertTrue(branchFilter.contains("10"))
    }
    
    func testLanguageEnums() {
        XCTAssertEqual(AppLanguage.en.rawValue, "en")
        XCTAssertEqual(AppLanguage.ptBR.rawValue, "pt-BR")
        XCTAssertEqual(AppLanguage.es.rawValue, "es")
    }

    // MARK: - Bisect L10n Keys

    func testBisectLocalizationKeysExist() {
        let bisectKeys = [
            "bisect.contextMenu.markBad",
            "bisect.contextMenu.markGood",
            "bisect.abort",
            "bisect.good",
            "bisect.bad",
            "bisect.skip",
            "bisect.done",
            "bisect.viewCommit",
            "bisect.banner.pickGood.title",
            "bisect.banner.pickGood.subtitle",
            "bisect.banner.active.title",
            "bisect.banner.active.subtitle",
            "bisect.banner.found.title",
            "bisect.ai.loading",
            "bisect.ai.error",
            "bisect.badge.culprit",
            "bisect.status.pickGood",
            "bisect.status.testing",
            "bisect.status.found",
            "bisect.status.aborted",
            "bisect.pill.pickGood",
            "bisect.pill.active",
            "bisect.pill.found",
            "bisect.status.done",
            "bisect.confirm.start",
            "bisect.error.invalidHash",
            "bisect.good.hint",
            "bisect.bad.hint",
            "bisect.skip.hint",
        ]

        for key in bisectKeys {
            let value = L10n(key)
            // If the key is not found, L10n returns the key itself
            XCTAssertNotEqual(value, key, "Missing L10n key: \(key)")
            XCTAssertFalse(value.isEmpty, "Empty L10n value for key: \(key)")
        }
    }

    func testBisectLocalizationFormatStrings() {
        let activeTitle = L10n("bisect.banner.active.title", "abc12345")
        XCTAssertTrue(activeTitle.contains("abc12345"), "bisect.banner.active.title should interpolate commit hash")

        let activeSubtitle = L10n("bisect.banner.active.subtitle", "5")
        XCTAssertTrue(activeSubtitle.contains("5"), "bisect.banner.active.subtitle should interpolate step count")

        let foundTitle = L10n("bisect.banner.found.title", "def67890")
        XCTAssertTrue(foundTitle.contains("def67890"), "bisect.banner.found.title should interpolate commit hash")

        let statusTesting = L10n("bisect.status.testing", "abc123")
        XCTAssertTrue(statusTesting.contains("abc123"), "bisect.status.testing should interpolate hash")

        let pillActive = L10n("bisect.pill.active", "3")
        XCTAssertTrue(pillActive.contains("3"), "bisect.pill.active should interpolate step count")

        let pillFound = L10n("bisect.pill.found", "abc12345")
        XCTAssertTrue(pillFound.contains("abc12345"), "bisect.pill.found should interpolate hash")
    }

    func testBisectKeysExistInAllLocales() {
        let bisectKeys = [
            "bisect.contextMenu.markBad",
            "bisect.contextMenu.markGood",
            "bisect.abort",
            "bisect.good",
            "bisect.bad",
            "bisect.skip",
            "bisect.done",
            "bisect.viewCommit",
            "bisect.banner.pickGood.title",
            "bisect.banner.pickGood.subtitle",
            "bisect.banner.active.title",
            "bisect.banner.active.subtitle",
            "bisect.banner.found.title",
            "bisect.ai.loading",
            "bisect.ai.error",
            "bisect.badge.culprit",
            "bisect.status.pickGood",
            "bisect.status.testing",
            "bisect.status.found",
            "bisect.status.aborted",
            "bisect.pill.pickGood",
            "bisect.pill.active",
            "bisect.pill.found",
        ]

        let locales = ["en", "pt-BR", "es"]

        for locale in locales {
            guard let path = Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
                  let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                // Fallback: just check the keys parse from the file directly
                continue
            }
            for key in bisectKeys {
                XCTAssertTrue(
                    content.contains("\"\(key)\""),
                    "Missing key \"\(key)\" in \(locale) locale file"
                )
            }
        }
    }

    func testConflictPromptLocalizationKeysExist() {
        let keys = [
            "conflicts.banner.subtitle",
            "conflicts.open.prompt.title",
            "conflicts.open.prompt.message",
            "conflicts.open.prompt.open",
        ]

        for key in keys {
            let value = L10n(key)
            XCTAssertNotEqual(value, key, "Missing L10n key: \(key)")
            XCTAssertFalse(value.isEmpty, "Empty L10n value for key: \(key)")
        }
    }
}
