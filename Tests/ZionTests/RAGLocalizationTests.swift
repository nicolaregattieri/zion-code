import XCTest
@testable import Zion

final class RAGLocalizationTests: XCTestCase {

    private let phase5Keys: [String] = [
        "rag.indexing.title",
        "rag.indexing.progress",
        "rag.indexing.paused.memory",
        "rag.embedding.assetMissing",
        "rag.scale.annRequired",
        "rag.evalGate.belowRecall",
        "rag.backend.nlContextual",
        "rag.backend.qodo",
        "rag.backend.promoted",
        "rag.settings.title",
        "rag.settings.hybridToggle",
        "rag.settings.reindex",
        "rag.settings.chunkCount",
        "rag.settings.lastIndexed",
        "chat.help.mention.code",
        "mention.code.token",
        "mention.code.empty",
        "rag.tool.notReady",
    ]

    func test_phase5_keys_existInAllLocales() {
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

            for key in phase5Keys {
                guard let value = dict[key] else {
                    XCTFail("Missing Phase 5 key \"\(key)\" in locale: \(locale)")
                    continue
                }
                XCTAssertFalse(
                    value.isEmpty,
                    "Empty value for Phase 5 key \"\(key)\" in locale: \(locale)"
                )
            }
        }
    }
}
