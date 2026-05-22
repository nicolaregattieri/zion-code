import XCTest
@testable import Zion

final class ChatLocalizationTests: XCTestCase {

    private let requiredKeys: [String] = [
        "chat.title",
        "chat.emptyState.headline",
        "chat.emptyState.example.history",
        "chat.emptyState.example.branch",
        "chat.emptyState.example.diff",
        "chat.composer.hint",
        "chat.composer.send",
        "chat.composer.stop",
        "chat.composer.newChat",
        "chat.slash.diff.label",
        "chat.slash.log.label",
        "chat.slash.status.label",
        "chat.slash.file.label",
        "chat.slash.commit.label",
        "chat.error.aiNotConfigured",
        "chat.error.send.title",
        "chat.contextHeader",
        "chat.slash.fileOutsideRepo",
        "chat.slash.empty.diff",
        "chat.head.unknown",
        "chat.tool.running",
        "chat.tool.completed",
        "chat.tool.failed",
        "chat.tool.error.readBeforeEdit",
        "chat.tool.error.fileExists",
        "chat.tool.error.outsideRepo",
        "chat.tool.error.bashNotAllowed",
        "chat.tool.error.maxHops",
        "chat.tool.error.editsDisabled",
        "chat.tool.error.invalidEdit",
        "chat.tool.error.textNotFound",
        "chat.harness.autoIncluded",
        "chat.harness.intent.lastCommit",
        "chat.harness.intent.currentChanges",
        "chat.harness.intent.recentHistory",
        "chat.harness.intent.status",
        "chat.harness.intent.fileContent",
        "chat.harness.intent.commitDetails",
        "chat.thread.list.title",
        "chat.thread.new",
        "chat.thread.delete",
        "chat.thread.rename",
        "chat.thread.untitled",
        "chat.thread.confirmDelete",
        "chat.thread.lastUpdatedAt",
        "chat.thread.empty",
        "chat.thread.sidebar.toggle",
        "chat.persistence.error",
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

    func testContextHeaderContainsPositionalTokens() {
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

            guard let dict = NSDictionary(contentsOfFile: path) as? [String: String],
                  let value = dict["chat.contextHeader"] else {
                XCTFail("Missing chat.contextHeader in locale: \(locale)")
                continue
            }

            // Verify all 3 string tokens and 1 integer token are present
            let stringTokenCount = value.components(separatedBy: "%@").count - 1
            let intTokenCount = value.components(separatedBy: "%d").count - 1
            XCTAssertEqual(stringTokenCount, 3,
                "chat.contextHeader in locale \(locale) should have 3 %@ tokens, found \(stringTokenCount)")
            XCTAssertEqual(intTokenCount, 1,
                "chat.contextHeader in locale \(locale) should have 1 %d token, found \(intTokenCount)")
        }
    }
}
